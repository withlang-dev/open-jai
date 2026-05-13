#import "Basic";
#import "Compiler";

make_options :: () -> Build_Options {
    w := compiler_create_workspace();
    options := get_build_options(w);
    options.output_executable_name = "snapshot-app";
    options.output_path = "./out/build-options-snapshot";
    options.stack_trace = false;
    options.backtrace_on_crash = .OFF;
    return options;
}

OPTIONS :: #run make_options();

#run {
    print("snapshot:% % % %\n",
        OPTIONS.output_executable_name,
        OPTIONS.output_path,
        OPTIONS.stack_trace,
        OPTIONS.backtrace_on_crash);
}

main :: () {}
