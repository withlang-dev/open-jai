# Bootstrap Example Sweep

Status date: 2026-05-06

This document tracks the current bootstrap compiler against `./examples`.

Latest sweep note:
- The corpus was re-swept after the parser/sema/codegen slice for container declarations, anonymous container types, typed aggregate literals, and `for` iterator bindings.

## Summary

- Compiler used for the sweep: `out/bootstrap/bin/openjai`
- Runtime object used: `out/bootstrap/lib/openjai_runtime.o`
- Preferred workflow: `make bootstrap`, `make test-bootstrap`, `make examples`
- Example files attempted: `313`
- Example files that compiled: `55`
- Example files that failed: `258`
- Source unit tests: `18/18` passing via `cd bootstrap && zig test src/test_main.zig`

## Caveats

- The sweep used the `Makefile`-produced artifact under `out/bootstrap/`. `make bootstrap` still reports a final LLVM/`clang++` link-step failure on macOS, but the output compiler binary is being refreshed and was used for the latest sweep.
- The repository `Makefile` is the preferred entrypoint. `SUPPORTED_EXAMPLES` is intended to cover the full `./examples` tree, so `make examples` should be treated as the corpus sweep target.
- Some files under `examples/` are helper fragments rather than standalone programs, for example:
  - `examples/08/part1.jai`
  - `examples/08/part3.jai`
  - `examples/08/subfolder/part2.jai`
- Those fragment files should not be treated as language failures by themselves, but they do expose current `#load` and entrypoint assumptions in the bootstrap compiler.

## Dominant Failure Buckets

- Parser coverage is still the main blocker.
  - `79` failures with `expected expression`
  - `25` failures with `expected procedure body`
  - `18` failures with `expected type expression`
  - `12` failures with `invalid character 0x60`
  - `9` failures with `expected ')' after parameter list`
- Module and standard-library loading is incomplete.
  - Unknown imports such as `String`, `Thread`, `Process`, `SDL`, `GL`, `Pool`, `TestScope`
- Context and runtime/compiler builtins are incomplete.
  - Unresolved names such as `context`, `alloc`, `append`, `get_time`, `seconds_since_init`, `get_current_workspace`, `get_command_line_arguments`, `formatStruct`
- Codegen/runtime correctness still has hard failures.
  - Loop examples no longer crash in the current sweep, but loop lowering is still semantically partial
  - Non-scalar printing and formatting coverage is still partial
  - Anonymous/global container values are currently placeholder-materialized in codegen

## Representative Failures By Feature Area

### 1. Aggregate Data Types And Literals

The parser now accepts a broader aggregate surface area, but member-level semantics and several declaration forms are still missing.

