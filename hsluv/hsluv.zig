// Human-friendly HSL conversion utility class.
//
// The math for most of this module was taken from:
//
//  * http://www.easyrgb.com
//  * http://www.brucelindbloom.com
//  * Wikipedia
//
// All numbers below taken from math/bounds.wxm wxMaxima file. We use 17
// digits of decimal precision to export the numbers, effectively exporting
// them as double precision IEEE 754 floats.
//
// "If an IEEE 754 double precision is converted to a decimal string with at
// least 17 significant digits and then converted back to double, then the
// final number must match the original"
//
// Source: https://en.wikipedia.org/wiki/Double-precision_floating-point_format
// =======
//

const std = @import("std");

pub const geo = @import("./src/geometry.zig");
pub const color_picker = @import("./src/color_picker.zig");
pub const contrast = @import("./src/contrast.zig");

const m = [3][3]f64{
    [3]f64{ 3.240969941904521, -1.537383177570093, -0.498610760293 },
    [3]f64{ -0.96924363628087, 1.87596750150772, 0.041555057407175 },
    [3]f64{ 0.055630079696993, -0.20397695888897, 1.056971514242878 },
};

const minv = [3][3]f64{
    [3]f64{ 0.41239079926595, 0.35758433938387, 0.18048078840183 },
    [3]f64{ 0.21263900587151, 0.71516867876775, 0.072192315360733 },
    [3]f64{ 0.019330818715591, 0.11919477979462, 0.95053215224966 },
};

const refY = 1.0;

const refU = 0.19783000664283;
const refV = 0.46831999493879;

// CIE LUV constants
const kappa = 903.2962962;
const epsilon = 0.0088564516;

const hexChars = "0123456789abcdef";

/// For a given lightness, return a list of 6 lines in slope-intercept
/// form that represent the bounds in CIELUV, stepping over which will
/// push a value out of the RGB gamut
pub fn getBounds(L: f64) [3 * 2]geo.Line {
    var result = [3 * 2]geo.Line{
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
    };

    var sub1: f64 = std.math.pow(f64, L + 16, 3) / 1560896;
    var sub2: f64 = if (sub1 > epsilon) sub1 else (L / kappa);

    for (m) |c, i| {
        var m1: f64 = c[0];
        var m2: f64 = c[1];
        var m3: f64 = c[2];

        var t: u2 = 0;
        while (t < 2) : (t += 1) {
            var top1: f64 = (284517 * m1 - 94839 * m3) * sub2;
            var top2: f64 = (838422 * m3 + 769860 * m2 + 731718 * m1) * L * sub2 - 769860 * @intToFloat(f64, t) * L;
            var bottom: f64 = (632260 * m3 - 126452 * m2) * sub2 + 126452 * @intToFloat(f64, t);

            result[2 * i + t] = geo.Line{
                .slope = top1 / bottom,
                .intercept = top2 / bottom,
            };
        }
    }

    return result;
}

/// For given lightness, returns the maximum chroma. Keeping the chroma value
/// below this number will ensure that for any hue, the color is within the RGB
/// gamut.
pub fn maxSafeChromaForL(L: f64) f64 {
    const bounds = getBounds(L);
    var min: f64 = std.math.POSITIVE_INFINITY;

    for (bounds) |bound| {
        const length: f64 = geo.distanceLineFromOrigin(bound);
        min = std.math.min(min, length);
    }

    return min;
}

pub fn maxChromaForLH(L: f64, H: f64) f64 {
    const hrad: f64 = H / 360 * std.math.pi * 2.0;
    //std.debug.warn("hrad={}\n", .{hrad});
    const bounds = getBounds(L);
    var min: f64 = std.math.inf_f64;

    var min_i: usize = 0;
    for (bounds) |bound, i| {
        const length: f64 = geo.lengthOfRayUntilIntersect(hrad, bound);
        if (length >= 0) {
            if (length < min) {
                min_i = i;
            }
            min = std.math.min(min, length);
        }
    }

    //std.debug.warn("minBound={}\n", .{bounds[min_i]});
    return min;
}

fn dotProduct(a: [3]f64, b: [3]f64) f64 {
    var sum: f64 = 0;

    for (a) |x, i| {
        sum += a[i] * b[i];
    }

    return sum;
}

