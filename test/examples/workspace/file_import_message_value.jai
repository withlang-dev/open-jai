#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);
    add_build_file("report_target.jai", w);

    while true {
        message := compiler_wait_for_message();
        if !message break;
        if message.kind == {
            case .FILE;
                file := cast(*Message_File) message;
                print("file:%\n", file.fully_pathed_filename);
            case .IMPORT;
                imported := cast(*Message_Import) message;
                print("import:%:%\n", imported.module_name, imported.fully_pathed_filename);
            case .COMPLETE;
                break;
            case;
        }
    }
    compiler_end_intercept(w);
}

main :: () {
}