- [examples/12/12.1_struct_declarations.jai](/Users/eric/open-jai/examples/12/12.1_struct_declarations.jai:69): `unresolved identifier 'formatStruct'`
- [examples/12/12.12_#as_using_entities.jai](/Users/eric/open-jai/examples/12/12.12_#as_using_entities.jai:14): `expected expression`
- [examples/12/12.14_member_procs.jai](/Users/eric/open-jai/examples/12/12.14_member_procs.jai:11): `unsupported type table field 'x'`
- [examples/18/18.1_array_literals.jai](/Users/eric/open-jai/examples/18/18.1_array_literals.jai:1): `expected expression`

Implication:
- Finish member-level semantics for `using`, `#as`, align/place directives, array/view syntax, and proper struct/enum runtime materialization.

### 2. Directives And Top-Level Conditionals

Directive parsing is still too narrow for real examples.

- [examples/20/20.2_assert.jai](/Users/eric/open-jai/examples/20/20.2_assert.jai:1): `expected top-level import, constant, or procedure declaration`
- [examples/26/26.4_no_reset.jai](/Users/eric/open-jai/examples/26/26.4_no_reset.jai:3): `expected top-level import, constant, or procedure declaration`
- [examples/29/29.4_get_computer_name.jai](/Users/eric/open-jai/examples/29/29.4_get_computer_name.jai:15): `expected top-level import, constant, or procedure declaration`

Implication:
- Add parser support for top-level directives and conditional compilation forms such as `#assert`, `#if`, `#else`, and related directive-driven declarations.

### 3. Modules And Standard Library Loading

The resolver and compilation pipeline still behave like a narrow stubbed import system.

- [examples/12/12.8_inner_module_test.jai](/Users/eric/open-jai/examples/12/12.8_inner_module_test.jai:1): `unknown Phase 1 import 'TestScope'`
- [examples/19/19.2_bytes.jai](/Users/eric/open-jai/examples/19/19.2_bytes.jai:1): `unknown Phase 1 import 'String'`
- [examples/21/21.2_leak_detect.jai](/Users/eric/open-jai/examples/21/21.2_leak_detect.jai:1): `unknown Phase 1 import 'Debug'`

Implication:
- Replace hardcoded import stubs with actual module discovery/loading and begin checking in enough OpenJai stdlib module sources for the example corpus.

### 4. Context, Allocator, And Runtime Builtins

The context system and standard runtime/compiler hooks are not implemented deeply enough yet.

- [examples/11/11.4_memory.jai](/Users/eric/open-jai/examples/11/11.4_memory.jai:1): `unresolved identifier 'alloc'`
- [examples/11/11.5_get_time.jai](/Users/eric/open-jai/examples/11/11.5_get_time.jai:1): `unresolved identifier 'get_time'`
- [examples/25/25.1_context.jai](/Users/eric/open-jai/examples/25/25.1_context.jai:1): `expected expression`
- [examples/25/25.2_stack_trace.jai](/Users/eric/open-jai/examples/25/25.2_stack_trace.jai:1): `unresolved identifier 'context'`
- [examples/30/30.1_workspaces.jai](/Users/eric/open-jai/examples/30/30.1_workspaces.jai:1): `unresolved identifier 'get_current_workspace'`

Implication:
- Implement the real `Context` surface, add `#add_context` handling across the pipeline, and expose the runtime/compiler builtins used by the example corpus.

### 5. Procedures, Overloading, And Polymorphism

The current procedure parser and sema are still well short of Jai’s actual procedure model.

- [examples/17/17.4_default_args.jai](/Users/eric/open-jai/examples/17/17.4_default_args.jai:1): `expected ')' after parameter list`
- [examples/17/17.5_multiple_return.jai](/Users/eric/open-jai/examples/17/17.5_multiple_return.jai:1): `expected procedure body`
- [examples/18/18.10_var_args.jai](/Users/eric/open-jai/examples/18/18.10_var_args.jai:1): `expected ')' after parameter list`
- [examples/22/22.5_lambdas.jai](/Users/eric/open-jai/examples/22/22.5_lambdas.jai:1): `expected type expression`

Implication:
- Extend parsing and sema for default args, named args, multiple returns, variadics, lambdas, overload resolution, and polymorphic procedures.

### 6. Codegen And Runtime Correctness

Some examples make it through parse/sema and then fail because lowering/runtime behavior is still unsafe or incomplete.

- [examples/15/15.3_for.jai](/Users/eric/open-jai/examples/15/15.3_for.jai:1): now compiles
- [examples/15/15.4_break.jai](/Users/eric/open-jai/examples/15/15.4_break.jai:1): now compiles
- [examples/15/15.8_for_reverse.jai](/Users/eric/open-jai/examples/15/15.8_for_reverse.jai:1): now compiles
- [examples/17/17.10_println.jai](/Users/eric/open-jai/examples/17/17.10_println.jai:1): `Phase 3 print supports string, integer, float, bool, void, pointer, and type arguments`

Implication:
- Broaden formatting/printing and proper value materialization for structs, arrays, and richer types.

### 7. FFI And Platform Surface

The parser/resolver/codegen do not yet support the FFI and platform conditionals required by later examples.

- [examples/19/19.8_windows_input.jai](/Users/eric/open-jai/examples/19/19.8_windows_input.jai:1): `expected expression`
- [examples/29/29.4_get_computer_name.jai](/Users/eric/open-jai/examples/29/29.4_get_computer_name.jai:1): top-level conditional / FFI parsing failure
- [examples/30/30.1_workspaces.jai](/Users/eric/open-jai/examples/30/30.1_workspaces.jai:1): compiler API unresolved

Implication:
- Add `#system_library`, `#foreign`, `#c_call`, OS constants, and compiler/workspace intrinsics as real first-class features.

## Non-Language Or Infrastructure Failures

These need to be fixed before repeated corpus sweeps are reliable.

- `make bootstrap` currently fails in the final LLVM/`clang++` link step on macOS.
- A few failures are entrypoint or fragment related rather than true feature failures:
  - `No program entry point was found`
  - `source file is empty`

## Recommended Implementation Order

1. Keep `make bootstrap` as the build entrypoint, but fix or fully explain the final macOS LLVM link failure so the build status is trustworthy.
2. Finish parser support for directives, top-level conditionals, and the remaining aggregate/member syntax.
3. Implement real module loading and stdlib import resolution.
4. Extend sema for struct fields, `using`, `#as`, align/place directives, and context/runtime builtins.
5. Broaden runtime value formatting and proper container materialization in codegen.
6. Add procedure-system features: default args, multiple returns, variadics, lambdas, overloads, polymorphism.
7. Implement FFI and compiler API support.

## Immediate Next Slice

The highest-yield next slice is now:

1. directive/member parsing inside aggregate declarations: `using`, `#as`, `#align`, `#place`, `#specified`
2. runtime/compiler builtins needed by the early data-structure examples: `formatStruct`, `alloc`, `get_time`, `seconds_since_init`
3. import-system expansion for `String`, `Thread`, `Debug`, and related early modules

That combination should retire a large share of the current front-end and builtin failures without reopening the already-fixed loop and container crashes.