// Used for rgb conversions
fn fromLinear(c: f64) f64 {
    if (c <= 0.0031308) {
        return 12.92 * c;
    } else {
        return 1.055 * std.math.pow(f64, c, 1 / 2.4) - 0.055;
    }
}

fn toLinear(c: f64) f64 {
    if (c > 0.04045) {
        return std.math.pow(f64, (c + 0.055) / (1 + 0.055), 2.4);
    } else {
        return c / 12.92;
    }
}

/// XYZ coordinates are ranging in [0;1] and RGB coordinates in [0;1] range.
/// @param tuple An array containing the color's X,Y and Z values.
/// @return An array containing the resulting color's red, green and blue.
pub fn xyzToRgb(tuple: [3]f64) [3]f64 {
    return [3]f64{
        fromLinear(dotProduct(m[0], tuple)),
        fromLinear(dotProduct(m[1], tuple)),
        fromLinear(dotProduct(m[2], tuple)),
    };
}

/// RGB coordinates are ranging in [0;1] and XYZ coordinates in [0;1].
/// @param tuple An array containing the color's R,G,B values.
/// @return An array containing the resulting color's XYZ coordinates.
pub fn rgbToXyz(tuple: [3]f64) [3]f64 {
    var rgbl = [3]f64{
        toLinear(tuple[0]),
        toLinear(tuple[1]),
        toLinear(tuple[2]),
    };

    return [3]f64{
        dotProduct(minv[0], rgbl),
        dotProduct(minv[1], rgbl),
        dotProduct(minv[2], rgbl),
    };
}

/// http://en.wikipedia.org/wiki/CIELUV
/// In these formulas, Yn refers to the reference white point. We are using
/// illuminant D65, so Yn (see refY in Maxima file) equals 1. The formula is
/// simplified accordingly.
pub fn yToL(Y: f64) f64 {
    if (Y <= epsilon) {
        return (Y / refY) * kappa;
    } else {
        return 116 * std.math.pow(f64, Y / refY, 1.0 / 3.0) - 16;
    }
}

pub fn lToY(L: f64) f64 {
    if (L <= 8) {
        return refY * L / kappa;
    } else {
        return refY * std.math.pow(f64, (L + 16) / 116, 3);
    }
}

/// XYZ coordinates are ranging in [0;1].
/// @param tuple An array containing the color's X,Y,Z values.
/// @return An array containing the resulting color's LUV coordinates.
pub fn xyzToLuv(tuple: [3]f64) [3]f64 {
    var X: f64 = tuple[0];
    var Y: f64 = tuple[1];
    var Z: f64 = tuple[2];

    // This divider fix avoids a crash on Python (divide by zero except.)
    var divider: f64 = (X + (15 * Y) + (3 * Z));
    var varU: f64 = 4 * X;
    var varV: f64 = 9 * Y;

    if (divider != 0) {
        varU /= divider;
        varV /= divider;
    } else {
        varU = std.math.nan_f64;
        varV = std.math.nan_f64;
    }

    var L: f64 = yToL(Y);

    if (L == 0) {
        return [3]f64{ 0, 0, 0 };
    }

    const U: f64 = 13 * L * (varU - refU);
    const V: f64 = 13 * L * (varV - refV);

    return [3]f64{ L, U, V };
}

/// XYZ coordinates are ranging in [0;1].
/// @param tuple An array containing the color's L,U,V values.
/// @return An array containing the resulting color's XYZ coordinates.
pub fn luvToXyz(tuple: [3]f64) [3]f64 {
    //std.debug.warn("luv2xyz={} {} {}\n", .{ tuple[0], tuple[1], tuple[2] });
    const L: f64 = tuple[0];
    const U: f64 = tuple[1];
    const V: f64 = tuple[2];

    if (L == 0) {
        return [3]f64{ 0, 0, 0 };
    }

    const varU: f64 = U / (13 * L) + refU;
    const varV: f64 = V / (13 * L) + refV;

    const Y: f64 = lToY(L);
    const X: f64 = 0 - (9 * Y * varU) / ((varU - 4) * varV - varU * varV);
    const Z: f64 = (9 * Y - (15 * varV * Y) - (varV * X)) / (3 * varV);

    return [3]f64{ X, Y, Z };
}

