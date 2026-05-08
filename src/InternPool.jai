// Port of bootstrap/src/InternPool.zig.

Type_Id :: int;

Well_Known_Types :: struct {
    void_type: Type_Id;
    bool_type: Type_Id;
    s64_type: Type_Id;
    string_type: Type_Id;
    any_type: Type_Id;
}

well_known_types :: () -> Well_Known_Types {
    wk: Well_Known_Types;
    wk.void_type = 0;
    wk.bool_type = 1;
    wk.s64_type = 2;
    wk.string_type = 3;
    wk.any_type = 4;
    return wk;
}

Intern_Pool :: struct {
    next_type: Type_Id;
}

intern_pool_init :: () -> Intern_Pool {
    pool: Intern_Pool;
    pool.next_type = 5;
    return pool;
}

