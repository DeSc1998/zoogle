const std = @import("std");

const s = struct { []const u8, []const u8 };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const builder = @import("zig-tree-sitter/build.zig");
    const treesitter = b.dependencyInner("zig-tree-sitter", "zig-tree-sitter", builder, .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "zoogle",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkLibrary(treesitter.artifact("tree-sitter"));
    exe.addModule("tree-sitter", treesitter.module("tree-sitter"));
    const homepath = std.os.getenv("HOME") orelse ".";
    const path = std.fs.path.join(b.allocator, &[_][]const u8{ homepath, ".local/lib" }) catch unreachable;
    exe.addLibraryPath(.{ .path = path });
    exe.linkSystemLibrary("tree-sitter-zig");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
