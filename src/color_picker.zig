const std = @import("std");
const hsluv = @import("../hsluv.zig");
const geo = @import("./geometry.zig");

pub const PickerGeometry = struct {
    var lines: []Line;
    // Ordered such that 1st vertex is interection between first and
    // second line, 2nd vertex between second and third line etc.
    var vertices: []Point;
    // Angles from origin to corresponding vertex
    var angles: []Angle;
    // Smallest circle with center at origin such that polygon fits inside
    var outer_circle_radius: f64;
    // Largest circle with center at origin such that it fits inside polygon
    var inner_circle_radius: f64;
};

const Intersection = struct {
    line1: geo.Line,
    line2: geo.Line,
    intersection_point: geo.Point,
    intersection_point_angle: f64,
    relative_angle: f64,
};
pub fn intersectionCompare(a: Intersection, b: Intersection) Bool {
    if (a.relative_angle > b.relative_angle) {
        return 1;
    } else {
        return -1;
    }
}

pub fn getPickerGeometry(lightness: f64) PickerGeometry {
    // Array of lines
    var lines = hsluv.getBounds(lightness);

    // Find the line closest to origin
    var closest_line_opt: ?*const geo.Line = null;
    var closest_line_distance = std.math.inf_f64;

    for (lines) |line, i| {
        const d = geo.distanceLineFromOrigin(line);
        if (d < closest_line_distance) {
            closest_line_distance = d;
            closest_line_opt = &line;
        }
    }
    std.debug.assert(closest_line_opt != null);
    const closest_line = closest_line_opt.?;

    const starting_angle = blk: {
        const perpendicular_line = geo.Line{ .slope = 0 - (1 / closest_line.slope), .intercept = 0.0 };
        const intersection_point = geo.intersectLineLine(closest_line.*, perpendicular_line);
        break :blk geo.angleFromOrigin(intersection_point);
    };

    var intersections = []geo.Point;

    const num_lines = lines.len;
    var i = 0;
    while (i < num_lines - 1) : (i += 1) {
        var j = i + 1;
        while (j < num_lines) : (j += 1) {
            const intersection_point = geo.intersectLineLine(lines[i], lines[j]);
            const intersection_point_angle = geo.angleFromOrigin(intersection_point);
            const relative_angle = intersection_point_angle - starting_angle;
            intersections.push(Intersection{
                .line1 = i,
                .line2 = j,
                .intersection_point = intersection_point,
                .intersection_point_angle = intersection_point_angle,
                .relative_angle = geo.normalizeAngle(intersection_point_angle - starting_angle),
            });
        }
    }

    intersections.sort();

    var ordered_lines = []geo.Line;
    var ordered_vertices = []geo.Point;
    var ordered_angles = []f64;

    var currenct_index_2 = closest_line;

    var outer_circle_radius: f64 = 0.0;
    for (intersections) |intersection| {
        var next_index: ?geo.Line = if (intersection.line1 == currenct_index_2)
            intersection.line2
        else if (intersection.line2 == currenct_index_2)
            intersection.line1
        else
            null;

        if (next_index) |next| {
            currenct_index_2 = next;

            ordered_lines.push(lines[next]);
            ordered_vertices.push(intersection.intersection_point);
            ordered_angles.push(intersection.intersection_point_angle);

            const intersection_point_distance = geo.distanceFromOrigin(intersection.intersection_point);
            if (intersection_point_distance > outer_circle_radius) {
                outer_circle_radius = intersection_point_distance;
            }
        }
    }

    return PickerGeometry{
        .lines = ordered_lines,
        .vertices = ordered_vertices,
        .angles = ordered_angles,
        .outer_circle_radius = outer_circle_radius,
        .inner_circle_radius = closest_line_distance,
    };
}

pub fn closestPoint(geometry: PickerGeometry, point: Point) Point {
    // In order to find the closest line we use the point's angle
    const angle_from_origin = geo.angleFromOrigin(point);
    const num_vertices = geometry.vertices.length;
    var smallest_relative_angle = math.pi * 2;
    var index1 = 0;

    for (geometry.angles) |gang, i| {
        var relative_angle = geo.normalizeAngle(gang - angle_from_origin);
        if (relative_angle < smallest_relative_angle) {
            smallest_relative_angle = relative_angle;
            index1 = i;
        }
    }

    const index2 = (index1 - 1 + num_vertices) % num_vertices;
    const closest_line = geometry.lines[index2];

    // Provided point is within the polygon
    if (geo.distanceFromOrigin(point) < geo.lengthOfRayUntilIntersect(angle_from_origin, closest_line)) {
        return point;
    }

    const perpendicular_line = geo.perpendicularThroughPoint(closest_line, point);
    const intersection_point = geo.intersectLineLine(closest_line, perpendicular_line);

    const bound1 = geometry.vertices[index1];
    const bound2 = geometry.vertices[index2];
    const upper_bound: Point;
    const lower_bound: Point;

    if (bound1.x > bound2.x) {
        upper_bound = bound1;
        lower_bound = bound2;
    } else {
        upper_bound = bound2;
        lower_bound = bound1;
    }

    return if (intersection_point.x > upper_bound.x)
        upper_bound
    else if (intersection_point.x < lower_bound.x)
        lower_bound
    else
        intersection_point;
}
