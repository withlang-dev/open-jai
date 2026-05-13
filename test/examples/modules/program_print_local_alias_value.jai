#import "Basic";
#import "Compiler";

render_code :: (code: Code) -> string {
    PP :: #import "Program_Print";
    root := compiler_get_nodes(code);
    builder: String_Builder;
    PP.print_expression(*builder, root);
    return builder_to_string(*builder);
}

#run {
    code :: #code value :: 42;
    rendered := render_code(code);
    print("program-print:%\n", rendered);
}

main :: () {}
