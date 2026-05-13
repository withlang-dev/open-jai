#import "String";

#scope_export;

Workspace :: int;
Code :: #type int;

Optimization_Type :: enum {
    DEBUG;
    OPTIMIZED;
}

Source_Code_Location :: struct {
    fully_pathed_filename: string;
    line_number: int;
}

Build_Options_LLVM_Options :: struct {
    output_bitcode: bool;
    output_llvm_ir: bool;
}

Build_Options :: struct {
    output_executable_name: string;
    output_path: string;
    output_type: string;
    backend: string;
    import_path: [..] string;
    compile_time_command_line: [..] string;
    stack_trace: bool;
    backtrace_on_crash: string;
    array_bounds_check: string;
    cast_bounds_check: string;
    null_pointer_check: string;
    enable_bytecode_inliner: bool;
    runtime_storageless_type_info: bool;
    do_output: bool;
    llvm_options: Build_Options_LLVM_Options;
}

Message :: struct {
    kind: string;
    workspace: Workspace;
}

Message_File :: struct {
    kind: string;
    workspace: Workspace;
    fully_pathed_filename: string;
}

Message_Import :: struct {
    kind: string;
    workspace: Workspace;
    module_name: string;
    module_type: string;
    fully_pathed_filename: string;
}

Message_Phase :: struct {
    kind: string;
    workspace: Workspace;
    phase: string;
    executable_name: string;
    executable_write_failed: bool;
    linker_exit_code: int;
}

Message_Typechecked :: struct {
    kind: string;
    workspace: Workspace;
    all: [] *Code_Node;
    declarations: [] *Code_Node;
}

Message_Debug_Dump :: struct {
    kind: string;
    workspace: Workspace;
    dump_text: string;
}

Message_Complete :: struct {
    kind: string;
    workspace: Workspace;
    error_code: int;
}

Code_Node :: struct {
    kind: string;
    node_flags: string;
    type: Type;
    subexpressions: [] *Code_Node;
    enclosing_load: *Code_Node;
}

Code_Literal :: struct {
    using node: Code_Node;
    value_type: string;
    _s64: s64;
    _string: string;
}

Code_Argument :: struct {
    expression: *Code_Node;
}

Code_Procedure_Call :: struct {
    using node: Code_Node;
    arguments_unsorted: [] Code_Argument;
}

Code_Declaration :: struct {
    using node: Code_Node;
    name: string;
    expression: *Code_Node;
    notes: [] Code_Note;
}

Code_Note :: struct {
    text: string;
}

Type_Info :: struct {
    type: string;
    runtime_size: int;
}

Type_Info_Pointer :: struct {
    points_to: Type;
}

compiler_create_workspace :: () -> Workspace #foreign;
get_current_workspace :: () -> Workspace #foreign;
get_build_options :: (workspace: Workspace = 0) -> Build_Options #foreign;
set_build_options :: (options: Build_Options, workspace: Workspace = 0) #foreign;
set_build_options_dc :: (options: Build_Options) #foreign;
set_optimization :: (options: *Build_Options, optimization: Optimization_Type, runtime_checks := false) #foreign;

compiler_begin_intercept :: (workspace: Workspace) #foreign;
compiler_wait_for_message :: () -> *Message #foreign;
compiler_end_intercept :: (workspace: Workspace) #foreign;
compiler_set_workspace_status :: (status: int, workspace: Workspace = 0) #foreign;
compiler_custom_link_command_is_complete :: (workspace: Workspace = 0, exit_code := 0) #foreign;

add_build_file :: (path: string, workspace: Workspace = 0) #foreign;
add_build_string :: (source: string, workspace: Workspace = 0) #foreign;
add_global_data :: (data: string, name := "") -> *void #foreign;
run_command :: (command: string, args: ..string) -> int #foreign;

compiler_get_nodes :: (code: Code) -> *Code_Node, [] *Code_Node #foreign;
compiler_get_code :: (root: *Code_Node) -> Code #foreign;
print_expression :: (builder: *String_Builder, node: *Code_Node) #foreign;
code_to_string :: (code: Code) -> string #foreign;
make_location :: (node: *Code_Node) -> Source_Code_Location #foreign;
compiler_report :: (message: string) #foreign;
compiler_report :: (message: string, location: Source_Code_Location) #foreign;

get_type_table :: () -> [] Type_Info #foreign;
is_subclass_of :: (info: *Type_Info, name: string) -> bool #foreign;
