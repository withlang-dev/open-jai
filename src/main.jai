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

main :: () {
    print("OpenJai Jai compiler port: source tree is present; compiler execution is not self-hosted yet.\n");
}
