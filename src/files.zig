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

pub fn stdFiles(alloc: std.mem.Allocator, version: []const u8) !std.ArrayList([]const u8) {
    const stdPath = findStdFromZigup(alloc, version) catch "/usr/lib/zig/std";
    var dir = try std.fs.openDirAbsolute(stdPath, .{});
    defer dir.close();
    const files = filesOfDir(alloc, dir.makeOpenPathIterable(".", .{}));
    return files;
}

fn findStdFromZigup(alloc: std.mem.Allocator, version: []const u8) ![]const u8 {
    if (!isZigupinstalled()) {
        return error.ZigupNotInstalled;
    }
    const home = std.os.getenv("HOME") orelse return error.HomeEnvNotSet;
    const zig = try std.fs.path.join(alloc, &[_][]const u8{ home, "zig", version, "files/lib/std" });
    defer alloc.free(zig);

    if (std.fs.accessAbsolute(zig, .{})) |_| {
        return zig;
    } else |_| {
        return error.DirectoryNotFound;
    }
}

fn isZigupinstalled() bool {
    const binDir = std.fs.openDirAbsolute("/usr/bin", .{}) catch return false; // TODO: only works on linux
    defer binDir.close();
    binDir.access("zigup", .{}) catch return false;
    return true;
}
