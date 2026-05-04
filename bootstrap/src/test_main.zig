/// Test root for the OpenJai bootstrap compiler unit tests.
///
/// This file imports every module that has `test` blocks but does NOT
/// transitively import `codegen/llvm.zig` (which requires LLVM static libs
/// that cannot be linked via Zig's own linker in the test configuration).
///
/// To add tests: add them to the relevant module file. This file only needs
/// updating when a new module file is created.
const std = @import("std");

// Modules with test blocks — all safe to link without LLVM.
comptime {
    _ = @import("lexer.zig");
    _ = @import("Token.zig");
    _ = @import("Ast.zig");
    _ = @import("string_table.zig");
    _ = @import("InternPool.zig");
    _ = @import("Type.zig");
    _ = @import("Value.zig");
    _ = @import("diagnostics.zig");
    _ = @import("target.zig");
    _ = @import("parser.zig");
    _ = @import("resolve.zig");
    _ = @import("Sema.zig");
    _ = @import("Bytecode.zig");
    _ = @import("bytecode_gen.zig");
    _ = @import("vm.zig");
    // NOTE: Compilation.zig is intentionally excluded because it transitively
    // imports codegen/llvm.zig, which requires LLVM static libraries that
    // cannot be linked by Zig's built-in linker in the test configuration.
    // The Compilation integration test runs via `zig build test-examples`.
}
