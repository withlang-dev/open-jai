#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);
    compiler_set_workspace_status(.FAILED);

    while true {
        message := compiler_wait_for_message();
        if !message break;

        if message.kind == .PHASE {
            phase := cast(*Message_Phase) message;
            if phase.phase == .POST_WRITE_EXECUTABLE {
                print("post failed:% linker:%\n", phase.executable_write_failed, phase.linker_exit_code);
            }
        }

        if message.kind == .COMPLETE {
            complete := cast(*Message_Complete) message;
            print("complete error:%\n", complete.error_code);
            break;
        }
    }

    compiler_end_intercept(w);
}

main :: () {}
