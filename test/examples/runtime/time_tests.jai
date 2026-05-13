compile_time_time_and_calendar_values_are_real :: () {
    expect_compile_output("test/examples/runtime/time_value.jai", "time:true true true true true true true\n");
} @TestProcedure

expression_form_run_calendar_is_materialized :: () {
    expect_program_output("test/examples/runtime/calendar_run_value.jai", "calendar:true true\n");
} @TestProcedure
