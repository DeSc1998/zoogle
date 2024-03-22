const std = @import("std");
const tree = @import("tree-sitter");

pub const Tree = tree.Tree;
pub const Node = tree.Node;
pub const Language = tree.Language;
pub const Parser = tree.Parser;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const allocator = arena.allocator();

pub extern fn tree_sitter_zig() tree.TSLanguage;

fn nodetype(node: ?tree.Node) !?[]u8 {
    if (node) |n| {
        return try std.fmt.allocPrint(allocator, "{s}", .{n.type()});
    } else {
        return null;
    }
}

pub const NodeType = enum {
    Identifier,
    Decl,
    FnProto,
    VarDecl,
    ErrorUnionExpr,
    SuffixExpr,
    PrefixTypeOp,
    ParamDeclList,
    ParamDecl,
    ParamType,
    ContainerDecl,
    ContainerDeclType,

    fn toString(self: NodeType) []const u8 {
        return map.get(self) orelse unreachable;
    }

    pub fn eql(comptime self: NodeType, treenode: tree.Node) bool {
        const other = nodetype(treenode) catch return false;
        if (other) |o| {
            return std.mem.eql(u8, NodeType.toString(self), o);
        } else {
            return false;
        }
    }
};

const map = b: {
    const m = std.enums.EnumMap(NodeType, []const u8);
    var m1 = m.init(.{
        .Identifier = "IDENTIFIER",
        .Decl = "Decl",
        .FnProto = "FnProto",
        .VarDecl = "VarDecl",
        .ErrorUnionExpr = "ErrorUnionExpr",
        .SuffixExpr = "SuffixExpr",
        .PrefixTypeOp = "PrefixTypeOp",
        .ParamDeclList = "ParamDeclList",
        .ParamDecl = "ParamDecl",
        .ParamType = "ParamType",
        .ContainerDecl = "ContainerDecl",
        .ContainerDeclType = "ContainerDeclType",
    });

    break :b m1;
};

pub fn expectNodeByType(node: ?tree.Node, comptime self: NodeType) !tree.Node {
    if (node) |n| {
        if (NodeType.eql(self, n)) {
            return n;
        } else {
            // std.log.err("Expected {s} but got {s}", .{ NodeType.toString(self), (nodetype(n) catch unreachable) orelse "null" });
            return error.NodeTypeMismatch;
        }
    } else {
        return error.NodeNotFound;
    }
}

pub fn expectNodeBySlice(node: ?tree.Node, chars: []const u8) !tree.Node {
    if (node) |n| {
        const node_t = try nodetype(n);
        if (std.mem.eql(u8, node_t.?, chars)) {
            return n;
        } else {
            return error.NodeTypeMismatch;
        }
    } else {
        return error.NodeNotFound;
    }
}

pub fn filterDecls(root: ?tree.Node) !std.ArrayList(tree.Node) {
    var decls = std.ArrayList(tree.Node).init(allocator);
    if (root) |n| {
        const child_count = n.child_count();
        for (0..child_count) |i| {
            const child = if (n.child(@truncate(i))) |c| c else continue;
            const n_type = try std.fmt.allocPrint(allocator, "{s}", .{child.type()});
            defer allocator.free(n_type);
            if (std.mem.eql(u8, n_type, NodeType.toString(.Decl))) {
                const node = child.child(0) orelse continue;
                try decls.append(node);
            }
        }
    }
    return decls;
}

pub fn parseFile(file: []const u8) !Tree {
    const lang = tree.Language.from(tree_sitter_zig());
    var parser = try Parser.init(lang);
    defer parser.deinit();
    return try parser.parse_string(file, .UTF8, null);
}

pub fn printTree(node: Node, writer: anytype, indent: usize) !void {
    try writer.writeByteNTimes(' ', indent);
    try writer.print("{s}\n", .{node.type()});
    for (0..node.child_count()) |child_index| {
        const child = if (node.child(@truncate(child_index))) |c| c else continue;
        try printTree(child, writer, indent + 2);
    }
}
