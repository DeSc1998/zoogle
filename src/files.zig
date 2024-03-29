const std = @import("std");

pub fn filesOfDir(alloc: std.mem.Allocator, iterDir: std.fs.IterableDir) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(alloc);
    var iter = iterDir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const path = try alloc.dupe(u8, try iterDir.dir.realpathAlloc(alloc, entry.name));
            defer alloc.free(path);
            try result.append(try alloc.dupe(u8, path));
        } else if (entry.kind == .directory) {
            var sub = try filesOfDir(alloc, try iterDir.dir.makeOpenPathIterable(entry.name, .{}));
            defer sub.deinit();
            try result.appendSlice(sub.items);
        }
    }
    return result;
}

pub fn filterZigFiles(alloc: std.mem.Allocator, files: std.ArrayList([]const u8)) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(alloc);
    for (files.items) |file| {
        if (std.mem.endsWith(u8, file, ".zig")) {
            try result.append(file);
        }
    }
    return result;
}
