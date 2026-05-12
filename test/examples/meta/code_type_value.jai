#import "Basic";
#import "Compiler";

print_caller_code_type :: (code: Code) #expand {
    type_name :: #run type_to_string(code.type);
    print("caller type: %\n", type_name);
}

#run {
    integer_code :: #code 41 + 1;
    string_code :: #code "hello";

    print("integer code type: %\n", type_to_string(integer_code.type));
    print("string code type: %\n", type_to_string(string_code.type));
}

main :: () {
    print_caller_code_type(3.25);
}
