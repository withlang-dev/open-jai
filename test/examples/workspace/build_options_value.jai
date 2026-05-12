#import "Basic";
#import "Compiler";

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

    assert(w == 3);
    assert(options.backend == "LLVM");
    assert(options.output_type == "EXECUTABLE");
    assert(options.output_executable_name == "openjai_program");
    assert(options.output_path == "./out/test-build-options");
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

    return 12345;
}

SUMMARY :: #run validate_build_options();

main :: () {
    print("%\n", SUMMARY);
}
