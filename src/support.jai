// Shared support layer for the Jai port of the bootstrap compiler.
//
// This file intentionally stays small. It is the compatibility boundary for
// pieces that are direct stdlib/container calls in the Zig implementation.

String_View :: string;
Node_Index :: int;
Token_Index :: int;

NULL_NODE :: 0;

Source_Buffer :: struct {
    path: string;
    text: string;
}

Compile_Result :: enum {
    OK;
    FAILED;
}

Port_Module_Status :: enum {
    PORTED;
    STRUCTURAL;
    TODO;
}

port_note :: (module_name: string, status: Port_Module_Status) {
    // Keep module status reachable from ordinary Jai code while the port is in
    // progress. The implementation is intentionally side-effect free by
    // default so importing modules does not spam compiler output.
}

