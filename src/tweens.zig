const math = @import("std").math;

pub fn reverseLinear(T: type, x: T) T {
    return 1.0 - x;
}

pub fn easeInSine(T: type, x: T) T {
    return 1.0 - @cos((x * math.pi) / 2.0);
}

pub fn easeOutSine(T: type, x: T) T {
    return @sin((x * math.pi) / 2.0);
}

pub fn easeInOutSine(T: type, x: T) T {
    return -(@cos(math.pi * x) - 1.0) / 2.0;
}

pub fn easeInQuad(T: type, x: T) T {
    return x * x;
}

pub fn easeOutQuad(T: type, x: T) T {
    return 1.0 - (1.0 - x) * (1.0 - x);
}

pub fn easeInOutQuad(T: type, x: T) T {
    if (x < 0.5) {
        return 2.0 * x * x;
    } else {
        return 1.0 - math.pow(T, -2.0 * x + 2.0, 2.0) / 2.0;
    }
}

pub fn easeInCubic(T: type, x: T) T {
    return x * x * x;
}

pub fn easeOutCubic(T: type, x: T) T {
    return 1.0 - math.pow(T, 1.0 - x, 3.0);
}

pub fn easeInOutCubic(T: type, x: T) T {
    if (x < 0.5) {
        return 4.0 * x * x * x;
    } else {
        return 1.0 - math.pow(T, -2.0 * x + 2.0, 3.0) / 2.0;
    }
}

pub fn easeInQuart(T: type, x: T) T {
    return x * x * x * x;
}

pub fn easeOutQuart(T: type, x: T) T {
    return 1.0 - math.pow(T, 1.0 - x, 4.0);
}

pub fn easeInOutQuart(T: type, x: T) T {
    if (x < 0.5) {
        return 8.0 * x * x * x * x;
    } else {
        return 1.0 - math.pow(T, -2.0 * x + 2.0, 4.0) / 2.0;
    }
}

pub fn easeInQuint(T: type, x: T) T {
    return x * x * x * x * x;
}

pub fn easeOutQuint(T: type, x: T) T {
    return 1.0 - math.pow(T, 1.0 - x, 5.0);
}

pub fn easeInOutQuint(T: type, x: T) T {
    if (x < 0.5) {
        return 16.0 * x * x * x * x * x;
    } else {
        return 1.0 - math.pow(T, -2.0 * x + 2.0, 5.0) / 2.0;
    }
}

pub fn easeInExpo(T: type, x: T) T {
    if (x == 0.0) {
        return x;
    } else {
        return math.pow(T, 2.0, 10.0 * x - 10.0);
    }
}

pub fn easeOutExpo(T: type, x: T) T {
    if (x == 1.0) {
        return x;
    } else {
        return 1.0 - math.pow(T, 2.0, -10.0 * x);
    }
}

pub fn easeInOutExpo(T: type, x: T) T {
    if (x == 0 or x == 1) {
        return x;
    } else if (x < 0.5) {
        return math.pow(T, 2.0, 20.0 * x - 10.0) / 2.0;
    } else {
        return (2.0 - math.pow(T, 2.0, -20.0 * x + 10.0)) / 2.0;
    }
}

pub fn easeInCirc(T: type, x: T) T {
    return 1.0 - @sqrt(1.0 - x * x);
}

pub fn easeOutCirc(T: type, x: T) T {
    return @sqrt(1.0 - (x - 1.0) * (x - 1.0));
}

pub fn easeInOutCirc(T: type, x: T) T {
    if (x < 0.5) {
        return (1.0 - @sqrt(1.0 - (2.0 * x) * (2.0 * x))) / 2.0;
    } else {
        return (@sqrt(1.0 - math.pow(T, -2.0 * x + 2.0, 2.0)) + 1) / 2.0;
    }
}
