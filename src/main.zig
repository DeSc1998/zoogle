const std = @import("std");
const defs = @import("definitions.zig");
const matcher = @import("match.zig");

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

pub const Foo = struct {
    a: u8,
    b: u8,
    c: u8,

    pub const Inner = struct {
        a: u8,
        b: u8,
        c: u8,

        pub fn format(self: Inner, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("a: {}, b: {}, c: {}", .{ self.a, self.b, self.c });
        }
    };

    pub fn format(self: Foo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("a: {}, b: {}, c: {}", .{ self.a, self.b, self.c });
    }
};

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
    var parsed_functions = std.ArrayList(defs.FunctionDef).init(allocator);
    defer parsed_functions.deinit();
    for (files.items) |file| {
        const functions = try defs.collectFunctionsFile(allocator, file, true);
        defer functions.deinit();
        try parsed_functions.appendSlice(functions.items);
    }
    const metrics = try matcher.match(allocator, parsed_functions.items[0], parsed_functions.items);
    defer allocator.free(metrics);
    for (metrics) |m| {
        std.debug.print("value {}: {s}\n", .{ m.value, try m.function.format() });
    }
    for (parsed_functions.items) |*f| {
        defer f.deinit();
    }
}

test "function type" {
    const alloc = std.testing.allocator;
    const source = try alloc.dupeZ(u8, "fn f(i32, _:  _, _: _a) void {}");
    var ast = try std.zig.Ast.parse(alloc, source, .zig);
    defer ast.deinit(alloc);
    const functions = try defs.collectFunctions(alloc, &ast, false);
    defer functions.deinit();
    try std.testing.expect(functions.items.len == 1);
    var f = functions.items[0];
    defer f.deinit();
    std.debug.print("{s}\n", .{try f.format()});
}
