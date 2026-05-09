# OpenJai True Runtime Design

This document defines the runtime architecture OpenJai is implementing in the
bootstrap compiler. It is inspired by With's actual source layout and linker
behavior, and by Zig's target-driven standard-library/runtime layering, but
adapted to Jai's language surface and OpenJai's current bootstrap source.

The current OpenJai seed runtime is useful only as a bootstrapping artifact:
`bootstrap/rt/core.zig` exports `__openjai_*` symbols, `bootstrap/build.zig`
installs `openjai_runtime.o`, and `bootstrap/src/link.zig` can consume either a
single object or a manifest. That is not the final runtime model. The final
model must make runtime support explicit, target-aware, inspectable, and
replaceable by Jai sources as the compiler becomes more complete.

The end-state language rule is strict: OpenJai is 100% self-hosted and the
repository contains only Jai and assembly source. Zig, C, C++, Objective-C,
Rust, shell-generated source, or other implementation languages are allowed
only as temporary bootstrap scaffolding while the compiler is being brought up.
Every such file must have a Jai-or-assembly replacement path and must be deleted
from the final self-hosted codebase.

## Goals

- No placeholder-backed runtime behavior. If generated code needs a runtime
  symbol, it must be implemented by a runtime object or linking must fail with a
  clear diagnostic.
- Keep all build artifacts under `out/`.
- Support a stable runtime ABI for generated programs independent of the
  bootstrap implementation language.
- Finish with a Jai-plus-assembly-only repository. No C, C++, Zig, Objective-C,
  Rust, or other implementation-language source remains in the self-hosted
  tree.
- Split target-independent runtime services from target-specific OS backends.
- Link only the runtime objects a program actually needs.
- Own program startup explicitly, including `_start`/platform entry bridges, runtime
  initialization, command-line argument capture, user `main` dispatch, and
  process termination.
- Make runtime and linker selection target-driven at compile/link time, not
  based on runtime kernel probing.
- Make inline assembly a compiler/codegen feature, not a runtime stub.
- Preserve manifest-based linking so Zig and Jai runtime objects use the same
  user-facing `--runtime` contract while the runtime source is ported.

## Architecture

Generated Jai code calls `__openjai_*` runtime support functions. The
target-independent runtime implements those support functions in terms of a
small lower-level platform ABI named `oj_rt_*`.

```text
user Jai code
  -> selected startup object
  -> __openjai_runtime_init(argc, argv)
  -> user main / __program_main
  -> generated calls to __openjai_* helpers
  -> openjai_rt_core object
  -> oj_rt_* platform ABI
  -> one selected platform backend object
  -> OS ABI / freestanding hooks
```

There are two runtime layers:

- **Core runtime**: allocation policy, strings, arrays, print formatting,
  assertion/panic support, type-info helpers, dynamic array helpers, and
  compiler-emitted support symbols.
- **Platform backend**: file descriptors, process exit, clock, arguments,
  environment, virtual memory, path/file operations, and other OS calls.
- **Startup shim**: selected per target/output mode. It owns the executable
  entry symbol, calls `__openjai_runtime_init`, dispatches the user program, and
  exits through the platform backend. It is separate from the core runtime so
  dynamic libraries, tests, freestanding outputs, and normal executables can
  use different entry contracts without changing generated user code.

The core runtime must not call libc, libSystem, Win32, or raw syscalls directly.
It calls only `oj_rt_*`. A platform backend owns all OS ABI details.

## Runtime Object Set

The manifest lists runtime objects in dependency order. The full runtime set is
part of this implementation, not a deferred expansion:

```text
openjai_rt_core.o
openjai_rt_start_exe.o
openjai_rt_platform_darwin_aarch64.o
openjai_rt_panic.o
openjai_rt_file.o
openjai_rt_process.o
openjai_rt_thread.o
openjai_rt_allocator_debug.o
openjai_rt_type_info.o
openjai_rt_compiler_host.o
```

The current bootstrap can build these objects from Zig sources first. That is
temporary scaffolding only. The stable contract is the object names, exported
symbols, and manifest format. The same manifest entries are preserved as each
object is ported to Jai or assembly runtime source. The finished runtime object
set is produced from only Jai and assembly.

## Zig-Derived Design Decisions

Zig's actual source model is the comparison point for runtime structure:

- Startup is real runtime source selected by target/output mode, not incidental
  linker behavior. OpenJai follows this by making startup objects explicit.
- Target selection happens from compile/link configuration. OpenJai does not
  inspect the running kernel to decide which syscall ABI to use.
- The OS boundary stays low and narrow. Zig routes through `std.posix`,
  `std.c`, or raw Linux syscall modules; OpenJai routes through `oj_rt_*`.
