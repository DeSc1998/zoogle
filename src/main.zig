const std = @import("std");
const defs = @import("definitions.zig");

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

// for testing
fn foo(c: u8) [10]u8 {
    return [_]u8{c} ** 10;
}

// for testing
fn Array(comptime T: type, comptime len: usize) type {
    return [len]T;
}

// for testing
fn bar(c: u8) Array(u8, 10) {
    return [_]u8{c} ** 10;
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

        const functions = try defs.collectFunctions(&ast);
        defer functions.deinit();
        for (functions.items) |f| {
            const params = try std.mem.join(allocator, ", ", f.params);
            defer allocator.free(params);
            std.debug.print("fn {s}({s}) {s}\n", .{ f.name, params, f.return_type });
        }
    }
}

test "function type" {
    const alloc = std.testing.allocator;
    const source = "fn f(_: i32, _:  _) void {}";
    var ast = try std.zig.Ast.parse(alloc, source, .zig);
    defer ast.deinit(alloc);
    const functions = try defs.collectFunctions(&ast);
    defer functions.deinit();
    try std.testing.expect(functions.items.len == 1);
    const f = functions.items[0];
    std.debug.print("fn {s} {s} {s}\n", .{ f.name, f.params, f.return_type });
}
