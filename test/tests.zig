const std = @import("std");
const math = std.math;

const hsluv = @import("hsluv");

const MAXDIFF: f64 = 0.0000000001;
const MAXRELDIFF: f64 = 0.000000001;

/// modified from
/// https://randomascii.wordpress.com/2012/02/25/comparing-floating-point-numbers-2012-edition/
fn expectAlmostEqualRelativeAndAbs(a: f64, b: f64) bool {
    // Check if the numbers are really close -- needed
    // when comparing numbers near zero.
    var diff: f64 = math.fabs(a - b);
    if (diff <= MAXDIFF) {
        return true;
    }

    var abs_a = math.fabs(a);
    var abs_b = math.fabs(b);
    var largest: f64 = if (abs_b > abs_a) abs_b else abs_a;

    return diff <= largest * MAXRELDIFF;
}

fn expectTuplesClose(label: []const u8, expected: [3]f64, actual: [3]f64) void {
    var mismatch: bool = false;
    var deltas = [3]f64{ undefined, undefined, undefined };

    for (expected) |ex, i| {
        deltas[i] = math.fabs(ex - actual[i]);
        if (!expectAlmostEqualRelativeAndAbs(ex, actual[i])) {
            mismatch = true;
        }
    }

    if (mismatch) {
        std.debug.warn("MISMATCH {}\n", .{label});
        std.debug.warn(" expected: {}, {}, {}\n", .{ expected[0], expected[1], expected[2] });
        std.debug.warn("   actual: {}, {}, {}\n", .{ actual[0], actual[1], actual[2] });
        std.debug.warn("   deltas: {}, {}, {}\n", .{ deltas[0], deltas[1], expected[2] });
    }

    std.testing.expectEqual(mismatch, false);
}

test "test RGB channel bounds" {
    // TODO: Consider clipping RGB channels instead and testing with 0 error tolerance
    const max_color = 16;
    var r: u16 = 0;
    while (r <= max_color) : (r += 1) {
        var g: u16 = 0;
        while (g <= max_color) : (g += 1) {
            var b: u16 = 0;
            while (b <= max_color) : (b += 1) {
                var sample = [3]f64{ @intToFloat(f64, r) / max_color, @intToFloat(f64, g) / max_color, @intToFloat(f64, b) / max_color };
                var hsluvc = hsluv.rgbToHsluv(sample);
                var hpluv = hsluv.rgbToHpluv(sample);
                var rgbHsluv = hsluv.hsluvToRgb(hsluvc);
                var rgbHpluv = hsluv.hpluvToRgb(hpluv);
                expectTuplesClose("RGB -> HSLuv -> RGB", sample, rgbHsluv);
                expectTuplesClose("RGB -> HPLuv -> RGB", sample, rgbHpluv);

                // test consistency
                const hex = hsluv.rgbToHex(sample);
                std.testing.expectEqual(hex, hsluv.hsluvToHex(hsluv.hexToHsluv(&hex)));
                std.testing.expectEqual(hex, hsluv.hpluvToHex(hsluv.hexToHpluv(&hex)));
            }
        }
    }
}

fn toFloat3(array: std.json.Value) [3]f64 {
    const v0 = switch (array.Array.span()[0]) {
        .Float => |value| value,
        .Integer => |value| @intToFloat(f64, value),
        else => unreachable,
    };
    const v1 = switch (array.Array.span()[1]) {
        .Float => |value| value,
        .Integer => |value| @intToFloat(f64, value),
        else => unreachable,
    };
    const v2 = switch (array.Array.span()[2]) {
        .Float => |value| value,
        .Integer => |value| @intToFloat(f64, value),
        else => unreachable,
    };

    return [3]f64{ v0, v1, v2 };
}

test "test HSLuv snapshot" {
    const file_contents = @embedFile("./snapshot-rev4.json");

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var parser = std.json.Parser.init(allocator, false);
    const tree = try parser.parse(file_contents);

    switch (tree.root) {
        .Object => |object| {
            var itr = object.iterator();
            while (itr.next()) |field| {
                const field_name = field.key;
                const field_rgb = toFloat3(field.value.Object.getValue("rgb").?);
                const field_xyz = toFloat3(field.value.Object.getValue("xyz").?);
                const field_luv = toFloat3(field.value.Object.getValue("luv").?);
                const field_lch = toFloat3(field.value.Object.getValue("lch").?);
                const field_hpluv = toFloat3(field.value.Object.getValue("hpluv").?);
                const field_hsluv = toFloat3(field.value.Object.getValue("hsluv").?);

                // forward functions

                const rgbFromHex = hsluv.hexToRgb(field_name);
                const xyzFromRgb = hsluv.rgbToXyz(field_rgb);
                const luvFromXyz = hsluv.xyzToLuv(field_xyz);
                const lchFromLuv = hsluv.luvToLch(field_luv);
                const hsluvFromLch = hsluv.lchToHsluv(field_lch);
                const hpluvFromLch = hsluv.lchToHpluv(field_lch);
                const hsluvFromHex = hsluv.hexToHsluv(field_name);
                const hpluvFromHex = hsluv.hexToHpluv(field_name);

                expectTuplesClose(field_name, field_rgb, rgbFromHex);
                expectTuplesClose(field_name, field_xyz, xyzFromRgb);
                expectTuplesClose(field_name, field_luv, luvFromXyz);
                expectTuplesClose(field_name, field_lch, lchFromLuv);
                expectTuplesClose(field_name, field_hsluv, hsluvFromLch);
                expectTuplesClose(field_name, field_hpluv, hpluvFromLch);
                expectTuplesClose(field_name, field_hsluv, hsluvFromHex);
                expectTuplesClose(field_name, field_hpluv, hpluvFromHex);

                // backward functions

                const lchFromHsluv = hsluv.hsluvToLch(field_hsluv);
                const lchFromHpluv = hsluv.hpluvToLch(field_hpluv);
                const luvFromLch = hsluv.lchToLuv(field_lch);
                const xyzFromLuv = hsluv.luvToXyz(field_luv);
                const rgbFromXyz = hsluv.xyzToRgb(field_xyz);
                const hexFromRgb = hsluv.rgbToHex(field_rgb);
                const hexFromHsluv = hsluv.hsluvToHex(field_hsluv);
                const hexFromHpluv = hsluv.hpluvToHex(field_hpluv);

                expectTuplesClose("hsluvToLch", field_lch, lchFromHsluv);
                expectTuplesClose("hpluvToLch", field_lch, lchFromHpluv);
                expectTuplesClose("lchToLuv", field_luv, luvFromLch);
                expectTuplesClose("luvToXyz", field_xyz, xyzFromLuv);
                expectTuplesClose("xyzToRgb", field_rgb, rgbFromXyz);
                std.testing.expect(std.ascii.eqlIgnoreCase(field_name, &hexFromRgb));
                std.testing.expect(std.ascii.eqlIgnoreCase(field_name, &hexFromHsluv));
                std.testing.expect(std.ascii.eqlIgnoreCase(field_name, &hexFromHpluv));
            }
        },
        else => unreachable,
    }
}
