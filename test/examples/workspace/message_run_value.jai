#import "Basic";
#import "Compiler";

first_message :: () -> Message {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);
    message := compiler_wait_for_message();
    compiler_end_intercept(w);
    return message;
}

MESSAGE :: #run first_message();

#run {
    print("message:%:%\n", MESSAGE.kind, MESSAGE.workspace);
}

main :: () {}
