# OpenJai Test Framework Specification

## 1. Purpose

OpenJai's test framework exists to test Jai programs as real programs. A language
test should look like ordinary Jai code, with the smallest possible amount of
framework interaction.

The framework is based on Jai's published testing model:

- Test files are normal Jai source files.
- Test procedures are normal zero-argument procedures tagged with
  `@TestProcedure`.
- Tests are discovered automatically by compiler introspection.
- Regular `assert` calls are counted and reported by a test assertion handler.
- The build/test driver is itself Jai source, not an external registration file.

The initial OpenJai test corpus lives under `test/examples`. Those tests wrap the
existing `examples` programs and progressively replace compile-only coverage with
assertive behavioral coverage.

## 2. Design Goals

The framework must provide:

- Independent-program style tests: test files should compile as normal Jai code
  where practical.
- Automatic discovery: no manual list of test procedures for ordinary tests.
- Minimal ceremony: `@TestProcedure` plus ordinary `assert` should be enough.
- Useful reporting: show which files and procedures ran, assert counts, failures,
  and source locations.
- Module test support: tests discovered in imported modules should be registered
  once, even if a module is imported multiple times.
- Compiler-test support: tests may compile other Jai files, inspect compiler
  messages, and assert expected compile success or expected diagnostics.

## 3. Directory Layout

The repository-level test layout is:

```text
test/
  tests.jai                 Test framework entry point and build driver.
  framework/                Framework implementation modules.
  examples/                 Example-derived language tests.
  reports/                  Generated reports, ignored by source control.
```

`test/examples` mirrors `examples` by topic where useful:

```text
test/examples/03/hello_sailor_tests.jai
test/examples/26/meta_code_tests.jai
test/examples/30/workspace_tests.jai
```

The mirror does not need a one-file-per-example rule. Related examples may be
grouped when one test procedure can express their shared invariant clearly.

## 4. Test Procedure Contract

A test procedure is any procedure declaration with a `TestProcedure` note:

```jai
simple_language_test :: () {
    assert(1 + 1 == 2);
} @TestProcedure
```

Discovery rules:

- The declaration must be a procedure.
- The procedure must accept zero arguments.
- The procedure may return `void` or a value that is ignored by the runner.
- Structs, variables, constants, and non-procedure declarations with the note are
  ignored.
- Invalid test procedures produce a warning and are not registered.
- A procedure is registered at most once, even if discovered through multiple
  import paths.

The note is intentionally ordinary Jai metadata. It has no effect outside the
test driver unless the active metaprogram chooses to inspect it.

## 5. Assertion Semantics

Tests use normal Jai `assert`.

The runner overrides the implicit assertion handler while a test procedure is
running. Each assertion records:

- source filename
- line number
- enclosing test procedure
- pass/fail result
- optional formatted message

A failed assertion does not terminate the whole test executable. It marks the
current test procedure as failed, records the failure, and continues according to
the configured failure policy.

Default failure policy:

- Continue after assertion failure inside the current test.
- Continue running later test procedures.
- Exit the test executable with non-zero status if any test failed.

The framework should also support a fail-fast option for local debugging.

## 6. Test Discovery Pipeline

The framework uses compiler metaprogramming:

1. Create or use a test workspace.
2. Add test files and requested module imports.
3. Intercept compiler messages.
4. Wait until all possible source has been typechecked.
5. Inspect declarations and notes.
6. Register all valid `@TestProcedure` procedures.
7. Insert or generate runner code that calls registered tests.
8. Continue compilation of the test executable.

The discovery phase depends on the compiler API surface specified in
`docs/open_jai_spec.md`, especially:

- workspaces and build options
- compiler intercept messages
- code declarations and notes
- `#insert` or generated build strings
- source locations

Discovery must be deterministic. Given the same set of files, tests run in stable
order: filename order, then declaration order within each file.

## 7. Runner Semantics

The generated test executable performs:

```text
initialize report
for each discovered test:
  set current test context
  install assertion handler
  run test procedure
  restore assertion handler
  record duration and result
write report
print summary
exit 0 if all passed else non-zero
```

Each test procedure must run in an isolated context where possible:

- assertion counts reset per procedure
- temporary allocator/accounting state may be reset per procedure
- framework globals are not reset unless explicitly marked as per-test state

The first implementation may be single-threaded. Parallel test execution is out
of scope until deterministic reporting and isolation are implemented.

## 8. Report Format

