#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace();
    options := get_build_options(w);
    options.output_executable_name = "custom-app";
    options.use_custom_link_command = true;
    set_build_options(options, w);

    compiler_begin_intercept(w);

    while true {
        message := compiler_wait_for_message();
        if !message break;

        if message.kind == .PHASE {
            phase := cast(*Message_Phase) message;
            if phase.phase == .READY_FOR_CUSTOM_LINK_COMMAND {
                print("ready:%\n", phase.executable_name);
                compiler_custom_link_command_is_complete();
            } else if phase.phase == .POST_WRITE_EXECUTABLE {
                print("post:%\n", phase.executable_name);
            }
        }

        if message.kind == .COMPLETE {
            complete := cast(*Message_Complete) message;
            print("complete:% error:%\n", complete.executable_name, complete.error_code);
            break;
        }
    }

    compiler_end_intercept(w);
}

main :: () {}
