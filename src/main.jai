#import "Basic";

#load "support.jai";
#load "Token.jai";
#load "diagnostics.jai";
#load "target.jai";
#load "string_table.jai";
#load "InternPool.jai";
#load "Type.jai";
#load "Value.jai";
#load "Ast.jai";
#load "Bytecode.jai";
#load "lexer.jai";
#load "parser.jai";
#load "resolve.jai";
#load "Sema.jai";
#load "vm.jai";
#load "bytecode_gen.jai";
#load "codegen/llvm.jai";
#load "link.jai";
#load "Compilation.jai";
#load "openjai_test_runner.jai";

print_usage :: () {
    print("usage: openjai <input.jai> [--check] [-o output] [--runtime runtime.o]\n");
}

main :: () {
    argc := compiler_arg_count();
    if argc < 2 {
        print_usage();
        exit(64);
    }

    input_path := compiler_arg(1);
    if input_path == "-h" || input_path == "--help" {
        print_usage();
        return;
    }

    output_path := "out/a.out";
    runtime_path := "out/bootstrap/lib/openjai_runtime.o";
    check_only := false;

    i := 2;
    while i < argc {
        arg := compiler_arg(i);
        if arg == "--check" {
            check_only = true;
        } else if arg == "-o" {
            i += 1;
            if i >= argc {
                print("openjai: error: expected output path after -o\n");
                exit(64);
            }
            output_path = compiler_arg(i);
        } else if arg == "--runtime" {
            i += 1;
            if i >= argc {
                print("openjai: error: expected runtime object path after --runtime\n");
                exit(64);
            }
            runtime_path = compiler_arg(i);
        } else {
            print("openjai: error: unrecognized argument '%'\n", arg);
            exit(64);
        }
        i += 1;
    }

    source := compiler_read_file(input_path);
    if !source {
        print("openjai: error: could not read '%'\n", input_path);
        exit(1);
    }

    result := compile_source_with_options(input_path, output_path, runtime_path, check_only, source);
    if result == .FAILED exit(1);
}