The console summary is intentionally small:

```text
OpenJai tests
  PASS test/examples/03/hello_sailor_tests.jai::hello_sailor_compiles (1 assert)
  FAIL test/examples/12/struct_tests.jai::struct_layout_matches (2/3 asserts)

Summary: 127 tests, 482 asserts, 1 failed
Report: test/reports/latest.txt
```

The detailed report contains:

- run timestamp
- compiler revision if available
- command line
- per-file summary
- per-test summary
- assertion failures with source locations
- compiler-test failures with expected and actual diagnostics

Reports are generated artifacts and should not be committed by default.

## 9. Example Test Coverage Model

Every file under `examples` should eventually have at least one corresponding
test under `test/examples`.

Coverage levels:

- **Compile coverage:** the example compiles with `--check`.
- **Run coverage:** the example compiles and executes without crashing.
- **Output coverage:** stdout/stderr match expected text or stable patterns.
- **Semantic coverage:** targeted asserts validate the feature the example is
  meant to demonstrate.
- **Negative coverage:** invalid programs intentionally fail with expected
  diagnostics.

Initial example tests may begin as compile coverage, but each test file should
state the stronger behavior it intends to reach.

## 10. Compiler-Test Procedures

Some tests need to compile other files rather than only run ordinary Jai code.
The framework exposes helper procedures such as:

```jai
expect_compile_success :: (path: string);
expect_compile_failure :: (path: string, expected_message: string);
expect_compile_output :: (path: string, expected: string);
expect_compile_output_contains :: (path: string, needle: string);
expect_program_output :: (path: string, expected: string);
expect_program_output_contains :: (path: string, needle: string);
```

These helpers are normal test-framework procedures. They may use workspaces,
`add_build_file`, `add_build_string`, intercept messages, or `run_command`
internally.

For deterministic compiler tests:

- Diagnostics are matched on stable message text and source location where
  possible.
- Tests should not depend on absolute local paths unless the expected behavior is
  path-related.
- Tests should avoid wall-clock timing assertions.

## 11. Negative Tests

Negative tests live next to positive tests when they explain the same feature,
or under `test/examples/negative` when they are general compiler diagnostics.

A negative test must declare:

- source file or generated source string
- expected failure phase, if relevant
- expected diagnostic substring
- whether multiple diagnostics are allowed

The framework passes a negative test only when compilation fails for the expected
reason.

## 12. Interaction With Existing Examples

The current `make examples` target remains the broad compile-through acceptance
sweep. The test framework adds stronger assertions.

The intended progression is:

1. Add compile-success tests for all existing examples.
2. Add output tests for examples with deterministic output.
3. Convert high-value examples into direct `@TestProcedure` semantic tests.
4. Add negative tests for parser, resolver, sema, macro, and compiler API
   diagnostics.

Examples that depend on platform services, graphics, audio, system libraries, or
external tools may start at compile coverage and be promoted later when a stable
test environment exists.

## 13. Required Compiler Support

The framework requires these OpenJai capabilities:

- notes on declarations, especially procedure declarations
- declaration/type information sufficient to detect zero-argument procedures
- workspace creation and build-option mutation
- `add_build_file` and `add_build_string`
- compiler intercept/message loop
- source locations for diagnostics and assertions
- assertion-handler override via context
- deterministic compile-time execution for runner generation

If one of these capabilities is not yet implemented, the framework should expose
a clear unsupported diagnostic rather than silently skipping tests.

## 14. Source Control Rules

Commit:

- test source files
- framework source files
- small golden output files when stable and reviewed

Do not commit by default:

- generated test executables
- `test/reports`
- temporary generated Jai files
- local machine paths

## 15. Initial Milestones

Milestone 1: Specification and layout.

- Create this document.
- Create `test/examples`.

Milestone 2: Minimal runner.

- Implement `test/tests.jai`.
- Discover local `@TestProcedure` procedures.
- Run tests and count assertions.

Milestone 3: Compiler helpers.

- Add compile-success and compile-failure helpers.
- Add compile-success coverage for all `examples` files.

Milestone 4: Behavioral example tests.

- Add output or semantic tests for deterministic examples.
- Prioritize `examples/26` and `examples/30` because they exercise compiler meta
  APIs, macros, code insertion, and workspaces.

Milestone 5: Reports.

- Emit console summaries and `test/reports/latest.txt`.
- Include source locations and per-file/per-procedure summaries.
