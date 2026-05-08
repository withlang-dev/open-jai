// Port of bootstrap/src/Type.zig.

Type :: struct {
    index: Type_Id;
}

type_void :: () -> Type {
    return .{0};
}

type_bool :: () -> Type {
    return .{1};
}

type_s64 :: () -> Type {
    return .{2};
}

type_string :: () -> Type {
    return .{3};
}

type_any :: () -> Type {
    return .{4};
}

type_is_string :: (t: Type) -> bool {
    return t.index == 3;
}

