source_location_fields_are_real_values :: () {
    expect_program_output("test/examples/meta/source_location_value.jai", "23\n");
} @TestProcedure

expression_form_run_source_location_is_materialized :: () {
    expect_program_output("test/examples/meta/source_location_run_value.jai", "run-loc:true true\n");
} @TestProcedure
