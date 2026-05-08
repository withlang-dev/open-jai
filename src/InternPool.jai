// Port of bootstrap/src/InternPool.zig.

Type_Id :: int;

VOID_TYPE :: 0;
BOOL_TYPE :: 1;
S8_TYPE :: 2;
S16_TYPE :: 3;
S32_TYPE :: 4;
S64_TYPE :: 5;
S128_TYPE :: 6;
U8_TYPE :: 7;
U16_TYPE :: 8;
U32_TYPE :: 9;
U64_TYPE :: 10;
U128_TYPE :: 11;
FLOAT32_TYPE :: 12;
FLOAT64_TYPE :: 13;
STRING_TYPE :: 14;
TYPE_TYPE :: 15;
ANY_TYPE :: 16;
VECTOR3_TYPE :: 17;
APOLLO_TIME_TYPE :: 18;
CALENDAR_TYPE :: 19;
TYPE_TABLE_TYPE :: 20;
TYPE_INFO_TYPE :: 21;

Intern_Key_Tag :: enum {
    type_void;
    type_bool;
    type_int;
    type_float;
    type_string;
    type_type;
    type_any;
    type_vector3;
    type_apollo_time;
    type_calendar;
    type_table;
    type_info;
    type_proc;
    type_pointer;
    value_string;
    value_int;
    value_bool;
}

Intern_Key :: struct {
    tag: Intern_Key_Tag;
    signed: bool;
    bits: int;
    index: Type_Id;
    int_value: int;
    bool_value: bool;
}

Intern_Pool :: struct {
    next_type: Type_Id;
    string_count: int;
}

intern_pool_init :: () -> Intern_Pool {
    pool: Intern_Pool;
    pool.next_type = TYPE_INFO_TYPE + 1;
    pool.string_count = 0;
    return pool;
}

intern_pointer_type :: (pool: *Intern_Pool, child: Type_Id) -> Type_Id {
    result := pool.next_type;
    pool.next_type += 1;
    return result;
}

intern_proc_type :: (pool: *Intern_Pool, sig_node: Node_Index) -> Type_Id {
    result := pool.next_type;
    pool.next_type += 1;
    return result;
}

intern_string_value :: (pool: *Intern_Pool, value: string) -> Type_Id {
    result := pool.next_type;
    pool.next_type += 1;
    pool.string_count += 1;
    return result;
}

