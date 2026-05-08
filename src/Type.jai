// Port of bootstrap/src/Type.zig.

Type :: struct {
    index: Type_Id;
}

type_init :: (index: Type_Id) -> Type {
    return .{index};
}

type_void :: () -> Type {
    return type_init(VOID_TYPE);
}

type_bool :: () -> Type {
    return type_init(BOOL_TYPE);
}

type_string :: () -> Type {
    return type_init(STRING_TYPE);
}

type_apollo_time :: () -> Type {
    return type_init(APOLLO_TIME_TYPE);
}

type_calendar :: () -> Type {
    return type_init(CALENDAR_TYPE);
}

type_any :: () -> Type {
    return type_init(ANY_TYPE);
}

type_is_void :: (t: Type) -> bool {
    return t.index == VOID_TYPE;
}

type_is_bool :: (t: Type) -> bool {
    return t.index == BOOL_TYPE;
}

type_is_string :: (t: Type) -> bool {
    return t.index == STRING_TYPE;
}

type_is_integer :: (t: Type) -> bool {
    return t.index >= S8_TYPE && t.index <= U128_TYPE;
}

type_is_any :: (t: Type) -> bool {
    return t.index == ANY_TYPE;
}

type_is_pointer :: (t: Type) -> bool {
    return t.index > TYPE_INFO_TYPE;
}

type_is_float :: (t: Type) -> bool {
    return t.index == FLOAT32_TYPE || t.index == FLOAT64_TYPE;
}

type_size_of :: (t: Type) -> int {
    if t.index == VOID_TYPE return 0;
    if t.index == BOOL_TYPE return 1;
    if t.index == S8_TYPE || t.index == U8_TYPE return 1;
    if t.index == S16_TYPE || t.index == U16_TYPE return 2;
    if t.index == S32_TYPE || t.index == U32_TYPE || t.index == FLOAT32_TYPE return 4;
    if t.index == S64_TYPE || t.index == U64_TYPE || t.index == FLOAT64_TYPE return 8;
    if t.index == S128_TYPE || t.index == U128_TYPE return 16;
    if t.index == STRING_TYPE return 16;
    if t.index == ANY_TYPE return 16;
    if t.index == VECTOR3_TYPE return 12;
    if t.index == APOLLO_TIME_TYPE return 16;
    if t.index == CALENDAR_TYPE return 8;
    return 8;
}

