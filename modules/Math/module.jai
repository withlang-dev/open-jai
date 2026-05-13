#scope_export;

PI :: 3.14159265358979323846;
TAU :: 6.28318530717958647692;

Vector2 :: struct {
    x: float;
    y: float;
}

Vector3 :: struct {
    x: float;
    y: float;
    z: float;
}

Vector4 :: struct {
    x: float;
    y: float;
    z: float;
    w: float;
}

make_vector2 :: (x: float, y: float) -> Vector2 {
    return Vector2.{x, y};
}

make_vector3 :: (x: float, y: float, z: float) -> Vector3 {
    return Vector3.{x, y, z};
}

make_vector4 :: (x: float, y: float, z: float, w: float) -> Vector4 {
    return Vector4.{x, y, z, w};
}

min :: (a: $T, b: T) -> T {
    if a < b return a;
    return b;
}

max :: (a: $T, b: T) -> T {
    if a > b return a;
    return b;
}

clamp :: (value: $T, low: T, high: T) -> T {
    if value < low return low;
    if value > high return high;
    return value;
}

abs :: (value: int) -> int {
    if value < 0 return -value;
    return value;
}

abs :: (value: s64) -> s64 {
    if value < 0 return -value;
    return value;
}

abs :: (value: float) -> float {
    if value < 0 return -value;
    return value;
}

abs :: (value: float64) -> float64 {
    if value < 0 return -value;
    return value;
}

sin :: (value: float64) -> float64 #foreign;
sqrt :: (value: float64) -> float64 #foreign;
cos :: (value: float64) -> float64 #foreign;
