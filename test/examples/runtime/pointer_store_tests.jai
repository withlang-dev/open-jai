compile_time_pointer_stores_update_addressed_locals :: () {
    expect_compile_output("test/examples/runtime/pointer_store_value.jai", "ptrstore:7 11 true\n");
} @TestProcedure
