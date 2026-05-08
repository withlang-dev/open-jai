// Port of bootstrap/src/Value.zig.

Value_Kind :: enum {
    VOID;
    INT;
    FLOAT;
    BOOL;
    STRING;
}

Value :: struct {
    kind: Value_Kind;
    int_value: int;
    float_value: float;
    bool_value: bool;
    string_value: string;
}

value_void :: () -> Value {
    v: Value;
    v.kind = .VOID;
    return v;
}

