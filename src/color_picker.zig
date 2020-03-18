const hsluv = @import("hsluv");
const geo = @import("geometry");

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
    var closest_index_2: ?*Line = null;
    var closest_line_distance: f64 = std.math.positive_infinity;

    for (lines) |line, i| {
        const d = geo.distanceLineFromOrigin(line);
        if (d < closest_line_distance) {
            closest_line_distance = d;
            closest_index_2 = i;
        }
    }

    const starting_angle = blk: {
        const closest_line = lines[closest_index_2];
        const perpendicular_line = Line{ .slope = 0 - (1 / closest_line.slope), .intercept = 0.0 };
        const intersection_point = geo.intersectLineLine(closest_line, perpendicular_line);
        break :blk geo.angleFromOrigin(intersection_point);
    };

    var intersections = []Intersections;

    const num_lines = lines.len;
    var i1 = 0;
    while (i1 < num_lines - 1) : (i1 += 1) {
        var i2 = i1 + 1;
        while (i2 < num_lines) : (i2 += 1) {
            const intersection_point = geo.intersectLineLine(lines[i1], lines[i2]);
            const intersection_point_angle = geo.angleFromOrigin(intersection_point);
            const relative_angle = intersection_point_angle - starting_angle;
            intersections.push(Intersection{
                .line1 = i1,
                .line2 = i2,
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

    var next_index_2;
    var current_intersection;
    var intersection_point_distance;

    var currenct_index_2 = closest_index_2;

    var outer_circle_radius: f64 = 0.0;
    for (intersections) |intersection| {
        current_intersection = intersection;
        next_index_2 = null;
        if (current_intersection.line1 == currenct_index_2) {
            next_index_2 = current_intersection.line2;
        } else if (current_intersection.line2 == currenct_index_2) {
            next_index_2 = current_intersection.line1;
        }
        if (next_index_2 != null) {
            currenct_index_2 = next_index_2;

            ordered_lines.push(lines[next_index_2]);
            ordered_vertices.push(current_intersection.intersection_point);
            ordered_angles.push(current_intersection.intersection_point_angle);

            intersection_point_distance = geo.distanceFromOrigin(current_intersection.intersection_point);
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
    var smallest_relative_angle = Math.PI * 2;
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
