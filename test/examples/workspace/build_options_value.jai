#import "Basic";
#import "Compiler";

round_trip_options :: (options: Build_Options) -> Build_Options {
    return options;
}

option_executable_name :: (options: Build_Options) -> string {
    return options.output_executable_name;
}

validate_build_options :: () -> int {
    w := compiler_create_workspace();
    options := get_build_options(w);

    options.backend = .LLVM;
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "openjai_program";
    options.output_path = "./out/test-build-options";
    options.stack_trace = false;
    options.backtrace_on_crash = .OFF;
    options.array_bounds_check = .ON;
    options.cast_bounds_check = .FATAL;
    options.null_pointer_check = .ON;
    options.enable_bytecode_inliner = true;
    options.runtime_storageless_type_info = true;

    import_path: [..] string;
    array_add(*import_path, ..options.import_path);
    array_add(*import_path, "local_modules");
    options.import_path = import_path;
    set_build_options(options, w);

    stored := get_build_options(w);
    assert(stored.output_executable_name == "openjai_program");
    assert(stored.output_path == "./out/test-build-options");
    assert(stored.import_path.count == 2);
    assert(stored.import_path[1] == "local_modules");

    options.output_path = "./out/should-not-alias";
    stored_again := get_build_options(w);
    assert(stored_again.output_path == "./out/test-build-options");

    set_optimization(*stored_again, Optimization_Type.OPTIMIZED);
    assert(stored_again.stack_trace == false);
    assert(stored_again.backtrace_on_crash == "OFF");
    assert(stored_again.array_bounds_check == "OFF");
    assert(stored_again.cast_bounds_check == "OFF");
    assert(stored_again.null_pointer_check == "OFF");
    assert(stored_again.enable_bytecode_inliner == true);

    set_optimization(*stored_again, Optimization_Type.DEBUG, true);
    assert(stored_again.stack_trace == true);
    assert(stored_again.backtrace_on_crash == "ON");
    assert(stored_again.array_bounds_check == "ON");
    assert(stored_again.cast_bounds_check == "NONFATAL");
    assert(stored_again.null_pointer_check == "ON");
    assert(stored_again.enable_bytecode_inliner == false);

    assert(w == 3);
    assert(options.backend == "LLVM");
    assert(options.output_type == "EXECUTABLE");
    assert(options.output_executable_name == "openjai_program");
    assert(options.output_path == "./out/should-not-alias");
    assert(options.stack_trace == false);
    assert(options.backtrace_on_crash == "OFF");
    assert(options.array_bounds_check == "ON");
    assert(options.cast_bounds_check == "FATAL");
    assert(options.null_pointer_check == "ON");
    assert(options.enable_bytecode_inliner == true);
    assert(options.runtime_storageless_type_info == true);
    assert(options.import_path.count == 2);
    assert(options.import_path[0] == "modules");
    assert(options.import_path[1] == "local_modules");
    assert(option_executable_name(options) == "openjai_program");

    round_tripped := round_trip_options(options);
    assert(round_tripped.output_path == "./out/should-not-alias");
    assert(round_tripped.import_path.count == 2);
    assert(round_tripped.import_path[1] == "local_modules");

    return 12345;
}

SUMMARY :: #run validate_build_options();

main :: () {
    print("%\n", SUMMARY);
}