- Darwin uses libSystem because raw Darwin syscalls are not a stable public
  ABI. Linux raw syscall backends require real inline assembly support.
- The linker must become a target-aware graph builder. The current `cc`
  invocation is a bootstrap mechanism; the design requires explicit startup,
  core runtime, backend runtime, system libraries, and feature object edges.

The major intentional difference from Zig is ABI shape. Zig mostly compiles
standard-library runtime source directly into each program. OpenJai keeps a
stable generated-code ABI (`__openjai_*`) because Jai's standard modules,
runtime type information, `Any`, printing, allocation, and compiler-host
features need a fixed boundary while the runtime implementation moves from Zig
objects to Jai and assembly source. Unlike Zig, OpenJai's final repository does
not keep an implementation-language runtime/compiler layer underneath the
self-hosted compiler.

## Platform ABI

The platform ABI is deliberately small. It is the only OS boundary available to
core runtime and standard-module behavior.

All functions that can fail return negative OpenJai error codes. Pointer-return
functions return null on failure. Backends convert native error reporting
(`errno`, `GetLastError`, Mach/Kern errors, freestanding hooks) to OpenJai
errors.

Core ABI:

```c
int64_t  oj_rt_write(int32_t fd, const uint8_t *data, uint64_t len);
int64_t  oj_rt_read(int32_t fd, uint8_t *data, uint64_t len);
int32_t  oj_rt_open(const uint8_t *path_z, int32_t flags, int32_t mode);
int32_t  oj_rt_close(int32_t fd);
int64_t  oj_rt_seek(int32_t fd, int64_t offset, int32_t whence);
int32_t  oj_rt_stat(const uint8_t *path_z, OpenJai_Rt_Stat *out);
int32_t  oj_rt_mkdir(const uint8_t *path_z, int32_t mode);
int32_t  oj_rt_getcwd(uint8_t *buf, uint64_t len);

void    *oj_rt_mmap(uint64_t len);
void     oj_rt_munmap(void *ptr, uint64_t len);

void     oj_rt_exit(int32_t code);
int64_t  oj_rt_clock_realtime_ns(void);
int64_t  oj_rt_clock_monotonic_ns(void);
int32_t  oj_rt_to_calendar(uint64_t low_ns, int64_t timezone, OpenJai_Calendar *out);
const uint8_t *oj_rt_getenv_z(const uint8_t *name_z);
```

Process arguments are normalized by the selected startup object and passed to
`__openjai_runtime_init(argc, argv)`. They are not queried from the platform
backend by core runtime code.

Required data layout:

```c
typedef struct OpenJai_Rt_Stat {
    int64_t size;
    int32_t is_dir;
    int32_t is_file;
    int64_t modified_ns;
} OpenJai_Rt_Stat;
```

OpenJai canonical flags:

```text
OJ_O_RDONLY = 0
OJ_O_WRONLY = 1
OJ_O_RDWR   = 2
OJ_O_CREAT  = 0x0200
OJ_O_TRUNC  = 0x0400
OJ_O_APPEND = 0x0800

OJ_SEEK_SET = 0
OJ_SEEK_CUR = 1
OJ_SEEK_END = 2
```

OpenJai error codes use POSIX-compatible values for portability:

```text
OJ_EPERM=1, OJ_ENOENT=2, OJ_EIO=5, OJ_EBADF=9, OJ_EAGAIN=11,
OJ_ENOMEM=12, OJ_EACCES=13, OJ_EEXIST=17, OJ_ENOTDIR=20,
OJ_EISDIR=21, OJ_EINVAL=22, OJ_ENFILE=23, OJ_EMFILE=24,
OJ_ENOSPC=28, OJ_EPIPE=32, OJ_ERANGE=34, OJ_ENOSYS=38
```

Backends retry interruptible syscalls internally where the platform has an
`EINTR` concept. Core runtime code does not know about `EINTR`.

## Platform Backend Selection

Selection is target based, not runtime kernel probing:

| Target | Backend strategy |
| --- | --- |
| Darwin aarch64/x86_64 | libSystem ABI wrappers. Darwin syscall ABI is not a stable public contract. |
| Linux aarch64/x86_64 | raw syscalls through backend assembly; the Jai `#asm` implementation must be capable of expressing the same wrappers. |
| Windows x86_64/aarch64 | Win32/NT API backend with fd-to-handle translation. |
| Freestanding | weak user-overridable hooks or explicit `ENOSYS` stubs. |

The runtime implementation includes Darwin and Linux backends as first-class
targets. Windows and freestanding backends use the same object contract.
Unsupported targets fail during link/runtime selection with a target-specific
message until their backend object exists.

