const std = @import("std");
const defs = @import("definitions.zig");
const matcher = @import("match.zig");
const files = @import("files.zig");
const input = @import("input.zig");

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

}

    }

pub fn main() !void {
    const args = try collectArgs();
    if (args.items.len < 2) {
        std.debug.print("usage: zoogle <input>\n", .{});
        return error.NotEnoughArgs;
    }
    const in = try input.parse(allocator, args.items[1]);
    const srcFiles = try files.filesOfDir(allocator, try std.fs.cwd().openIterableDir("src", .{}));
    defer srcFiles.deinit();
    const fs = try files.filterZigFiles(allocator, srcFiles);
    defer fs.deinit();
    var parsed_functions = std.ArrayList(defs.FunctionDef).init(allocator);
    defer parsed_functions.deinit();
    for (fs.items) |file| {
        const functions = try defs.collectFunctionsFile(allocator, file, true);
        defer functions.deinit();
        try parsed_functions.appendSlice(functions.items);
    }
    const metrics = try matcher.match(allocator, in, parsed_functions.items);
    std.mem.sort(matcher.MatchMetric, metrics, {}, struct {
        fn lessThan(_: void, a: matcher.MatchMetric, b: matcher.MatchMetric) bool {
            return a.value > b.value;
        }
    }.lessThan);
    defer allocator.free(metrics);
    for (metrics[0..5]) |m| {
        std.debug.print("{s}\n", .{try m.function.format()});
    }
    for (parsed_functions.items) |*f| {
        f.deinit();
    }
}

test "function type" {
    const alloc = std.testing.allocator;
    const source = "fn f(i32, _, _a) void";
    var def = try input.parse(alloc, source);
    defer def.deinit();
    std.debug.print("{s}\n", .{try def.format()});
    try std.testing.expect(def.params.items.len == 2);
}