/// @param tuple An array containing the color's L,U,V values.
/// @return An array containing the resulting color's LCH coordinates.
pub fn luvToLch(tuple: [3]f64) [3]f64 {
    var L: f64 = tuple[0];
    var U: f64 = tuple[1];
    var V: f64 = tuple[2];

    var C: f64 = std.math.sqrt(U * U + V * V);
    var H: f64 = 0.0;

    // Greys: disambiguate hue
    if (C >= 0.00000001) {
        var Hrad: f64 = std.math.atan2(f64, V, U);
        H = (Hrad * 180.0) / std.math.pi;

        if (H < 0) {
            H = 360 + H;
        }
    }

    return [3]f64{ L, C, H };
}

/// @param tuple An array containing the color's L,C,H values.
/// @return An array containing the resulting color's LUV coordinates.
pub fn lchToLuv(tuple: [3]f64) [3]f64 {
    //std.debug.warn("lchToLuv={} {} {}\n", .{ tuple[0], tuple[1], tuple[2] });
    var L: f64 = tuple[0];
    var C: f64 = tuple[1];
    var H: f64 = tuple[2];

    var Hrad: f64 = 2.0 * std.math.pi * H / 360.0;
    var U: f64 = std.math.cos(Hrad) * C;
    var V: f64 = std.math.sin(Hrad) * C;

    return [3]f64{ L, U, V };
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100].
/// @param tuple An array containing the color's H,S,L values in HSLuv color space.
/// @return An array containing the resulting color's LCH coordinates.
pub fn hsluvToLch(tuple: [3]f64) [3]f64 {
    //std.debug.warn("hsluv2Lch={} {} {}\n", .{ tuple[0], tuple[1], tuple[2] });
    var H: f64 = tuple[0];
    var S: f64 = tuple[1];
    var L: f64 = tuple[2];

    // White and black: disambiguate chroma
    if (L > 99.9999999) {
        return [3]f64{ 100, 0, H };
    }

    if (L < 0.00000001) {
        return [3]f64{ 0, 0, H };
    }

    var max: f64 = maxChromaForLH(L, H);
    //std.debug.warn("MAX={}\n", .{max});
    var C: f64 = max / 100 * S;

    return [3]f64{ L, C, H };
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100].
/// @param tuple An array containing the color's LCH values.
/// @return An array containing the resulting color's HSL coordinates in HSLuv color space.
pub fn lchToHsluv(tuple: [3]f64) [3]f64 {
    var L: f64 = tuple[0];
    var C: f64 = tuple[1];
    var H: f64 = tuple[2];

    // White and black: disambiguate chroma
    if (L > 99.9999999) {
        return [3]f64{ H, 0, 100 };
    }

    if (L < 0.00000001) {
        return [3]f64{ H, 0, 0 };
    }

    var max: f64 = maxChromaForLH(L, H);
    var S: f64 = C / max * 100;

    return [3]f64{ H, S, L };
}

/// HSLuv values are in [0;360], [0;100] and [0;100].
/// @param tuple An array containing the color's H,S,L values in HPLuv (pastel variant) color space.
/// @return An array containing the resulting color's LCH coordinates.
pub fn hpluvToLch(tuple: [3]f64) [3]f64 {
    var H: f64 = tuple[0];
    var S: f64 = tuple[1];
    var L: f64 = tuple[2];

    if (L > 99.9999999) {
        return [3]f64{ 100, 0, H };
    }

    if (L < 0.00000001) {
        return [3]f64{ 0, 0, H };
    }

    var max: f64 = maxSafeChromaForL(L);
    var C: f64 = max / 100 * S;

    return [3]f64{ L, C, H };
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100].
/// @param tuple An array containing the color's LCH values.
/// @return An array containing the resulting color's HSL coordinates in HPLuv (pastel variant) color space.
pub fn lchToHpluv(tuple: [3]f64) [3]f64 {
    var L: f64 = tuple[0];
    var C: f64 = tuple[1];
    var H: f64 = tuple[2];

    // White and black: disambiguate saturation
    if (L > 99.9999999) {
        return [3]f64{ H, 0, 100 };
    }

    if (L < 0.00000001) {
        return [3]f64{ H, 0, 0 };
    }

    var max: f64 = maxSafeChromaForL(L);
    var S: f64 = C / max * 100;

    return [3]f64{ H, S, L };
}