## Startup Contract

OpenJai owns process startup instead of relying on an accidental host-language `main`
shape. The selected startup object is responsible for:

1. Exporting the target/output-mode entry symbol.
2. Normalizing `argc`/`argv` or platform-equivalent process arguments.
3. Calling `__openjai_runtime_init(argc, argv)`.
4. Calling the generated user entry bridge.
5. Calling `__openjai_runtime_fini()`.
6. Exiting through `oj_rt_exit(status)`.

Required startup variants:

```text
openjai_rt_start_exe.o              normal native executable
openjai_rt_start_test.o             test runner executable
openjai_rt_start_dynamic_library.o  dynamic library initialization hooks
openjai_rt_start_freestanding.o     user-provided entry hook
```

The bootstrap may initially implement only the native executable startup for
the host target, but missing variants are not treated as success. Selecting an
unsupported output mode fails with a diagnostic naming the missing startup
object.

## Core Runtime Symbols

Generated code calls stable high-level symbols. Existing `__openjai_*` names
remain, but their implementation lives in core runtime objects and calls
`oj_rt_*` internally.

Required core symbols:

```text
__openjai_runtime_init(argc, argv)
__openjai_runtime_fini()

__openjai_print(data, len)
__openjai_print_return_int(data, len)
__openjai_print_int(value)
__openjai_print_format_int(value, base, minimum_digits)
__openjai_print_float(value)
__openjai_print_format_float(value, width, trailing_width, zero_removal, mode)
__openjai_print_bool(value)
__openjai_print_type(type_id)

__openjai_alloc(size)
__openjai_realloc(ptr, old_size, new_size)
__openjai_free(ptr)
__openjai_memcpy(dst, src, len)
__openjai_memset(dst, byte, len)
__openjai_memcmp(a, b, len)

__openjai_assert_fail(location, message)
__openjai_panic(location, message)
__openjai_exit(status)

__openjai_arg_count()
__openjai_arg_value(index)
__openjai_read_entire_file(path_data, path_len)
__openjai_write_entire_file(path_data, path_len, contents_data, contents_len)
__openjai_get_time_ns()
__openjai_seconds_since_init()
```

Dynamic/static array support must be real runtime ABI, not ad hoc raw heap
bytes:

```text
__openjai_new_array(count, element_size, element_align)
__openjai_array_free(array)
__openjai_array_count(array)
__openjai_array_data(array)
```

`NewArray(count, T, alignment=N)` lowers to this runtime API and returns
the actual Jai array representation expected by indexing, `.count`, iteration,
and `array_free`.

## Runtime Type Information

Jai examples rely on runtime type information for printing, `type_info`,
`runtime_size`, enum/struct metadata, and `Any`. This is a required runtime
object backed by a codegen-emitted type table.

Design:

- Codegen emits a readonly type table section for every compiled program.
- `__openjai_print_type`, `type_info`, and `Any` helpers read that table.
- Build options such as `runtime_storageless_type_info` and
  `#type_info_none` affect emitted table content, not runtime placeholder
  behavior.
- Missing metadata produces a deterministic runtime diagnostic if accessed
  despite being disabled.

## Linker Contract

The existing manifest support in `bootstrap/src/link.zig` is the right base.
It is extended into a target-aware linker graph:

1. **Target-aware manifest selection**
   - default runtime path resolves to `out/bootstrap/lib/openjai_runtime.manifest`;
   - manifest includes target tags or is target-specific by filename, e.g.
     `openjai_runtime_darwin_aarch64.manifest`;
   - link fails if no backend matches the compilation target.

2. **Explicit startup/core/backend edges**
   - select exactly one startup object from output mode and target;
   - include `openjai_rt_core.o`;
   - include exactly one platform backend object;
   - include target system libraries required by the backend, such as
     libSystem on Darwin or no libc for Linux raw-syscall mode.

3. **Symbol-driven object selection**
   - compile object first;
   - run `nm -u` or platform equivalent;
   - include only needed feature runtime objects;
   - always include core + selected platform backend.

4. **Embedded runtime fallback**
   - embed runtime objects into the compiler binary;
   - prefer fresh objects under `out/bootstrap/lib`;
   - fall back to extracted embedded objects under `out/tmp/openjai_runtime`.

No runtime object is silently optional if a referenced symbol remains
unresolved. Link errors name the missing runtime symbol and the runtime
object expected to provide it.

## Inline Assembly

Inline assembly is not runtime functionality. It must be implemented as a
compiler pipeline feature:

```text
parser (#asm block)
  -> typed AST node preserving template, constraints, clobbers, modifiers
  -> sema validation against target and register class
  -> IR intrinsic or backend-specific low-level node
  -> LLVM inline asm or target assembler emission
```

