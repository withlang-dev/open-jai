# OpenJai Cross-Compilation Plan

OpenJai does not currently support true cross-compilation. This plan describes
the implementation path for compiling on one host while producing binaries for a
different target.

## Goal

Make the target platform explicit throughout the compiler pipeline:

```text
Jai source
  -> parse and semantic analysis
  -> target-independent bytecode/IR
  -> target-specific object file
  -> target-specific runtime objects
  -> target-specific linker
  -> executable for the requested target
```

This is required for a post-self-host bootstrap strategy where an existing
OpenJai compiler can produce seed compilers for new platforms.

## 1. Add A Real Target Model

Introduce a compiler target object instead of relying on the host platform.

Required fields:

```text
Target
  os: linux | macos | windows
  arch: x86_64 | aarch64
  abi: gnu | musl | macos | msvc | none
  object_format: elf | macho | coff
  pointer_size
  endian
  llvm_triple
```

Add CLI support:

```sh
openjai main.jai -target linux-x86_64
openjai main.jai -target linux-aarch64
openjai main.jai -target macos-aarch64
```

The default target remains the host target.

## 2. Remove Host Assumptions From Compiler Decisions

Audit all compiler code that uses host OS/architecture information. Replace
semantic target decisions with the requested `Target`.

Host information is still valid for:

- running the compiler process;
- compile-time execution services used by `#run`;
- host filesystem/process access during metaprogramming.

Requested target information must drive:

- pointer size and layout;
- ABI/calling convention;
- object format;
- LLVM triple;
- runtime manifest selection;
- linker selection and arguments.

## 3. Separate Host Compile-Time Execution From Target Runtime

`#run` executes on the host machine. Emitted program code runs on the target.

Examples:

```text
#run file_exists(...)      -> host file operation
runtime file_exists(...)   -> target runtime call
```

The compile-time VM and compiler intrinsics must continue to use host services.
The LLVM/object backend must emit calls to target runtime symbols.

## 4. Make Runtime Manifests Target-Specific

Install runtime manifests and objects by target:

```text
out/bootstrap/lib/runtime/macos-aarch64/openjai_runtime.manifest
out/bootstrap/lib/runtime/linux-x86_64/openjai_runtime.manifest
out/bootstrap/lib/runtime/linux-aarch64/openjai_runtime.manifest
```

Manifest shape:

```text
target linux x86_64
object openjai_rt_start_exe.o
object openjai_rt_core.o
object openjai_rt_platform_linux_x86_64.o
system_library c
```

The compiler must select the manifest by requested target, not host target.

## 5. Compile Runtime Objects Per Target

Runtime code should be split into:

- target-independent core runtime;
- executable entry/start code;
- target OS/architecture platform layer.

Initial targets:

```text
macos-aarch64
linux-x86_64
linux-aarch64
```

Linux runtime should avoid unnecessary libc dependency where practical. Raw
syscall-backed runtime code makes cross-linking much easier because it avoids a
target sysroot for simple programs.

## 6. Teach LLVM Codegen To Use Requested Target

LLVM codegen must set the module target triple from `Target`, not from the host.

Examples:

```text
x86_64-unknown-linux-gnu
aarch64-unknown-linux-gnu
arm64-apple-macosx
x86_64-apple-macosx
```

The target machine must emit object files for the requested target:

```text
linux   -> ELF
macos   -> Mach-O
windows -> COFF
```

## 7. Add Target-Specific Linker Selection

Use LLD with target-appropriate flavor:

```text
Linux ELF:   ld.lld
macOS:       ld64.lld
Windows:     lld-link
```

Linux example:

```sh
ld.lld main.o openjai_rt_start_exe.o openjai_rt_core.o openjai_rt_platform_linux_x86_64.o -o app
```

macOS example:

```sh
ld64.lld main.o openjai_rt_start_exe.o openjai_rt_core.o openjai_rt_platform_macos_aarch64.o \
  -o app \
  -lSystem \
  -syslibroot <macos-sdk>
```

If target libc/system libraries are needed, the linker must accept an explicit
target sysroot. The early implementation should prefer runtime paths that do
not require target libc for basic programs.

## 8. Implement In Small Targeted Milestones

Milestone 1: target parsing and plumbing

- Add `-target`.
- Store target in compiler options.
- Preserve host target as default.
- Print target in verbose/build diagnostics.

Milestone 2: runtime target manifests

- Generate/install target-named runtime objects.
- Generate target-specific manifests.
- Select runtime manifest by requested target.

Milestone 3: LLVM target triple

- Thread target into LLVM codegen.
- Set module triple.
- Emit target object file.

Milestone 4: Linux object/link path

- Cross-emit `hello.jai` from macOS to Linux object.
- Link with `ld.lld`.
- Run on Linux or under an emulator/container.

Milestone 5: bootstrap seed production

- Build `openjai` for a non-host target.
- Copy seed to target machine.
- Run stage chain on target:

```sh
./openjai-seed src/main.jai -o out/stage1/openjai
./out/stage1/openjai src/main.jai -o out/stage2/openjai
./out/stage2/openjai src/main.jai -o out/stage3/openjai
cmp out/stage2/openjai out/stage3/openjai
```

## 9. Verification

Add tests for:

- target string parsing;
- target object format selection;
- runtime manifest selection;
- LLVM triple selection;
- compile-time host operations still using host behavior;
- generated runtime calls using target runtime symbols;
- cross-target `hello.jai` object emission;
- cross-target link smoke tests where toolchains are available.

## Non-Goals

- Do not implement cross-compilation as scattered host checks.
- Do not make generated C the default bootstrap path.
- Do not require maintaining two compilers after self-hosting; archived bootstrap
  and seed binaries are bootstrap artifacts, not active compiler frontends.

