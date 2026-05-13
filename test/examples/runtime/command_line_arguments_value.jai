#import "Basic";

#run {
    args := get_command_line_arguments();
    found := false;
    last_is_sentinel := args.count > 0 && args[args.count - 1] == "openjai-runtime-argv-sentinel";

    for args {
        if it == "openjai-runtime-argv-sentinel" {
            found = true;
        }
    }

    print("argv:% %\n", last_is_sentinel, found);
}

main :: () {}
