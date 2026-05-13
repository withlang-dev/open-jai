pool_module_is_loaded_from_source_and_updates_pool_state :: () {
    expect_program_output_contains(
        "examples/34/34.3_pool.jai",
        "pool memblock size 65536 bytes.\npool has 65400 bytes left.\npool contains now 136 bytes.\n");
} @TestProcedure

flat_pool_module_is_loaded_from_source_and_allocates_memory :: () {
    expect_program_output_contains(
        "examples/34/34.6_flat_pool.jai",
        "(2) 'thing' is:");
} @TestProcedure

allocator_modules_report_ownership_through_real_allocator_procs :: () {
    expect_program_output_contains(
        "examples/21/21.3_allocators_check.jai",
        "[true] says \"modules/Pool\"\n[false] says \"modules/Flat_Pool\"\n[false] says \"rpmalloc 1.4.4\"");
} @TestProcedure
