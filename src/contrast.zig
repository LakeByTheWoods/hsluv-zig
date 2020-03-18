const hsluv = @import("hsluv");

pub const W3C_CONTRAST_TEXT = 4.5;
pub const W3C_CONTRAST_LARGE_TEXT = 3;

pub fn contrastRatio(L1: f64, L2: f64) f64 {
    // https://www.w3.org/TR/WCAG20-TECHS/G18.html#G18-procedure
    const Y1 = hsluv.lToY(L1);
    const Y2 = hsluv.lToY(L2);

    const lighterY = std.math.max(Y1, Y2);
    const darkerY = std.math.min(Y1, Y2);
    return (lighterY + 0.05) / (darkerY + 0.05);
}

/// Gets the minimum relative luminance of the lighter color so that they satisfy
///   the given contrast ratio.
/// NB: This differs from the haxe refernce. The reference assumes darkerL is 0
pub fn lighterMinL(r: f64, darkerL: f64) f64 {
    const darkerY = hsluv.lToY(darkerL);
    return hsluv.yToL((darkerY + 0.05) * r - 0.05);
}

/// What is the maximum lightness of the darker color that satisfies the given
///   contrast ratio.
pub fn darkerMaxL(r: f64, lighterL: f64) f64 {
    const lighterY = hsluv.lToY(lighterL);
    const maxY = (20 * lighterY - r + 1) / (20 * r);
    return hsluv.yToL(maxY);
}
