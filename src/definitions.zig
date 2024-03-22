const std = @import("std");
const tree = @import("tree.zig");

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

    fn attachStructName(self: *FunctionDef, name: []const u8) !void {
        const tmp = try std.mem.join(self.alloc, ".", &[_][]const u8{ name, self.name });
        self.alloc.free(self.name);
        self.name = tmp;
    }
};

pub fn collectFunctionsFile(alloc: std.mem.Allocator, file: []const u8, skip_private: bool) !std.ArrayList(FunctionDef) {
    const tmp = try std.fs.cwd().readFileAlloc(alloc, file, std.math.maxInt(usize));
    var t = try tree.parseFile(tmp);
    return collectFunctions(alloc, &t, tmp, skip_private);
}

pub fn collectFunctions(alloc: std.mem.Allocator, t: *tree.Tree, source: []const u8, skip_private: bool) !std.ArrayList(FunctionDef) {
    defer t.deinit();
    defer alloc.free(source);
    var functions = std.ArrayList(FunctionDef).init(alloc);
    const decls = try tree.filterDecls(t.root());
    for (decls.items) |decl| {
        if (tree.NodeType.eql(.FnProto, decl)) {
            if (skip_private and is_private(decl)) continue;
            const func = try collectFunction(alloc, source, decl);
            try functions.append(func);
        } else if (tree.NodeType.eql(.VarDecl, decl)) {
            if (skip_private and is_private(decl)) continue;
            if (is_struct(decl) or is_enum(decl) or is_union(decl)) {
                const struct_funcs = try collectFunctionsFromStruct(alloc, decl, source, skip_private);
                defer struct_funcs.deinit();
                try functions.appendSlice(struct_funcs.items);
            }
        }
    }
    return functions;
}

fn is_private(decl: tree.Node) bool {
    const parent = tree.expectNodeByType(decl.parent(), .Decl) catch unreachable;
    _ = tree.expectNodeBySlice(parent.prev_sibling(), "pub") catch |err| {
        if (err == error.NodeNotFound) return true;
        if (err == error.NodeTypeMismatch) return true;
        return false;
    };
    return false;
}

fn is_struct_impl(decl: tree.Node, chars: []const u8) bool {
    const expr_node = tree.expectNodeByType(decl.child(decl.child_count() - 2), .ErrorUnionExpr) catch return false;
    const suffix_node = tree.expectNodeByType(expr_node.child(0), .SuffixExpr) catch return false;
    const container_decl = tree.expectNodeByType(suffix_node.child(0), .ContainerDecl) catch return false;
    const container_decl_type = tree.expectNodeByType(container_decl.child(0), .ContainerDeclType) catch return false;
    _ = tree.expectNodeBySlice(container_decl_type.child(0), chars) catch return false;
    return true;
}

fn is_struct(decl: tree.Node) bool {
    return is_struct_impl(decl, "struct");
}

fn is_union(decl: tree.Node) bool {
    return is_struct_impl(decl, "union");
}

fn is_enum(decl: tree.Node) bool {
    return is_struct_impl(decl, "enum");
}

fn collectFunctionsFromStruct(
    alloc: std.mem.Allocator,
    node: tree.Node,
    source: []const u8,
    skip_private: bool,
) !std.ArrayList(FunctionDef) {
    var functions = std.ArrayList(FunctionDef).init(alloc);
    const struct_name = try tree.expectNodeByType(node.child(1), .Identifier);
    const struct_node = try tree.expectNodeByType(node.child(3), .ErrorUnionExpr);
    const suffix_node = try tree.expectNodeByType(struct_node.child(0), .SuffixExpr);
    const container_decl = try tree.expectNodeByType(suffix_node.child(0), .ContainerDecl);
    const struct_members = try tree.filterDecls(container_decl);
    defer struct_members.deinit();
    for (struct_members.items) |member| {
        if (tree.NodeType.eql(.FnProto, member)) {
            if (skip_private and is_private(member)) continue;
            var func = try collectFunction(alloc, source, member);
            try func.attachStructName(try nodeToSlice(alloc, source, struct_name));
            try functions.append(func);
        }
    }
    return functions;
}

fn collectFunction(alloc: std.mem.Allocator, source: []const u8, decl: tree.Node) !FunctionDef {
    _ = try tree.expectNodeByType(decl, .FnProto);
    const name = try tree.expectNodeByType(decl.child(1), .Identifier);
    const params = try collectParams(alloc, source, decl.child(2));
    const return_type = try collectReturnType(alloc, source, decl.child(3));
    return FunctionDef{
        .alloc = alloc,
        .name = try nodeToSlice(alloc, source, name),
        .return_type = return_type,
        .params = params,
    };
}

fn collectParams(alloc: std.mem.Allocator, source: []const u8, paramNode: ?tree.Node) !std.ArrayList([]const u8) {
    var params = std.ArrayList([]const u8).init(alloc);
    if (paramNode) |p| {
        _ = try tree.expectNodeByType(p, .ParamDeclList);
        const child_count = p.child_count();
        for (1..child_count - 1) |childIndex| {
            const node = p.child(@truncate(childIndex));
            const type_node = try collectParam(alloc, source, node) orelse continue;
            try params.append(type_node);
        }
    }
    return params;
}

fn collectParam(alloc: std.mem.Allocator, source: []const u8, paramNode: ?tree.Node) !?[]const u8 {
    if (paramNode) |p| {
        _ = tree.expectNodeByType(p, .ParamDecl) catch return null;
        for (0..p.child_count()) |childIndex| {
            const node = p.child(@truncate(childIndex));
            if (tree.NodeType.eql(.ParamType, node.?)) {
                return try nodeToSlice(alloc, source, node.?);
            }
        }
    } else {
        return error.NodeNotFound;
    }
    return null;
}

fn collectReturnType(alloc: std.mem.Allocator, source: []const u8, returnNode: ?tree.Node) ![]const u8 {
    if (returnNode) |r| {
        if (tree.NodeType.eql(.ErrorUnionExpr, r)) {
            return try nodeToSlice(alloc, source, r);
        } else if (tree.NodeType.eql(.PrefixTypeOp, r)) {
            const end = traverseReturnType(alloc, source, r) catch return error.NodeNotFound;
            return try alloc.dupe(u8, source[r.start_byte()..end]);
        } else {
            _ = try tree.expectNodeBySlice(r, "!");
            const next = r.next_sibling() orelse return error.NodeNotFound;
            const end = traverseReturnType(alloc, source, next) catch return error.NodeNotFound;
            return try alloc.dupe(u8, source[r.start_byte()..end]);
        }
    } else {
        return error.NodeNotFound;
    }
}

fn traverseReturnType(alloc: std.mem.Allocator, source: []const u8, returnNode: ?tree.Node) !usize {
    if (returnNode) |r| {
        if (tree.NodeType.eql(.PrefixTypeOp, r)) {
            return traverseReturnType(alloc, source, r.next_sibling());
        } else return r.end_byte();
    } else {
        return error.NodeNotFound;
    }
}

fn nodeToSlice(alloc: std.mem.Allocator, source: []const u8, node: ?tree.Node) ![]const u8 {
    if (node) |n| {
        const start = n.start_byte();
        const end = n.end_byte();
        const n_slice = source[start..end];
        return try alloc.dupe(u8, n_slice);
    } else {
        return error.NodeNotFound;
    }
}
