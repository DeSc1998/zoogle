const std = @import("std");

pub const FunctionDef = struct {
    alloc: std.mem.Allocator,
    name: []const u8,
    return_type: []const u8,
    params: std.ArrayList([]const u8),

    pub fn deinit(self: *FunctionDef) void {
        self.alloc.free(self.name);
        self.alloc.free(self.return_type);
        self.params.deinit();
    }

    pub fn format(self: FunctionDef) ![]const u8 {
        const params = try std.mem.join(self.alloc, ", ", self.params.items);
        defer self.alloc.free(params);
        return try std.fmt.allocPrint(self.alloc, "fn {s}({s}) {s}", .{ self.name, params, self.return_type });
    }
};

pub fn collectFunctionsFile(alloc: std.mem.Allocator, file: []const u8, skip_private: bool) !std.ArrayList(FunctionDef) {
    const tmp = try std.fs.cwd().readFileAlloc(alloc, file, std.math.maxInt(usize));
    const source = try alloc.dupeZ(u8, tmp);
    alloc.free(tmp);

    var ast = try std.zig.Ast.parse(alloc, source, .zig);
    return collectFunctions(alloc, &ast, skip_private);
}

pub fn collectFunctions(alloc: std.mem.Allocator, ast: *std.zig.Ast, skip_private: bool) !std.ArrayList(FunctionDef) {
    defer ast.deinit(alloc);
    var functions = std.ArrayList(FunctionDef).init(alloc);
    for (ast.rootDecls()) |decl_idx| {
        const decl = ast.nodes.get(decl_idx);
        if (decl.tag == .fn_decl) {
            var buffer: [1]std.zig.Ast.Node.Index = undefined;
            if (ast.fullFnProto(&buffer, decl_idx)) |fn_decl| {
                if (fn_decl.visib_token) |_| {} else {
                    if (skip_private) continue;
                }
                const params = try collectParams(alloc, ast.*, fn_decl);
                const return_type = ast.nodes.get(fn_decl.ast.return_type);
                const name = ast.tokenSlice(fn_decl.ast.fn_token + 1);
                const returnType = try nodeToSlice(alloc, ast.*, return_type);

                try functions.append(.{
                    .alloc = alloc,
                    .name = try alloc.dupe(u8, name),
                    .return_type = try alloc.dupe(u8, returnType),
                    .params = params,
                });
            }
        }
    }
    return functions;
}

fn collectParams(alloc: std.mem.Allocator, ast: std.zig.Ast, proto: std.zig.Ast.full.FnProto) !std.ArrayList([]const u8) {
    var params = std.ArrayList([]const u8).init(alloc);
    var param_it = proto.iterate(&ast);
    while (param_it.next()) |param| {
        const type_node = ast.nodes.get(param.type_expr);
        try params.append(try nodeToSlice(alloc, ast, type_node));
    }
    return params;
}

fn nodeToSlice(alloc: std.mem.Allocator, ast: std.zig.Ast, node: std.zig.Ast.Node) ![]const u8 {
    switch (node.tag) {
        .identifier, .number_literal => {
            const main_token = ast.tokenSlice(node.main_token);
            return main_token;
        },
        .call_one => {
            const lhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.lhs));
            const rhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(alloc, u8, &[_][]const u8{ lhs, "(", rhs, ")" });
        },
        .call => {
            const lhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.lhs));
            const extra = ast.extraData(node.data.rhs, std.zig.Ast.Node.SubRange);
            const params = ast.extra_data[extra.start..extra.end];
            var tmp = std.ArrayList([]const u8).init(alloc);
            for (params) |param| {
                try tmp.append(try nodeToSlice(alloc, ast, ast.nodes.get(param)));
            }
            const params_str = try std.mem.join(alloc, ", ", tmp.items);
            return try std.mem.concat(alloc, u8, &[_][]const u8{ lhs, "(", params_str, ")" });
        },
        .field_access => {
            const lhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.lhs));
            const rhs = ast.tokenSlice(node.data.rhs);
            return try std.mem.concat(alloc, u8, &[_][]const u8{ lhs, ".", rhs });
        },
        .ptr_type => {
            const rhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(alloc, u8, &[_][]const u8{ "*", rhs });
        },
        .array_type => {
            const lhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.lhs));
            const rhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(alloc, u8, &[_][]const u8{ "[", lhs, "]", rhs });
        },
        .ptr_type_aligned => {
            const rhs = try nodeToSlice(alloc, ast, ast.nodes.get(node.data.rhs));
            const main_token = ast.tokenSlice(node.main_token);
            if (std.mem.eql(u8, main_token, "*")) {
                return try std.mem.concat(alloc, u8, &[_][]const u8{ "*", rhs });
            } else {
                return try std.mem.concat(alloc, u8, &[_][]const u8{ "[]", rhs });
            }
        },
        else => |tag| {
            std.debug.print("not implemented type: {}\n", .{tag});
            return error.NotImplemented;
        },
    }
}
