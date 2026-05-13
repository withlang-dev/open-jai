#import "Basic";
#import "Compiler";

#run {
    options := get_build_options();
    found := false;
    for options.compile_time_command_line {
        if it == "openjai-command-line-sentinel" {
            found = true;
        }
    }
    print("found:%\n", found);
}

main :: () {
}
