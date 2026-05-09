# Bootstrap Compiler Gap Analysis

This document supersedes the older example-sweep view for planning purposes.
The current bootstrap can compile the example corpus in check mode, but that is
not the same as implementing the Jai language and compiler API semantics. A
large part of the current success comes from placeholders, `any` fallbacks, and
compile-through behavior.

The immediate project priority is now:

1. Identify all bootstrap gaps that are hidden by compile-through acceptance.
2. Replace placeholder paths with real parser, resolver, sema, bytecode, VM,
   runtime, and codegen semantics.
3. Keep `make test` green while upgrading tests from compile coverage to
   behavioral coverage.
4. Resume self-host work only after the bootstrap is a trustworthy seed.

## Current Known-Good Baseline

- `make test` passes.
- `make examples` passes in check mode through the Makefile test flow.
- `out/bootstrap/bin/openjai` can build the Jai self-host source into
  `out/stage1/openjai`.
- `out/stage1/openjai examples/hello.jai --check` passes.

These facts should be treated as baseline health checks, not as proof of
semantic completeness.

## Primary Bootstrap Completeness Problems

### 1. Placeholder Imports And Symbols

The resolver still hardcodes many modules and symbols instead of loading and
typechecking real module source.

Examples of placeholder modules or symbol sets:

- `System`, `Windows`, `Process`, `Input`, `Window_Creation`,
  `Windows_Resources`
- `Simp`, `GL`, `SDL`, `glfw`, `raylib`
- `File`, `File_Utilities`, `BuildCpp`
- `Debug`, `Sort`, `Hash_Table`, `Pool`, `Flat_Pool`, `rpmalloc`
- `Compiler`, `Metaprogram_Plugins`, `Machine_X64`

Required work:

- Implement real module discovery and loading instead of hardcoded import
  acceptance.
- Add or model enough standard modules for tests to exercise real declarations.
- Stop accepting unknown imported APIs as `.placeholder` unless the program has
  explicitly declared `#placeholder`.
- Add diagnostics that distinguish real unresolved names from intentionally
  deferred build symbols.

### 2. Compiler/Meta API Is Mostly Stubbed

The `Compiler` module surface is not spec-complete. Many APIs are accepted as
placeholders or return generic values.

Known incomplete APIs:

- `compiler_create_workspace`
- `get_current_workspace`
- `get_build_options`, `set_build_options`, `set_build_options_dc`
- `set_optimization`
- `add_build_file`, `add_build_string`
- `compiler_begin_intercept`, `compiler_wait_for_message`,
  `compiler_end_intercept`, `compiler_set_workspace_status`
- `compiler_report`, `make_location`
- `compiler_get_nodes`, `compiler_get_code`, `print_expression`,
  `code_to_string`
- `compiler_get_version_info`,
  `compiler_custom_link_command_is_complete`
- `add_global_data`
- `run_command`

Required work:

- Define real host-backed value types for workspaces, build options, messages,
  source locations, code trees, and global-data handles.
- Replace integer and `any` stand-ins with typed compile-time values.
- Implement a deterministic workspace manager and compiler message loop.
- Add behavioral tests for each API; compile-only tests are insufficient.

### 3. `Code` And `Code_Node` Are Not Real AST Values Yet

The bootstrap accepts many code/meta examples, but editable AST semantics are
not complete.

Missing or incomplete behavior:

- `#code` should produce a stable `Code` value with AST fragment, source
  provenance, capture scope, and expression/statement/declaration
  classification.
- `Code.type` should reflect the captured root type.
- `compiler_get_nodes` should return real root and expression nodes in stable
  traversal order.
- `compiler_get_code` should round-trip edits to a real node tree.
- `Code_Node` subtypes such as `Code_Literal`, `Code_Procedure_Call`, and
  `Code_Declaration` should have checked, host-backed fields.
- Casts like `cast(*Code_Literal) node` should operate on actual node values.
- `print_expression` and `code_to_string` should serialize the real AST.

Required work:

- Build an internal code-tree representation and expose it through compile-time
  values.
- Replace placeholder-backed Code/Code_Node field access.
- Test AST mutation and round-trip semantics directly.

### 4. Macro Expansion And `#insert` Are Partial

