// Port of bootstrap/src/Value.zig.

Value :: struct {
    index: Type_Id;
}

value_init :: (index: Type_Id) -> Value {
    return .{index};
}

value_to_integer :: (value: Value, failed: *bool) -> int {
    failed.* = true;
    return 0;
}

value_to_string :: (value: Value, failed: *bool) -> string {
    failed.* = true;
    return "";
}

