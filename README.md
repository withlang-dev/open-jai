# OpenJai

OpenJai is an open source implementation effort for a Jai-style systems
programming language and compiler. The project is guided by
[`docs/open_jai_spec.md`](docs/open_jai_spec.md), with the current bootstrap
compiler implemented in Zig under [`bootstrap/`](bootstrap/).

The goal is to build a fast, ahead-of-time compiled, low-level language for
game programming, general-purpose systems work, and metaprogramming-heavy
development. OpenJai is intended to prioritize developer productivity first,
then performance, then safety.

## Status

This repository currently contains an early Zig bootstrap compiler. It is not
yet the final self-hosting OpenJai compiler.

The bootstrap compiler has the start of the full pipeline:

```text
source -> lexer -> parser -> AST -> semantic analysis -> bytecode -> LLVM object -> linked executable
```

Current support is still incomplete, but the bootstrap compiler now covers a
large example-driven surface, including compile-through checks for the example
corpus. The complete language described in the spec remains work in progress.

## Repository Layout

```text
bootstrap/   Zig implementation of the bootstrap compiler
src/         Jai port of the bootstrap compiler, kept structurally aligned
docs/        Language spec and compiler implementation notes
examples/    Jai/OpenJai example programs used as compiler milestones
test/        Jai-style test framework and example-derived tests
out/         Generated build output, ignored by git
```

Important docs:

- [`docs/open_jai_spec.md`](docs/open_jai_spec.md): language goals and
  specification notes.
- [`docs/OpenJai_implementation_notes.md`](docs/OpenJai_implementation_notes.md):
  bootstrap compiler architecture and implementation plan.
- [`docs/open_jai_test_spec.md`](docs/open_jai_test_spec.md): Jai-style test
  framework design and example-test conventions.

## Requirements

The current bootstrap build expects:

- Zig 0.16
- LLVM installed under `/usr/local/llvm`
- `/usr/local/llvm/bin/llvm-config`
- `/usr/local/llvm/bin/clang++`
- macOS SDK tools available through `xcrun`

The language goals include broader platform support, but the current bootstrap
build script is wired to this local LLVM/macOS toolchain.

## Build

Build the bootstrap compiler:

```sh
make bootstrap
```

This writes generated files under `out/`:

```text
out/bootstrap/bin/openjai
out/bootstrap/lib/openjai_runtime.o
out/zig-cache/
```

Build the currently supported example subset:

```sh
make examples
```

`make examples` checks every `*.jai` file under `examples/` by default.
Generated outputs are written under `out/examples/`, mirroring the source tree.

Run all repository tests:

```sh
make test
```

This runs the Zig bootstrap tests, the example compile sweep, and the Jai-style
test harness.

Check the Jai source port:

```sh
make selfhost-check
```

The Jai compiler port lives under `src/` and mirrors the Zig bootstrap compiler
module boundaries. The Zig bootstrap compiler remains the trusted compiler until
the Jai port can compile `examples/hello.jai` end-to-end.

Clean generated output:

```sh
make clean
```

## Running the Bootstrap Compiler Directly

After `make bootstrap`, compile a supported source file with:

```sh
out/bootstrap/bin/openjai examples/03/3.1_hello_sailor.jai \
  -o out/examples/03/3.1_hello_sailor \
  --runtime out/bootstrap/lib/openjai_runtime.o
```

The compiler CLI is currently:

```text
openjai <input.jai> [--check] [-o output] [--runtime runtime.o]
```

## Examples

`make examples` runs the broad compile-through acceptance sweep for the example
corpus. The `SUPPORTED_EXAMPLES` list is discovered dynamically from
`examples/**/*.jai`.

You can also override the example list:

```sh
make examples EXAMPLES="examples/03/3.1_hello_sailor.jai examples/05/5.1_literals.jai"
```

## Tests

The project has two layers of tests:

- `make test-bootstrap`: Zig unit tests for the bootstrap compiler.
- `make test-jai`: Jai-style tests described by
  [`docs/open_jai_test_spec.md`](docs/open_jai_test_spec.md).

Use `make test` for the full local suite.

## Git Hygiene

Build products are intentionally kept out of the source tree and ignored by git:

- `out/`
- `**/.zig-cache/`
- `**/zig-out/`
- `**/.build/`

Generated artifacts should go under `out/`, not next to source files.

## License

The OpenJai compiler is MIT licensed.
