// Port of bootstrap/src/Compilation.zig.

Compilation_Options :: struct {
    input_path: string;
    output_path: string;
    runtime_path: string;
    check_only: bool;
}

Compilation :: struct {
    options: Compilation_Options;
}

compilation_init :: (options: Compilation_Options) -> Compilation {
    comp: Compilation;
    comp.options = options;
    return comp;
}

compile_source :: (comp: *Compilation, source: string) -> Compile_Result {
    diag := diagnostic_init(comp.options.input_path, source);
    tokens := lexer_tokenize(source, *diag);
    ast := parse(source, tokens, *diag);
    resolved := resolve(*ast, *diag, !comp.options.check_only);
    pool := intern_pool_init();
    typed := sema_analyze(*ast, *resolved, *pool, *diag);
    program := bytecode_generate(*ast, *typed, *resolved, *diag);
    if diag.failed return .FAILED;
    if comp.options.check_only return .OK;
    object_path := comp.options.output_path;
    if llvm_emit_object(*program, object_path, *diag) == .FAILED return .FAILED;
    return link_executable(object_path, comp.options.runtime_path, comp.options.output_path, *diag);
}

