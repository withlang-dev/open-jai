#import "Basic";
#import "Compiler";

make_llvm_options :: () -> Build_Options_LLVM_Options {
    options := get_build_options();
    options.llvm_options.output_bitcode = true;
    options.llvm_options.output_llvm_ir = true;
    return options.llvm_options;
}

LLVM_Options :: #run make_llvm_options();

#run {
    print("llvm-options:% %\n", LLVM_Options.output_bitcode, LLVM_Options.output_llvm_ir);
}

main :: () {}
