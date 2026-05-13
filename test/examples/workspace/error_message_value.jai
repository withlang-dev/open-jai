#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);
    add_build_string(#string END
main :: () {
    x := ;
}
END
    , w);

    while true {
        message := compiler_wait_for_message();
        if !message break;
        if message.kind == {
            case .ERROR;
                print("error:%\n", message.workspace);
            case .COMPLETE;
                complete := cast(*Message_Complete) message;
                print("complete:%\n", complete.error_code);
                break;
            case;
        }
    }
    compiler_end_intercept(w);
}

main :: () {
}