Macro examples compile, but the implementation is not a general parse/splice and
scope-resolution engine.

Missing or incomplete behavior:

- `#expand` as a real compile-time macro-expansion pipeline.
- Code-typed macro arguments receiving caller syntax.
- `#caller_code`, `#caller_location`, and `#location(code)` returning real
  values.
- `#insert` in expression, statement, declaration, and lvalue positions.
- `#insert -> string`, `#insert -> Code`.
- `#insert,scope()` and `#insert,scope(target)` resolving identifiers against
  the captured scope.
- Nested/local macro expansion inside procedure scopes.

Required work:

- Implement macro invocation as a compile-time execution mode with typed syntax
  arguments.
- Parse inserted strings in the correct syntactic context.
- Splice generated AST into the caller and rerun needed resolution/sema passes.
- Add negative tests for bad inserts and scope failures.

### 5. Compile-Time Execution Is Too Narrow

The `#run` and compile-time execution paths still have expression and value
limits.

Missing or incomplete behavior:

- Full ordinary procedure execution in the VM.
- Compile-time values beyond scalar placeholders: strings, code values,
  source locations, workspaces, messages, build options, arrays/slices, structs,
  pointers, and handles.
- Correct execution order for top-level `#run`, initializer `#run`, and nested
  expression-form `#run`.
- Real host intrinsic dispatch instead of arbitrary placeholder propagation.
- `run_command` and file/process APIs as real host calls.

Required work:

- Separate ordinary VM execution from host compiler intrinsics.
- Make unsupported compile-time paths explicit diagnostics.
- Add tests where `#run` returns and propagates non-scalar values.

### 6. Parser Coverage Still Uses Opaque Nodes

The parser accepts many forms by preserving opaque text or unsupported nodes.
This is useful for compile-through but insufficient for semantic compilation.

Known weak areas:

- Container member directives and attributes.
- Full procedure signatures: default args, named returns, multiple returns,
  variadics, polymorphic parameters, baked parameters, `using` parameters.
- Lambdas, anonymous procedures, procedure types, and local procedures.
- Full `for` grammar and iterator expansion.
- Inline assembly blocks.
- FFI directives and platform conditionals.
- Complex type expressions and aggregate literals.

Required work:

- Replace opaque parse nodes with structured AST nodes by feature area.
- Ensure resolver/sema/codegen consume those structured nodes.
- Keep parser tests paired with semantic tests so accepted syntax is not inert.

### 7. Type System And Sema Are Not Deep Enough

Semantic analysis still falls back to `any` for many features.

Missing or incomplete behavior:

- Real struct, union, enum, array, slice, and dynamic-array type layout.
- `using`, `#as`, `#place`, `#align`, `#no_padding`, `#specified`.
- Proper pointer/address/lvalue checking.
- Full overload resolution.
- Polymorphic procedures and structs.
- Default arguments and named arguments.
- Multiple return values.
- Type info and reflection values.
- Proper `Context` semantics.

Required work:

- Introduce concrete semantic entities for declarations, scopes, types, and
  values.
- Stop using `any` as a compatibility escape hatch for known language features.
- Add semantic tests that inspect output, layout, and type errors.

### 8. Codegen And Runtime Materialization Are Partial

The runtime and LLVM lowering support a useful subset, but many accepted
programs are not actually lowered with faithful behavior.

Runtime foundation status:

- Runtime artifacts are now rooted under `bootstrap/rt`.
- The bootstrap installs a linker-facing runtime manifest at
  `out/bootstrap/lib/openjai_runtime.manifest`.
- The linker accepts a runtime manifest and resolves relative object paths from
  the manifest directory.
- `make runtime` builds and prints the active runtime manifest.
- The current seed implementation remains Zig-backed, but the build/link shape
  is no longer hardcoded to a single magic runtime object.

Known gaps:

- Struct/union/enum materialization and formatting.
- Aggregate literals and nested containers.
- Dynamic arrays, slices, and array views beyond simple cases.
- Pointer arithmetic and dereference semantics.
- Correct stack/local storage for complex values.
- Full print/format behavior.
- Real `type_info`, `formatStruct`, `type_to_string`, enum helpers.
- Proper time/sleep/thread/process/file APIs instead of dummy values.
- FFI calls, system libraries, C calling convention, dynamic libraries.
- Inline assembly.

