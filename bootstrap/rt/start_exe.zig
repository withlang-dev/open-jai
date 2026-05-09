extern fn __openjai_runtime_init(argc: i32, argv: ?[*]?[*:0]const u8) void;
extern fn __openjai_runtime_fini() void;
extern fn __openjai_user_main() void;
extern fn oj_rt_exit(code: i32) noreturn;

export fn main(argc: i32, argv: ?[*]?[*:0]const u8) i32 {
    __openjai_runtime_init(argc, argv);
    __openjai_user_main();
    __openjai_runtime_fini();
    oj_rt_exit(0);
}
