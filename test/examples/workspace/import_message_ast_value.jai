#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);
    add_build_string(#string END
#import "Basic";
#import "Basic";

main :: () {
    // #import "CommentOnly";
    text := "#import \"StringOnly\";";
}
END
    , w);

    import_count := 0;
    while true {
        message := compiler_wait_for_message();
        if !message break;

        if message.kind == .IMPORT {
            imported := cast(*Message_Import) message;
            print("import:%\n", imported.module_name);
            import_count += 1;
        }

        if message.kind == .COMPLETE {
            print("imports:%\n", import_count);
            break;
        }
    }
    compiler_end_intercept(w);
}

main :: () {
}
