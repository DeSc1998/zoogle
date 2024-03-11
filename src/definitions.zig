const std = @import("std");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub const FunctionDef = struct {
    name: []const u8,
    return_type: []const u8,
    params: []const []const u8,
};

pub fn collectFunctions(ast: *std.zig.Ast) !std.ArrayList(FunctionDef) {
    var functions = std.ArrayList(FunctionDef).init(allocator);
    for (ast.rootDecls()) |decl_idx| {
        const decl = ast.nodes.get(decl_idx);
        if (decl.tag == .fn_decl) {
            var buffer: [1]std.zig.Ast.Node.Index = undefined;
            if (ast.fullFnProto(&buffer, decl_idx)) |fn_decl| {
                if (fn_decl.visib_token) |_| {} else {
                    continue; // NOTE: skip if private
                }
                const params = try collectParams(ast, fn_decl);
                const return_type = ast.nodes.get(fn_decl.ast.return_type);

                try functions.append(.{
                    .name = ast.tokenSlice(fn_decl.ast.fn_token + 1),
                    .return_type = try nodeToSlice(ast, return_type),
                    .params = params.items,
                });
            }
        }
    }
    return functions;
}

fn collectParams(ast: *std.zig.Ast, proto: std.zig.Ast.full.FnProto) !std.ArrayList([]const u8) {
    var params = std.ArrayList([]const u8).init(allocator);
    var param_it = proto.iterate(ast);
    while (param_it.next()) |param| {
        const type_node = ast.nodes.get(param.type_expr);
        try params.append(try nodeToSlice(ast, type_node));
    }
    return params;
}

fn nodeToSlice(ast: *std.zig.Ast, node: std.zig.Ast.Node) ![]const u8 {
    switch (node.tag) {
        .identifier, .number_literal => {
            const main_token = ast.tokenSlice(node.main_token);
            return main_token;
        },
        .call_one => {
            const lhs = try nodeToSlice(ast, ast.nodes.get(node.data.lhs));
            const rhs = try nodeToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ lhs, "(", rhs, ")" });
        },
        .call => {
            const lhs = try nodeToSlice(ast, ast.nodes.get(node.data.lhs));
            const extra = ast.extraData(node.data.rhs, std.zig.Ast.Node.SubRange);
            const params = ast.extra_data[extra.start..extra.end];
            var tmp = std.ArrayList([]const u8).init(allocator);
            for (params) |param| {
                try tmp.append(try nodeToSlice(ast, ast.nodes.get(param)));
            }
            const params_str = try std.mem.join(allocator, ", ", tmp.items);
            return try std.mem.concat(allocator, u8, &[_][]const u8{ lhs, "(", params_str, ")" });
        },
        .field_access => {
            const lhs = try nodeToSlice(ast, ast.nodes.get(node.data.lhs));
            const rhs = ast.tokenSlice(node.data.rhs);
            return try std.mem.concat(allocator, u8, &[_][]const u8{ lhs, ".", rhs });
        },
        .ptr_type => {
            const rhs = try nodeToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ "*", rhs });
        },
        .array_type => {
            const lhs = try nodeToSlice(ast, ast.nodes.get(node.data.lhs));
            const rhs = try nodeToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ "[", lhs, "]", rhs });
        },
        .ptr_type_aligned => {
            const rhs = try nodeToSlice(ast, ast.nodes.get(node.data.rhs));
            const main_token = ast.tokenSlice(node.main_token);
            if (std.mem.eql(u8, main_token, "*")) {
                return try std.mem.concat(allocator, u8, &[_][]const u8{ "*", rhs });
            } else {
                return try std.mem.concat(allocator, u8, &[_][]const u8{ "[]", rhs });
            }
        },
        else => |tag| {
            std.debug.print("not implemented type: {}\n", .{tag});
            return error.NotImplemented;
        },
    }
}
