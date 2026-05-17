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

min :: (a: $T, b: T, rest: ..T) -> T {
    result := min(a, b);
    for rest if it < result result = it;
    return result;
}

max :: (a: $T, b: T) -> T {
    if a > b return a;
    return b;
}

max :: (a: $T, b: T, rest: ..T) -> T {
    result := max(a, b);
    for rest if it > result result = it;
    return result;
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

Quaternion :: struct {
    x: float;
    y: float;
    z: float;
    w: float;
}

Matrix3 :: struct {
    union {
        coef: [3][3] float;
        v: [3] Vector3;
        struct {
            _11: float; _12: float; _13: float;
            _21: float; _22: float; _23: float;
            _31: float; _32: float; _33: float;
        }
    }
}

Matrix4 :: struct {
    union {
        coef: [4][4] float;
        v: [4] Vector4;
        struct {
            _11: float; _12: float; _13: float; _14: float;
            _21: float; _22: float; _23: float; _24: float;
            _31: float; _32: float; _33: float; _34: float;
            _41: float; _42: float; _43: float; _44: float;
        }
    }
}

Matrix3_Identity :: Matrix3.{_11=1, _22=1, _33=1};
Matrix4_Identity :: Matrix4.{_11=1, _22=1, _33=1, _44=1};

operator + :: (a: Vector2, b: Vector2) -> Vector2 { return Vector2.{x=a.x+b.x, y=a.y+b.y}; }
operator - :: (a: Vector2, b: Vector2) -> Vector2 { return Vector2.{x=a.x-b.x, y=a.y-b.y}; }
operator * :: (a: Vector2, s: float) -> Vector2 #symmetric { return Vector2.{x=a.x*s, y=a.y*s}; }
operator / :: (a: Vector2, s: float) -> Vector2 { return Vector2.{x=a.x/s, y=a.y/s}; }

operator + :: (a: Vector3, b: Vector3) -> Vector3 { return Vector3.{x=a.x+b.x, y=a.y+b.y, z=a.z+b.z}; }
operator - :: (a: Vector3, b: Vector3) -> Vector3 { return Vector3.{x=a.x-b.x, y=a.y-b.y, z=a.z-b.z}; }
operator * :: (a: Vector3, s: float) -> Vector3 #symmetric { return Vector3.{x=a.x*s, y=a.y*s, z=a.z*s}; }
operator / :: (a: Vector3, s: float) -> Vector3 { return Vector3.{x=a.x/s, y=a.y/s, z=a.z/s}; }

operator + :: (a: Vector4, b: Vector4) -> Vector4 { return Vector4.{x=a.x+b.x, y=a.y+b.y, z=a.z+b.z, w=a.w+b.w}; }
operator - :: (a: Vector4, b: Vector4) -> Vector4 { return Vector4.{x=a.x-b.x, y=a.y-b.y, z=a.z-b.z, w=a.w-b.w}; }
operator * :: (a: Vector4, s: float) -> Vector4 #symmetric { return Vector4.{x=a.x*s, y=a.y*s, z=a.z*s, w=a.w*s}; }
operator / :: (a: Vector4, s: float) -> Vector4 { return Vector4.{x=a.x/s, y=a.y/s, z=a.z/s, w=a.w/s}; }

operator + :: (a: Quaternion, b: Quaternion) -> Quaternion { return Quaternion.{x=a.x+b.x, y=a.y+b.y, z=a.z+b.z, w=a.w+b.w}; }
operator - :: (a: Quaternion, b: Quaternion) -> Quaternion { return Quaternion.{x=a.x-b.x, y=a.y-b.y, z=a.z-b.z, w=a.w-b.w}; }
operator * :: (a: Quaternion, s: float) -> Quaternion #symmetric { return Quaternion.{x=a.x*s, y=a.y*s, z=a.z*s, w=a.w*s}; }

dot_product :: (a: Vector2, b: Vector2) -> float {
    return a.x*b.x + a.y*b.y;
}

dot_product :: (a: Vector3, b: Vector3) -> float {
    return a.x*b.x + a.y*b.y + a.z*b.z;
}

dot_product :: (a: Vector4, b: Vector4) -> float {
    return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
}

dot_product :: (a: Quaternion, b: Quaternion) -> float {
    return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
}

cross_product :: (a: Vector3, b: Vector3) -> Vector3 {
    r: Vector3;
    r.x = a.y*b.z - a.z*b.y;
    r.y = a.z*b.x - a.x*b.z;
    r.z = a.x*b.y - a.y*b.x;
    return r;
}

length_squared :: (v: Vector2) -> float { return dot_product(v, v); }
length_squared :: (v: Vector3) -> float { return dot_product(v, v); }
length_squared :: (v: Vector4) -> float { return dot_product(v, v); }
length_squared :: (q: Quaternion) -> float { return dot_product(q, q); }

length :: (v: Vector2) -> float { return cast(float) sqrt(cast(float64) dot_product(v, v)); }
length :: (v: Vector3) -> float { return cast(float) sqrt(cast(float64) dot_product(v, v)); }
length :: (v: Vector4) -> float { return cast(float) sqrt(cast(float64) dot_product(v, v)); }
length :: (q: Quaternion) -> float { return cast(float) sqrt(cast(float64) dot_product(q, q)); }

normalize :: (v: Vector3) -> Vector3 {
    len := length(v);
    if len == 0 return v;
    r: Vector3;
    r.x = v.x / len;
    r.y = v.y / len;
    r.z = v.z / len;
    return r;
}

unit_vector :: (v: Vector3) -> Vector3 { return normalize(v); }

lerp :: (a: float, b: float, t: float) -> float {
    return a + (b - a) * t;
}

lerp :: (a: Vector3, b: Vector3, t: float) -> Vector3 {
    r: Vector3;
    r.x = a.x + (b.x - a.x) * t;
    r.y = a.y + (b.y - a.y) * t;
    r.z = a.z + (b.z - a.z) * t;
    return r;
}

lerp :: (a: Quaternion, b: Quaternion, t: float) -> Quaternion {
    r: Quaternion;
    r.x = a.x + (b.x - a.x) * t;
    r.y = a.y + (b.y - a.y) * t;
    r.z = a.z + (b.z - a.z) * t;
    r.w = a.w + (b.w - a.w) * t;
    return r;
}

slerp :: (a: Quaternion, b: Quaternion, t: float) -> Quaternion {
    d := dot_product(a, b);
    bx := b.x; by := b.y; bz := b.z; bw := b.w;
    if d < 0 { d = -d; bx = -bx; by = -by; bz = -bz; bw = -bw; }
    if d > 0.9995 {
        r: Quaternion;
        r.x = a.x + (bx - a.x) * t;
        r.y = a.y + (by - a.y) * t;
        r.z = a.z + (bz - a.z) * t;
        r.w = a.w + (bw - a.w) * t;
        return r;
    }
    theta_0 := acos(cast(float64) d);
    theta   := theta_0 * cast(float64) t;
    s0 := cast(float) cos(theta) - cast(float) (cast(float64) d * sin(theta) / sin(theta_0));
    s1 := cast(float) (sin(theta) / sin(theta_0));
    r: Quaternion;
    r.x = a.x * s0 + bx * s1;
    r.y = a.y * s0 + by * s1;
    r.z = a.z * s0 + bz * s1;
    r.w = a.w * s0 + bw * s1;
    return r;
}

set_from_axis_and_angle :: (q: *Quaternion, axis: Vector3, angle: float) {
    half := cast(float64) angle * 0.5;
    s := cast(float) sin(half);
    q.x = axis.x * s;
    q.y = axis.y * s;
    q.z = axis.z * s;
    q.w = cast(float) cos(half);
}

get_axis_and_angle :: (q: Quaternion) -> float64, float64, float64, float64 {
    len_sq := cast(float64) (q.x*q.x + q.y*q.y + q.z*q.z);
    angle := 2.0 * atan2(sqrt(len_sq), cast(float64) q.w);
    if len_sq < 0.00001 {
        return 0.0, 0.0, 1.0, angle;
    }
    inv := 1.0 / sqrt(len_sq);
    return cast(float64) q.x * inv, cast(float64) q.y * inv, cast(float64) q.z * inv, angle;
}

sin :: (value: float64) -> float64 #foreign;
sqrt :: (value: float64) -> float64 #foreign;
cos :: (value: float64) -> float64 #foreign;
tan :: (value: float64) -> float64 #foreign;
asin :: (value: float64) -> float64 #foreign;
acos :: (value: float64) -> float64 #foreign;
atan :: (value: float64) -> float64 #foreign;
atan2 :: (y: float64, x: float64) -> float64 #foreign;
pow :: (base: float64, exponent: float64) -> float64 #foreign;
exp :: (value: float64) -> float64 #foreign;
log :: (value: float64) -> float64 #foreign;
floor :: (value: float64) -> float64 #foreign;
ceil :: (value: float64) -> float64 #foreign;
round :: (value: float64) -> float64 #foreign;
