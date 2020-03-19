const std = @import("std");
const math = std.math;

pub const Point = struct {
    x: f64,
    y: f64,
};

pub const Line = struct {
    slope: f64,
    intercept: f64,
};

// All angles in radians
pub const Angle = f64;

pub fn intersectLineLine(a: Line, b: Line) Point {
    var x = (a.intercept - b.intercept) / (b.slope - a.slope);
    var y = a.slope * x + a.intercept;
    return Point{ .x = x, .y = y };
}

pub fn distanceFromOrigin(point: Point) f64 {
    return math.sqrt(math.pow(f64, point.x, 2) + math.pow(f64, point.y, 2));
}

pub fn distanceLineFromOrigin(line: Line) f64 {
    // https://en.wikipedia.org/wiki/Distance_from_a_point_to_a_line
    return math.fabs(line.intercept) / math.sqrt(math.pow(f64, line.slope, 2) + 1);
}

pub fn perpendicularThroughPoint(line: Line, point: Point) Line {
    var slope = -1 / line.slope;
    var intercept = point.y - slope * point.x;
    return Line{
        .slope = slope,
        .intercept = intercept,
    };
}

pub fn angleFromOrigin(point: Point) Angle {
    return math.atan2(f64, point.y, point.x);
}

pub fn normalizeAngle(angle: Angle) Angle {
    const m = 2 * math.pi;
    return @rem(((@rem(angle, m)) + m), m); // TODO: Should this be rem or mod?
}

pub fn lengthOfRayUntilIntersect(theta: Angle, line: Line) f64 {
    // theta  -- angle of ray starting at (0, 0)
    // m, b   -- slope and intercept of line
    // x1, y1 -- coordinates of intersection
    // len    -- length of ray until it intersects with line
    //
    // b + m * x1        = y1
    // len              >= 0
    // len * cos(theta)  = x1
    // len * sin(theta)  = y1
    //
    //
    // b + m * (len * cos(theta)) = len * sin(theta)
    // b = len * sin(hrad) - m * len * cos(theta)
    // b = len * (sin(hrad) - m * cos(hrad))
    // len = b / (sin(hrad) - m * cos(hrad))
    return line.intercept / (std.math.sin(theta) - line.slope * std.math.cos(theta));
}
