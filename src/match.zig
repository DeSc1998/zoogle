const std = @import("std");
const defs = @import("definitions.zig");

const MatchMetric = struct {
    function: defs.FunctionDef,
    value: i32,
};

pub fn match(alloc: std.mem.Allocator, target: defs.FunctionDef, candidats: []defs.FunctionDef) ![]MatchMetric {
    var metrics = try alloc.alloc(MatchMetric, candidats.len);
    for (candidats, 0..) |candidat, i| {
        metrics[i] = .{
            .function = candidat,
            .value = matchMetric(target, candidat),
        };
    }
    return metrics;
}

fn matchMetric(target: defs.FunctionDef, candidat: defs.FunctionDef) i32 {
    if (std.mem.containsAtLeast(u8, candidat.name, 1, target.name)) {
        return 10;
    }
    return 0;
}
