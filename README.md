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

Current support is intentionally narrow. It can compile a small Phase 1 subset
of the examples, while the complete language described in the spec remains
work in progress.

## Repository Layout

```text
bootstrap/   Zig implementation of the bootstrap compiler
docs/        Language spec and compiler implementation notes
examples/    Jai/OpenJai example programs used as compiler milestones
out/         Generated build output, ignored by git
```

Important docs:

- [`docs/open_jai_spec.md`](docs/open_jai_spec.md): language goals and
  specification notes.
- [`docs/OpenJai_implementation_notes.md`](docs/OpenJai_implementation_notes.md):
  bootstrap compiler architecture and implementation plan.

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

Example binaries and objects are written under `out/examples/`, mirroring the
source tree.

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
openjai <input.jai> [-o output] [--runtime runtime.o]
```

## Examples

`make examples` builds the examples that the current Phase 1 compiler supports.
As language support grows, add more files to `SUPPORTED_EXAMPLES` in the
[`Makefile`](Makefile).

You can also override the example list:

```sh
make examples EXAMPLES="examples/03/3.1_hello_sailor.jai examples/05/5.1_literals.jai"
```

## Git Hygiene

Build products are intentionally kept out of the source tree and ignored by git:

- `out/`
- `**/.zig-cache/`
- `**/zig-out/`
- `**/.build/`

Generated artifacts should go under `out/`, not next to source files.

## License

The OpenJai compiler is MIT licensed.
