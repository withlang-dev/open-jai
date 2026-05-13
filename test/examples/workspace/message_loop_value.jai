#import "Basic";
#import "Compiler";

message_kind :: (message: Message) -> string {
    return message.kind;
}

#run {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);

    while true {
        message := compiler_wait_for_message();
        if !message break;

        print("%:%\n", message_kind(message), message.workspace);

        if message.kind == .PHASE {
            phase := cast(*Message_Phase) message;
            print("phase:%\n", phase.phase);
        }

        if message.kind == .TYPECHECKED {
            typechecked := cast(*Message_Typechecked) message;
            print("checked:%\n", typechecked.all.count);
        }

        if message.kind == .COMPLETE break;
    }

    compiler_end_intercept(w);
}

main :: () {}
