const math = @import("std").math;

pub fn reverseLinear(x: anytype) @TypeOf(x) {
    return 1.0 - x;
}

pub fn easeInSine(x: anytype) @TypeOf(x) {
    return 1.0 - @cos((x * math.pi) / 2.0);
}

pub fn easeOutSine(x: anytype) @TypeOf(x) {
    return @sin((x * math.pi) / 2.0);
}

pub fn easeInOutSine(x: anytype) @TypeOf(x) {
    return -(@cos(math.pi * x) - 1.0) / 2.0;
}

pub fn easeInQuad(x: anytype) @TypeOf(x) {
    return x * x;
}

pub fn easeOutQuad(x: anytype) @TypeOf(x) {
    return 1.0 - (1.0 - x) * (1.0 - x);
}

pub fn easeInOutQuad(x: anytype) @TypeOf(x) {
    if (x < 0.5) {
        return 2.0 * x * x;
    } else {
        return 1.0 - math.pow(@TypeOf(x), -2.0 * x + 2.0, 2.0) / 2.0;
    }
}

pub fn easeInCubic(x: anytype) @TypeOf(x) {
    return x * x * x;
}

pub fn easeOutCubic(x: anytype) @TypeOf(x) {
    return 1.0 - math.pow(@TypeOf(x), 1.0 - x, 3.0);
}

pub fn easeInOutCubic(x: anytype) @TypeOf(x) {
    if (x < 0.5) {
        return 4.0 * x * x * x;
    } else {
        return 1.0 - math.pow(@TypeOf(x), -2.0 * x + 2.0, 3.0) / 2.0;
    }
}

pub fn easeInQuart(x: anytype) @TypeOf(x) {
    return x * x * x * x;
}

pub fn easeOutQuart(x: anytype) @TypeOf(x) {
    return 1.0 - math.pow(@TypeOf(x), 1.0 - x, 4.0);
}

pub fn easeInOutQuart(x: anytype) @TypeOf(x) {
    if (x < 0.5) {
        return 8.0 * x * x * x * x;
    } else {
        return 1.0 - math.pow(@TypeOf(x), -2.0 * x + 2.0, 4.0) / 2.0;
    }
}

pub fn easeInQuint(x: anytype) @TypeOf(x) {
    return x * x * x * x * x;
}

pub fn easeOutQuint(x: anytype) @TypeOf(x) {
    return 1.0 - math.pow(@TypeOf(x), 1.0 - x, 5.0);
}

pub fn easeInOutQuint(x: anytype) @TypeOf(x) {
    if (x < 0.5) {
        return 16.0 * x * x * x * x * x;
    } else {
        return 1.0 - math.pow(@TypeOf(x), -2.0 * x + 2.0, 5.0) / 2.0;
    }
}

pub fn easeInExpo(x: anytype) @TypeOf(x) {
    if (x == 0.0) {
        return x;
    } else {
        return math.pow(@TypeOf(x), 2.0, 10.0 * x - 10.0);
    }
}

pub fn easeOutExpo(x: anytype) @TypeOf(x) {
    if (x == 1.0) {
        return x;
    } else {
        return 1.0 - math.pow(@TypeOf(x), 2.0, -10.0 * x);
    }
}

pub fn easeInOutExpo(x: anytype) @TypeOf(x) {
    if (x == 0 or x == 1) {
        return x;
    } else if (x < 0.5) {
        return math.pow(@TypeOf(x), 2.0, 20.0 * x - 10.0) / 2.0;
    } else {
        return (2.0 - math.pow(@TypeOf(x), 2.0, -20.0 * x + 10.0)) / 2.0;
    }
}

pub fn easeInCirc(x: anytype) @TypeOf(x) {
    return 1.0 - @sqrt(1.0 - x * x);
}

pub fn easeOutCirc(x: anytype) @TypeOf(x) {
    return @sqrt(1.0 - (x - 1.0) * (x - 1.0));
}

pub fn easeInOutCirc(x: anytype) @TypeOf(x) {
    if (x < 0.5) {
        return (1.0 - @sqrt(1.0 - (2.0 * x) * (2.0 * x))) / 2.0;
    } else {
        return (@sqrt(1.0 - math.pow(@TypeOf(x), -2.0 * x + 2.0, 2.0)) + 1) / 2.0;
    }
}

pub fn easeOutElastic(x: anytype) @TypeOf(x) {
    if (x == 0 or x == 1) {
        return x;
    } else {
        return math.pow(@TypeOf(x), 2.0, -10.0 * x) * @sin((x * 10.0 - 0.75) * math.tau / 3.0) + 1.0;
    }
}