Required work:

- Add real runtime representations for compound values.
- Lower all accepted structured values instead of typed placeholders.
- Add runtime tests for every example that currently only compiles.

### 9. Workspace And Build System Semantics Are Incomplete

Build examples compile, but the compiler is not faithfully running Jai's build
system model.

Missing or incomplete behavior:

- Workspace numbering and lifecycle.
- Build option structs with readable/writable fields.
- Build file/string mutation and `#placeholder` fulfillment.
- Intercepted compiler phases and messages.
- Custom link commands and output-type/backend selection.
- Global data embedding.
- Build/run loops that produce and execute target programs.

Required work:

- Implement a single-threaded but real workspace scheduler.
- Add message queue objects and phase progression.
- Make `add_build_string` inject source into the target workspace.
- Test `examples/30` behavior, not just compilation.

### 10. Test Framework Is Still Bootstrap-Hosted And Incomplete

The test framework discovers and runs tests, but it is not yet the full Jai test
model from the spec.

Missing or incomplete behavior:

- Discovery through real compiler declarations/notes rather than limited
  bootstrap scanning.
- Assertion handler override through implicit context.
- Imported-module test registration exactly once.
- Compiler-test helpers implemented through workspaces/intercept APIs.
- Run/output coverage for every example.
- Negative compiler tests for expected diagnostics.

Required work:

- Upgrade compile tests to behavioral tests topic by topic.
- Add explicit tests for every placeholder-backed feature before replacing the
  placeholder.
- Treat any example-output mismatch as a compiler bug.

## High-Priority Bootstrap Work Order

1. **Placeholder inventory gate**
   - Add a test or report that enumerates all accepted placeholder symbols.
   - Fail new tests when a feature silently resolves to placeholder/`any` unless
     explicitly allowed.
   - Status: implemented for implicit resolver placeholders. The bootstrap now
     tracks hardcoded placeholder symbols separately from explicit
     `#placeholder` declarations, records which implicit placeholders are used,
     and fails compilation with a sorted symbol list when any are reached.
     This intentionally makes the old compile-through examples red until the
     underlying compiler features are implemented.

2. **Real module loading**
   - Replace hardcoded import lists with actual module resolution.
   - Start with `Basic`, `String`, `File`, `Compiler`, `Thread`, `Process`.

3. **Compiler host values**
   - Implement typed compile-time values for `Workspace`, `Build_Options`,
     `Source_Code_Location`, `Code`, `Code_Node`, and `Message`.

4. **Code tree semantics**
   - Implement `#code`, `compiler_get_nodes`, `compiler_get_code`,
     `print_expression`, and `code_to_string` as real AST operations.

5. **Macro insertion semantics**
   - Implement general `#insert` parsing/splicing and captured-scope
     resolution.

6. **Workspace/build semantics**
   - Implement real workspaces, build options, `add_build_file`,
     `add_build_string`, intercept messages, and reporting.

7. **Compound value sema/codegen**
   - Replace `any` fallback for structs, arrays, dynamic arrays, slices, and
     pointers with real layout and lowering.

8. **Procedure system**
   - Complete defaults, named args, multiple returns, variadics, lambdas,
     overloads, polymorphism, and procedure pointers.

9. **FFI/platform/runtime APIs**
   - Implement `#foreign`, `#system_library`, `#c_call`, dynamic libraries,
     file/process/thread APIs, and inline asm.

10. **Self-host resume gate**
    - Resume self-host work only when the bootstrap can pass behavioral tests
      for the compiler/meta/build APIs it needs, without placeholder-backed
      success.

## Definition Of Done For Bootstrap Completeness

The bootstrap should be considered a trustworthy seed when:

- `make test` passes with behavioral tests, not just compile-through tests.
- `make examples` includes run/output checks for examples with stable output.
- Placeholder resolution is limited to explicit `#placeholder` declarations.
- Compiler/meta APIs return typed host values.
- `examples/26` and `examples/30` pass semantic tests for code trees, macros,
  workspaces, messages, build options, and generated builds.
- Accepted source constructs are represented in structured AST/sema/codegen,
  not opaque parse nodes.
- Unsupported features produce deterministic diagnostics instead of fake values.