/// RGB values are ranging in [0;1].
/// @param tuple An array containing the color's RGB values.
/// @return A string containing a `#RRGGBB` representation of given color.
pub fn rgbToHex(tuple: [3]f64) []u8 {
    var h: []u8 = "#";

    for (tuple) |x| {
        var chan: f64 = x;
        var c = std.math.round(chan * 255);
        var digit2 = c % 16;
        var digit1 = Std.int((c - digit2) / 16);
        h += hexChars.charAt(digit1) + hexChars.charAt(digit2);
    }

    return h;
}

/// RGB values are ranging in [0;1].
/// @param hex A `#RRGGBB` representation of a color.
/// @return An array containing the color's RGB values.
pub fn hexToRgb(hex: []u8) [3]f64 {
    hex = hex.toLowerCase();
    var ret: [3]f64 = undefined ** 3;
    for (ret) |r| {
        var digit1 = hexChars.indexOf(hex.charAt(i * 2 + 1));
        var digit2 = hexChars.indexOf(hex.charAt(i * 2 + 2));
        var n = digit1 * 16 + digit2;
        r = (n / 255.0);
    }
    return ret;
}

/// RGB values are ranging in [0;1].
/// @param tuple An array containing the color's LCH values.
/// @return An array containing the resulting color's RGB coordinates.
pub fn lchToRgb(tuple: [3]f64) [3]f64 {
    return xyzToRgb(luvToXyz(lchToLuv(tuple)));
}

/// RGB values are ranging in [0;1].
/// @param tuple An array containing the color's RGB values.
/// @return An array containing the resulting color's LCH coordinates.
pub fn rgbToLch(tuple: [3]f64) [3]f64 {
    return luvToLch(xyzToLuv(rgbToXyz(tuple)));
}

// RGB <--> HPLuv

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param tuple An array containing the color's HSL values in HSLuv color space.
/// @return An array containing the resulting color's RGB coordinates.
pub fn hsluvToRgb(tuple: [3]f64) [3]f64 {
    return lchToRgb(hsluvToLch(tuple));
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param tuple An array containing the color's RGB coordinates.
/// @return An array containing the resulting color's HSL coordinates in HSLuv color space.
pub fn rgbToHsluv(tuple: [3]f64) [3]f64 {
    return lchToHsluv(rgbToLch(tuple));
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param tuple An array containing the color's HSL values in HPLuv (pastel variant) color space.
/// @return An array containing the resulting color's RGB coordinates.
pub fn hpluvToRgb(tuple: [3]f64) [3]f64 {
    return lchToRgb(hpluvToLch(tuple));
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param tuple An array containing the color's RGB coordinates.
/// @return An array containing the resulting color's HSL coordinates in HPLuv (pastel variant) color space.
pub fn rgbToHpluv(tuple: [3]f64) [3]f64 {
    return lchToHpluv(rgbToLch(tuple));
}

// Hex

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param tuple An array containing the color's HSL values in HSLuv color space.
/// @return A string containing a `#RRGGBB` representation of given color.
pub fn hsluvToHex(tuple: [3]f64) []u8 {
    return rgbToHex(hsluvToRgb(tuple));
}

pub fn hpluvToHex(tuple: [3]f64) []u8 {
    return rgbToHex(hpluvToRgb(tuple));
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param tuple An array containing the color's HSL values in HPLuv (pastel variant) color space.
/// @return An array containing the color's HSL values in HSLuv color space.
pub fn hexToHsluv(s: []u8) [3]f64 {
    return rgbToHsluv(hexToRgb(s));
}

/// HSLuv values are ranging in [0;360], [0;100] and [0;100] and RGB in [0;1].
/// @param hex A `#RRGGBB` representation of a color.
/// @return An array containing the color's HSL values in HPLuv (pastel variant) color space.
pub fn hexToHpluv(s: []u8) [3]f64 {
    return rgbToHpluv(hexToRgb(s));
}
