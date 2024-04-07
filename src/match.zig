const std = @import("std");
const defs = @import("definitions.zig");

pub const MatchMetric = struct {
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

fn eqlCaseInsensitive(target: u8, candidat: u8) bool {
    return std.ascii.toLower(target) == std.ascii.toLower(candidat);
}

fn matchLoosely(target: []const u8, candidat: []const u8) i32 {
    var current: usize = 0;
    var matchvalue: i32 = 0;
    for (candidat) |c| {
        if (current >= target.len) {
            break;
        }
        if (eqlCaseInsensitive(c, target[current])) {
            current += 1;
            matchvalue += 3;
        }
    }
    matchvalue -= @as(i32, @intCast((target.len - current) * 2));
    return matchvalue;
}

fn matchLooselyReversed(target: []const u8, candidat: []const u8) i32 {
    var currentTarget: usize = 0;
    var currentCandidat: usize = 0;
    var matchvalue: i32 = 0;
    while (currentCandidat < candidat.len and currentTarget < target.len) {
        const charTarget = target[target.len - currentTarget - 1];
        const charCandidat = candidat[candidat.len - currentCandidat - 1];
        if (eqlCaseInsensitive(charTarget, charCandidat)) {
            currentTarget += 1;
            matchvalue += 3;
        }
        currentCandidat += 1;
    }
    matchvalue -= @as(i32, @intCast((candidat.len - currentTarget) * 2));
    return matchvalue;
}

fn matchMetric(target: defs.FunctionDef, candidat: defs.FunctionDef) i32 {
    const matchName = matchLoosely(target.name, candidat.name);
    const matchReturn = matchLooselyReversed(target.return_type, candidat.return_type);
    const diff: i128 = @as(i128, target.params.items.len) - @as(i128, candidat.params.items.len);
    var matchParams = if (std.math.absInt(diff)) |d| @as(i32, @truncate(d)) * -50 else |_| 0;
    if (diff == 0) {
        for (target.params.items, candidat.params.items) |t, c| {
            matchParams += matchLooselyReversed(t, c);
        }
    } else if (diff > 0) {
        var i: usize = 0;
        while (i < candidat.params.items.len) : (i += 1) {
            matchParams += matchLooselyReversed(target.params.items[i], candidat.params.items[i]);
        }
    } else {
        var i: usize = 0;
        while (i < target.params.items.len) : (i += 1) {
            matchParams += matchLooselyReversed(target.params.items[i], candidat.params.items[i]);
        }
    }
    return matchName + matchParams + matchReturn;
}