Runtime backends use standalone `.s` files for raw syscall stubs until Jai
`#asm` lowering is complete. After that, Linux raw syscall backends can live in
Jai runtime source containing `#asm`. Darwin keeps using libSystem wrappers
because that is the stable ABI.

Calling a platform ABI does not permit platform-language source in the
repository. Darwin bindings, Windows bindings, and other OS declarations are
written in Jai. Any required raw target glue is assembly.

The non-placeholder `#asm` implementation:

- parse Jai `#asm` blocks into a structured AST instead of compile-through text;
- reject unsupported modifiers/registers loudly;
- lower simple clobber-only and single-output blocks;
- add regression tests from `examples/28`;
- enables Linux syscall wrappers to move from standalone assembly to Jai source.

## Implementation Plan

1. **Freeze the manifest contract**
   - Keep direct-object compatibility.
   - Make manifest entries explicit and documented.
   - Verify `make runtime` prints all active runtime objects.

2. **Add explicit startup objects**
   - Add host executable startup as `openjai_rt_start_exe.o`.
   - Route program startup through `__openjai_runtime_init`,
     generated user entry, `__openjai_runtime_fini`, and `oj_rt_exit`.
   - Fail unsupported output modes with missing-startup diagnostics.

3. **Introduce `oj_rt_*` backend ABI**
   - Add a platform layer under `bootstrap/rt/`.
   - Move direct libc/libSystem/Zig std process/file calls out of core runtime.
   - Core runtime calls only `oj_rt_*`.

4. **Split runtime objects**
   - Produce `openjai_rt_core.o` and one host backend object.
   - Update manifest to list both.
   - Link hello and file I/O examples through the split manifest.

5. **Make allocation and arrays real**
   - Replace `malloc/free` core use with allocator-on-`oj_rt_mmap`.
   - Implement `__openjai_new_array` and lower `NewArray` to it.
   - Add behavioral tests for examples using `New`, `NewArray`, indexing, and
     `array_free`.

6. **Move file/time/args to platform ABI**
   - Implement read/write entire file from
     `oj_rt_open/read/write/close/stat/mkdir`.
   - Implement arguments from `__openjai_runtime_init`.
   - Implement time through `oj_rt_clock_realtime_ns` and
     `oj_rt_clock_monotonic_ns`.
   - Implement local/UTC calendar conversion through `oj_rt_to_calendar`.

7. **Replace opaque linker invocation with a target-aware linker graph**
   - Model startup, core runtime, backend runtime, feature runtime objects, and
     system libraries as explicit graph edges.
   - Include feature runtime objects based on unresolved symbols.
   - Keep core/backend mandatory.
   - Emit clear diagnostics for missing runtime providers.

8. **Implement real `#asm`**
   - Parser/sema/codegen first.
   - Then add Linux raw syscall backend.

9. **Port runtime from Zig to Jai/assembly**
   - Keep the same symbols and manifest names.
   - Replace Zig object sources one runtime object at a time.
   - Write platform declarations in Jai and raw target glue in assembly.
   - Gate each replacement with bootstrap tests and example behavioral tests.

10. **Delete non-Jai/non-assembly implementation sources**
   - Remove remaining Zig runtime/compiler/bootstrap sources once the Jai
     compiler can rebuild itself.
   - Remove any generated C/C++/Objective-C/Rust bridge source if introduced
     during bootstrapping.
   - Keep only Jai, assembly, documentation, tests, and build metadata needed
     to build the self-hosted compiler/runtime.

## Verification Gates

Runtime work is not done when examples compile. Each milestone needs behavioral
checks:

- `make runtime` lists target-aware object manifests.
- Native executable startup runs through OpenJai startup, init, fini, and
  `oj_rt_exit`, not incidental C `main` behavior.
- `examples/hello.jai` builds and runs using the split runtime.
- File read/write examples build and run without Zig std file helpers in core.
- Allocation examples validate real memory layout and deallocation.
- `NewArray` examples validate count, indexing, alignment, and `array_free`.
- Time/args examples validate runtime values, not compile-time placeholders.
- Unsupported target/backend combinations fail with explicit diagnostics.
- `#asm` examples either run correctly or fail at parse/sema with exact
  unsupported-feature diagnostics.
- A source audit can enforce the final language rule: implementation source is
  Jai or assembly only, with no C, C++, Zig, Objective-C, Rust, or other
  implementation-language files left in the self-hosted tree.

The strict rule remains: if the compiler accepts a runtime-facing feature, it
must either lower to real runtime/compiler functionality or fail loudly at the
first unsupported phase.
