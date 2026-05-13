local_module_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/module_import_value.jai", "17\n");
} @TestProcedure

local_module_alias_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/module_alias_import_value.jai", "17\n");
} @TestProcedure

local_module_scope_file_keeps_private_helpers_private :: () {
    expect_compile_failure("test/examples/modules/module_private_import_value.jai", "unresolved identifier 'hidden_module_value'");
} @TestProcedure

commented_module_imports_do_not_load_source :: () {
    expect_compile_failure("test/examples/modules/module_comment_import_value.jai", "unresolved identifier 'comment_only_value'");
} @TestProcedure

duplicate_module_imports_load_source_once :: () {
    expect_compile_output("test/examples/modules/module_duplicate_import_value.jai", "duplicate module loaded\n");
} @TestProcedure

process_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/process_module_import_value.jai", "process:0 process-module  false\n");
} @TestProcedure

file_utilities_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/file_utilities_module_import_value.jai", "file-utilities:true true copied\n");
} @TestProcedure

build_cpp_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/build_cpp_module_import_value.jai", "build-cpp:true\n");
} @TestProcedure

posix_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/posix_module_import_value.jai", "posix:0 1 2\n");
} @TestProcedure

system_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/system_module_import_value.jai", "system:true true\n");
} @TestProcedure

program_print_module_import_loads_real_source_from_local_alias :: () {
    expect_compile_output("test/examples/modules/program_print_local_alias_value.jai", "program-print:value :: 42\n");
} @TestProcedure

testscope_module_import_loads_real_source :: () {
    expect_program_output("test/examples/modules/testscope_module_import_value.jai", "42\n");
} @TestProcedure

check_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/check_module_import_value.jai", "check:true\n");
} @TestProcedure

debug_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/debug_module_import_value.jai", "debug:direct\n");
} @TestProcedure

debug_module_alias_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/debug_module_alias_import_value.jai", "debug:alias\n");
} @TestProcedure

windows_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/windows_module_import_value.jai", "windows:0 -10 -11 -12\n");
} @TestProcedure

machine_x64_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/machine_x64_module_import_value.jai", "machine-x64:false false\n");
} @TestProcedure

windows_resources_module_import_loads_real_source_from_local_alias :: () {
    expect_compile_output("test/examples/modules/windows_resources_module_import_value.jai", "windows-resources:0\n");
} @TestProcedure

mail_module_import_loads_real_source_from_local_alias :: () {
    expect_compile_output("test/examples/modules/mail_module_import_value.jai", "mail:true false\n");
} @TestProcedure

sort_module_import_loads_real_source_and_runtime_sorting_works :: () {
    expect_compile_output("test/examples/modules/sort_module_import_value.jai", "sort:[-272, -5, 3.14, 5, 8, 17, 42, 108] [\"brown\", \"dog\", \"fox\", \"jumped\", \"lazy\", \"over\", \"quick\", \"the\", \"the\"]\n");
} @TestProcedure

hash_table_module_import_loads_real_source_and_finds_values :: () {
    expect_compile_output("test/examples/modules/hash_table_module_import_value.jai", "hash:true 521-1234 false false \n");
} @TestProcedure

input_module_import_loads_real_source_and_event_defaults_work :: () {
    expect_compile_output("test/examples/modules/input_module_import_value.jai", "input:1 1 true true true 640 480 0 0 false\n");
} @TestProcedure

window_creation_module_import_loads_real_source_and_tracks_dimensions :: () {
    expect_compile_output("test/examples/modules/window_creation_module_import_value.jai", "window:1 2 800 600 320 240 0 0\n");
} @TestProcedure

simp_module_import_loads_real_source_and_tracks_render_state :: () {
    expect_compile_output("test/examples/modules/simp_module_import_value.jai", "simp:true 1 32 32 true 24 42 false 1 1\n");
} @TestProcedure

gl_module_import_loads_real_source_and_tracks_state :: () {
    expect_compile_output("test/examples/modules/gl_module_import_value.jai", "gl:true 1 OpenJai OpenJai GL 1.0 1 2 3 640 true\n");
} @TestProcedure

sound_modules_import_real_source_and_track_streams :: () {
    expect_compile_output("test/examples/modules/sound_module_import_value.jai", "sound:1 true true true true 1 4 2\n");
} @TestProcedure

bindings_generator_module_import_loads_real_source :: () {
    expect_compile_output("test/examples/modules/bindings_generator_module_import_value.jai", "bindings:true true 31 1 1 1 1 2 true\n");
} @TestProcedure
