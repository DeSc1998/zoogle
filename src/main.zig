const std = @import("std");

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

fn collectArgs() !std.ArrayList([]const u8) {
    var args = std.ArrayList([]const u8).init(allocator);
    var it = std.process.args();
    while (it.next()) |arg| {
        try args.append(arg);
    }
    return args;
}

const FunctionDef = struct {
    name: []const u8,
    return_type: []const u8,
    params: []const []const u8,
};

fn collectFunctions(ast: *std.zig.Ast) !std.ArrayList(FunctionDef) {
    var functions = std.ArrayList(FunctionDef).init(allocator);
    for (ast.rootDecls()) |decl_idx| {
        const decl = ast.nodes.get(decl_idx);
        if (decl.tag == .fn_decl) {
            var buffer: [1]std.zig.Ast.Node.Index = undefined;
            if (ast.fullFnProto(&buffer, decl_idx)) |fn_decl| {
                const params = try collectParams(ast, fn_decl);
                const return_type = ast.nodes.get(fn_decl.ast.return_type);

                try functions.append(.{
                    .name = ast.tokenSlice(fn_decl.ast.fn_token + 1),
                    .return_type = try typeindexToSlice(ast, (return_type)),
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
        try params.append(try typeindexToSlice(ast, type_node));
    }
    return params;
}

fn typeindexToSlice(ast: *std.zig.Ast, node: std.zig.Ast.Node) ![]const u8 {
    const Node = std.zig.Ast.Node;
    _ = Node;
    switch (node.tag) {
        .identifier => {
            return ast.tokenSlice(node.main_token);
        },
        .call_one => {
            const lhs = try typeindexToSlice(ast, ast.nodes.get(node.data.lhs));
            const rhs = try typeindexToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ lhs, "(", rhs, ")" });
        },
        .field_access => {
            const lhs = try typeindexToSlice(ast, ast.nodes.get(node.data.lhs));
            const rhs = ast.tokenSlice(node.data.rhs);
            //const rhs = try typeindexToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ lhs, ".", rhs });
        },
        .number_literal => {
            return try std.fmt.allocPrint(allocator, "{}", .{node.main_token});
        },
        .ptr_type => {
            const rhs = try typeindexToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ "*", rhs });
        },
        .array_type => {
            const lhs = try typeindexToSlice(ast, ast.nodes.get(node.data.lhs));
            const rhs = try typeindexToSlice(ast, ast.nodes.get(node.data.rhs));
            return try std.mem.concat(allocator, u8, &[_][]const u8{ "[", lhs, "]", rhs });
        },
        .ptr_type_aligned => {
            const rhs = try typeindexToSlice(ast, ast.nodes.get(node.data.rhs));
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

pub fn main() !void {
    const args = try collectArgs();
    var files = std.ArrayList([]const u8).init(allocator);
    defer files.deinit();
    var i: usize = 0;
    while (i < args.items.len) : (i += 1) {
        if (std.mem.endsWith(u8, args.items[i], ".zig")) {
            try files.append(args.items[i]);
        }
    }
    for (files.items) |file| {
        const tmp = try std.fs.cwd().readFileAlloc(allocator, file, std.math.maxInt(usize));
        const source = try allocator.dupeZ(u8, tmp);
        defer allocator.free(tmp);
        defer allocator.free(source);

        var ast = try std.zig.Ast.parse(allocator, source, .zig);
        defer ast.deinit(allocator);

        const functions = try collectFunctions(&ast);
        defer functions.deinit();
        for (functions.items) |f| {
            std.debug.print("fn {s} {s} {s}\n", .{ f.name, f.params, f.return_type });
        }
    }
}
