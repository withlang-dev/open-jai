#import "Basic";
#import "Compiler";

#run {
    w := compiler_create_workspace();
    compiler_begin_intercept(w);
    add_build_file(tprint("%/report_target.jai", #filepath), w);

    while true {
        message := compiler_wait_for_message();
        if !message break;

        if message.kind == .TYPECHECKED {
            typechecked := cast(*Message_Typechecked) message;
            for decl: typechecked.declarations {
                expr := decl.expression;
                if equal(expr.name, "reported") {
                    compiler_report("declaration was reported\n", make_location(expr));
                }
            }
        }

        if message.kind == .COMPLETE break;
    }

    compiler_end_intercept(w);
}

main :: () {}
