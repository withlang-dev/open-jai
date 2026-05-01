# The OpenJai Language Specification

By Eric Hartford
Quixi AI
Lazarus AI

This specification was created by reading "The Way to Jai" by Ivo Balbaert (https://github.com/Ivo-Balbaert/The_Way_to_OpenJai)
It is being used to create OpenJai - an open source implementation of the Jai compiler.

---

## 1. Status and Origin

- Jai was created by Jonathan Blow, game designer/developer and CEO of Thekla
  Inc., known for _Braid_ (2008) and _The Witness_ (2016), both written in C++.
- Jai is closed source.
- OpenJai was created by Eric Hartford, Founder and CEO of Quixi AI, and Chief
  Scientist of Lazarus AI.
- OpenJai is open source.


### Release Plan

- OpenJai is publically available on GitHub today.  (https://github.com/withlang-dev/open-jai)


### Licensing

- The OpenJai compiler is MIT licensed

### Business Model

None.

---

## 2. Language Classification

- OpenJai is an **ahead-of-time (AOT) compiled**, **imperative**, **statically
  typed**, **strongly typed** language.
- It is **not** an object-oriented language -- no classes, no inheritance.
- Its primary focus is **game programming**, but it is also suited for
  **general-purpose** and **low-level systems programming** (comparable to
  C/C++, D, or Rust). OpenJai is lower-level than Java or C#.
- Blow describes OpenJai as "C+" -- between C and C++, or "C++ done right."
- OpenJai allows programmers to get as low-level as they desire.
- Designed for good programmers; no training wheels for beginners.

---

## 3. Design Goals and Priorities

OpenJai's priorities, in explicit order:

1. **Developer productivity** -- quality of life, simplicity, expressive power,
   and joy.
2. **Performance** -- on par with C++ or even C.
3. **Safety** -- bounds checking, default initialization, useful error messages.

### Properties Derived from These Priorities

- Simple, consistent syntax with expressive power.
- A very high-speed compiler (goal: 1M lines/sec from scratch).
- Excellent runtime performance.
- Fast by default, simple by default -- avoids slow-by-default abstractions
  that require additional complexity to recover performance.
- Language concepts should be orthogonal, not conflicting.
- Designed to leave room for personal programming style.

### What OpenJai Explicitly Does Not Have

In the interest of performance and simplicity, OpenJai has **none** of:

- Garbage collection (GC)
- Automatic memory management (manual memory management required)
- Exception handling (considered too complex, too heavy on performance)
- RAII (Resource Acquisition Is Initialization) -- avoids the friction of
  mandatory copy constructors, move constructors, iterators, etc.
- `goto`
- Header files
- Forward declarations
- Preprocessor macros (OpenJai macros are more like Lisp macros)
- External build systems (makefiles, CMake, etc.) -- builds are controlled
  from within the language

---

## 4. Compiler

### Overview

- Compilation speed goal: 1 million lines of code in < 1 second (from scratch,
  no delta builds).
- No header files, no forward declarations needed.
- The build process is controlled from within the language itself and is the
  same across all platforms.


### Architecture

OpenJai source code is processed through the following pipeline:

```
Source code → AST → Byte-code → Machine code
                                  ↑
                          (via LLVM IR, or directly via x64 backend)
```

1. **Front-end**: Source code is parsed into an **abstract syntax tree** (AST),
   which is then converted to an internal **byte-code**. The front-end is
   primarily written by Jonathan Blow.
2. **Back-end**: The byte-code is converted to executable machine code by one
   of two backends (see "Backends" below).

The compiler uses a hand-written **recursive descent top-down parser**. It
does **not** process code in a single pass in lexical order (as C++ does).
Instead, the compiler performs **multiple passes** to find all definitions,
which is why forward declarations are not needed and definition/declaration
order is irrelevant.

The compiler runs **multi-threaded** as a kind of job system.

### Byte-Code Interpreter

The compiler contains an internal **byte-code interpreter** that can execute
programs at **compile-time** (e.g., via the `#run` directive). When a
procedure or program is run at compile-time, its byte-code is executed by
this interpreter. The results (calculated values, procedures constructed
through meta-programming, etc.) are funneled back into the source code, and
compilation continues as normal.

At run-time, a OpenJai executable runs native machine code directly -- the
byte-code interpreter is not involved.

### Compile-Time AST Access

The developer can:
- **Modify the generated AST** at compile-time (via meta-programming and
  macros).
- **Access the compiler** through a **compiler message loop** (a structured
  interface for communicating with the compiler during compilation).


### Platform Support

- **Windows** (primary development platform, because most games target Windows
  first).
- **Linux** (64-bit).
- **macOS**.
- **WSL2** (Windows Subsystem for Linux) is also supported.

Compiler executable names:

| Platform | Executable   |
|----------|--------------|
| Windows  | `OpenJai.exe`    |
| Linux    | `OpenJai-linux`  |
| macOS    | `OpenJai-macos`  |

On Linux/macOS, the executable is typically renamed to `OpenJai` after extraction
and made executable with `chmod +x`.

The LLVM linker is bundled per-platform as `lld-linux` or `lld-macos` (also
requires `chmod +x`).

#### Supported Architectures

- **x86** architecture only (with limited Nintendo Switch support).
- **OS / Platforms**: Windows, (Ubuntu) Linux, macOS, at least one gaming
  console.
- The LLVM backend can in principle target the full range of architectures and
  platforms that LLVM supports.

### Platform Prerequisites

- **Windows**: Requires at least one Windows SDK and one Visual C++
  Redistributable installed. If not present, run `vs_BuildTools.exe` and
  install C++ build tools.
- **Linux (64-bit)**: Some distributions (Ubuntu, Mint, etc.) may point
  `libdl`, `librt`, or `libpthread` to 32-bit versions. Fix by installing
  `libc6-dev-amd64`. For OpenGL modules (e.g., `Simp`), install `libgl-dev`.
- **WSL2**: The OpenJai compiler must reside inside the WSL filesystem; placing it
  on the Windows filesystem causes ~10x slower compilation.

### Backends

The compiler supports two code-generation backends:

| Backend | Flag    | Description                                |
|---------|---------|--------------------------------------------|
| LLVM    | `-llvm` | The default backend. Converts byte-code to LLVM IR, then to machine code. Performs elaborate code optimizations. Slower compilation, but produces faster/smaller executables. Intended for production/release builds. Targets the full range of LLVM-supported architectures. |
| x64     | `-x64`  | A custom backend. Converts byte-code directly to x64 machine code. Fast but naive code generation with no optimization. Intended for development-phase builds. |

WebAssembly (WASM) output is also possible via the LLVM backend, enabling
browser-based deployment of OpenJai programs.

The backend can be overridden by a metaprogram at build time.

The LLVM backend is the default and can be explicitly specified with
`OpenJai -llvm filename.OpenJai` (but `-llvm` can be left out).

### Debug and Release Builds

**Debug builds** (the default) are intended for development:
- A `.pdb` file with debugging info is produced (Windows).
- Stack trace information is included.
- Optimizations are disabled to avoid hiding erroneous behavior.

**Release builds** are intended for production deployment:
- Enabled with the `-release` flag: `OpenJai -release program.OpenJai`.
- No debugging or stack-trace info.
- All optimizations enabled (LLVM `-O2`).
- The LLVM backend is recommended for release builds.
- Build options can also be configured from within OpenJai code via the build
  system and `Build_Options`.

Example executable sizes (hello world program, Windows):

| Mode    | x64 backend | LLVM backend |
|---------|-------------|--------------|
| Debug   | 367 MB      | 268 MB       |
| Release | 314 MB      | 122 MB       |

To reduce build time:
- Remove the `.pdb` file before compiling.
- Compile with the x64 backend.

### Command-Line Interface

Running `OpenJai` with no arguments prints:

> _You need to provide an argument telling the compiler what to compile!
> Sorry. Pass -help for help._

Use `OpenJai -help` or `OpenJai -?` to see all available options.

#### Invocation Structure

The full invocation syntax is:

```
OpenJai <options> program.OpenJai - <user metaprogram args> -- <meta options> +Plugin <plugin options>
```

- **`<options>`** -- zero or more compiler flags (may also appear after the
  source file name).
- **`program.OpenJai`** -- any argument not starting with `-`, and before a lone
  `-`, is the name of the file to compile.
- **`-` (lone dash)** -- separates compiler arguments from user metaprogram
  arguments. Everything after `-` is ignored by the compiler and passed to
  the user-level metaprogram (see also "compiler command-line arguments").
- **`--`** -- introduces front-end options for the metaprogram (e.g.,
  `-- import_dir`, `-- meta`).
- **`+Plugin`** -- invokes a plugin (see "Plugins" below).

Simple examples:

```
OpenJai program.OpenJai
OpenJai -x64 -release program.OpenJai
OpenJai program.OpenJai -x64
OpenJai -x64 program.OpenJai - info for compile_time execution
```

#### Compiler Options Reference

**Backends:**

| Flag    | Description                                              |
|---------|----------------------------------------------------------|
| `-x64`  | Use the x64 backend (unless overridden by a metaprogram). |
| `-llvm` | Use the LLVM backend (default).                          |

**Code injection:**

| Flag       | Description                                            |
|------------|--------------------------------------------------------|
| `-add arg` | Add the string `arg` to the target program as code.    |
| `-run arg` | Start a `#run` directive that parses and runs `arg` as code. |

`-add arg` injects `arg` as source code into the target program. Declarations
made this way are visible to the program as if they were written in the source
file. For example, `-add "n := 42"` makes the variable `n` available to the
program at file scope.

`-run arg` wraps `arg` in a `#run` directive and executes it at compile time.
The output appears in the compiler output before the program is compiled. For
example, `-run write_string(\"Hello!\n\")` prints `Hello!` during compilation.
On Windows, `-run` only works from a `cmd` prompt window, not from Terminal.

Multiple flags can be combined:

```
OpenJai -run write_string(\"Hello!\n\") -add "n := 42" -verbose program.OpenJai
```

**Debugging:**

| Flag            | Description                                         |
|-----------------|-----------------------------------------------------|
| `-debugger`     | Drop into the interactive debugger on a crash during compile-time execution. |
| `-debug_for`    | Enable debugging of `for_expansion` macros (otherwise the debugger skips them). |
| `-very_debug`   | Build with extra debugging facilities (slower execution, catches more problems). |
| `-msvc_format`  | Use Visual Studio's message format for error messages. |
| `-natvis`       | Use natvis-compatible type names in debug info (`array<T>` instead of `[] T`, etc.). |
| `-verbose`      | Output extra information about what the metaprogram is doing (input files, add strings, run strings, plugins, output path, executable name). |
| `-no_inline`    | Disable inlining throughout the program (useful when debugging). |

**Output:**

| Flag               | Description                                      |
|--------------------|--------------------------------------------------|
| `-output_path dir` | Set the directory for output files (e.g., the executable). |
| `-exe name`        | Set the output executable name.                  |
| `-no_color`        | Disable ANSI terminal coloring in output messages. |
| `-quiet`           | Reduce statistics output from the compiler.      |

**Modules:**

| Flag               | Description                                      |
|--------------------|--------------------------------------------------|
| `-import_dir path` | Add a directory to the list searched by `#import`. Can be used multiple times. |
| `-- import_dir path` | Same, but for importing modules into the metaprogram. |

**Performance / optimization:**

| Flag                     | Description                                |
|--------------------------|--------------------------------------------|
| `-release`               | Disable stack traces and enable optimizations (LLVM `-O2`). |
| `-release_debug`         | Like `-release` but less optimized; keeps user-level stack traces. |
| `-no_dce`                | Turn off dead code elimination (temporary flag; prefer `Build_Options`). |
| `-no_check`              | Do not import `modules/Check`; disables augmented error checking (e.g., for `print()` calls). |
| `-no_check_bindings`     | Disable checking of module bindings when `modules/Check` runs. No effect with `-no_check`. |
| `-no_split`              | Disable split modules when compiling with the LLVM backend. |
| `-no_backtrace_on_crash` | Do not catch OS-level exceptions and print a stack trace on crash. Less code imported at startup; crashes may look like silent exits. |
| `-context_size n`        | Set the size of `#Context` in bytes (e.g., `-context_size 2048`). |

**Metaprogram:**

| Flag                  | Description                                   |
|-----------------------|-----------------------------------------------|
| `-- meta Name`        | Replace the default metaprogram with `Name`.  |

**Miscellaneous:**

| Flag             | Description                                        |
|------------------|----------------------------------------------------|
| `-version`       | Print the compiler version.                        |
| `-help` / `-?`   | Print help/usage information.                     |
| `-report_poly`   | Print the Polymorph Report when compilation is done. |
| `-no_cwd`        | Turn off the compiler's initial change of working directory (temporary flag). |

**Developer options** (shown via `OpenJai -- help`):

`import_dir`, `meta`, `-no_jobs`, `-randomize`, `-seed`, `-extra`, `-chaos`

### Plugins

A **plugin** is a module that the metaprogram calls to implement specific
functionality during compilation. All plugins operate within the metaprogram
(compile time), not in the target program.

#### Invoking Plugins

Plugins are invoked on the command line with `-plug Name` (or `-plugin Name`),
or with `+Name` syntax. Each `+` invokes a new plugin, and all arguments
between that `+` and the next `+` are sent to that plugin.

```
OpenJai main.OpenJai -plug TestRunner
OpenJai -x64 program.OpenJai +Icon -icon icon_filename.ico +Autorun
OpenJai -x64 program.OpenJai +Icon -icon icon_filename.ico +Autorun - args for the metaprogram
OpenJai example.OpenJai -plug My_Plugin --- import_dir ../../
```

The `Default_Metaprogram` (see §37) scans for `-plug` arguments, then
initializes and imports those plugins using the `Metaprogram_Plugins` module.

#### How Plugins Receive Compiler Messages

The `Default_Metaprogram` communicates with loaded plugins by passing each
compiler message to every plugin's message callback:

```Jai
message_loop :: (w: Workspace) {
    while true {
        message := compiler_wait_for_message();
        for plugins if it.message it.message(it, message);

        if message.kind == .COMPLETE break;
    }
}
```

Each plugin receives every compiler message and can act on whichever message
kinds are relevant to its functionality. See §37 (Compiler Message Loop) for
details on message kinds.

#### Creating a Plugin

To create a custom plugin, use the `Example_Plugin` module in the standard
distribution as a starting point. The essential requirement is to implement
a `get_plugin` procedure and adapt it to the plugin's needs. The
`Default_Metaprogram` calls `get_plugin` to obtain the plugin's callbacks
(such as the `message` callback shown above).

#### Standard Plugins

The following plugins are included in the standard distribution:

| Plugin | Description | Invocation |
|--------|-------------|------------|
| `Check` | Error-checking plugin that validates constructs such as ensuring `print()` has the correct number of user arguments. | `-plug Check` |
| `Polymorph_Report` | Reports how many polymorphs were deduplicated and which call sites resulted in unique polymorphs of a procedure. | `-plug Polymorph_Report` |
| `Program_Print` | Prints types when encountering a `TYPE_DEFINITION` message. | `-plug Program_Print` |
| `IProf` | Instruments the main program and imported modules for profiling: gathers and reports information on procedure calls. | `-plug IProf` |
| `Autorun` | Automatically runs the program when compilation completes successfully. | `-plug Autorun` |

Example using `Autorun`:

```
OpenJai test.OpenJai -plug Autorun
```

Output:
```
[Autorun] Running: d:/OpenJai/testing/test
Hello, Sailor from OpenJai!
```

### Build Philosophy

OpenJai's command-line options are deliberately minimal. The language favors
**configuration from code**: build options are set from OpenJai code itself
(via the metaprogram and `Build_Options`), which is the same on all
platforms. This replaces external build systems (makefiles, CMake, etc.)
with a single mechanism using the OpenJai language the programmer already knows.

---

## 5. Performance Characteristics

- For simple serial code (math on scalar values): almost equivalent to C.
- For SIMD processing: generated code is 4--8% slower than C.
- Benchmark (Daniel Tan, Dec 2022): OpenJai chess engine Ceij vs. C++ Stockfish:
  - Initially ~20% slower than C++.
  - After replacing SIMD assembly with pure C: only ~5% slower.
  - After hand-optimizing `#asm` blocks: same speed as Stockfish.
- Conclusion: well-written OpenJai code can match C performance.

---

## 6. C Interoperability

- C code and OpenJai code can coexist; they interoperate seamlessly via a
  Foreign Function Interface (FFI).
- OpenJai code can be built on top of existing C libraries.
- This enables gradual migration from C/C++ to OpenJai: project parts can be
  converted incrementally, with OpenJai calling into remaining C modules.
- Calling C is not necessary for performance -- benchmarks show OpenJai performance
  is comparable to C. The main reasons to call C are to reuse existing
  libraries (especially in game development: graphics, audio, compression) and
  to speed up initial development.
- Blow uses C interfaces to OpenGL and stb_image for his OpenJai test code.
- FFI cannot be used during `#run` (compile-time execution).

### The `#foreign` Directive

To access a C function, declare it with a OpenJai signature and add `#foreign`
followed by a library constant. The compiler imports the C function with the
same name.

```Jai
rand  :: () -> s64   #foreign libc;
clock :: () -> s64   #foreign libc;
```

The declaration must use OpenJai syntax and OpenJai types that correspond to the
original C types. The library constant (`libc` above) must be declared
separately via `#system_library` or `#library`.

An optional second argument to `#foreign` specifies the original C function
name when the OpenJai name differs:

```Jai
compress_bound :: (inputSize: s32) -> s32
    #foreign lz4 "LZ4_compressBound";
```

This binds `compress_bound` in OpenJai to the C symbol `LZ4_compressBound` in the
`lz4` library.

### System Libraries (`#system_library`)

`#system_library` declares a named constant representing an OS-level shared
library (a library the OS linker knows how to find by name):

```Jai
libc     :: #system_library "libc";       // Linux C standard library
crt      :: #system_library "msvcrt";     // Windows C runtime
kernel32 :: #system_library "kernel32";   // Windows kernel32
d3d11    :: #system_library "d3d11";      // DirectX 11
```

Functions are then declared against these constants:

```Jai
kernel32 :: #system_library "kernel32";

ReadConsoleA :: (
    hConsoleHandle: HANDLE,
    buff: *u8,
    chars_to_read: s32,
    chars_read: *s32,
    lpInputControl := *void
) -> bool #foreign kernel32;
```

### Dynamic Libraries (`#library`)

`#library` declares a user-provided dynamic library (`.dll` or `.so` file)
for foreign functions written in C, OpenJai, or another language:

```Jai
lz4  :: #library "liblz4";
FMOD :: #library "../../lib/fmod";
```

The path inside the quotes can be a full or relative path (relative to the
source file). The `.dll` or `.so` file must be placed next to the compiled
OpenJai executable at run time.

Functions from the library are then declared with `#foreign`:

```Jai
LZ4_compressBound :: (inputSize: s32) -> s32   #foreign lz4;
LZ4_compress_fast :: (source: *u8, dest: *u8, sourceSize: s32,
    maxDestSize: s32, acceleration: s32) -> s32 #foreign lz4;
LZ4_sizeofState   :: () -> s32                 #foreign lz4;
```

On Windows, the linker requires both a `.dll` and an import library (`.lib`).
The import library contains only linking metadata, not actual code.

### Converting C Header Files

OpenJai does not use header files, but C header files contain the signatures
needed for binding. Steps to convert a C function declaration to OpenJai:

1. Add `::` after the name.
2. Move the return type to the end (after `->`).
3. Swap parameter types and names (OpenJai uses `name: Type` order).
4. Add the `#foreign library` declaration.

Additional conversion rules:

- C `char *` becomes `*u8`.
- C references (`&`) become pointers (`*`).
- Remove C qualifiers like `const`.
- Enums should almost always specify a 32-bit size:
  `IL_Result :: enum s32` or `D3DCOMPILE_FLAGS :: enum_flags u32`.
- For C `int` and `float` where the exact size is unclear, default to 32-bit
  versions (`s32`, `float32`); if data comes out mangled, try a different size.
- Rename any C parameter that collides with a OpenJai keyword (e.g., `context`
  becomes `ctx`).
- After compiling, verify data passed to/from the library: incorrect values
  often indicate incorrectly sized struct members or parameters.

### Callbacks and the `#c_call` Directive

`#c_call` makes a procedure use the C calling convention (C ABI). It is used
for procedures that must be callable from C code, including callbacks passed
to C libraries. The implicit context is **not** passed to `#c_call`
procedures (see §30).

The `#type` directive can be combined with `#c_call` to define a callback
type with the expected C-compatible signature:

```Jai
IL_LoggingLevel :: u16;
IL_Logger_Callback :: #type (level: IL_LoggingLevel, text: *u8,
    ctx: *void) -> void #c_call;
```

This is the OpenJai equivalent of the C typedef:
`typedef void(*IL_Logger_Callback)(IL_LoggingLevel level, const char* text, void* context);`

When implementing a `#c_call` procedure, `void` must be specified explicitly
if the procedure does not return a value. Native OpenJai procedures (like `print`
or `log`) cannot be called directly inside a `#c_call` procedure -- you must
first establish a context with `push_context`:

```Jai
logger_callback :: (level: IL_LoggingLevel, text: *u8, ctx: *void) #c_call {
    new_context: Context;
    push_context new_context {
        print("I am in logger callback");
        log("%", to_string(text));
    }
}
```

Without `push_context`, calling a native procedure produces:
`Error: Cannot call into a native procedure, from a #c_call procedure, without using push_context.`

### Platform-Specific Foreign Calls with `#if`

Because foreign library APIs differ by OS, `#if` (see §31) is commonly used
to select the correct library and function declarations at compile time:

```Jai
#if OS == .WINDOWS {
    kernel32 :: #system_library "kernel32";
    GetComputerNameA :: (lpBuffer: *u8, nSize: *u32) -> s32
        #foreign kernel32;
} else #if OS == .LINUX {
    libc :: #system_library "libc";
    gethostname :: (name: *s8, namelen: u64) -> s32 #foreign libc;
}
```

Only the code for the current OS is compiled. This allows writing a single
cross-platform wrapper (e.g., `get_computer_name`) that delegates to the
appropriate OS function.

### The `Bindings_Generator` Module

The standard distribution includes a `Bindings_Generator` module that
automates the creation of OpenJai FFI bindings from C/C++ header files. It
generates OpenJai wrapper declarations (procedure signatures, types, constants)
from C/C++ source, eliminating most of the manual conversion work. The output
may not cover every case but provides a substantial starting point.

A bindings generation is **not** a conversion from C++ to OpenJai. The generated
OpenJai declarations allow OpenJai code to **call** the compiled C/C++ code in the
library through the `#foreign` directive. Function bodies (implementation
code) are not translated.

The `Bindings_Generator` is typically used from a build file (often called
`generate.OpenJai` or `first.OpenJai`). The companion module `BuildCpp` provides
`build_cpp_dynamic_lib` for compiling C++ source into a dynamic library as
part of the build. The `Check` module provides `do_error_checking` for
augmented compile-time checking of generated bindings.

The generated output file (e.g., `windows.OpenJai`, `linux.OpenJai`, `macos.OpenJai`)
is platform-specific and is auto-generated -- any manual changes are
overwritten on the next generation. See §37 for a full build example.

### Calling User-Defined C Libraries (Step by Step)

To call functions from a custom C library:

1. Write C source code (e.g., `my.c`).
2. Write OpenJai declarations using `#foreign` and `#library`:
   ```Jai
   my :: #library "libmy";
   add_int :: (a: s32, b: s32) -> s32 #foreign my;
   ```
3. Compile the C code to an object file: `gcc -c my.c`
4. Create a shared library: `gcc -shared -o libmy.dll my.c` (or `.so` on
   Linux).
5. On Windows, create an import library: `ar rcs libmy.lib my.o`
6. Compile the OpenJai program: `OpenJai program.OpenJai`
7. Run the resulting executable.

---

## 7. Language Features Overview

### Big Ideas

- **Context** -- an implicit context system (e.g., for switching memory
  allocation schemes). A context is established with `push_context`, which
  sets the active context for all code within its block.
- **Directives** -- `#`-prefixed compiler directives (e.g., `#import`).
- **Run-time type reflection** (introspection and run-time type information).
- **Full compile-time code execution** -- programs can be run at compile time.

### Medium Ideas

- **Polymorphic procedures** -- compile-time polymorphism.
- **Polymorphic structs.**
- **Integrated build system** -- builds controlled from within OpenJai.
- **Module system.**

### Small Ideas

- **Initialization by default.**
- **No printf formatters.**
- **Type distinction.**
- **Universal declaration syntax** -- `::` and `:=`.
- **No references** -- just values and pointers.
- **No const.**
- **Maybe by reference** -- a parameter-passing mode.
- **Data-only pseudo-inheritance.**
- **Custom iterators.**
- **`#asm` blocks** -- inline assembly.
- **Macros** -- not C/C++ preprocessor macros; more like Lisp macros.
- **Powerful macro system.**
- **Inlining control** -- explicit control over inlining.
- **LLVM optimizations** -- explicit control over LLVM optimization settings.
- **Bounds checking.**
- **`defer`** -- delays execution of a statement/block to scope exit (LIFO
  order). Inspired by Go, but scoped to blocks rather than functions.
- **Low-level memory management tools** for allocation and freeing (`alloc`,
  `free`, `realloc`, `New`).

---

## 8. Program Structure

### Imports

Modules are imported with the `#import` directive:

```Jai
#import "Basic";
```

### Entry Point

Every OpenJai program requires an entry point called `main`. Compiling a file
without `main` produces:

> Error: No program entry point was found. (The designated entry point name
> is 'main'.)

A `main` procedure is written as:

```Jai
main :: () {
    assert(5 == 5.0);
}
```

- `main` is declared using `::` (the universal declaration syntax for
  constants/procedures).
- `()` is the parameter list (empty for `main`).
- `main` has **no return value** (unlike C). The absence of `->` after the
  parameter list means no return type.
- The procedure body is enclosed in braces `{ }`.
- Statements are terminated with semicolons.
- Normally a program stops after execution of the last statement in `main()`.

### Startup Sequence

The user's `main` is not the true entry point of a OpenJai executable. The actual
entry point is `__system_entry_point`, defined in the `Runtime_Support` module
(`modules/Runtime_Support.OpenJai`). The startup sequence is:

1. **`__system_entry_point(argc, argv)`** -- exported as the C-level `main`
   symbol via `#program_export "main"`. This is the OS-level entry point.
2. **`__OpenJai_runtime_init(argc, argv)`** -- stores the command-line arguments
   in `__command_line_arguments` (an array with `.count` and `.data` fields),
   initializes the primary thread's temporary storage, and returns a pointer
   to the first thread's `Context`.
3. **`push_context first_thread_context`** -- establishes the context for the
   main thread.
4. **`__program_main()`** -- calls the user's `main` procedure. Declared with
   `#runtime_support` to link it to the user-defined `main`.

A corresponding `__OpenJai_runtime_fini` cleanup function exists but is currently
empty.

```Jai
#program_export "main"
__system_entry_point :: (argc: s32, argv: **u8) -> s32 #c_call {
    __OpenJai_runtime_init(argc, argv);

    push_context first_thread_context {
        __program_main :: () #runtime_support;
        __program_main();
    }

    return 0;
}
```

### Declaration Order Independence

The order in which `#import` statements, procedure definitions, `#run`
directives, and other top-level declarations appear in a source file **does
not matter**. The compiler performs multiple passes. By convention, `main` is
placed at the bottom of the source file for easy discovery.

### Workspaces

The compiler organizes compilation into **workspaces**. Each workspace
represents a completely separate compilation environment. When the compiler
starts, it creates workspaces automatically:

- **Workspace 1** -- reserved for the default metaprogram's internal use.
- **Workspace 2** -- the "Target Program" workspace for the file specified on
  the command line.

Additional workspaces (3, 4, ...) can be created programmatically from a
build metaprogram. See §37 for full details on workspaces and the build
system.

### Default Metaprogram

When no custom build metaprogram is specified, the compiler uses
`Default_Metaprogram` (from `modules/Default_Metaprogram.OpenJai`) to drive the
build. It sets up the working directory, names the output executable based on
command-line arguments, and translates command-line flags (e.g., `-release`,
`-x64`) into `Build_Options`. It only accepts arguments preceded by `-`.

The default metaprogram can be replaced with a custom one (see §37).

### Project Structure

A OpenJai project has a single main source file (by convention `main.OpenJai`)
containing the `main()` procedure, structured with `#import` and `#load`
directives.

For simple programs, a single source file compiled with `OpenJai main.OpenJai`
suffices.

For small to medium-sized projects, the conventional folder structure is:

```
project_name/
    run/
        data/             # fonts, images, sound files, etc.
        project_name.exe  # compiled executable
    src/
        main.OpenJai          # entry point, #loads other source files
        other .OpenJai files
    build.OpenJai             # build metaprogram (describes compilation in OpenJai)
```

- `main.OpenJai` uses `#load` to pull in other source files from `src/`.
- `build.OpenJai` (formerly `first.OpenJai`) is a OpenJai source file that describes the
  project's compilation process in OpenJai itself. Compilation is started with
  `OpenJai build.OpenJai`.
- The executable is placed in the `run/` folder (formerly `run_tree/`) via
  build options:
  ```Jai
  set_build_options_dc(.{output_path="run", output_executable_name="project_name"});
  ```

#### Source File Conventions

Statement order in a OpenJai source file is not mandatory, but for readability:

1. Place `#import` directives at the top.
2. Follow with `#load` directives.
3. Then global declarations (constants, variables, types).
4. Then procedure definitions.
5. Place `main()` at the **bottom** of the main file for easy discovery.

Remove unused `#import` directives -- while not a major problem, they
increase compilation time and binary size.

---

## 9. Comments

- `//` starts a single-line comment (at the start of a line or mid-line).
- `/* ... */` delimits a block comment.
- Block comments **can be nested**: `/* block /* nested */ */` is valid.
- Comments are not compiled.

The tutorial uses `// =>` as a convention for showing program output in
examples. This is a book convention, not a language feature.

---

## 10. Procedures

OpenJai calls what most languages call "functions" **procedures**.

### Declaration Syntax

Procedures are declared with `::` (constant declaration) and require no
keyword (`proc`, `function`, `func`, `fn`, etc.):

```Jai
main :: () {
    // body
}
```

The general form is:

```
name :: (parameters) -> return_type { body }
```

- `::` indicates a compile-time constant binding.
- `(parameters)` is the parameter list (may be empty).
- `-> return_type` specifies the return type. If omitted, the procedure has
  no return value.
- `{ body }` contains the executable statements.

Writing `main () :: {}` (identifier before parentheses before `::`) is a
syntax error.

Procedure names follow the same rules as variable names and are written in
`snake_case` by convention. Because they are declared with `::`, procedures
are **constants** -- they cannot be rebound at run-time.

The order of procedure definitions does not matter at file scope -- a
procedure can be called before it is defined. However, inside a procedure
body, a local procedure **must** be defined before it is called (no
forward-referencing of constant declarations inside procedure bodies).

### Lambda Syntax (`=>`)

For one-line procedures, a concise lambda syntax is available using `=>`:

```Jai
lam :: (a, b) => a + b;
print("% \n", lam(1, 2));    // => 3
```

When using `=>`, the argument types and return type can be omitted (inferred
by the compiler). The body of the lambda is the expression after `=>` --
no braces or `return` keyword needed.

Lambdas are commonly passed as arguments to higher-order functions (see
"Higher-Order Functions" below).

### Parameters and Arguments

Each argument in the parameter list must have its type specified separately:

```Jai
sum :: (x: int, y: int, z: int) -> int { return x + y + z; }
```

The number of parameters at the call site must match the number of arguments,
except when default values are provided (see below).

Type mismatches produce clear error messages:

```
Error: Number mismatch. Type wanted: int; type given: float32.
```

A parameter can be a procedure call (the call is evaluated first, and the
result is passed as the argument value).

#### Passing by Value vs Passing by Pointer

Arguments of size <= 8 bytes (basic types such as `s64`, `u8`, `Type`, any
pointer, any enum) are always **passed by value** (a copy is made). The
original variable is not affected by changes to the parameter inside the
procedure.

Larger values (> 8 bytes), including `Any`, `string`, structs, and arrays,
are most likely **passed by reference** (pointer) for efficiency, but are
still **immutable** inside the procedure -- the compiler forbids modification.
The actual passing convention is up to the compiler for optimization purposes.

To modify a variable inside a procedure, pass an explicit pointer:

```Jai
passing_pointer :: (m: *int) {
    << m = 108;
}

n := 42;
passing_pointer(*n);
print("%\n", n);     // => 108
```

The same mechanism applies to struct variables:

```Jai
change_name :: (pers: *Person) {
    pers.name = "Jon";
}

bob := Person.{name = "Robert"};
change_name(*bob);
print("%\n", bob.name);    // => Jon
```

#### Struct Arguments Are Immutable

Struct arguments cannot be modified directly in a procedure. Attempting to
assign to an immutable argument produces:

```
Error: Can't assign to an immutable argument.
```

Instead, create a local copy, modify it, and return the copy:

```Jai
perlin :: (p: Vector2) -> Vector2 {
    p_ := p;
    p_ *= 2;
    return p_;
}
```

#### Default Values for Arguments

Arguments can have **default values**, specified in the argument list:

```Jai
proc1 :: (a: int = 0) { print("a is %\n", a); }
hello :: (a := 9, b := 9) { print("a is %, b is %\n", a, b); }
```

When using a default value, **type inference** (`:=`) can be used in the
argument declaration.

When a procedure is called and no parameter is supplied for an argument with
a default value, the default value is used:

```Jai
hello(1, 2);    // => a is 1, b is 2
hello(1);       // => a is 1, b is 9
hello();        // => a is 9, b is 9
hello(b = 42);  // => a is 9, b is 42
```

A default value need not be a literal -- it can be any symbol, variable, or
even a procedure call.

#### Named Arguments

Arguments can be passed by name at the call site using `name = value`:

```Jai
a2 := square(x = c);
make_character(name = "Fred", catch_phrase = "Hot damn!", color = BLUE);
```

Named arguments allow parameters to be specified in any order, regardless of
the declaration order. This is especially useful for procedures with many
arguments of the same type, or when some arguments have default values.

After the first argument with a default value, subsequent parameters **must**
be passed with their argument name. Once named arguments are used, you
cannot switch back to unnamed (positional) arguments.

Partially naming arguments is allowed but requires caution; the compiler
checks parameters carefully.

#### Autocasting a Parameter with `xx`

If a parameter's type does not match the argument type, the `xx` autocast
operator can be used at the call site to cast the parameter:

```Jai
test_xx :: (f: float) { print("f is %\n", f); }

n: int = 5;
// test_xx(n);      // Error: Number mismatch. Type wanted: float; type given: int.
test_xx(xx n);      // => f is 5
```

#### Variadic Arguments (`..`)

A procedure can accept a variable number of arguments using `..`:

```Jai
var_args :: (args: ..int) { ... }
proc1 :: (s: string, args: ..Any) { ... }
```

The `..` before the type declares a variadic parameter. The general form is:

```
(arg1: type1, arg2: type2, ..., args: ..type)
```

The variadic parameter must be the **last** in the argument list (to avoid
ambiguity). All variable arguments are collected into an **array view**
(`[]type`). The count is available via `args.count`, and the arguments can
be iterated with `for args`.

If all variable arguments must share a type, specify it (e.g., `..int`). To
accept any type, use `..Any`.

**Spreading an array into variadic arguments**: An existing array can be
expanded into a variadic parameter with `..`:

```Jai
arr := int.[1, 2, 3, 4, 5, 6, 7];
var_args(..arr);            // same as var_args(1,2,3,4,5,6,7)
var_args(args = ..arr);     // same, using named argument
```

**Named variadic arguments**: A named variadic argument can be combined with
default arguments:

```Jai
varargs_proc :: (s := "Fred", f := 2.5, v: ..string) { }
varargs_proc(f = 3.14, s = "How", v = "are", "you", "tonight?");
```

After the varargs name is used, all subsequent parameters go into the variable
argument.

**Example** (inline variadic wrapper):

```Jai
println :: inline (msg: string, args: ..Any) {
    print(msg, ..args);
    print("\n");
}
```

At the call site, `..args` expands the variadic argument list.

#### Using Struct Namespaces in Procedure Arguments

The `using` keyword can be applied to procedure arguments to import the
struct's namespace into the procedure body:

```Jai
print_position_b :: (entity: *Entity) {
    using entity;
    print("(%, %)\n", position.x, position.y);
}

print_position_c :: (using entity: *Entity) {
    print("(%, %)\n", position.x, position.y);
}

print_position_d :: (entity: *Entity) {
    using entity.position;
    print("(%, %)\n", x, y);
}
```

`using` can be placed inside the body, on the argument itself, or on a
nested field.

#### The `#as` Directive in Procedure Arguments

When a struct field is declared with `using #as` (see §24), instances of the
subtype can be passed directly where the supertype is expected:

```Jai
A :: struct { data: int = 108; }
B :: struct { using #as a: A; }

proc1 :: (a: A) { print("Calling proc :: (a: A)\n"); }

b: B;
proc1(b);     // OK: B implicitly casts to A
```

When `using` is applied to the argument, the same implicit cast applies
and the fields are also directly accessible:

```Jai
proc2 :: (using a: A) { print("a.data = %\n", data); }
proc2(b);     // OK: implicit cast + namespace import
```

### Return Values

A procedure's return type is specified after `->`:

```Jai
square :: (x: float) -> float { return x * x; }
```

If a procedure does not return a value (like `main`), the `->` is omitted, or
`-> void` can be written explicitly.

`return` exits the procedure immediately, breaking out of all scopes back to
the call site. It can stand alone (just exits the procedure) or pass back one
or more values.

Unlike Rust or Go, procedures do **not** return tuple objects. Return values
are passed in registers.

#### Multiple Return Values

A procedure can return multiple values, listed after `->` and separated by
commas:

```Jai
proc1 :: () -> int, int {
    return 3, 5;
}
```

For clarity, multiple return types may be enclosed in parentheses:
`-> (int, int)`. Parentheses are required when a procedure with multiple
return values is used as an argument in another procedure.

At the call site, the returned values are assigned to an equal number of
variables:

```Jai
x, y := proc1();    // x is 3, y is 5
```

It is not necessary to capture all return values. Uncaptured values are
silently discarded:

```Jai
a := proc1();       // a is 3 (second value discarded)
```

#### The `_` Discard Identifier

The name `_` represents values you do not care about. It does not need to be
declared and can be used to explicitly discard return values:

```Jai
result, ok, _ := to_integer(text);   // discard the 3rd return value
```

#### Named and Default Return Values

Return values can be named:

```Jai
proc2 :: () -> a: int, b: int {
    a := 100;
    b := 200;
    return a, b;
}
```

Return values can also have **default values** (they must be named when
defaults are provided):

```Jai
proc3 :: (var: bool) -> a: int = 100, b: int = 200 {
    if var == true then return;          // returns defaults: 100, 200
    else return 1_000_000;              // returns 1000000, 200 (b keeps default)
}
```

When a `return` does not provide values for all named return parameters, the
defaults are used.

#### Named Return Values at the Return Site

When a procedure has named return values, the `return` statement can
explicitly name which values it is setting, using `name = value` syntax:

```Jai
ask_guess :: (high: int) -> result: int, ok: bool {
    // ...
    return result = 0, ok = false;
}
```

This is analogous to named arguments at a call site. It makes the intent
clear and allows setting return values in any order.

#### The `#must` Directive

The `#must` directive, placed after the return type, requires that the return
value(s) be assigned to a variable at the call site -- they cannot be
ignored:

```Jai
mult :: (n1: float, n2: float) -> float #must {
    return n1 * n2;
}

// mult(n, m);          // Error: Return value 1 is being ignored, which is disallowed by #must.
mm := mult(n, m);       // OK: return value is captured
```

This prevents a common class of bugs where important return values (e.g.,
error codes) are accidentally ignored.

### Local (Nested) Procedures

Procedures defined at the top level (outside any procedure) are **global
procedures**. A procedure defined inside another procedure is a **local**
(also called **inner** or **nested**) procedure:

```Jai
main :: () {
    add :: (x: int, y: int) -> int { return x + y; };
    print("%\n", add(1, 2));    // => 3
}
```

Local procedures can be called from within the enclosing procedure. They are
only visible in the scope where they are defined.

**Limitations:**

- An inner procedure **cannot access outer variables** (from the enclosing
  procedure's stack frame). Attempting this produces:
  `Error: Attempt to use a variable from an outer stack frame. (Closures are not supported.)`

- A procedure **cannot see** inner procedures defined inside other procedures:
  `Error: Undeclared identifier 'display'.`

- Inner procedures must be defined before they are called (no
  forward-referencing inside procedure bodies).

Local procedures promote code hygiene by limiting visibility -- only make
procedures global when they are used in multiple places.

### Anonymous Procedures and Lambdas

An **anonymous procedure** (or **lambda**) has no name. It can be defined and
called immediately, or assigned to a variable:

```Jai
// Defined and called immediately:
() {
    print("one\n");
}();

// Assigned to a variable:
anproc := () { print("one in anproc\n"); };
anproc();

// With return value:
a := () -> int { return 42; }();

// With parameters:
s := 3;
b := (s: int) -> int { return s * 2; }(s);
```

The `=>` lambda syntax (see above) is especially elegant for writing
anonymous functions.

### Procedure Overloading

Procedures are **overloaded** when they share the same name but have
different argument lists (different argument types):

```Jai
proc1 :: (n: u8) -> u8 { return n * 2; }
proc1 :: (n: u16) -> u16 { return n * 2; }
```

Overload resolution selects the **smallest and closest fit** for the argument
types. Two overloads with identical argument lists in the same scope produce:

```
Error: Two overloaded definitions of the same procedure can't have identical argument lists.
```

#### Overloading Across Scopes

When overloaded procedures exist in both global and local scopes, the
resolution mechanism searches **all overload versions regardless of scope**
and picks the overload where the argument types fit best. If a local overload
matches, it is chosen.

Overloading leads to code duplication when the logic is the same but types
differ. OpenJai's solution for this is **polymorphic procedures** (see below).

### Operator Overloading

Operators are built-in procedures (e.g., `+` for addition, `[]` for indexing).
OpenJai allows user-defined types to provide implementations for these operators
using the `operator` keyword.

The general form resembles a procedure declaration:

```
operator token :: (argument list) -> (return-type list)
```

**Overloadable operators:**

```
+  -  *  /  %  ^
+=  -=  *=  ==  !=
<<  >>  <<<  >>>
&  |  []  []=  *[]
```

The following operators **cannot** be overloaded: `=` and `New`.

#### Defining an Operator Overload

An operator overload is defined at module or file scope, just like a regular
procedure:

```Jai
Obj :: struct {
    array: [10]int;
}

operator [] :: (obj: Obj, i: int) -> int {
    return obj.array[i];
}
```

This allows `obj[i]` instead of `obj.array[i]` for instances of `Obj`.

#### Index Operators: `[]`, `[]=`, and `*[]`

Three index-related operators can be overloaded independently:

- **`[]`** -- read access (e.g., `val := obj[i];`).
- **`[]=`** -- write access (e.g., `obj[i] = 10;`). Overloading `[]=` also
  enables compound assignment operators like `+=`, `*=`, `/=`, `^=`, etc.
  on indexed elements.
- **`*[]`** -- pointer-to-element access (e.g., `ptr := *obj[i];`), allowing
  the caller to obtain and dereference a pointer to the underlying element.

```Jai
operator [] :: (obj: Obj, i: int) -> int {
    return obj.array[i];
}

operator []= :: (obj: *Obj, i: int, item: int) {
    obj.array[i] = item;
}

operator *[] :: (obj: *Obj, i: int) -> *int {
    return *obj.array[i];
}
```

Note that `[]=` and `*[]` take a **pointer** to the struct as their first
argument, since they need to mutate or expose the internal storage.

#### The `#symmetric` Directive

When an operator is commutative with respect to argument order (e.g.,
`Vector3 * float` should give the same result as `float * Vector3`), the
`#symmetric` directive eliminates the need to define both orderings:

```Jai
operator * :: (a: Vector3, k: float) -> Vector3  #symmetric;
```

With `#symmetric`, both `a * 3.0` and `3.0 * a` resolve to this overload.

#### Calling Operator Overloads Explicitly

An operator overload can be called as a regular procedure using the `operator`
keyword:

```Jai
f := operator -(d, e);          // equivalent to: f := d - e;
f := Basic.operator -(d, e);    // qualified with module name
```

#### The `#poke_name` Directive

The `#poke_name` directive injects a name from the current scope into an
imported module, making it visible to that module's existing code. This is
commonly used to supply additional operator overloads (or other procedure
overloads) to a library module that was not originally aware of your types.

```Jai
Math :: #import "Math";

Vector4 :: struct { x, y, z, w : float; }

dot_product :: (a: Vector4, b: Vector4) -> float {
    return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
}

#poke_name Math dot_product;
```

Here, the `Math` module already defines `dot_product` overloads for `Vector2`,
`Vector3`, and `Quaternion`. The `#poke_name` directive adds a fourth overload
for `Vector4`, so `Math.dot(v1, v2)` works with `Vector4` arguments. (The
`Math` module defines `dot :: dot_product;` internally.)

Similarly, `#poke_name` can inject an `operator==` into a module like
`Hash_Table` so it can compare keys of a user-defined type:

```Jai
using Hash_Table :: #import "Hash_Table";
#poke_name Hash_Table operator==;
```

### Polymorphic Procedures

Polymorphic procedures are OpenJai's answer to code duplication caused by
overloading. They are analogous to C++ templates, Java/C# generics, or
parameterized functions in other languages.

A **type variable** is declared with a `$` prefix in the parameter list. The
compiler infers the concrete type at each call site and **bakes out** a
specialized copy of the procedure for that type:

```Jai
convert :: (arg: $T) {
    print("% of type %, cast to bool is %\n", arg, type_of(arg), cast(bool) arg);
}

convert(0);               // bakes out a version for s32
convert(69105.33);         // bakes out a version for float32
convert("Hello, Sailor!"); // bakes out a version for string
```

Each distinct concrete type produces one compiled version. Subsequent calls
with the same type reuse the already-compiled version.

#### Type Variable Rules

- The `$` prefix **defines** the type variable. There must be exactly one
  `$T` definition per polymorphic variable name in a procedure. A second
  `$T` produces: `Error: "is already defined as polymorphic variable"`.
- After its defining occurrence, `T` may be used without `$` in the same
  parameter list, in the return type, and in the procedure body:

  ```Jai
  add :: (p: $T, q: T) -> T {
      return p + q;
  }
  ```

  Here `p` defines `T`; `q` and the return type reuse it. Both arguments
  must be the same type.

- Type variable names must start with a capital letter (e.g., `T`, `R`,
  `Targ`).
- The `$` also identifies which parameter is **authoritative** for error
  messages. When types conflict, the error refers to the `$`-marked
  parameter.
- A procedure can have **multiple** polymorphic type variables:

  ```Jai
  proc :: (a: $A, b: $B, c: $C) -> B, C { ... }
  ```

  OpenJai guarantees that a particular procedure is compiled only once for any
  given combination of type variables.

#### Type Matching Behavior

When the same type variable is used for multiple parameters, all must resolve
to the same concrete type:

```Jai
add :: (p: $T, q: T) -> T { return p + q; }

add(1, 2);      // OK: T = int
add(1.0, 2.0);  // OK: T = float32
add(1, 2.0);    // Error: Number mismatch. Type wanted: int; type given: float.
```

The parameter marked with `$` determines the type. Other parameters using the
same type variable must match.

#### Polymorphic Types in Complex Positions

Type variables can appear inside array types, pointer types, and other
compound positions:

**Array item type:**
```Jai
arr_sum :: (a: [] $T) -> T {
    result: T;
    for a result += it;
    return result;
}
```

**Pointer type:**
```Jai
my_swap :: (a: *$T, b: *T) {
    tmp := <<a;
    <<a = <<b;
    <<b = tmp;
}
```

**Dynamic array type:**
```Jai
array_add :: (array: *[..] $T, item: T) #no_abc
```

#### Polymorphic Array Size

The `$` prefix can also be used on the **size** of a fixed-size array
parameter, binding it as a compile-time constant:

```Jai
describe_array :: (x: [$N] $T) {
    print("An array of % items of type %\n", N, T);
}

x := int.[1,2,3,4];
describe_array(x);  // => An array of 4 items of type s64
```

Both `N` and `T` must be known at compile time. Either can be used
independently -- `$T` can be replaced by a concrete type so only the size
is polymorphic, or vice versa.

This enables generic functions that preserve array sizes in their return
types:

```Jai
map :: (array_a: [$N] $T, f: (T) -> T) -> [N] T {
    array_b: [N] T;
    for i: 0..N-1 {
        array_b[i] = f(array_a[i]);
    }
    return array_b;
}

array_a := int.[1, 2, 3, 4, 5, 6, 7, 8];
array_b := map(array_a, (x) => x + 100);
// => [101, 102, 103, 104, 105, 106, 107, 108]
```

#### Polymorphic Procedures with Structs

A polymorphic procedure can accept any struct that has the required members.
The type must be provided explicitly at the call site -- struct literals
without a type designation cannot match a polymorphic variable:

```Jai
check_temperature :: (s: $T) {
    if s.temperature < -20  print("Too cold!!!\n");
    else                    print("Temperature okay!\n");
}

check_temperature(Ice_Cream_Info.{num_scoops=4});  // OK
// check_temperature(.{num_scoops=4});
// Error: Attempt to match a literal, without a type designation,
// to a polymorphic variable.
```

#### Polymorphic Procedures as Arguments

A polymorphic procedure can be passed as an argument to a higher-order
function. The type variable is resolved when matched against the expected
signature:

```Jai
apply_int :: (f: (x: int) -> int, x: int, count: int) -> int {
    for 1..count x = f(x);
    return x;
}

square :: (x: $T) -> T { return x * x; }

b := apply_int(square, 4, 4);  // T resolves to int via f's signature
```

#### The `#procedure_of_call` Directive

`#procedure_of_call` obtains the concrete procedure that **would** be called
for a given polymorphic call, without actually calling it. This is useful for
inspecting the result of polymorphic resolution:

```Jai
add :: (p: $T, q: T) -> T { return p + q; }

i1: int = 1;
i2: int = 2;
proc :: #procedure_of_call add(i1, i2);
print("%\n", type_of(proc));
// => procedure (s64, s64) -> s64

f1: float = 1;
f2: float = 2;
proc2 :: #procedure_of_call add(f1, f2);
print("%\n", type_of(proc2));
// => procedure (float32, float32) -> float32
```

#### Restricting Polymorphic Types with `$T/Base`

A polymorphic parameter can be **restricted** to accept only a specific
polymorphic struct type, or any struct that incorporates it.

**Exact struct match** -- using `PolyStruct($T)` in the parameter type
restricts the argument to instances of that exact polymorphic struct:

```Jai
proc1 :: (x: PolyStruct($T)) { }
```

**Subtype match with `/`** -- the `$T/Base` syntax matches any type `T`
that **is or incorporates** `Base` (via `using`). This is not traditional
inheritance -- it is structural matching:

```Jai
proc1 :: (x: $T/PolyStruct) { }
```

`T` will only match if the target type matches `PolyStruct`, involving
strongly-typed type checking. Crucially, `x` does not have to **be** a
`PolyStruct` -- it can simply incorporate one via `using`:

```Jai
MyStruct :: struct {
    using ps: PolyStruct;
    extra: int;
}
```

This enables component-based systems where each struct links to a shared
component via `using _c: SomeComponent;`.

Multiple styles are available for accessing polymorphic struct parameters
in procedure signatures:

```Jai
Hash_Table :: struct (K: Type, V: Type, N: int) {
    keys: [N] K;
    values: [N] V;
}

proc1 :: (table: Hash_Table($K, $V, $N), key: K, value: V) { }
proc2 :: (table: $T/Hash_Table, key: T.K, value: T.V) { }
proc3 :: (table: $T, key: T.K, value: T.V) { }
proc4 :: (table: Hash_Table, key: table.K, value: table.V) { }
```

`proc4` demonstrates **implicit polymorphism** -- no `$` is needed because
the compiler infers polymorphism from the use of `table.K` and `table.V`.

#### The `$T/interface` Syntax (Structural Typing)

`$T/interface Object` requires that the type `T` has **at least** the fields
that struct `Object` has, regardless of the actual type. This is similar to
**traits**, **interfaces**, or **concepts** in other languages and enables
duck typing:

```Jai
Matchable :: struct {
    name:  string;
    color: Color;
}

discuss :: (x: $T/interface Matchable) {
    print("x has a name '%' and has color %.\n", x.name, x.color);
}
```

Any struct that has `name: string` and `color: Color` fields can be passed
to `discuss`, even if it has additional fields and is not related to
`Matchable`:

```Jai
Thing :: struct {
    duration: float64;
    tag:      string;
    name:     string;
    type:     Type;
    color:    Color;
}

discuss(Matchable.{"Nice", .ORANGE});  // OK
discuss(thing);                         // OK -- Thing has name and color
```

The actual type is preserved -- `type_of(x)` returns the concrete type
(`Thing`, not `Matchable`).

#### Performance

There is **no runtime overhead** from polymorphism. There is no dynamic
dispatch, no dynamic type checking, and no JIT compilation. After polymorph
resolution (solving for `$T` etc.), the compiler bakes out a full copy of the
procedure with the concrete types. The resulting machine code is identical to
a hand-written non-polymorphic version.

Polymorphic functions are generated at **compile time**, not at runtime.
Because OpenJai is strongly typed, every call to a polymorphic function is
type-checked at compile time.


### Higher-Order Functions

A **higher-order function** is a procedure that takes another procedure as
an argument, or returns one:

```Jai
add100 :: (a: []int, proc: (int) -> int) -> []int {
    result: [..]int;
    for a   array_add(*result, proc(a[it_index]));
    return result;
}

array_b := add100(array_a, (x) => x + 100);
```

A procedure's second parameter declares its expected signature; any procedure
(including lambdas) matching that signature can be passed.

Higher-order functions can also be polymorphic, enabling patterns like `map`:

```Jai
map :: (array: [] $T, f: (T) -> $R) -> [] R {
    result: [] R;
    result.count = array.count;
    result.data = alloc(result.count * size_of(R));
    for array result[it_index] = f(it);
    return result;
}

b := map(a, square);        // named procedure
c := map(a, x => x * x);   // lambda
d := map(a, x => x + 100);  // lambda
```

#### Closures

Unlike C++ or Rust, OpenJai does **not** support closures or capture blocks.
Lambdas cannot capture variables from their enclosing scope. However, macros
with backtick references can emulate closure-like behavior (see §33, Macros).

#### Recursive Lambdas

A lambda can call itself recursively using `#this`:

```Jai
call_with :: (arg: $T, f: (T)) {
    f(arg);
}

call_with(5, x => { print("x is %\n", x); if x > 0 then #this(x-1); });
```

### `#bake_arguments`

The `#bake_arguments` directive creates a new procedure by pre-filling
(baking in) specific arguments of an existing procedure, leaving the
remaining arguments as parameters. The result is a **pre-compiled** procedure
with fewer parameters:

```Jai
add :: (a, b) => a + b;
add10 :: #bake_arguments add(a=10);

c := add10(20);    // => 30
```

```Jai
mult :: (a: float, b: float) -> float { return a * b; }
mult1 :: #bake_arguments mult(b = -9);

mult1(2);    // => -18
```

`#bake_arguments` procedures are pre-compiled functions, **not closures**.
This differs from default parameter values: `#bake_arguments` creates a
distinct procedure, whereas default values keep a single procedure.

OpenJai has function currying through `#bake_arguments`, but only at compile
time. There is no runtime function currying.

#### `$` Auto-Bake

A `$` before a parameter name (not a type) **auto-bakes** that argument:
the value must be a compile-time constant. If a runtime variable is passed,
the compiler errors:

```Jai
proc :: ($a: int) -> int { return a + 100; }

proc(42);    // OK: 42 is a constant => 142
// proc(b);  // Error: requires a bake-able literal
```

#### `$$` Optional Auto-Bake

`$$` before a parameter makes it **optionally constant**. If the argument is
a compile-time constant, it is baked in; otherwise the procedure runs
normally. This can be combined with `is_constant()` for compile-time
branching:

```Jai
proc2 :: ($$a: int) -> int {
    #if is_constant(a) {
        return a + 100;    // compile-time path
    } else {
        return a * 2;       // runtime path
    }
}

proc2(42);    // constant: returns 142
b := 20;
proc2(b);     // variable: returns 40
```

Auto-bakes (`$` and `$$`) can be used together with `$T` type variables.

#### Creating Dynamic Arrays with Polymorphism

Polymorphic procedures with `Type` parameters can create typed data
structures:

```Jai
make_dynamic_array :: ($T: Type, allocator: Allocator, capacity := 8) -> [..]T {
    arr: [..]T;
    arr.allocator = allocator;
    array_reserve(*arr, capacity);
    return arr;
}

arrdyn := make_dynamic_array(int, temp);
```

### `#bake_constants`

The `#bake_constants` directive bakes a **polymorphic type variable** to a
concrete type, converting a polymorphic procedure into a non-polymorphic one.
This is distinct from `#bake_arguments`, which bakes argument **values**.

```Jai
display_xy :: (v: $T) {
    print("x coordinate is %\n", v.x);
    print("y coordinate is %\n", v.y);
}

baked1 :: #bake_constants display_xy(T = Vector2);
```

`baked1` now has the effective signature `(v: Vector2)`. Passing a different
type (e.g., `Vector3`) produces a type mismatch error.

`#bake_constants` also works with polymorphic **return types**:

```Jai
random :: () -> $T {
    value := 0xcafe;
    return cast(T) value;
}

random_s32 :: #bake_constants random(T = s32);
random_u8  :: #bake_constants random(T = u8);
```

Calling `random()` directly without specifying `T` is an error. The baked
versions resolve the type at compile time.

Multiple type variables can be baked simultaneously using named arguments:

```Jai
named_bake_test :: (a1: $A, a2: A, b1: $B, b2: B) -> A, B {
    a_sum := a1 + a2;
    b_product := b1 * b2;
    return a_sum, b_product;
}

nbt :: #bake_constants named_bake_test(A = float, B = int);
sum, product := nbt(1, 2, 3, 4);  // => Sum is 3, product is 12
```

`#bake_constants` makes the argument type fixed at compile time -- it
eliminates branches and optimizes the code path for the specific type.

#### `#bake_constants` with Structs

`#bake_constants` can also be used with `#bake_arguments` on structs.
A polymorphic struct can use `#bake_arguments` to partially apply its
parameters:

```Jai
TwoD :: struct (M: int, N: int) {
    array: [M][N] int;
}

TwoDb :: #bake_arguments TwoD(M = 5);

twod: TwoDb(N = 2);
// twod.M == 5, twod.N == 2
```

#### `#bake_constants` with `#this` in Structs

A polymorphic struct can embed a baked procedure using `#this` to refer
to the struct's own type:

```Jai
printer :: (x: $T) {
    print("PRINTING!!! %\n", x);
}

Polymorphic_Struct :: struct (T: Type, N: int) {
    values:  [N] T;
    pointer: *#this;

    proc :: #bake_constants printer(T = #this);
}

p0: Polymorphic_Struct(float, 3);
p0.proc(p0);  // => PRINTING!!! {[0, 0, 0], null}
```

Here `#this` inside the struct resolves to the struct type itself
(`Polymorphic_Struct(float, 3)`), so `proc` becomes a printer specialized
for that exact struct type.

### Inlining Procedures

**Inlining** replaces a procedure call with the procedure's body at the call
site, eliminating call overhead and improving performance.

Inlining can be specified in two ways:

**At the procedure declaration** -- with `inline` or `no_inline` before the
parameter list:

```Jai
test_local_inline :: inline (x: int) { /* ... */ }
```

**At the call site** -- with `inline` or `no_inline` before the call:

```Jai
test_local(1);              // normal call
inline test_local(1);       // inlined at this call site
test_local_inline(2);       // inlined (declared as inline)
no_inline test_local_inline(2);  // NOT inlined at this call site
```

Inlining is a **directive**, not a hint -- it forces the compiler to attempt
inlining. In certain cases inlining may be impossible (e.g., recursive
procedures).

A procedure declared as `:: inline` is inlined by default at all call sites
unless overridden with `no_inline` at a specific call site.

### Recursive Procedures

A **recursive procedure** calls itself within its body:

```Jai
factorial :: (n: int) -> int {
    if n <= 1 return 1;
    return n * factorial(n - 1);
}
```

Each recursive call pushes a frame on the stack. A **base case** (here
`n <= 1`) is required to stop the recursion. Without a base case, the
program crashes with:

```
The program crashed because of a stack overflow.
```

Stack depth is limited; deep recursion will cause a stack overflow. Recursive
solutions may be logically simple but are often not the most performant.

### The `#this` Directive

`#this` refers to the current procedure, struct type, or data scope that
contains it, as a **compile-time constant**.

In a recursive procedure, `#this` can replace the procedure name:

```Jai
factorial2 :: (n: int) -> int {
    if n <= 1 return 1;
    return n * #this(n - 1);
}
```

In `main`, `#this` refers to `main` itself (its address). `#this` is a
compile-time constant (`is_constant(#this)` returns `true`).

`#this` can also be used to declare **recursive structs** (see §24) and
**recursive lambdas** (see "Recursive Lambdas" above).

### Function Pointers (Procedure Types)

A procedure's **type** is its **signature** -- its argument types and return
types:

```Jai
print("%\n", type_of(sum));
// => procedure (s64, s64, s64) -> s64
```

A procedure is an address in memory (a **function pointer**). A variable can
hold a procedure value by declaring it with the procedure's signature:

```Jai
p_ptr: (int, int, int) -> int = sum;
d := p_ptr(1, 2, 3);    // calls sum => d is 6
```

Type inference also works:

```Jai
p_ptr := sum;            // type inferred as procedure (s64, s64, s64) -> s64
```

### Reflection on Procedures

Procedure type information is available through `Type_Info_Procedure`. Cast
the result of `type_info(type_of(proc))` to `*Type_Info_Procedure` to access:

- `argument_types` -- an array of `*Type_Info`, one per argument.
- `return_types` -- an array of `*Type_Info`, one per return value.
- `info.type` -- the `Type_Info_Tag`, which is `PROCEDURE`.

```Jai
info_procedure := cast(*Type_Info_Procedure) type_info(type_of(add));
print("%\n", info_procedure.info.type);    // => PROCEDURE

for info_procedure.argument_types {
    print("% ", << it);    // => {INTEGER, 8}  {INTEGER, 8}
}

for info_procedure.return_types {
    print("% ", << it);    // => {INTEGER, 8}
}
```

### The `#procedure_name` Directive

`#procedure_name()` returns the statically-known (compile-time) name of the
containing procedure as a string:

```Jai
add :: (x: int, y: int) -> int {
    print("The proc name is: %", #procedure_name());
    return x + y;
}

main :: () {
    print("%\n", #procedure_name());    // => main
    add(2, 3);                           // => The proc name is: add
}
```

### The `#deprecated` Directive

A procedure can be marked as deprecated with `#deprecated`, optionally
followed by a message string:

```Jai
old_function :: () #deprecated "please use new_function :: () instead" {}

old_function();
// => Warning: This procedure is deprecated.
//    Note: "please use new_function :: () instead"
```

Calling a deprecated procedure produces a **compiler warning** (not an
error). The message tells developers what to use instead.

### Known Standard Procedures

| Procedure | Module  | Description                                        |
|-----------|---------|----------------------------------------------------|
| `print`   | `Basic` | Prints formatted output to stdout (see below).     |
| `assert`  | `Basic` | Asserts a condition is true (see below).           |
| `exit`    | `Basic` | Exits the program with an integer status code. Code after `exit` is never executed. Convention: 0 = success, < 0 = error. |
| `min`     | `Basic` | Returns the minimum of its arguments.              |
| `max`     | `Basic` | Returns the maximum of its arguments.              |
| `current_time_consensus` | `Basic` | Returns the current time as `Apollo_Time`. Use for calendar dates. |
| `current_time_monotonic` | `Basic` | Returns the current monotonic time as `Apollo_Time`. Use for measuring durations and simulations (never jumps due to NTP or DST). |
| `to_calendar` | `Basic` | Converts an `Apollo_Time` to a calendar struct. Takes a timezone argument (`.UTC` or `.LOCAL`). |
| `calendar_to_string` | `Basic` | Converts a calendar struct to a human-readable date string. |
| `to_float64_seconds` | `Basic` | Converts an `Apollo_Time` duration to `float64` seconds. |
| `seconds_since_init` | `Basic` | Returns elapsed time since program initialization as `float64` seconds. Simple alternative to Apollo Time for measuring durations. |
| `sleep_milliseconds` | `Basic` | Suspends execution for the given number of milliseconds. |
| `alloc`   | `Basic` | Allocates a contiguous block of bytes on the heap. Signature: `alloc :: (size: s64, allocator: Allocator = .{}) -> *void`. Returns a `*void` pointer to uninitialized memory; must be cast to the desired pointer type. Must be freed with `free`. |
| `realloc` | `Basic` | Resizes previously allocated heap memory. Signature: `realloc :: (memory: *void, size: s64, old_size: s64, allocator: Allocator = .{}) -> *void`. |
| `New`     | `Basic` | Convenience wrapper around `alloc`: allocates an instance of the given type on the heap, zero-initializes it, and returns a typed pointer (e.g., `New(int)` returns `*s64`). Must be freed with `free`. |
| `Dynamic_New` | `Basic` | Like `New`, but can be used when the type is not known at compile-time: `z := Dynamic_New(T); defer free(z);`. |
| `free`    | `Basic` | Frees heap memory previously allocated with `alloc` or `New`. Signature: `free :: (memory: *void, allocator: Allocator = .{})`. The pointer becomes dangling after this call. |
| `get_field` | `Basic` | Returns detailed info about a named field of a struct type: `get_field(type_info(MyStruct), "field_name")`. Returns a `Type_Info_Struct_Member` and offset. |
| `is_subclass_of` | `Compiler` | Checks whether a struct type has a `using #as` relationship to a named supertype: `is_subclass_of(cast(*Type_Info) type_info(Sub), "Super")`. |
| `compiler_set_type_info_flags` | `Compiler` | Sets type info flags on a type without modifying its definition. Flags include `.NO_TYPE_INFO` and `.PROCEDURES_ARE_VOID_POINTERS`. Must be called with `#run`. |
| `NewArray` | `Basic` | Heap-allocates an array: `NewArray(count, type)`. Accepts optional `alignment` parameter (e.g., `NewArray(500, int, alignment=64)`). Free with `array_free`. |
| `array_add` | `Basic` | Adds item(s) to a dynamic array: `array_add(*arr, item)`. A version with no item argument adds a default-initialized element and returns a pointer to it: `ptr := array_add(*arr);`. Takes a pointer to the array. |
| `array_add_if_unique` | `Basic` | Like `array_add`, but only adds the item if it is not already present. |
| `array_find` | `Basic` | Checks if an item is present: `array_find(arr, value)`. Returns `true`/`false`. Does not require a pointer (read-only). |
| `array_copy` | `Basic` | Copies one array into another: `array_copy(*dest, src)` or `dest := array_copy(src)`. |
| `array_reset` | `Basic` | Empties a dynamic array: `array_reset(*arr)`. |
| `array_reserve` | `Basic` | Pre-allocates capacity: `array_reserve(*arr, count)`. Avoids repeated reallocation when the approximate final size is known. |
| `array_free` | `Basic` | Frees the memory of a dynamic or heap-allocated array: `array_free(arr)`. |
| `peek` | `Basic` | Returns the last item of a dynamic array without removing it. |
| `pop` | `Basic` | Returns and removes the last item of a dynamic array. |
| `sprint` | `Basic` | Like `print`, but allocates and returns the result as a string: `sprint :: (format_string: string, args: .. Any) -> string`. The returned string must be freed. |
| `tprint` | `Basic` | Like `sprint`, but uses temporary storage (no manual free needed). See §21. |
| `copy_string` | `Basic` | Allocates a heap copy of a string. The copy is mutable and must be freed. |
| `to_string` | `Basic` | Converts a `*u8` (C string) or `[] u8` to a OpenJai `string`. Also accepts `(*u8, s64)` to create a string from a raw pointer and byte count: `to_string(buffer.data, bytes_read)`. |
| `to_c_string` | `String` | Converts a OpenJai `string` to a zero-terminated `*u8` (C string). Heap-allocates; must be freed. |
| `string_to_int` | `String` | Parses an integer from a string: `string_to_int :: (str: string) -> int, bool`. Returns the value and a success flag. |
| `string_to_float` | `String` | Parses a float from a string: `string_to_float :: (str: string) -> float, bool`. |
| `to_integer` | `String` | Parses an integer: `to_integer :: (s: string) -> result: int, success: bool, remainder: string`. |

### `print` Procedure

Defined in module `Basic` (file `Print.OpenJai`). Signature:

```Jai
print :: (format_string: string, args: .. Any, to_standard_error := false) -> bytes_printed: s64
```

- `args: .. Any` declares a **variadic** parameter (`..`) of type `Any`.
  Because all types convert to `Any`, `print` can accept and print values
  of any type. The type information is available at both compile time and
  run time.
- The first argument must be a **string**. Passing a non-string (e.g.,
  `print(42)`) produces **Error: Type mismatch. Type wanted: string;
  type given: s64.**
- Use `%` as a substitution placeholder for values. Unlike C, no type
  specifier is needed (`%d`, `%s`, etc.) -- the compiler knows the types of
  all arguments.
- Numbered placeholders (`%1`, `%2`) allow reordering or reusing values:
  ```Jai
  print("%2 %1 %2\n", n, m);   // prints m, n, m
  ```
- The number of `%` placeholders must match the number of supplied arguments.
  A mismatch produces a **Warning**.
- To print a literal `%`, use `\%`. To separate two adjacent substitutions,
  use `%0%`.
- `print` returns the number of bytes printed.
- To print to standard error: `print("Error", to_standard_error = true);`

### `assert` Procedure

Defined in module `Basic`. Takes a boolean expression and an optional message
string. If the expression is `true`, nothing happens. If it is `false`, the
program stops with "Assertion failed", the source location, and a stack trace.
If an optional message string is provided, it is included in the output:

```Jai
assert(5 == 5.0);                         // passes silently
assert(4 == 5, "4 does not equal 5");     // Assertion failed: 4 does not equal 5
assert(type_of(n) == int);                // works with complex expressions
```

`assert` is useful for verifying program invariants during development and
debugging. Assert statements can be left in production code and disabled by
importing `Basic` with `ENABLE_ASSERT=false`:

```Jai
#import "Basic"()(ENABLE_ASSERT=false);
```

`ENABLE_ASSERT` is a program parameter for `Basic` and defaults to `true`.
When set to `false`, all `assert` calls compile to nothing — no performance
penalty. They can be quickly re-enabled by setting the parameter back to `true`
to diagnose production issues.

See also `#assert` for compile-time assertions (§29).

### Formatting Procedures

Defined in `Print.OpenJai` within the `Basic` module. These return `Formatter`
data structures that `print` knows how to use.

**`formatInt`**:

```Jai
formatInt :: (value: Any, base := 10, minimum_digits := 1,
              digits_per_comma: u16 = 0, comma_string := "") -> FormatInt
```

```Jai
formatInt(108, minimum_digits=2)                 // "108"
formatInt(108, base=16, minimum_digits=2)        // "6c"
formatInt(7, minimum_digits=2)                   // "07"
```

**`formatFloat`**:

```Jai
formatFloat :: (value: Any, width := -1, trailing_width := -1,
                mode := FormatFloat.Mode.DECIMAL,
                zero_removal := FormatFloat.Zero_Removal.YES) -> FormatFloat
```

```Jai
formatFloat(2.25193, width=4, trailing_width=3, zero_removal=.NO)    // "2.252"
formatFloat(3.14, width=1, trailing_width=3, zero_removal=.NO)      // "3.140"
formatFloat(3.14, width=1, trailing_width=3, zero_removal=.YES)     // "3.14"
formatFloat(12342345234.0, mode=.SCIENTIFIC)                         // "1.234235e+10"
```

**`formatStruct`**:

Provides additional control for printing structs:

```Jai
formatStruct(v3d,
    use_long_form_if_more_than_this_many_members = 2,
    use_newlines_if_long_form = true)
```

Produces output like:

```
{
    x = 1;
    y = 2;
    z = 3;
}
```

Default formatters are also available via `print_style.default_format_int` and
`print_style.default_format_float` from the Context.

### Low-Level Write Procedures

These are defined in `Preload` and `Runtime_Support`, so they do **not**
require importing `Basic`:

```Jai
write_string("Hello, World!\n");
write_strings("Hello", ",", " World!", "\n");
write_number(-42);
write_nonnegative_number(42);
```

---

## 11. Types

OpenJai is a **statically** and **strongly** typed language:

- **Statically typed**: the compiler must know the types of all constants,
  variables, and expressions at compile time.
- **Strongly typed**: a variable cannot change type (e.g., from number to
  string as in Python or Ruby). Conversion between types is strictly
  controlled, and operations can only work on certain types.

The type `Any` is an exception: variables of all types can be converted to
`Any` (see "The Any Type" below).

The type determines what operations can be performed on a value and how much
memory it occupies.

Besides the primitive types listed below, OpenJai also has other fundamental types:
`string`, pointer, procedure, struct, union, array, and enum.

### First-Class Types

Types in OpenJai are **first-class values**. A type can be stored in a variable,
passed to a procedure, compared, and manipulated like any other value.

Every type has type `Type`. The type of `Type` is itself `Type`:

```Jai
a: Type = float64;          // a holds the type float64
b := int;                   // b inferred as Type, value s64 (int is an alias)
c := type_of(42);           // c is Type, value s64
d := type_of(b);            // d is Type, value Type
var := Type;
print("%\n", type_of(var)); // => Type
```

If a type value is a compile-time constant (known at compile time), it can be
used to declare variables of that type.

`Type` is 8 bytes in size. `Code` is also a type.

The compiler has complete knowledge of all types at compile time. Some of this
information remains accessible at run time as **Run-Time Type Information
(RTTI)**.

### Type Aliases

An existing type can be given a new name using a constant declaration,
creating a **type alias**:

```Jai
Thread_Index :: s64;           // global type alias

main :: () {
    TI :: s32;                  // local type alias (constant of type Type, value s32)
    s: TI = 7;
    t: TI = 9;
    print("%\n", s * t);       // => 63
    print("%\n", size_of(TI)); // => 4
}
```

Variables of the aliased type can be used in all operations defined for the
underlying type. The built-in aliases `int` (for `s64`) and `float` (for
`float32`) are type aliases.

### The `#type` Directive

The `#type` directive tells the compiler that the following syntax is a
**type literal**. It is primarily used for defining procedure types and
type variants.

#### Defining Procedure Types

`#type` is used to name procedure signatures as types:

```Jai
my_proc :: (v: int) -> int { return v + 5; }
my_proc_type :: #type (int) -> int;
assert(type_of(my_proc) == my_proc_type);

a_proc_ptr : my_proc_type = my_proc;
result := a_proc_ptr(42);    // => 47
```

`#type` is needed to resolve ambiguous type grammar. Without it, certain
declarations do not compile:

```Jai
// proctest: Type : (s32) -> s32;     // error
proctest: Type : #type (s32) -> s32;  // ok
```

It can also be used with calling conventions:

```Jai
IL_LoggingLevel :: u16;
IL_Logger_Callback :: #type (level: IL_LoggingLevel, text: *u8, ctx: *void) -> void #c_call;
```

#### Type Variants (`#type,distinct` and `#type,isa`)

Type variants create new types derived from existing types with controlled
casting behavior. They differ from type aliases in that they provide type
safety -- the compiler will not implicitly convert between unrelated types.

The `variant_of` field of `Type_Info` indicates the underlying type.
Type variants have `Type_Info_Tag.VARIANT`.

**`#type,distinct`** creates a type that is fully distinct from its base type.
No implicit conversion is allowed in either direction:

```Jai
HandleA :: u32;                      // type alias -- freely interchangeable with u32
HandleB :: #type,distinct u32;       // distinct variant -- not interchangeable

u : u32     = 7;
a : HandleA = 42;
b : HandleB = 1776;

u = a;          // ok: HandleA is just an alias for u32
a = u;          // ok
// a = b;       // error: Type mismatch. Type wanted: HandleA; type given: HandleB
// b = u;       // error: Type mismatch
b = cast(HandleB) u;  // ok: explicit cast
b = xx (u + 1);       // ok: autocast
```

Math operations work on distinct types:

```Jai
a: Handle = 5;
print("%\n", 3 * a + 2);    // => 17
```

**`#type,isa`** creates a type that will implicitly cast **to** its base type,
but variants with the same base type will not implicitly cast to each other:

```Jai
Filename  :: #type,isa string;
Velocity3 :: #type,isa Vector3;

fn: Filename = "/home/var/usr/etc/dev/cake";
va: Velocity3 = .{1,2,3};
```

#### Inspecting Type Variants

```Jai
Handle :: #type,distinct u32;
ti := cast(*Type_Info) Handle;
print("%\n", ti.type);                // => VARIANT

hi := type_info(Handle);
print("%\n", <<hi.variant_of);        // => {INTEGER, 4}

Filename :: #type,isa string;
f := type_info(Filename);
print("%\n", <<f.variant_of);         // => {STRING, 16}
```

### Primitive Types

#### `bool`

Has only the values `true` and `false`. Takes 8 bits (1 byte).

**Boolean operators:**

| Operator | Name | Description |
|----------|------|-------------|
| `!`      | NOT  | Unary negation: `!true` is `false`, `!false` is `true`. |
| `&&`     | AND  | True only when both operands are true. |
| `\|\|`   | OR   | False only when both operands are false. |

`&&` and `||` use **short-circuit evaluation**:
- `&&`: if the first operand is `false`, the second is not evaluated.
- `||`: if the first operand is `true`, the second is not evaluated.

#### Integer Types

Ten integer types exist, varying by size and signedness:

| Type   | Size    | Range |
|--------|---------|-------|
| `s8`   | 1 byte  | −127 to 128 |
| `u8`   | 1 byte  | 0 to 255 |
| `s16`  | 2 bytes | −32,768 to 32,767 |
| `u16`  | 2 bytes | 0 to 65,535 |
| `s32`  | 4 bytes | −2,147,483,648 to 2,147,483,647 |
| `u32`  | 4 bytes | 0 to 4,294,967,295 |
| `s64`  | 8 bytes | −9,223,372,036,854,775,808 to 9,223,372,036,854,775,807 |
| `u64`  | 8 bytes | 0 to 18,446,744,073,709,551,615 |
| `s128` | 16 bytes | (128-bit signed) |
| `u128` | 16 bytes | (128-bit unsigned) |

`int` is an alias for `s64`.

Integer literal formats:

- Decimal: `42`, `0`, `-3`
- Binary: `0b10` (= 2)
- Hexadecimal: `0x10` (= 16)
- Underscores as digit separators: `16_777_216`, `0b1010_0010_0101_1111`

#### Floating-Point Types

Two floating-point types exist (both signed):

| Type      | Size    | Precision |
|-----------|---------|-----------|
| `float32` | 4 bytes | Single-precision |
| `float64` | 8 bytes | Double-precision |

`float` is an alias for `float32`.

Float literal formats:

- Decimal: `3.141592`
- Scientific notation: `5.98e24` (a `.` is required before the `e`, so write
  `1.0e-6` not `1e-6`)
- Hex float: use the `0h` prefix to specify floats in IEEE-754 format.

The `Math` module contains minimum and maximum range constants for integer and
float types: `FLOAT32_MIN`, `FLOAT32_MAX`, `S16_MIN`, `S16_MAX`, etc.

#### Implicit and Explicit Type Conversions

**Implicit widening**: A value can be assigned to a variable of a "bigger"
type without an explicit cast (e.g., `s8` → `s64`, `u8` → `u16`). The compiler
blocks assignments where the target type is too small or where signedness
conflicts:

```Jai
i: s16 = 80000;   // Error: Loss of information (trying to fit 64 bits into 16 bits).
j: u32 = -1;      // Error: Number signedness mismatch.
b: u8; c: u16;
b = c;             // Error: Loss of information (trying to fit 16 bits into 8 bits).
```

**Explicit cast**: `cast(Type) value` converts `value` to `Type`. Cast
operations perform range checks at runtime; if information would be lost, the
program panics:

```Jai
b = cast(u8) a;   // runtime error if a's value doesn't fit in u8
```

**Unchecked cast**: `cast, no_check(Type) value` skips the runtime range
check. The value is truncated silently. This also provides a performance
benefit:

```Jai
b = cast, no_check(u8) a;   // truncates to low 8 bits, no check
```

**Truncating cast**: `cast, trunc(Type) value` explicitly truncates bits that
don't fit.

**Float-to-integer cast**: Truncates the fractional part:

```Jai
pi := 3.14;
e: u8 = cast(u8) pi;   // e is 3
```

**Bool-to-integer cast**: `true` converts to `1`, `false` converts to `0`:

```Jai
e: u8 = xx true;    // e is 1
e = xx false;        // e is 0
```

**Integer-to-bool cast**: `0` converts to `false`; any other value converts to
`true`. Requires explicit `cast(bool)` (autocast `xx` does not work here):

```Jai
b1: bool = cast(bool) 0;     // false
b1 = cast(bool) -50;         // true
```

In general, a `cast(bool)` of a value is `false` if the value is zero, null,
or empty, and `true` if it contains a real value. This is called the
**truthiness** of a value.

#### Autocast (`xx`)

The `xx` operator performs an automatic cast when the compiler can infer the
target type:

```Jai
b: u8;
c: u16 = 50;
b = xx c;          // autocast c to u8
```

Runtime checks are still performed with `xx` -- it is equivalent to `cast()`
with bounds checking, not `cast, no_check()`.

Use `xx` for quick casts during development; use the full `cast()` form for
clarity in reviewed code.

#### `string`

The most common data type. String literals are enclosed in double quotes:
`"Hello, Sailor!"`. Strings are defined as structs internally (an array view
of bytes, `[] u8`). The internal definition in the `Preload` module is:

```Jai
Newstring :: struct {
    count : s64;   // number of bytes (not characters)
    data  : *u8;   // pointer to the first byte
}
```

This is the exact same definition as `Array_View_64`. A `string` variable is
always 16 bytes (regardless of content, including Unicode). The actual
character data is stored elsewhere -- string literals live in a read-only
segment of the binary.

The empty string `""` is the default value, with `count` = 0 and `data` =
`null`.

Strings are **UTF-8 encoded**. The `count` field is the number of bytes, not
the number of characters. For example, the string `"世界"` has `count` = 6
(each CJK character is 3 bytes in UTF-8).

Because strings are array views, the `.count` and `.data` fields can be
directly manipulated to create sub-views (slices):

```Jai
x := "Sailor";
x.count = 4;       // x is now "Sail"
x.count -= 1;
x.data += 1;       // x is now "ail"
```

A string can always be cast to `[] u8`. String constants are zero-terminated
and can be implicitly cast to `*u8` or `*s8` (for C interop), but a string
variable cannot be implicitly cast to `*u8`.

See §28 for comprehensive string operations.

#### `void`

A special type of size 0 with no values. Used when a variable has no value.
Other types cannot cast to `void`. A variable of type `void` prints as `void`.

#### Character Literals (`#char`)

OpenJai has no explicit character type. The `#char` directive applied to a
single-character string gives the numeric value of the ASCII character,
inferred as type `s64`:

```Jai
f := #char "1";   // f is 49 (the ASCII value of '1'), type s64
```

### Pointer Types

OpenJai follows the **C pointer model** -- pointers are allowed everywhere in code
and provide direct access to memory locations. OpenJai does **not** have smart
pointers (as in C++), and has **no references** (as in Java). There are only
values and pointers.

#### Declaration and Address-Of

Pointer types are written with a `*` prefix on the pointed-to type. The `*`
operator is also the **address-of** operator when applied to a value:

```Jai
a : int = 42;
b : *int;        // declaration: b is a pointer to an int
b = *a;          // address-of: point b at a
c := *a;         // type inferred as *s64
```

Pointers can point to any type: primitive types (int, float, bool), composite
types (strings, arrays, structs), and even other pointers.

#### Dereferencing

To obtain the value pointed to by a pointer (**dereferencing**), use the `<<`
prefix operator or the `.*` postfix operator:

```Jai
val := << ptr;   // prefix dereference (original syntax)
val := ptr.*;    // postfix dereference (added in v1.0.65, preferred)
```

The postfix `.*` form is preferred -- it requires less parenthesization and
avoids parsing ambiguities in `if` statements without braces. The prefix `<<`
form is planned for eventual removal. Both forms produce identical
`Code_Nodes`.

Dereferencing can also be used on the left-hand side to modify the pointed-to
value:

```Jai
<< ptr = 108;    // changes the value at the address ptr points to
```

In some cases, dereferencing happens automatically when using the pointer
itself, to simplify the syntax.

Taking an address and immediately dereferencing cancels out:

```Jai
a : int = 5;
b := <<*a;       // b is 5
```

#### Pointer Size

The size of a pointer is always **8 bytes** (`u64`) on a 64-bit machine,
regardless of what type it points to.

#### Null

The default (zero) value of any pointer is **`null`**. An uninitialized
pointer has the value `null`, meaning it has no address to point to.

```Jai
d: *u32;                             // d is null
print("%\n", d);                     // => null
print("%\n", type_of(null));         // => *void
```

The type of `null` is `*void`. Only pointer types can be assigned `null` --
it cannot be assigned to ints, structs, arrays, strings, or any other
non-pointer type.

#### Void Pointer (`*void`)

A `*void` is a pointer with no associated data type. It can hold the address
of any type and can be cast to any type, with the same functionality as C's
`void*`:

```Jai
ptr: *void;                          // no type information
print("%\n", << ptr);                // => void (if null)
```

A pointer to data of unknown type has type `*void`.

#### Pointers to Pointers

A pointer itself has an address, so pointers to pointers are possible at
arbitrary levels of indirection:

```Jai
a2: int = 3;
b2: *int = *a2;
c2: **int = *b2;
d2: ***int = *c2;
print("%\n", << << << d2);          // => 3
```

To reach the value, dereference once per level of indirection.

#### Null Pointer Dereference

Attempting to dereference a null pointer causes a **runtime crash** with a
stack trace. The program stops and prints the location of the fault.

Use `assert(ptr != null)` or print the pointer value to diagnose null pointer
bugs. Running the program at compile time with `#run main()` can also catch
null dereferences during compilation rather than at runtime.

#### Dangling Pointers

After heap memory is freed with `free()`, the pointer becomes **dangling** --
it should no longer be used, but OpenJai does not prevent access. The pointer
still retains its address and can still be dereferenced (yielding the old
value or garbage). To explicitly invalidate a pointer after freeing, assign
`null` to it:

```Jai
a := New(int);
<< a = 5;
free(a);           // a is now dangling
a = null;          // explicitly invalidate
```

#### Casting to Pointer Types

A pointer can be cast to a different pointer type:

```Jai
ptr1 := cast(*int) ptr;
```

If the pointer does not actually point to data of the target type, the result
is undefined -- it may give an unexpected value or crash the program.

### Structs

Structs are conceptually the most fundamental type in OpenJai. A struct is a
composite data type that groups multiple fields (member variables) of
potentially different types into a single entity. Structs are a lightweight
alternative to classes -- they have no methods, no inheritance, and no access
control. See §24 for full details.

A struct cannot be cast to a `bool`.

### Arrays

Arrays are a built-in data type for storing a series of items of the same type,
packed contiguously in memory. Arrays are defined internally as structs. OpenJai
supports three kinds of arrays: **static** (fixed-size), **dynamic**
(resizable), and **array views**. See §27 for full details.

### The Any Type

The **Any** type (defined in the `Preload` module) is the widest type in OpenJai.
It encompasses and matches all other types -- values of any type can be
converted to `Any`. This allows a single variable to hold values of different
types at different times:

```Jai
x: Any = 3.0;
x = 3;
x = "Hello";
x = main;       // even a procedure
print("%\n", type_of(x));    // => Any
print("%\n", type_of(main)); // => procedure ()
```

`Any` is 16 bytes in size (two 8-byte pointers on a 64-bit system). It is a
more informative and type-safe version of C's `void*`. Internally, `Any` is
defined as a struct in the `Preload` module:

```Jai
Any_Struct :: struct {
    type: *Type_Info;
    value_pointer: *void;
}
```

- **`type`** -- a pointer to a `Type_Info` struct containing metadata about the
  held value's type.
- **`value_pointer`** -- a `*void` pointer to the actual value (void because
  the type is not known statically).

#### Extracting Values from Any

To extract the value from an `Any`, cast `value_pointer` to a pointer of the
correct type, then dereference:

```Jai
x: Any = 3.0;
print("%\n", << cast(*float) x.value_pointer);    // => 3

x = "foo";
print("%\n", << cast(*string) x.value_pointer);   // => foo

n: s32 = 5;
a: Any = n;
print("%\n", << cast(*s32) a.value_pointer);       // => 5
```

#### Inspecting the Type of an Any

The `.type` field provides access to the held value's type information:

```Jai
a: Any = n;
print("%\n", << a.type);       // => {INTEGER, 4}
print("%\n", a.type.type);     // => INTEGER
```

- `<< a.type` dereferences to the full `Type_Info` (e.g., `{INTEGER, 4}`
  meaning integer type, 4 bytes).
- `a.type.type` gives the `Type_Info_Tag` value (e.g., `INTEGER`, `FLOAT`,
  `STRUCT`).

The tag can be used in `if`-`case` to dispatch on type:

```Jai
if a.type.type == {
    case Type_Info_Tag.FLOAT;     print("a is a float\n");
    case Type_Info_Tag.INTEGER;   print("a is an int\n");
}
```

The `print` procedure uses `Any` for its variadic arguments (`args: .. Any`),
which is why it can print values of any type. `print` uses the runtime type
information baked into `Any` to format values correctly.

### Type Comparisons

Types can be compared for equality with `==` and `!=`:

```Jai
y: float64 = 0.1;
assert(type_of(y) == float64);   // passes
n := 42;
assert(type_of(n) == int);       // passes
assert(type_of(n) != string);    // passes
b := int;
print("%\n", b == float);        // => false
```

### Memory Layout

The compiler knows the size of every type and allocates memory for a variable
at its declaration.

Known type sizes:

| Type      | Size     |
|-----------|----------|
| `bool`    | 1 byte   |
| `u8`/`s8` | 1 byte  |
| `u16`/`s16` | 2 bytes |
| `u32`/`s32`/`float32` | 4 bytes |
| `u64`/`s64`/`float64` | 8 bytes |
| `u128`/`s128` | 16 bytes |
| `Type`    | 8 bytes  |
| `*T` (any pointer) | 8 bytes (a `u64` address on 64-bit machines) |
| `string`  | 16 bytes (struct: pointer + count; size is constant regardless of string content, including Unicode) |
| `Any`     | 16 bytes (type pointer + value pointer) |

### Type Information System

At compile time, OpenJai deduces all there is to know about the types of all
variables and other code objects. This information is represented through a
hierarchy of `Type_Info` structs defined in the `Preload` module. The type
information system supports both compile-time meta-programming and runtime
reflection. Using type info to meta-program is also called _reflection_ or
_introspection_ in other languages.

#### The Type Table

A structure called `_type_table` contains all types used in the program. It is
populated at compile time and stored in the data segment of the executable,
making full introspection data available for all structs, functions, and enums
at runtime. The type table is not directly accessible; use `get_type_table()`
from the `Compiler` module to obtain it:

```Jai
#import "Compiler";

table := get_type_table();  // returns [] *Type_Info
print("The type table has % entries\n", table.count);
for table {
    print("%: type: %  size: %\n", it_index, it.type, it.runtime_size);
}
```

Each entry is a pointer to a `Type_Info` struct. Requesting type info for any
variable returns a pointer to its entry in the type table. See also the build
option `runtime_storageless_type_info` (§30).

#### `Type_Info`

`Type_Info` is the base struct containing metadata for all types that appear
in a program. It can be cast to more specific structs for additional
type-specific details:

```Jai
Type_Info :: struct {
    type:         Type_Info_Tag;
    runtime_size: s64;
}
```

- **`type`** -- a `Type_Info_Tag` enum value identifying the type category
  (e.g., `INTEGER`, `STRUCT`, `FLOAT`).
- **`runtime_size`** -- the size of the type in bytes.

#### `Type_Info_Tag`

`Type_Info_Tag` is an enum that enumerates all type categories in OpenJai:

```Jai
Type_Info_Tag :: enum u32 {
    INTEGER              :: 0;
    FLOAT                :: 1;
    BOOL                 :: 2;
    STRING               :: 3;
    POINTER              :: 4;
    PROCEDURE            :: 5;
    VOID                 :: 6;
    STRUCT               :: 7;
    ARRAY                :: 8;
    OVERLOAD_SET         :: 9;
    ANY                  :: 10;
    ENUM                 :: 11;
    POLYMORPHIC_VARIABLE :: 12;
    TYPE                 :: 13;
    CODE                 :: 14;
    VARIANT              :: 18;
}
```

#### Specialized Type_Info Structs

For nearly every type category, there is a specialized struct that extends
`Type_Info` with additional fields. These use `using #as` to embed the base
`Type_Info`, so they can be used wherever a `Type_Info` is expected:

```Jai
Type_Info_Integer :: struct {
    using #as info: Type_Info;
    signed: bool;
}
```

Known specialized structs include:

| Struct                     | For tag       | Additional fields                  |
|----------------------------|---------------|------------------------------------|
| `Type_Info_Integer`        | `INTEGER`     | `signed: bool`                     |
| `Type_Info_Struct`         | `STRUCT`      | `name`, `members`, `specified_parameters`, `status_flags`, `nontextual_flags`, `textual_flags`, `polymorph_source_struct`, `initializer`, `constant_storage` |
| `Type_Info_Enum`           | `ENUM`        | `name`, `enum_type_flags`, values, names |
| `Type_Info_Procedure`      | `PROCEDURE`   | `argument_types`, `return_types`   |

`Type_Info_Struct` is particularly rich. Its `.members` field is an array of
`Type_Info_Struct_Member` values, each containing:

| Field                       | Description                                    |
|-----------------------------|------------------------------------------------|
| `name`                      | The field name as a string.                    |
| `type`                      | Pointer to the field's `Type_Info`.            |
| `offset_in_bytes`           | Byte offset of the field within the struct.    |
| `flags`                     | Field flags (e.g., `.AS` for `#as` fields).    |
| `notes`                     | Array of annotation strings.                   |
| `offset_into_constant_storage` | Offset into constant storage.               |

#### The `type_info()` Procedure

`type_info()` takes a type as its argument and returns a `*Type_Info` (a
pointer to the appropriate specialized `Type_Info` struct). Through it, all
specific type information can be accessed:

```Jai
typ1 := << type_info(float64);
print("%\n", typ1);              // => {FLOAT, 8}
print("%\n", typ1.type);        // => FLOAT

print("%\n", type_info(Any).type);  // => ANY
```

For struct types, `type_info` returns a `*Type_Info_Struct`, which provides
access to the struct's members:

```Jai
ti := type_info(Vector3);               // *Type_Info_Struct
for member: ti.members {
    print("% - ", member.name);          // => x - y - z - ...
}
```

The `get_field` procedure retrieves detailed information about a specific
named field:

```Jai
z_info := get_field(type_info(Vector3), "z");
print("%\n", <<z_info);
// => {name = "z"; type = ...; offset_in_bytes = 8; flags = 0; notes = []; ...}
```

To get all available information on any type, dereference the result of
`type_info`:

```Jai
typ2 := << type_info(Vector3);
print("%\n", typ2);              // prints all struct metadata
print("%\n", typ2.type);        // => STRUCT
```

The same information for a struct can be obtained by explicit cast:

```Jai
tis := << cast(*Type_Info_Struct) Vector3;
```

`type_info` is commonly used in polymorphic procedures to test the type of a
`$T` argument.

#### Checking Whether an Enum Is `#specified`

The `enum_type_flags` field in `Type_Info_Enum` provides additional metadata
about an enum. The `SPECIFIED` flag indicates whether the enum was declared
with `#specified`:

```Jai
info := type_info(Direction);          // *Type_Info_Enum
if info.enum_type_flags & .SPECIFIED {
    print("specified\n");
} else {
    print("NOT specified\n");
}
```

#### Checking Struct Subclass Relationships

The member flags on `Type_Info_Struct_Member` can be used to determine whether
a struct uses `#as` with a particular type:

```Jai
uses_vector3_with_as :: (T: Type) -> bool {
    ti := cast(*Type_Info) T;
    if ti.type != .STRUCT  return false;

    tis := cast(*Type_Info_Struct) ti;
    for tis.members {
        if !(it.flags & .AS)             continue;
        if it.type != type_info(Vector3) continue;
        return true;
    }
    return false;
}
```

The `Compiler` module provides a built-in procedure for this:

```Jai
#import "Compiler";

tie := cast(*Type_Info) type_info(Employee);
if is_subclass_of(tie, "Person") {
    print("Employee is a subclass of Person\n");
}
```

`is_subclass_of` checks whether a struct has a `using #as` relationship to a
named supertype. A struct using `using` without `#as` is **not** considered a
subclass by this procedure.

#### Runtime Type Information Control

By default, the compiler bakes type information into the executable so it is
available at runtime. The `print` procedure, for example, uses this runtime
type info to format values correctly. Types for which the program calls
`type_info()`, or any type referenced by those recursively, are included.

To reduce executable size when runtime type info is not needed, the following
directives are available:

- **`#type_info_none`** -- a struct with this directive will have no runtime
  type info:

  ```Jai
  NoThing :: struct #type_info_none { ... }
  ```

- **`#type_info_procedures_are_void_pointers`** -- in structs with this
  directive, procedure fields do not retain their type info at runtime.

The same can be achieved without modifying the struct definition, using
`compiler_set_type_info_flags`:

```Jai
#run compiler_set_type_info_flags(NoThing, .NO_TYPE_INFO);
#run compiler_set_type_info_flags(Bundle_B, .PROCEDURES_ARE_VOID_POINTERS);
```

---

## 12. Constants and Variables

### Declaration Syntax Summary

```
NAME :: value;           // constant, type inferred
NAME : type : value;     // constant, type explicit

name := value;           // variable, type inferred
name : type = value;     // variable, type explicit
name : type;             // variable, default zero value
name : type = ---;       // variable, explicitly uninitialized
```

`::` defines a compile-time constant. `:=` defines a run-time variable. In
both cases the type can be inferred.

### Constants

A constant is declared with `::`:

```Jai
MASS_EARTH :: 5.97219e24;          // type inferred (float32)
MASS_EARTH0 : float : 5.97219e24; // type explicit
```

- By convention, constant names are `UPPER_SNAKE_CASE`.
- Constants cannot be reassigned: attempting `MASS_EARTH = 5.98e24;` produces
  **Error: Attempt to assign to a constant.**
- Duplicate constant names are not allowed.
- Constants declared outside any procedure are in **global scope** (known
  throughout the program).
- Constants declared inside a procedure are in **local scope**.

Constants in OpenJai include: static values, enums, structs, and **procedures**.
All procedures are constants (they use `::` and cannot be rebound at
run-time).

A compile-time computed constant can be created with `#run`:

```Jai
COMP_CALC :: #run (234 * 15);   // COMP_CALC is 3510, computed at compile time
```

The `is_constant()` procedure checks whether an expression is a compile-time
constant:

```Jai
is_constant(MASS_EARTH)  // true
is_constant("Hello")     // true
```

### Variables

A variable is a name given to a mutable memory location. No `var` or `mut`
keyword is needed. The value can change; the type cannot.

By convention, variable names are `snake_case`.

There are four declaration forms:

**Case 1 -- Type and value:**

```Jai
counter : int = 100;
first_name : string = "Jon";
```

**Case 2 -- Type only (default zero value):**

```Jai
counter : int;       // default 0
pi : float;          // default 0
valid : bool;        // default false
name : string;       // default ""
```

Default zero values: `0` for numbers, `false` for `bool`, `""` for `string`,
`null` for pointers. This is safer than C, where uninitialized variables have
random values.

**Case 3 -- Value only (type inferred):**

```Jai
counter := 100;       // int (s64)
pi := 3.14159;        // float (float32)
valid := false;        // bool
first_name := "Jon";   // string
```

This is the most commonly used form in practice.

**Case 4 -- Explicit un-initialization (`---`):**

```Jai
counter : int = ---;
average : float = ---;
```

Skips default zero initialization for performance. The variable may contain
any leftover value from that memory location (C-like behavior). The
programmer must initialize it before use.

### Assignment

Changing the value of a previously declared variable uses `=`:

```Jai
counter = 100;
```

Using `=` without a prior declaration is an error:
`counter5 = 101;` → **Error: Undeclared identifier 'counter5'.**

Assigning a value of the wrong type is an error:
`counter = "France";` → **Error: Type mismatch.**

### Multiple Assignment

Multiple variables can be declared and assigned in a single statement:

```Jai
n, m : u8 = 12, 13;       // explicit type
n, m := 12, 13;            // type inferred
p, q, r := 13;             // all three get 13
x, y := 1, "hello";       // mixed types
s, t := 2 + 3, 2 * 3;     // expressions
```

Separate declaration and assignment:

```Jai
n, m : int;
n, m = 1, 2;
```

Compound assignment (`n = m = 13;`) is **not** allowed. The `=` operator can
only be used at statement level.

Compound assignment operators can also be applied to multiple variables:

```Jai
a, b += 1;   // increments both a and b by 1
```

Advanced mixed declaration/modification in one statement:

```Jai
b := 5;
a, b=, c := 1, 2, 3;   // a and c declared, b modified
a, d:, c = 4, 5, 6;     // d declared, a and c modified
```

### Swapping Values

Values can be swapped with a compound assignment:

```Jai
n, m = m, n;   // swaps the values of n and m
```

Both variables must have the same type.

### Global Variables

Variables declared outside any procedure are in **global scope**, visible and
mutable throughout the entire program:

```Jai
global_var := 108;   // global scope

main :: () {
    print("%\n", global_var);   // accessible here
}
```

**Limitation**: Pointers to elements of global arrays are not compile-time
constants, so they cannot be initialized at file scope. They must be assigned
at runtime (e.g., inside `main`):

```Jai
players: [2]Pad;
player1: *Pad;         // declared at file scope but not initialized here
// player1 = *players[0];  // Error: not a constant expression

main :: () {
    player1 = *players[0];  // must be assigned at runtime
}
```

---

## 13. Scoping

### Scope Hierarchy

Variables and constants have a **scope** (or **lifetime**) -- the region of
code where they are accessible. When a variable goes out of scope, its memory
is freed.

Scopes are hierarchical: if an identifier is not defined in the current scope,
the compiler searches upward through parent scopes until it finds a match or
reports an error (`Error: Undeclared identifier 'n'.`).

### Data Scope vs Imperative Scope

OpenJai distinguishes two kinds of scopes:

**Data scope** (also called **global scope** or **application scope**): Code
outside of any procedure, including `main`. Data scope contains only
declarations -- there is no executing code and no notion of ordering.
Declarations in a data scope are unordered with respect to each other. Global
constants, global variables, enums, struct types, and procedures can all be
declared in data scope. By default, all declarations in data scope are
**exported** (visible to other code files that load this one).

**Imperative scope** (also called **procedural scope**): Code inside procedures
such as `main()`. Statements in imperative scope execute sequentially from top
to bottom at runtime.

### Global Scope

Variables or constants declared at the top level of a source file have
**global scope**. They are visible throughout the entire code file and in any
code files that load it. Global variables occupy memory for the entire duration
of the program. Variables defined inside `main` also stay active until `main`
ends, but they are not visible in other procedures or procedures called from
`main`.

### Local Scope

Variables and constants declared inside a code block are **local** to that
block. They are automatically freed when the block exits (at the closing `}`).
Procedures, conditionals, loops, and other control structures all create local
scopes.

An **anonymous code block** (`{ }`) can be used anywhere inside imperative
scope to create a new local scope:

```Jai
main :: () {
    x := 7;
    {
        n := 10;        // only visible inside this block
        print("%\n", n);
        print("%\n", x);  // parent scope is accessible
    }
    // n is not accessible here
    // print("%\n", n);  // Error: Undeclared identifier 'n'.
}
```

Unlike Rust, anonymous code blocks **cannot return a value** to be assigned.
Attempting this produces `Error: Unable to parse an expression to the right of
this binary operator.`

### Shadowing

A variable in an inner scope can **shadow** a variable with the same name in
an outer scope. Inside the inner scope, the inner variable takes precedence:

```Jai
main :: () {
    outer := 42;
    {
        outer := 99;   // new variable that shadows the outer one
        print("%\n", outer);   // => 99
    }
    print("%\n", outer);       // => 42 (original is unaffected)
}
```

A common pitfall with shadowing is accidentally using `:=` (declaration) when
`=` (assignment) is intended, creating a new local variable that shadows the
outer one instead of modifying it:

```Jai
player: *Pad;           // file-scope variable

main :: () {
    player = *players[0];    // correct: assigns to file-scope variable
    // player := *players[0];  // BUG: creates a local shadow; file-scope
    //                         // variable remains null, likely causing a crash
}
```

### Procedure Scope Rules

- Procedures can access global variables and constants from data scope.
- A procedure defined inside another procedure **cannot** access the local
  variables of the enclosing procedure, because it must be able to run
  independently.
- A nested procedure **can** access **constants** from any enclosing scope,
  including imperative scopes. Since procedures are constants, nested
  procedures can also call procedures defined in outer scopes.

### File Scope (`#scope_file`)

By default, all declarations in a source file are **exported** into
application (global) scope — they are visible to every other file in the
program. To restrict declarations to the file they appear in, place
`#scope_file;` before them:

```Jai
foxtrot :: "Application Scope (from file alpha).";  // exported

#scope_file;
tango :: "File Scope (in file alpha)";               // private to this file
```

Declarations after `#scope_file;` are in **file scope**: visible within that
file but invisible to other files that `#load` or `#import` it. If a
file-scoped name is the same as a name in application scope, code in the file
sees the file-scoped version (shadowing), while code in other files sees the
application-scope version.

To switch back to exported (application) scope within the same file, use
`#scope_export;`:

```Jai
#scope_file;
private_helper :: "only in this file";

#scope_export;
public_again :: "visible everywhere";
```

The directives are positional — each one affects all declarations that follow
it until the next scope directive or end of file.

**Example**: Given a main file that `#load`s two helper files, each helper can
shadow a global name with a file-scoped version. The main file and each helper
each see their own `tango`:

```Jai
// main file
#load "file_alpha.OpenJai";
#load "file_beta.OpenJai";
tango :: "Application Scope (from the main file).";
// main sees tango = "Application Scope (from the main file)."
```

```Jai
// file_alpha.OpenJai
#scope_file;
tango :: "File Scope (in file alpha)";
// file_alpha sees tango = "File Scope (in file alpha)"
```

```Jai
// file_beta.OpenJai
#scope_file;
tango :: "File Scope (in file beta)";
// file_beta sees tango = "File Scope (in file beta)"
```

### Module Scope (`#scope_module`)

Each module has its own scope that is **completely sealed off**: a module
cannot see the application scope of the importing project, and it cannot see
other modules (unless it imports them itself).

To make declarations private within a module (visible to all files in the
module but not to code that imports the module), use `#scope_module;`:

```Jai
#scope_module;
internal_helper :: () { /* ... */ }   // visible within the module only
```

### Scope Directive Summary

| Directive        | Effect on subsequent declarations                     |
|------------------|-------------------------------------------------------|
| `#scope_file`    | Private to the current file; not exposed via `#import` or `#load`. |
| `#scope_export`  | Public / application scope; exposed via `#import` and `#load`. This is the default. |
| `#scope_module`  | Private to the current module; visible across files within the module but not to importers. |

---

## 14. Naming Conventions

The following conventions are standard but not enforced by the language:

| Style | Usage | Examples |
|-------|-------|----------|
| `snake_case` | Identifiers: procedures, variables, macros | `birth_date`, `is_constant()` |
| `Capitalized_Snake_Case` | Types and imports | `Entity`, `Enemy_Entity`, `Command_Line` |
| `UPPER_SNAKE_CASE` | Constants and enum members | `MASS_EARTH`, `.SOUTH` |
| lowercase | Primitive types | `int`, `float`, `bool`, `string` |

Exceptions to these conventions exist in the standard library.

### Identifier Backslashes

A `\` followed by any number of spaces can be inserted into an identifier.
The backslash and spaces are ignored by the compiler — the resulting
identifier is the same as if they were not present. This allows vertically
aligning related variable names for readability:

```Jai
current_time: float64;
last\  _time: float64;    // same as last_time, aligned with current_time

hel\ lo := 5;
print("%\n", hello);      // => 5   (hel\ lo and hello are the same identifier)
```

This increases code readability for groups of related names but makes
text-based searching for identifiers harder.

---

## 15. Memory Management

OpenJai gives developers **complete control** over where and when memory is
allocated. There is no garbage collector and no automatic memory management.
The developer is responsible for freeing heap-allocated memory. If heap memory
is not freed when it is no longer needed, **memory leaks** occur -- the program
consumes ever-increasing memory, degrading performance.

The compiler packs values contiguously in memory (consecutive addresses,
adjacent blocks) to maximize cache locality and runtime performance.

### Stack and Heap

- **Stack**: Variables of basic types are stored on the stack by default for
  performance. Stack memory is freed automatically when the variable goes out
  of scope.
- **Heap**: Most of a program's memory is allocated on the heap (also called
  **dynamic allocation**). The developer is responsible for explicitly freeing
  heap memory.

### The `defer` Keyword

The `defer` keyword delays execution of a statement or code block until the
end of the current (enclosing) scope -- that is, just before the closing `}`.
This allows allocation and deallocation to be written adjacent in code, with
the compiler ensuring the deallocation happens at the right time.

```Jai
main :: () {
    n := New(int);
    defer free(n);      // free executes at the closing } of main
    << n = 42;
    // ... use n ...
}   // free(n) runs here
```

**Key properties:**

- `defer` can take a single statement or a code block enclosed in `{ }`.
  Optionally, the statement may be enclosed in parentheses `()`.
- Multiple `defer` statements in the same scope execute in **reverse (LIFO)
  order** -- Last In, First Out:

  ```Jai
  main :: () {
      print("1, ");
      defer print("5, ");
      print("2, ");
      defer print("4, ");
      print("3, ");
  }
  // Output: 1, 2, 3, 4, 5,
  ```

- `defer` operates at **scope** level, not function level. In loops, deferred
  statements execute at the end of each loop iteration, not at the end of the
  enclosing function. This is different from Go's `defer`.
- Variables referenced by a deferred statement use their value **at the time
  the defer executes** (scope exit), not at the time the `defer` is written:

  ```Jai
  x := 123;
  defer print("x is %\n", x);
  x = 234;
  // prints "x is 234" -- the value of x when the scope exits
  ```

- `defer` with a code block:

  ```Jai
  start_time := get_time();
  defer {
      elapsed := get_time() - start_time;
      print("Elapsed: % ms\n", elapsed * 1000);
  }
  // ... code to measure ...
  ```

**Common uses of `defer`:** freeing memory, closing files, releasing mutexes,
closing database connections, and measuring elapsed time.

### Allocating and Freeing Memory

All allocation and deallocation procedures are defined in the `Basic` module.

#### `alloc` and `free`

`alloc` allocates a contiguous block of bytes on the heap and returns a
`*void` pointer to uninitialized memory. The first argument is the size in
bytes. Because `alloc` returns `*void`, a cast to the desired pointer type
is needed:

```Jai
n := cast(*int) alloc(size_of(int));   // allocate 8 bytes on the heap
defer free(n);                          // schedule deallocation
<< n = 7;                               // write a value into the allocated memory
```

A common pattern for allocating a byte buffer:

```Jai
length := 108;
buffer := cast(*u8) alloc(length);
```

`free` takes a `*void` pointer to previously allocated memory and releases it:

```Jai
free :: (memory: *void, allocator: Allocator = .{})
```

After `free`, the pointer becomes **dangling** and should no longer be used.
Optionally, assign `null` to the pointer after freeing to prevent accidental
reuse.

#### `realloc`

`realloc` resizes previously allocated memory:

```Jai
realloc :: (memory: *void, size: s64, old_size: s64, allocator: Allocator = .{}) -> *void
```

#### `New`

`New` is a convenience procedure that wraps `alloc`: it allocates memory on
the heap for a value of the given type, zero-initializes it (sets to the
default value), and returns a typed pointer:

```Jai
n := New(int);      // returns *s64, value at pointer is 0
defer free(n);
<< n = 8;
```

`New` is not a language keyword -- it is a regular procedure defined in the
`Basic` module.

### Allocators

An **Allocator** is a specialized mechanism for allocating memory for objects.
Allocators store data efficiently and often provide simpler mechanisms for
freeing memory than manual `alloc`/`free` pairs.

The default allocator is `rpmalloc`, which does not depend on the operating
system's libc `malloc`.

#### Allocator Struct

Defined in the `Preload` module:

```Jai
Allocator :: struct {
    proc: Allocator_Proc;
    data: *void;
}
```

`Allocator_Proc` is a function pointer type:

```Jai
Allocator_Proc :: #type (mode: Allocator_Mode, size: s64, old_size: s64,
    old_memory: *void, allocator_data: *void) -> *void;
```

The default allocator is `.{}`, which initializes an `Allocator` with default
values.

#### Using Allocators

Many allocation procedures accept an optional `allocator` parameter:

```Jai
alloc_string :: (count: int, allocator: Allocator = .{}) -> string
New(Node, allocator = Alloc1);
```

Dynamic arrays store their allocator in a field and use it for resizing:

```Jai
arrdyn: [..] int;
arrdyn.allocator = Alloc1;
```

Custom allocators can be written by implementing the `Allocator_Proc` signature.

#### Allocation Lifetime Categories

According to Blow, there are roughly four categories of allocation lifetimes:

1. **Extremely short lived** -- can be thrown away by end of function.
2. **Short lived + well-defined lifetime** -- memory allocated "per frame."
3. **Long lived + well-defined owner** -- uniquely owned by a subsystem.
4. **Long lived + unclear owner** -- heavily shared, unknown when it may be
   accessed or freed.

Most allocations fall in category 1. Category 4 should be rare in well-written
programs. Categories 2 and 3 are best served by arena allocators like temporary
storage or a `Pool`.

#### Querying Allocator Ownership

Each allocator supports `IS_THIS_YOURS` queries via its `Allocator_Mode`,
allowing you to determine which allocator owns a given allocation at runtime:

```Jai
yours := cast(bool) it.proc(.IS_THIS_YOURS, 0, 0, memory, it.data);
```

The `get_capabilities` procedure returns an allocator's capabilities and name.

#### Global Data

Global data lives until program exit and does not need to be freed (the OS
reclaims it). To prevent the memory debugger from counting global data as a
leak:

```Jai
this_allocation_is_not_a_leak(some_global_data);
```

### Temporary Storage

**Temporary storage** is a built-in linear (bump) allocator. An allocation is a
simple pointer increment into a block of memory. Objects cannot be freed
individually -- all temporary memory is released at once via
`reset_temporary_storage()`.

Temporary storage is defined as a struct in the `Preload` module, with support
routines in `Basic`. Its memory resides in the `Context` (see §30).

```Jai
Temporary_Storage :: struct {
    data:     *u8;
    size:     s64;
    current_page_bytes_occupied: s64;
    total_bytes_occupied: s64;
    high_water_mark: s64;
    last_set_mark_location: Source_Code_Location;

    overflow_allocator := Allocator.{__default_allocator_proc, null};
    overflow_pages: *Overflow_Page;
    original_data: *u8;
    original_size: s64;

    Overflow_Page :: struct {
        next: *Overflow_Page;
        allocator: Allocator;
        size: s64;
    }
}
```

Temporary storage is much faster than `malloc`. If enough free memory is
available, the data pointer is advanced and the result is returned. If not,
additional memory is requested from the OS. Because temporary storage is
intended for small-to-medium allocations, this happens rarely.

**Abbreviation:** `temp` is shorthand for `__temporary_allocator`. Use
`push_allocator(temp)` to set temporary storage as the current allocator
(see §30).

#### When to Reset

Call `reset_temporary_storage()` at a natural boundary in your program. For
interactive programs (games, GUI apps), this is typically once per frame:

```Jai
while true {
    input();
    simulate();
    render();

    reset_temporary_storage();
}
```

#### When Temporary Storage Is Appropriate

- **Use it** when allocations have a short lifetime (within the current frame
  or function).
- **Do not use it** when data must live beyond the current frame, or be
  accessed by a separate thread that does not re-join before the reset.
- Do not keep pointers to things in temporary storage across a reset.

#### Overflow Behavior

In a debug build, if the `high_water_mark` exceeds the temporary storage
capacity, it falls back to the normal heap allocator. In a release build,
exceeding capacity may cause a crash or memory corruption.

#### Using Temporary Storage

**Strings with `tprint`:**

`tprint` is the equivalent of `sprint` that uses temporary storage -- no
manual `free` needed:

```Jai
tprint :: (format_string: string, args: .. Any) -> string;

temp_str := tprint("Hello %!\n", name);
```

`talloc_string` is the equivalent of `alloc_string` for temporary storage:

```Jai
talloc_string :: (count: int) -> string
```

**Dynamic arrays:**

```Jai
result: [..] int;
result.allocator = temp;
```

**String builders:**

```Jai
builder: String_Builder;
builder.allocator = temp;    // no need to call free_buffers
```

**`New` and `NewArray`:**

```Jai
node  := New(Node, allocator = temp);
array := NewArray(10, int, temp);
```

**`temporary_alloc`:** The `Basic` module defines `temporary_alloc`, which is
like `alloc` but uses temporary storage.

**Stack-based temporary storage:** The `auto_release_temp` macro (in `Basic`)
sets a mark, allowing temporary allocations to be released when the stack
unwinds.

#### Inspecting Temporary Storage Usage

```Jai
context.temporary_storage.total_bytes_occupied
```

This value returns to 0 after `reset_temporary_storage()` is called.

### Memory-Leak Detector

OpenJai has a built-in memory-leak detector, activated by importing `Basic` with
the `MEMORY_DEBUGGER` program parameter:

```Jai
#import "Basic"()(MEMORY_DEBUGGER=true);
```

This hooks `alloc()`, `free()`, and `realloc()` with routines that record all
allocations and frees. Enabling it slows down the program, so it should only
be used when investigating memory issues.

#### Usage

```Jai
report := make_leak_report();
for report.sorted_summaries
    print("** Summary %: **\n%\n", it_index, <<it);

log_leak_report(report);
```

A leak report can be requested at any time during program execution. It shows
the total bytes and allocation count of unfreed memory, along with stack traces
to the allocation sites.

The Visual Memory Debugger tool in the `Basic` module can communicate collected
allocation information to an external visualization client.

### Summary of Allocation and Freeing Methods

| Method | Counterpart | Description |
|--------|-------------|-------------|
| `alloc(n)` | `free` | Allocate `n` bytes of heap memory (like C `malloc`). |
| `New(T)` | `free` | Allocate and zero-initialize memory for type `T`. |
| `NewArray(n, T)` | `array_free` / `free` | Allocate a static array. |
| `array_reserve` | `array_free` / `free` | Pre-allocate capacity for dynamic arrays. |
| `sprint` | `free` | Build a formatted string on the heap. |
| `free_buffers` | -- | Release `String_Builder` memory. |
| `to_c_string()` | `free` | Convert to a null-terminated C string. |
| `tprint` | -- | Build a formatted string in temporary storage (no free needed). |
| `talloc_string` | -- | Allocate a string in temporary storage. |
| `temporary_alloc` | -- | Allocate bytes in temporary storage. |

### Related Design Decisions

OpenJai has **none** of: garbage collection, automatic memory management, or RAII.
These are omitted deliberately in the interest of performance and simplicity
(see also §3).

---

## 16. Expressions and Literals

Literal values are constant at compile-time. Constants and variables are
combined with operators to form **expressions** (e.g., `(a + b) * 3`).
An expression assigned to a variable forms a **statement**
(e.g., `x = (a + b) * 3;`). Each statement ends with a semicolon `;`.

### Operators

#### Assignment

- `=` is the assignment operator (statement-level only; compound assignment
  like `a = b = 1` is not allowed).

#### Comparison Operators

| Operator | Description |
|----------|-------------|
| `==`     | Equal to |
| `!=`     | Not equal to |
| `<`      | Less than |
| `<=`     | Less than or equal to |
| `>`      | Greater than |
| `>=`     | Greater than or equal to |

Comparison expressions produce a `bool` result. Values of different types
generally cannot be compared -- `0 == false` and `"3" == 3` both produce type
mismatch errors. Number types are the exception: `1 == 2.0` is allowed.

#### Arithmetic Operators

| Operator | Description |
|----------|-------------|
| `+`      | Addition |
| `-`      | Subtraction (also unary negation) |
| `*`      | Multiplication |
| `/`      | Division |
| `%`      | Modulo (integers only; not defined for floats) |

Compound assignment forms: `+=`, `-=`, `*=`, `/=`. For example, `a *= 5;` is
equivalent to `a = a * 5;`.

There are **no** increment (`++`) or decrement (`--`) operators.

Integer division truncates toward zero: `8 / 3` is `2`.

Addition (`+`) is only defined for numbers, not for strings.

Different integer types can be mixed in arithmetic (e.g., `s32 + u8` works),
but mixing integer and float types is an error:

```Jai
total_score *= 3.14;   // Error: Number mismatch. Type wanted: s64; type given: float32.
```

**Division by zero**: The compiler catches division by zero with constant
values at compile time. With variables, it causes a runtime crash (panic) with
a stack trace.

#### Bitwise Operators

| Operator | Description |
|----------|-------------|
| `\|`     | Bitwise OR |
| `&`      | Bitwise AND |
| `^`      | Bitwise XOR |
| `~`      | Bitwise NOT (one's complement, unary) |
| `<<`     | Shift left |
| `>>`     | Shift right |
| `<<<`    | Rotate left |
| `>>>`    | Rotate right |

Bitwise operators perform arithmetic shifts, following C's rules.

Common idioms:

```Jai
n % 2 == 0       // true if n is even
n & 1 == 0       // true if n is even (bitwise)
n & (n - 1) == 0 // true if n is a power of 2
```

#### Boolean Operators

See the `bool` type section (§11) for `!`, `&&`, `||` and short-circuit
evaluation.

#### Operator Precedence

OpenJai follows the same precedence rules as C. For example, `*`, `/`, and `%`
bind more tightly than `+` and `-`. Parentheses `()` override precedence.
Use parentheses to improve readability in complex expressions.

### Literal Formats

**Integer literals:**

- Decimal: `42`, `0`, `-3`
- Binary: prefix `0b` (e.g., `0b10` = 2)
- Hexadecimal: prefix `0x` (e.g., `0x10` = 16)
- Underscores as optional digit separators: `16_777_216`,
  `0b1010_0010_0101_1111`

**Float literals:**

- Decimal: `3.141592`
- Scientific notation: `5.98e24` (a decimal point is required before `e`, so
  write `1.0e-6` not `1e-6`)
- Hex float: prefix `0h` for IEEE-754 format

**String literals:**

- Enclosed in double quotes: `"Hello, Sailor!"`
- Full Unicode is supported in string content (Chinese, Japanese, emoji, etc.)
- Escape sequences (backslash codes):

| Escape     | Meaning |
|------------|---------|
| `\e`       | Escape character |
| `\n`       | Newline |
| `\r`       | Carriage return |
| `\t`       | Tab |
| `\"`       | Literal double quote |
| `\\`       | Literal backslash |
| `\0`       | Null byte (value 0) |
| `\%`       | Literal percent sign (in format strings) |
| `\xAB`     | Byte with hex value `AB` (any two hex digits, upper or lower case) |
| `\d123`    | Byte with decimal value `123` (max 255) |
| `\uABCD`   | 16-bit Unicode character U+ABCD, encoded as UTF-8 (e.g., `\u03C0` prints π) |
| `\UABCDEF12` | 32-bit Unicode character, encoded as UTF-8 |

**Multi-line string literals** use the `#string` directive followed by a
user-chosen delimiter token:

```Jai
multi := #string END
This
    is a
  multi-line string.
END;
```

All whitespace (tabs, newlines, spaces) is preserved. No characters may
appear between the delimiter and the string content except a newline.

**Bool literals:** `true`, `false`

**Character literals:** Use `#char` on a single-character string to get its
ASCII value as `s64` (e.g., `#char "1"` = 49).

### Built-in Operations

| Operation          | Description                                          |
|--------------------|------------------------------------------------------|
| `type_of(x)`       | Returns the type of the expression `x`. Can be used as a type (e.g., `y: type_of(x);`). |
| `size_of(T)`       | Returns the size in bytes of type `T`. Takes a type directly (e.g., `size_of(u16)`). To get the size of a variable, use `size_of(type_of(x))`. For complex type expressions, use `#type`: `size_of(#type [M][M] s8)`. |
| `type_info(T)`     | Returns a `*Type_Info` for type `T` (or the appropriate specialized struct, e.g., `*Type_Info_Struct` for structs). See §11, Type Information System. |
| `is_constant(x)`   | Returns `true` if `x` is a compile-time constant.   |

Example:

```Jai
x: int = 42;
y: type_of(x);                             // y has the same type as x (int)
memcpy(*y, *x, size_of(type_of(x)));       // copy x into y via memcpy
print("%\n", is_constant("Hello"));        // true
```

---

## 17. Control Flow: Branching

OpenJai's branching constructs allow code to execute different paths based on
boolean conditions. There is no `goto` in OpenJai. All branching constructs
define their own scope, so they can contain local variables.

Conditions after `if` (and other control-flow keywords) do **not** need to
be surrounded by parentheses, unlike C.

### The `if`-`else` Statement

```Jai
if condition {
    // executes when condition is true
}

if condition {
    // true branch
} else {
    // false branch (optional)
}
```

- The condition can be any `bool` value or boolean expression. For a `bool`
  variable `dead`, writing `if dead` is sufficient (no `if dead == true`).
- All comparison operators (`==`, `!=`, `<=`, `>=`, `<`, `>`) and boolean
  operators (`&&`, `||`, `!`) can be used in conditions.
- Only one branch executes. The `else` branch is optional.
- `else if` chains allow testing multiple conditions in sequence:

```Jai
if health >= 50 {
    print("Continue to fight!");
} else if health >= 20 {
    print("Stop the battle and regain health!");
} else {
    print("Hide and try to recover!");
}
```

#### One-Line `if` Statements

When the body contains only one statement, braces `{ }` can be omitted:

```Jai
if a == b  print("They're equal!\n");
```

The optional `then` keyword can be used for clarity:

```Jai
if dead then exit;
```

`then` is required when parsing would otherwise be ambiguous (e.g., when
the body begins with `<<`). It is recommended to use `( )` around the
condition in one-liners for readability.

#### Compiler Protection: `=` vs `==`

The classic C mistake of using `=` (assignment) instead of `==` (comparison)
in a condition is caught by the compiler:

```
if a = 5 { ... }
// Error: Operator '=' can only be used at statement level.
```

### Ternary Operator: `ifx`

The **`ifx`** keyword ("expression if") is OpenJai's ternary operator, equivalent
to `cond ? val1 : val2` in C. Unlike `if`, `ifx` **returns a value** and can
be used in expressions and assignments:

```Jai
c := ifx a > b  10  else  1000;
name := ifx thing then thing.name else get_default_name();
```

- The compiler checks that both branches return the **same type**, and that
  type must be known at compile-time.
- `then` and `else` are optional (same rules as `if`).
- Both branches can be code blocks. In a block, the **last expression** is
  the return value (a variable or a procedure call returning a value):

```Jai
name := ifx thing {
    print("True branch.\n");
    thing.name;               // last expression is the return value
} else {
    get_default_name();       // last expression is the return value
}
```

- `ifx` can be used in `return` statements:

```Jai
factorial :: (x: int) -> int {
    return ifx x <= 1 then 1 else x * factorial(x - 1);
}
```

#### Chaining `ifx` with `else ifx`

Multiple `ifx` expressions can be chained using `else ifx`, similar to
nested ternary operators in C but more readable:

```Jai
description :=
    ifx guess < game.answer then "too low"
    else ifx guess > game.answer then "too high"
    else "the answer!";
```

Each `else ifx` introduces a new condition. The final `else` provides the
default value when none of the conditions match. All branches must return
the same type.

#### `ifx` Shortcuts

When the `then` clause is omitted, `ifx` uses the condition subject's value
as the implicit true-result:

```Jai
x := 7;
y  := ifx x then x else 1;   // explicit: returns x (7) when truthy
y2 := ifx x else 1;           // shortcut: same as above, y2 is 7
y3 := ifx x > 5 else 0;       // y3 is 7 (true branch returns x)
y4 := ifx is_even(x);         // y4 is 0 (false, no else → zero default)
y5 := ifx !is_even(x);        // y5 is 7 (true → returns x)
```

### The `if`-`case` Construct (Switch)

When comparing a variable against many values, an `if`-`else if` chain can be
replaced with `if`-`case` (OpenJai's equivalent of C's `switch`-`case`):

```Jai
if var == {
    case valA;
        // ...
    case valB;
        // ...
    case;          // default case (no value)
        // ...
}
```

- A case branch begins with `case value;` and contains one or more statements
  (no `{ }` required around the branch body, though `{ }` can be used for
  readability).
- The `case;` form (no value) is the **default case**, executed when no other
  value matches.
- **Only one case branch ever executes** -- there is no implicit
  fall-through, which is the opposite of C's `switch` behavior (where
  `break` is needed to prevent fall-through).
- `if`-`case` works on **integers, strings, enums, bools, arrays, and
  floats** (but be very careful with floats due to floating-point
  approximation).

#### `#through` Directive

The `#through` directive forces **fall-through** to the next case branch,
causing that branch to execute as well:

```Jai
if a == {
    case 0;
        print("case 0\n");
    #through;
    case 1;
        print("case 1\n");    // also executes when a is 0
    case;
        print("default\n");   // does NOT execute when a is 0 (no #through above)
}
```

This is the **opposite** of C: in C, fall-through is the default and `break`
prevents it; in OpenJai, no fall-through is the default and `#through` enables it.

#### `#complete` Directive

When using `if`-`case` with an **enum** value, the `#complete` directive
requires all enum members to be covered. The compiler emits an error if any
case is missing:

```Jai
Val :: enum { A; B; C; }
a := Val.A;
if #complete a == {
    case Val.A;  print("A\n");
    case Val.B;  print("B\n");
    case Val.C;  print("C\n");
}
```

If a case is omitted:

```
Error: This 'if' was marked #complete...
... but the following enum value was missing:
```

Using `using` on the enum shortens case labels:

```Jai
using Val;
if e == {
    case A; print("A\n");
    case B; print("B\n");
    case C; print("C\n");
}
```

### Truthiness in `if` Tests

The **truthiness** of a value (see §11) determines which branch of an `if`
executes:

- A value is **truthy** (takes the `if` branch) when it contains a real
  value: a non-zero number, a non-empty string, a non-null pointer.
- A value is **falsy** (takes the `else` branch) when it is zero, `false`,
  empty (`""`), or `null`.

This enables concise tests for empty/zero/null:

```Jai
if var  { /* var is not zero/null/empty */ }
if !var { /* var is zero/null/empty */ }

if !count  exit;           // stop if count is 0
if !ptr    return;         // return if ptr is null
if str     print("str is not empty\n");
```

These idioms work for numbers (`0` is false), strings (`""` is false),
pointers (`null` is false), and bools (`false` is false).

### Common `if` Idioms

```Jai
if n % 2 == 0  // true if n is even (modulo)
if (n & 1) == 0  // true if n is even (bitwise)
if n & 1       // true if n is odd
```

---

## 18. Control Flow: Loops

OpenJai provides two loop constructs: `while` (condition-based) and `for`
(range/iterator-based). Both support `break`, `continue`, named loops, and
`defer`.

### `while` Loop

The `while` loop executes its body repeatedly as long as a condition is true.
The condition is checked at the beginning of each iteration.

```Jai
while condition {
    // body
}
```

- Parentheses around the condition are not required.
- Braces can be omitted for a single-statement body:

```Jai
while n < 10  n += 1;
```

#### Truthiness in `while` Conditions

Like `if` (see §17), the condition can be any value with truthiness: the loop
continues as long as the value is non-zero, non-empty, or non-null.

```Jai
n := 5;
while n {          // loops while n != 0
    n -= 1;
}

str := "OpenJai";
while str {        // loops while str is not empty
    str = "";      // stops the loop
}

ptr: *int;
while !ptr {       // loops while ptr is null
    // ...
}
```

#### Named `while` Loops

A `while` condition can be given a name by using a declaration-like syntax.
The name can be used with `break` or `continue` to target a specific loop
in nested contexts:

```Jai
while counting := count > 0 {
    if count == 5  break counting;
    count -= 1;
}
```

#### Infinite Loops

`while true { }` creates an infinite loop. `while 1 { }` is equivalent
because `1` casts to `true`. Use `break` to exit.

#### `defer` in Loops

A `defer` at the start of a `while` loop ensures the deferred statement
executes at the end of every iteration, even when `break` or `continue` is
used. This is the recommended way to update loop counters:

```Jai
x := 0;
while x < 10 {
    defer x += 1;          // executes at end of each iteration
    if x & 1  continue;    // skip odd values
    print("% - ", x);      // => 0 - 2 - 4 - 6 - 8 -
}
```

### `for` Loop

The `for` loop iterates over a **range** of successive integers or over an
**array** (static, dynamic, or view). See §27 for array-specific iteration
details.

```Jai
for start..end {
    // body -- use `it` as the implicit iteration variable
}
```

A **range** like `1..100` means all successive integers from `start` to `end`
**inclusive** (equivalent to [1, 100] in mathematical notation). For an
exclusive upper bound, use `end - 1`. The `start` and `end` values can be
variables, expressions, or even procedure calls.

#### Implicit Iteration Variable (`it`)

When no loop variable is named, OpenJai provides the implicit variable `it`:

```Jai
for 1..5  print("% ", it);    // => 1 2 3 4 5
```

#### Named Loop Variable

A named loop variable replaces `it`. When named, `it` is no longer defined:

```Jai
for number: 1..5  print("% ", number);
```

This is the same naming mechanism as in named `while` conditions.

#### One-Line and Block Forms

Braces can be omitted for a single-statement body:

```Jai
for 1..5  print("% ", it);          // one-line
for n: 1..count {                    // block form
    print("% ", n);
}
```

#### Reversed `for` Loop

The `<` modifier reverses the iteration direction. The range is still written
as `max..min`:

```Jai
for < i: 5..0 {
    print("% ", i);    // => 5 4 3 2 1 0
}
```

A reversed `for` where the first value is less than the second does not
execute at all.

A boolean variable can dynamically control the direction:

```Jai
for <= bool_var arr  print("%\n", it);
```

When `bool_var` is `false`, the loop iterates in normal (forward) order.

#### Index Type

The default type of the loop variable is `s64`. The index can be cast to a
smaller integer type by casting the range endpoint:

```Jai
for i: 0..cast(u8)255 {
    // i is u8
}
```

Cast bounds are checked.

#### Nested `for` Loops

`for` loops can be nested. Each loop has its own iteration variable:

```Jai
for i: 1..5 {
    for j: 10..15 {
        print("%, % / ", i, j);
    }
}
```

#### Restrictions

- A `for` loop directly over a **string** does not work. Instead, loop by
  index (`for i: 0..str.count-1 { ... str[i] ... }`) or cast the string to a
  byte array (`for cast([] u8) str { ... it ... }`).

### `break` and `continue`

#### `break`

`break` exits the innermost enclosing loop immediately. Execution continues
with the statement after the loop:

```Jai
for i: 0..5 {
    if i == 3  break;
    print("%, ", i);
}
// => 0, 1, 2,
```

**Named break**: `break name` exits the loop where `name` is the iteration
variable (for `for` loops) or the condition variable (for named `while`
loops). This is used to break out of an outer loop from within a nested loop:

```Jai
for i: 0..5 {
    for j: 0..5 {
        if i == 3  break i;    // breaks the outer loop
    }
}

while cond := x < 6 {
    if x == 3  break cond;     // breaks this while loop
}
```

A common pattern is using named break in a game event loop:

```Jai
while eventloop := true {
    for event: Input.events_this_frame {
        if event.type == .QUIT then
            break eventloop;
    }
}
```

#### `continue`

`continue` skips the rest of the current iteration and starts the next
iteration of the innermost enclosing loop:

```Jai
for i: 0..5 {
    if i == 3  continue;
    print("%, ", i);
}
// => 0, 1, 2, 4, 5,
```

**Named continue**: `continue name` continues the next iteration of the
named loop, skipping any inner loops:

```Jai
for i: 0..5 {
    for j: 0..5 {
        if i == 3  continue i;    // skips the inner loop for i == 3
    }
}

while cond := x < 6 {
    defer x += 1;
    if x == 3  continue cond;
}
```

For both `break` and `continue`, the iteration variable (in `for`) or
condition variable (in named `while`) serves as the loop label.

### Looping over Enum Values

The `enum_values_as_s64` procedure (see §26) can be used in a `for` loop to
iterate over all values of an enum:

```Jai
Direction :: enum { EAST; NORTH; WEST; SOUTH; }

for enum_values_as_s64(Direction) {
    print("%: %\n", it, cast(Direction) it);
}
// =>
//   0: EAST
//   1: NORTH
//   2: WEST
//   3: SOUTH
```

### Looping over Struct Members

Using `type_info()` and runtime reflection, a `for` loop can iterate over a
struct's member fields (see §24, Runtime Reflection).

---

## 19. Directives

OpenJai uses `#`-prefixed directives for compiler instructions. Known directives:

| Directive              | Description                                           |
|------------------------|-------------------------------------------------------|
| `#import`              | Import a module (e.g., `#import "Basic";`). See §20 for variants and named imports. |
| `#load`                | Loads the contents of a source file into the current file, like C's `#include`. See §20. |
| `#module_parameters`   | Declares module and/or program parameters for a module. See §20. |
| `#system_library`      | Declares a named constant for an OS-level shared library (e.g., `libc :: #system_library "libc";`). See §6. |
| `#library`             | Declares a named constant for a user-provided dynamic library (`.dll`/`.so`), e.g., `lz4 :: #library "liblz4";`. The path can be relative to the source file. The variant `#library,no_static_library` declares a dynamic-only library (no `.lib` import library required). See §6, §37. |
| `#foreign`             | Declares that a procedure is implemented in an external (C) library. Placed after the return type: `-> bool #foreign kernel32;`. The argument is a library constant declared via `#system_library` or `#library`. An optional second string argument specifies the C symbol name when it differs from the OpenJai name. See §6. |
| `#run`                 | Execute code at compile time (see below).             |
| `#asm`                 | Inline assembly block. See §36.                       |
| `#bytes`               | Inserts individual bytes into the program as raw machine code. Could be used to write a custom assembler. See §36. |
| `#char`                | Applied to a single-character string literal; yields the ASCII numeric value as `s64` (e.g., `#char "1"` = 49). |
| `#intrinsic`           | Marks a function as a compiler intrinsic (a low-level operation implemented directly by the compiler, closely mimicking a corresponding C function). |
| `#program_export`      | Exports a procedure as a symbol visible to the OS/linker. Optionally takes a string argument to specify the exported symbol name (e.g., `#program_export "main"`). Used to export functions from dynamic libraries (`.dll`/`.so`). See §6, §37. |
| `#elsewhere`           | Declares that a procedure's implementation is located in a separately compiled library (typically a dynamic library). Combined with a library constant: `dll_func :: () #no_context #elsewhere dynlib;`. See §37. |
| `#c_call`              | Specifies that a procedure uses the C calling convention. The implicit context is not passed to `#c_call` procedures. Used on procedures that must be callable from C or the OS (e.g., the program entry point, callbacks for C libraries). Native OpenJai procedures cannot be called from a `#c_call` procedure without `push_context`. See §6, §30. |
| `#no_context`          | Marks a procedure as not using the implicit context. Used on low-level procedures (e.g., `write_string`, `debug_break` in `Preload`) that must not depend on context availability. See §30. |
| `#add_context`         | Adds a user-defined field to the implicit `Context` struct. The field is accessed via `context.field_name`, not as a bare identifier. See §30. |
| `#runtime_support`     | Marks a procedure declaration as provided by the `Runtime_Support` module, linking a local declaration to the runtime-provided implementation. |
| `#scope_file`          | All declarations that follow are private to the current file (file scope). Not visible via `#import` or `#load`. |
| `#scope_export`        | Restores application (global/exported) scope for declarations that follow. Reverses `#scope_file`. |
| `#scope_module`        | All declarations that follow are private to the current module. Not visible to code that imports the module. |
| `#as`                  | Used on a struct field to enable implicit casting from the struct to the field's type. Combined with `using`, enables subtype-to-supertype casting (see §24). |
| `#align`               | Aligns a struct member field (or global/stack variable) relative to the start of the struct. Takes an alignment value in bytes (e.g., `#align 64`). Used for SIMD and cache-aligned data structures (see §24). |
| `#no_padding`          | Applied to a struct to suppress automatic padding bytes that the compiler would otherwise insert for word-size alignment (see §24). |
| `#place`               | Used inside a struct to overlay a field at the same memory location as a previously declared field, creating a union-like layout (see §25). |
| `#specified`           | Applied to an enum to require all member values to be explicitly declared (no auto-increment). Ensures enum values remain stable over time and are safe to serialize as integers (see §26). |
| `#through`             | Used inside an `if-case` branch to cause fall-through to the next case (see §17). By default, only one case branch executes; `#through` overrides this. Opposite of C's `switch` behavior. |
| `#complete`            | Used with `if-case` on enum values to require exhaustive matching of all enum members (see §17). The compiler emits an error if any enum case is missing. |
| `#type_info_none`      | Applied to a struct to suppress all runtime type information for that type, reducing executable size (see §11, Runtime Type Information Control). |
| `#type_info_procedures_are_void_pointers` | Applied to a struct so that procedure fields do not retain their type info at runtime (see §11, Runtime Type Information Control). |
| `#must`                | Applied after a procedure's return type to require that the return value(s) be captured at the call site. Ignoring a `#must` return value is a compile error (see §10). |
| `#this`                | Refers to the current procedure, struct type, or data scope as a compile-time constant. Can be used for recursive calls or recursive struct definitions (see §10). |
| `#procedure_name`      | Returns the statically-known name of the enclosing procedure as a compile-time string (see §10). |
| `#deprecated`          | Marks a procedure as deprecated. Calling it produces a compiler warning. Accepts an optional string message (see §10). |
| `#string`              | Defines a multi-line string literal. Followed by a user-chosen delimiter token; everything between the delimiter and its next occurrence becomes the string content, preserving all whitespace. See §16 and §29. |
| `#no_abc`              | Disables **array bounds checking** for the procedure it is applied to: `proc :: () #no_abc { }`. Improves performance in production builds at the cost of safety. See also the `array_bounds_check` build option (§27). |
| `#assert`              | Compile-time assertion. Takes a condition and an optional message string. If the condition is `false`, compilation stops with an error. See §29. |
| `#dump`                | Placed before a procedure body to display the generated byte code for that procedure at compile time. Used for low-level debugging. See §29. |
| `#symmetric`           | Applied to a binary operator overload to indicate that the operator is commutative: `operator * :: (a: Vector3, k: float) -> Vector3 #symmetric;` makes both `v * 3.0` and `3.0 * v` resolve to the same overload (see §10). |
| `#poke_name`           | Injects a name from the current scope into an imported module, making it visible to that module's existing code. Commonly used to supply additional operator or procedure overloads to a library module: `#poke_name Math dot_product;` (see §10). |
| `#compile_time`        | A directive that evaluates to `true` during compile-time execution and `false` at run-time. Used inside procedures to branch on whether code is running under `#run` or at normal run-time. Cannot be used as a constant. See §31. |
| `#no_reset`            | Applied to a global variable to retain its compile-time value at run-time. Without `#no_reset`, globals modified during `#run` are reset to their default (zero) values before the program starts. See §31. |
| `#if`                  | Conditional compilation directive. Evaluates a compile-time constant condition; if `true`, the following block is compiled into the executable; if `false`, the block is not compiled at all. Used for platform-specific code, debug/release builds, and conditional struct fields or enum values. See §31. |
| `#ifx`                 | One-line conditional compilation expression. Returns one of two values based on a compile-time constant condition: `name := #ifx OS == .WINDOWS then "win"; else "other";`. See §31. |
| `#insert`              | Inserts a compile-time string or `Code` value as source code at the insertion point. The inserted code is checked for validity during compilation. Can be combined with `#run` to insert dynamically generated code. See §31. |
| `#code`                | Constructs a value of type `Code` from a code block or expression: `#code { x += 7 }` or `#code (a < b)`. `Code` values can be inspected, manipulated as AST structures, and inserted with `#insert`. See §31. |
| `#file`                | The complete path (including filename) of the current source file. See §37. |
| `#line`                | The line number where this directive appears. See §37. |
| `#filepath`            | The path to the current file, without the filename. Can be a remote filepath. See §37. |
| `#location`            | Given a `Code` value, extracts the full path and line number: `#location(code)`. See §37. |
| `#caller_location`     | Used as a default parameter value; provides the source location (line number, file) from where a procedure is called. See §37. |
| `#placeholder`         | Tells the compiler that a symbol will be defined by the compile-time meta-program. The symbol can then be provided via `add_build_string`. See §37. |
| `#compiler`            | Marks a procedure as interfacing with the compiler as a library; it works with compiler internals. See §37. |

### `#run` Directive

`#run` tells the compiler to execute the specified procedure, expression, or
code block **during compile-time**. `#run` produces a constant as its result.

```Jai
#run main();          // run entire program at compile time
result := #run f();   // run f() at compile time, assign result to variable
PI :: #run compute_pi();  // compute a constant at compile time
```

This runs the specified code at compile time, before linking. Output from
`print` calls inside `#run` appears in the compiler output before the
"Running linker" line. The compiled executable still runs `main()` again at
run-time as normal.

`#run` can appear at the top level of a source file, in any order relative to
other declarations. It can also appear inside procedures.

**How it works:** Code targeted by `#run` is first converted to byte-code,
which is then executed in the compiler's built-in interpreter. The interpreter
can also dynamically load DLLs and look up symbols in them. Compile-time
execution is therefore somewhat slower than native run-time execution.

**Capabilities and uses:**

- Test conditions before compiling: `#run assert(condition)` will abort
  compilation if the condition is false.
- Insert build-time data (sometimes called "baking data into the binary"):
  `srgb_table: [] float = #run generate_linear_srgb();`
- Run test cases at compile time.
- Perform code style checks or automated code review.
- Dynamically generate code and insert it to be compiled (the core of
  meta-programming; see `#insert` in §31).
- Contact build servers and retrieve/send build data.
- Download specifications and generate header files.

**Limitations:**

- FFI (Foreign Function Interface, §29) cannot be used during `#run`.
- `#run` can access and modify global variables, but by default globals are
  reset to their initial (zero) values before the executable runs. Use
  `#no_reset` to retain compile-time values at run-time (see §31).
- `#run` can return basic struct values and multidimensional arrays. Pointers
  inside structs may cause complications because pointer values are not
  retained between compile-time and run-time.

**Polymorphic procedures and `#run`:** When a polymorphic procedure contains
a `#run` directive, the `#run` executes once per unique type instantiation,
not once per call. For example, if `comprun(x: $T)` contains `#run print(T)`,
calling it three times with `u8` arguments triggers the `#run` only once for
`T == u8`.

A constant declaration cannot use a non-`#run` procedure call:

```Jai
PI :: compute_pi();       // Error: not constant
PI :: #run compute_pi();  // OK: computed at compile time
```

### Shebang (`#!`) on Linux

On Linux, a OpenJai source file can be made directly executable using the shebang
mechanism:

```
#! /path/to/OpenJai/bin/OpenJai
```

This line must be the first line of the file. After `chmod u+x`, the file can
be run directly (e.g., `./program.OpenJai`), which invokes compilation and
compile-time execution via `#run`.

---

## 20. Modules

OpenJai's standard library is distributed as **modules** in the `modules/`
directory of the compiler distribution. Modules are imported with `#import`.

Imported modules are always built from source, in full, every time you compile
your program.

### Identifier Resolution Order

When the compiler encounters an identifier (type, variable, or procedure), it
searches in this order:

1. The current source file.
2. Imported modules (via `#import`).
3. Loaded files (via `#load`).

### Module Structure

A module can take one of two forms:

1. **Single file**: A single `.OpenJai` file in the modules directory (e.g.,
   `modules/Random.OpenJai`), imported as `#import "Random";`.

2. **Directory**: A subfolder containing a `module.OpenJai` file and optionally
   additional source files (e.g., `modules/Basic/module.OpenJai`). The
   `module.OpenJai` file typically assembles the module's source files using
   `#load` and imports other modules the current module depends on.

When a module is imported, the compiler searches the module search path
(the **import path**):

1. First for a file named `ModuleName.OpenJai`.
2. If not found, for a subfolder `ModuleName/` containing `module.OpenJai`.

If neither is found:

```
Error: Unable to find a module called 'ModuleName' in any of the module
search directories.
Info: ... Searched path 'c:/OpenJai/modules/'.
```

Module names are most often capitalized, but there are exceptions.

Modules are installed globally on a machine by default, so all OpenJai applications
use the same modules collection. A planned system will allow modules to be
copied locally into an application for build stability.

### `#load` Directive

The `#load` directive copies the contents of a source file into the current
file, analogous to C's `#include`. All code from loaded files is compiled as
part of the current compilation unit:

```Jai
#load "part1.OpenJai";
#load "subfolder/part2.OpenJai";
#load "part3.OpenJai";
```

The path is relative to the calling file. Loading is hierarchical: a loaded
file can itself contain `#load` directives.

`#load` is used to structure a project by splitting code into separate files
grouped by functionality. A `module.OpenJai` typically uses `#load` to assemble
the module's component files:

```Jai
// Basic/module.OpenJai
#load "Array.OpenJai";
#load "Simple_String.OpenJai";
#load "String_Builder.OpenJai";
#load "Print.OpenJai";
#load "Int128.OpenJai";
#load "Apollo_Time.OpenJai";
#load "string_to_float.OpenJai";
#load "float_to_string.OpenJai";
```

**Key difference between `#load` and `#import`**: Code from a `#load`-ed file
has access to the global scope of the file that loaded it. Code from an
`#import`-ed module does **not** have access to the importing file's global
scope.

### Named Imports

An import can be given a name, creating a namespace:

```Jai
Math :: #import "Math";
y := Math.sqrt(2.0);
```

The name is a compile-time constant (bound with `::`) and does not have to
match the module name:

```Jai
Long :: #import "Long_Name_Library";
```

To make all symbols from a named import available without qualification, use
`using`:

```Jai
Math :: #import "Math";
using Math;
y := sqrt(2.0);    // no prefix needed
```

#### Handling Naming Conflicts

When two modules export the same name, named imports prevent conflicts:

```Jai
Lib1 :: #import "Lib1";
Lib2 :: #import "Lib2";

a := Lib1.proc1();   // proc1 from Lib1
b := Lib2.proc1();   // proc1 from Lib2
```

Alternatively, only one module needs a named import:

```Jai
#import "Lib1";
Lib2 :: #import "Lib2";

a := proc1();         // proc1 from Lib1 (unqualified)
b := Lib2.proc1();    // proc1 from Lib2
```

The `using,except` syntax can selectively exclude names:

```Jai
Lib1 :: #import "Lib1";
using,except(proc1) Lib1;   // import everything from Lib1 except proc1
```

### Import Variants

Beyond the standard `#import "ModuleName"`, three specialized forms exist:

**`#import, file`** -- import a specific file from a module:

```Jai
module :: #import, file "module1/module.OpenJai";
```

**`#import, dir`** -- import a directory as a module:

```Jai
raylib :: #import, dir "../raylib/raylib";
```

This is equivalent to using `-import_dir "../raylib/raylib"` on the command
line.

**`#import, string`** -- import a string as source code:

```Jai
#import, string "factorial :: (x: int) -> int { if x <= 1 return 1; return x * factorial(x-1); }";
```

The imported string is written to `.added_strings_w2.OpenJai` in the `.build/`
folder.

### Module Search Paths (`-import_dir`)

By default, modules are searched in `OpenJai/modules/`. Additional search paths
are added with `-import_dir`:

```
OpenJai program.OpenJai -import_dir "./"                     # current directory
OpenJai program.OpenJai -import_dir "/path/to/mod1"          # absolute path
OpenJai program.OpenJai -import_dir arg1, arg2, arg3         # multiple paths
```

Custom modules can be placed in a separate directory (rather than in
`OpenJai/modules/`, which may be overwritten on compiler updates) and made known
to the compiler with `-import_dir`.

For importing modules into the metaprogram (rather than the target program),
use `-- import_dir path`.

### Module and Program Parameters

Modules can declare parameters that importing code can set. Parameters are
declared with `#module_parameters` at the top of a module:

```Jai
#module_parameters(VERBOSE := false);
```

There are two kinds of parameters, declared in two separate parenthesized
lists:

```Jai
#module_parameters (module_params) (program_params);
```

1. **Module parameters** (first list): Only active within the imported module's
   scope.
2. **Program parameters** (second list): Active throughout the entire program.

If no explicit value is provided at import time, the default from the module
definition is used.

#### Example: Basic Module Parameters

The `Basic` module declares:

```Jai
#module_parameters ()
    (MEMORY_DEBUGGER := false,
     ENABLE_ASSERT := true,
     REPLACEMENT_INTERFACE: $I/interface Memory_Debugger_Interface = Memory_Debugger_Interface,
     VISUALIZE_MEMORY_DEBUGGER := true);
```

The first list (module parameters) is empty. The second list contains program
parameters including `ENABLE_ASSERT`, which defaults to `true`.

To disable assertions:

```Jai
#import "Basic"()(ENABLE_ASSERT=false);
```

#### Creating Custom Module Parameters

A custom module with parameters:

```Jai
// TestModule_Params/module.OpenJai
#import "Basic";
#module_parameters(VERBOSE := false);

#run {
    if VERBOSE {
        print("The module is in VERBOSE mode\n");
    } else {
        print("The module is in NON_VERBOSE mode\n");
    }
}
```

Importing with a parameter override:

```Jai
#import "TestModule_Params" (VERBOSE=true);
```

### Known Modules

### Preload Module

The **Preload** module is the most fundamental module in OpenJai. It is
**implicitly loaded** whenever the compiler starts -- it does not need to be
imported with `#import`. It contains the minimal definitions the compiler needs
in order to compile user source code.

Preload defines:

- Enums for `Operating_System`.
- `Type_Info` definitions (run-time type information).
- `Allocator`, `Logger`, `Stack trace`, `Context`, `Temporary Storage`,
  `Source Code location`.
- `Array_View` and `Resizable_Array`.
- **Intrinsic functions** -- very low-level functions marked with `#intrinsic`
  that closely mimic corresponding C functions:

```Jai
memcpy :: (dest: *void, source: *void, count: s64)        #intrinsic;
memcmp :: (a: *void, b: *void, count: s64) -> s16          #intrinsic;
memset :: (dest: *void, value: u8, count: s64)             #intrinsic;
```

| Intrinsic | Description                                                          |
|-----------|----------------------------------------------------------------------|
| `memcpy`  | Copies `count` bytes from `source` to `dest`.                       |
| `memcmp`  | Compares the first `count` bytes of `a` and `b`. Returns < 0 if `a` < `b`, > 0 if `a` > `b`, 0 if equal. |
| `memset`  | Sets `count` bytes of `dest` to `value`.                            |

Because Preload is implicitly available, these intrinsics can be called from
any OpenJai code without an `#import`.

### Known Modules

| Module                | Description                                       |
|-----------------------|---------------------------------------------------|
| `Preload`             | Implicitly loaded. Minimal compiler-required definitions (types, intrinsics, allocator, context, etc.). See above. |
| `Basic`               | Fundamental utilities (`print`, `assert`, `exit`, `get_command_line_arguments`, etc.), Apollo Time, time functions, and `String_Builder`. On Linux, imports `POSIX`. |
| `POSIX`               | POSIX/libc bindings (e.g., `dlfcn.h` wrappers). Contains `libc_bindings.OpenJai`. Provides `read`, `STDIN_FILENO`, and other standard POSIX functions. |
| `Windows`             | Windows API bindings. Provides types like `HANDLE` and functions like `GetStdHandle`. Constants include `STD_INPUT_HANDLE`, `STD_OUTPUT_HANDLE`, etc. |
| `Check`               | Augmented error checking (e.g., validates `print()` calls). Imported by default; disable with `-no_check`. |
| `Runtime_Support`     | Defines the true program entry point (`__system_entry_point`), runtime initialization (`__OpenJai_runtime_init`/`__OpenJai_runtime_fini`), and the bridge to the user's `main` (`__program_main`). Handles command-line argument storage, context initialization, and temporary storage setup. |
| `Default_Metaprogram` | The default build driver used when no custom metaprogram is specified. Also contains the help text for `OpenJai` command-line options and translates options into `Build_Options`. |
| `Math`                | Mathematical constants and functions (see below). |
| `Random`              | Random number generation (see below). |
| `PCG`                 | Advanced random number generation using the PCG algorithm. Same API as `Random`. |
| `Simp`                | High-level 2D graphics framework with OpenGL backend (requires `libgl-dev` on Linux). Provides `immediate_triangle`, `immediate_quad`, font loading (`Dynamic_Font`, `get_font_at_size`), texture loading (`Texture`, `texture_load_from_file`), and render target management. See §40. |
| `GL`                  | OpenGL bindings. Provides OpenGL function pointers loaded via `gl_load`. Used with SDL or GLFW for context creation. |
| `SDL`                 | SDL2 (Simple DirectMedia Layer) bindings. Cross-platform access to audio, keyboard, mouse, joystick, and graphics hardware via OpenGL/Direct3D. |
| `glfw`                | GLFW bindings for OpenGL/Vulkan window and context creation. Removed from the distribution after v0.1.027; available in earlier versions. |
| `d3d_compiler`        | Direct3D shader compiler bindings (Windows). |
| `d3d11`               | Direct3D 11 bindings (Windows). |
| `d3d12`               | Direct3D 12 bindings (Windows). Contains a minimal example. |
| `GetRect`             | Simple UI module that works with Simp. Provides buttons, dropdowns, text fields, sliders, checkboxes, and other GUI widgets. See §40. |
| `Window_Creation`     | Platform-independent window creation. Provides `create_window`, `get_window_resizes`, `get_render_dimensions`, `get_mouse_pointer_position`. See §40. |
| `Input`               | Platform-independent input handling for keyboard and mouse. Provides `update_window_events`, `events_this_frame`, and event types (`.QUIT`, `.KEYBOARD`). See §40. |
| `Sound_Player`        | Audio playback. Provides `Sound_Player`, `Mixer_Sound_Data`, `Sound_Stream`, and `make_stream`. Supports WAV and OGG formats (OGG via `Wav_File` module). See §40. |
| `Wav_File`            | WAV file parsing. Provides `get_wav_header` for reading WAV format headers. Used with `Sound_Player`. |
| `Windows_Resources`   | Windows-specific utilities: `disable_runtime_console` (suppress console window for GUI apps) and `set_icon_by_data` (attach icons to executables). |
| `Ico_File`            | ICO file creation. Provides `create_ico_file_from_bitmap_filename` to generate icon data from PNG images. Used with `Windows_Resources`. |
| `String`              | String utility procedures: comparisons, searching, splitting, joining, trimming, replacing. Also provides path utilities (`path_strip_filename`, `is_absolute_path`, etc.). |
| `Command_Line`        | Sophisticated command-line option processing (beyond `get_command_line_arguments` in `Basic`). |
| `Compiler`            | Provides compile-time utilities including `is_subclass_of`, `compiler_set_type_info_flags`, and other compiler interaction procedures. |
| `Sort`                | Sorting algorithms: `quick_sort` and `bubble_sort`. Both take a comparison procedure as a second argument. |
| `Intro_Sort`          | Sorting using the insertion sort algorithm. |
| `Hash_Table`          | Hash table (associative array) data structure. Provides `Table(K, V)`, `table_add`, `table_find`, `table_remove`. Iterable with `for`. |
| `Pool`                | Arena-style memory allocator (default block size 64 KB). Provides `pool_allocator_proc`, `get`, `release`, `reset`, `set_allocators`. Useful for allocations with well-defined lifetimes that are freed together. |
| `Flat_Pool`           | Simpler arena allocator with potentially better performance. Provides `flat_pool_allocator_proc`, `get`, `reset`, `fini`. |
| `Mail`                | SMTP e-mail sending (plain-text or HTML) with optional CC, BCC, and attachments. Uses `Curl` under the hood. |
| `Curl`                | libcurl bindings. Supports HTTP downloads, FTP, and is used by the `Mail` module. |
| `rpmalloc`            | The rpmalloc allocator (v1.4.4). Used as OpenJai's default allocator. Provides `rpmalloc_allocator_proc`. Requires explicit init via `.STARTUP` mode. |
| `File`                | File I/O operations: `file_open`, `file_close`, `file_read`, `file_write`, `file_length`, `file_set_position`, `read_entire_file`, `write_entire_file`, `file_exists`, `file_delete`, `file_move`, `make_directory_if_it_does_not_exist`, `delete_directory`. Has Windows and Unix variants. |
| `File_Utilities`      | Higher-level file utilities: `visit_files`, `copy_file`, path manipulation, and the `File_Visit_Info` struct for directory traversal. |
| `File_Async`          | Asynchronous file operations. |
| `File_Watcher`        | File system watching/notification. |
| `Process`             | OS process management: `run_command`, `create_process`, `write_to_process`, `read_from_process`. See §39. |
| `Thread`              | OS-level threading: `Thread` struct, thread groups, `Mutex`, `Semaphore`. See §38. |
| `System`              | System-level utilities including `get_path_of_running_executable`. |

### Random Module

The `Random` module provides random number generation:

```Jai
random_seed :: (new_seed: u32)
random_get :: () -> u64
random_get_zero_to_one :: () -> float
random_get_within_range :: (min: float, max: float) -> float
```

| Procedure | Description |
|-----------|-------------|
| `random_seed` | Sets the global random seed. |
| `random_get` | Returns a random `u64` (0 to 18,446,744,073,709,551,615). |
| `random_get_zero_to_one` | Returns a random `float` in [0.0, 1.0]. |
| `random_get_within_range` | Returns a random `float` in [min, max]. |

Without seeding, `random_get` and related procedures produce the same
sequence of numbers on every run. To get non-repeating sequences, seed with
a time value:

```Jai
random_seed(current_time_monotonic().low);
```

`random_seed` stores the value in `context.random_state`, where it is
automatically used by the other `random_` procedures. The `PCG` module
provides the same procedures with a more sophisticated algorithm.

### Math Module

The `Math` module provides mathematical operations with an emphasis on game
programming (e.g., matrix multiplication). It contains:

- **Constants**: `PI`, `TAU`, `FLOAT64_MIN`, `FLOAT64_MAX`, `FLOAT64_INFINITY`,
  `FLOAT64_NAN`, and min/max range constants for numeric types (`FLOAT32_MIN`,
  `FLOAT32_MAX`, `S16_MIN`, `S16_MAX`, etc.).
- **Functions**: `abs`, `log2`, and other common math functions.
- **Constructor helpers**: `make_vector2(x, y)`, `make_vector3(x, y, z)`,
  `make_vector4(x, y, z, w)` -- convenience procedures for creating vector
  values (alternative to struct literal syntax like `Vector2.{x, y}`).
- **Types**: `Vector2`, `Vector3`, `Vector4`, `Quaternion`, `Matrix2`,
  `Matrix3`, `Matrix4`, `Plane` (all structs).
- **Color utilities**.

### Sort Module

The `Sort` module provides implementations of bubble sort and quicksort. Both
procedures sort arrays in-place and require a comparison procedure as the
second argument.

```Jai
#import "Sort";
#import "String";  // for compare_strings

arrf := float.[8, 108, 42, 5, 3.14, 17, -5, -272];
quick_sort(arrf, compare_floats);
// arrf is now [-272, -5, 3.14, 5, 8, 17, 42, 108]

arrs := string.["the", "quick", "brown", "fox"];
bubble_sort(arrs, compare_strings);
// arrs is now ["brown", "fox", "quick", "the"]
```

| Procedure | Description |
|-----------|-------------|
| `quick_sort(array, compare_proc)` | Quicksort. Generally preferred for performance. |
| `bubble_sort(array, compare_proc)` | Bubble sort. Simple but O(n^2). |

The comparison procedure takes two values and returns an ordering result.
Built-in comparators include `compare_floats` (from `Sort`) and
`compare_strings` / `compare` (from `String`).

The `Intro_Sort` module provides an alternative using the insertion sort
algorithm.

### Hash_Table Module

The `Hash_Table` module provides an associative array (hash map) data
structure that maps keys to values.

#### Creating and Populating

```Jai
#import "Hash_Table";

table := New(Table(string, string));
table_add(table, "John Smith", "521-8976");
table_add(table, "Lisa Smith", "521-1234");
```

#### Lookup

`table_find` returns two values: the found value and a `bool` indicating
success.

```Jai
value, success := table_find(table, "Lisa Smith");
if success  print("Found: %\n", value);  // "521-1234"
```

#### Removal

```Jai
table_remove(table, "Lisa Smith");
```

#### Iteration

Hash tables are iterable with `for`. Inside the loop, `it` is the value and
`it_index` is the key:

```Jai
for table {
    key, value := it_index, it;
    print("% -> %\n", key, value);
}
```

Iteration order is **not** insertion order.

### Pool Module

The `Pool` module provides an arena-style memory allocator for quickly
allocating many blocks of varying sizes when all blocks share approximately the
same lifetime. Memory is allocated from the pool as needed and freed all at
once via `release`. The default block size is 64 KB (`pool.memblock_size`).

#### Basic Usage

```Jai
#import "Pool";

pool: Pool;
memory := get(*pool, 64);  // allocate 64 bytes from the pool
// ... use memory ...
release(*pool);             // free all pool memory back to OS
```

#### Using a Pool as the Context Allocator

A pool can be installed as the context allocator so that all allocations in a
scope use it:

```Jai
pool: Pool;
set_allocators(*pool);

new_context := context;
new_context.allocator.proc = pool_allocator_proc;
new_context.allocator.data = *pool;
push_context new_context {
    // all allocations in here use the pool
    memory := alloc(256);
}
release(*pool);
```

#### Using a Pool with `New`

Pass the pool allocator as the second argument to `New`:

```Jai
palloc: Allocator;
palloc.proc = pool_allocator_proc;
palloc.data = *pool;

person := New(Person, allocator = palloc);
```

#### Using a Pool in a Macro

```Jai
use_pool :: (code: Code) #expand {
    pool: Pool;
    set_allocators(*pool);
    push_allocator(pool_allocator_proc, *pool);
    #insert code;
    release(*pool);
}

main :: () {
    x: string;
    use_pool(#code {
        x = "some allocated data";
    });
}
```

#### Pool Operations

| Procedure / Field | Description |
|-------------------|-------------|
| `get(*pool, size)` | Allocate `size` bytes from the pool. |
| `release(*pool)` | Free all pool memory back to the OS. Internally calls `reset` first. |
| `reset(*pool)` | Mark all pool memory as available for reuse without returning it to the OS. Future allocations are fast. If `pool.overwrite_memory` is set, clears memory to a stamp value. |
| `set_allocators(*pool)` | Initialize the pool to use `context.allocator` for its own backing allocations. |
| `pool.memblock_size` | Size of each backing memory block (default 65536 / 64 KB). |
| `pool.bytes_left` | Free space remaining in the current block. Starts at 0 before first allocation (the first `get` or `alloc` triggers a block allocation). |
| `pool.overwrite_memory` | When set, `reset` will clear memory to a stamp value. |
| `pool_allocator_proc` | The allocator procedure to assign to `context.allocator.proc`. |

### Flat_Pool Module

The `Flat_Pool` module is a simpler alternative to `Pool` with potentially
better performance characteristics.

```Jai
#import "Flat_Pool";

pool: Flat_Pool;
memory := cast(*u8) get(*pool, 100);  // allocate 100 bytes

fpalloc: Allocator;
fpalloc.proc = flat_pool_allocator_proc;
fpalloc.data = *pool;
thing := New(Thing, allocator = fpalloc);

reset(*pool, overwrite_memory=true);   // mark memory reusable, overwrite contents
fini(*pool);                           // release memory to OS
```

| Procedure | Description |
|-----------|-------------|
| `get(*pool, size)` | Allocate `size` bytes. |
| `reset(*pool, overwrite_memory=)` | Mark memory as reusable. With `overwrite_memory=true`, overwrites contents (reads from freed memory return garbage). |
| `fini(*pool)` | Release all memory to the OS. Not strictly needed at program exit. |
| `flat_pool_allocator_proc` | The allocator procedure for use with `context.allocator.proc`. |

### Mail Module

The `Mail` module provides SMTP e-mail sending with support for plain-text or
HTML messages, CC, BCC, and attachments. It uses the `Curl` module internally.

```Jai
Mail :: #import "Mail";

smtp: Mail.Mail_Server;
smtp.host       = "smtp.example.com";
smtp.port       = "587";
smtp.enable_ssl = true;
smtp.username   = USERNAME;
smtp.password   = PASSWORD;

m: Mail.Mail_Message;
m.from    = "sender@example.com";
m.to      = addresses;     // [..] string
m.subject = "Subject line";
m.body    = "Message body";
m.html    = false;          // true for HTML messages

result := Mail.mail_send(smtp, m);
```

On Windows, `libcurl.dll` and `libcurl.lib` must be in the same directory as
the executable (or the platform equivalent on other OSes).

### Apollo Time (Basic Module)

OpenJai uses **Apollo Time** as its basis for working with time. Defined in the
`Basic` module, Apollo Time is a cross-platform time implementation with both
high precision and very long range. It is a 128-bit integer representing the
number of **femtoseconds** (10^15 per second) since the Apollo 11 Moon Landing.

```Jai
Apollo_Time :: struct {
    low:  u64;
    high: s64;
}
```

The common arithmetic operators (`+`, `-`, etc.) are **operator overloaded**
for `Apollo_Time` and implemented in inline assembly for speed.

#### Getting the Current Time

```Jai
now := current_time_consensus();           // for calendar dates
calendar_utc := to_calendar(now, .UTC);    // convert to calendar struct
calendar_local := to_calendar(now, .LOCAL);
s := calendar_to_string(calendar_utc);     // "15 January 2026, 15:58:24"
```

The calendar struct contains the fields: `year`, `month_starting_at_0`,
`day_of_month_starting_at_0`, `day_of_week_starting_at_0`, `hour`, `minute`,
`second`, `millisecond`, and `time_zone`.

#### Measuring Durations

**Simple approach** using `seconds_since_init`:

```Jai
start_time := seconds_since_init();
sleep_milliseconds(100);
elapsed := seconds_since_init() - start_time;   // float64 seconds
```

**High-precision approach** using monotonic Apollo Time:

```Jai
start := current_time_monotonic();
sleep_milliseconds(100);
end := current_time_monotonic();
duration := end - start;                         // Apollo_Time
ms := to_float64_seconds(duration) * 1000;       // convert to milliseconds
```

Use `current_time_consensus` for calendar dates. Use
`current_time_monotonic` for measuring durations and simulations — a monotonic
clock never jumps forward or backward due to NTP or Daylight Savings Time
updates.

### Command-Line Arguments (Basic Module)

`get_command_line_arguments` (from `Basic`) retrieves the arguments passed to
the program on the command line. It returns a `[]string` (array of strings).

```Jai
#import "Basic";

main :: () {
    args := get_command_line_arguments();
    defer array_reset(*args);

    print("Number of command line arguments: %\n", args.count);
    for args {
        print("Position: % - Value: %\n", it_index, it);
    }
}
```

- **Index 0** is the executable name (e.g., `"myprogram.exe"`).
- **Index 1 onwards** are the actual user-supplied arguments.
- The returned array should be cleaned up with `defer array_reset(*args)`.
- Individual arguments are accessed as `args[1]`, `args[2]`, etc.

Example invocation and output:

```
$ ./myprogram 42 "hello" 3.14
Number of command line arguments: 4
Position: 0 - Value: ./myprogram
Position: 1 - Value: 42
Position: 2 - Value: hello
Position: 3 - Value: 3.14
```

All arguments arrive as strings. Use `string_to_int`, `string_to_float`, etc.
(from `String`) to convert them to numeric types.

For more sophisticated option parsing (flags, named parameters, etc.), use the
`Command_Line` module.

---

## 21. Files and Compilation

### Source Files

- OpenJai source files conventionally use the `.OpenJai` extension, but the compiler
  does not enforce this.
- Source file naming convention: lowercase, words separated by `_` (e.g.,
  `hello_sailor.OpenJai`, `struct_literals.OpenJai`). Spaces in filenames should be
  avoided; if unavoidable, quote the filename on the command line
  (e.g., `OpenJai "space invaders.OpenJai"`).
- Whitespace and indentation are not significant to the compiler. The
  convention is 4 spaces per indentation level.
- Multiple statements may appear on a single line, separated by `;`.

### Compilation Process

Compiling a file named `2.1_program.OpenJai` produces an executable named `2`
(or `2.exe` on Windows). The output name can be overridden with `-exe NAME`.

OpenJai follows the **single compilation unit model**: compilation and linking
produce a single executable as output.

The `OpenJai` command **only compiles** the program; it does not execute it.
Execution is a separate step (e.g., `./hello_sailor` on Linux/macOS,
`hello_sailor` on Windows).

### Build Artifacts

Compilation creates a hidden `.build/` directory containing:

- `.obj` files (object files, e.g., `hello_sailor_0_w2.obj`)
- `.lib` and `.exp` files (Windows)
- `.pdb` file (debug symbols, Windows)

### Linker

The back-end compiler produces several artifacts in the hidden `.build/`
folder (`.obj`, `.exp`, and `.lib` files on Windows). The linker combines
these object files (and sometimes OS-specific libraries) statically into one
output executable.

| Platform | Linker |
|----------|--------|
| Windows  | `link.exe` from MSVC |
| Linux    | `lld-linux` (bundled LLVM linker) |
| macOS    | `lld-macos` (bundled LLVM linker) |

The link phase with the LLVM backend on Windows can take about 3--30x longer
than the compilation phase.

### Compiler Output and Timing

On successful compilation, the compiler prints statistics:

```
Stats for Workspace 2 ("Target Program"):
Lexer lines processed: 6481 (11075 including blank lines, comments.)
Front-end time: 0.054479 seconds.
llvm      time: 0.042108 seconds.

Compiler  time: 0.096587 seconds.
Link      time: 0.328986 seconds.
Total     time: 0.425573 seconds.
```

The timing breakdown:

```
Front-end time + Backend time (x64 or llvm) = Compiler time
Compiler time + Link time = Total time
```

### Compile-Time vs Run-Time

These are two distinct phases:

1. **Compile-time** (or **build-time**): The phase when `OpenJai program.OpenJai` runs.
   Source code is analyzed, errors are reported, and (if successful) an
   executable is produced. OpenJai can also execute code during this phase via
   `#run`.
2. **Run-time**: The phase when the compiled executable runs
   (e.g., `./program`).

### Compiler Error Behavior

- The compiler stops at the **first error** it encounters and reports only
  that error. No executable is generated.
- Error messages include the file path, line number, and column number.
- After fixing an error, the next compilation may reveal additional errors.
- **Warnings** are rare. When issued, compilation continues and an executable
  is still generated.

### Run-Time Errors

At run-time, a program can crash (panic) due to abnormal conditions such as:

- Array/string bounds-check violations (index out of range).
- Division by zero.
- Cast bounds-check failures (e.g., casting a value that doesn't fit in the
  target type).
- Null pointer dereference (produces a stack trace showing the fault
  location).

---

## 22. Game Programming Target

OpenJai specifically targets game programming, where a game is defined as a program
which:

- Runs in real-time.
- Is interactive.
- Renders some sort of 3D scene.
- Is targeted at modern gaming hardware (PCs and consoles).

OpenJai is intended to be usable as a C++ replacement for AAA-scale projects.

---

## 23. Tooling and Editor Support

Editor plugins and support exist for: **vim**, **Emacs**, **Sublime Text 3**,
**Notepad++**, **Kakoune**, and **Visual Studio Code**. There is also
**Focus**, an editor written entirely in OpenJai.

### Visual Studio Code

The recommended plugin is **"The Language"** by Iain King, which provides
basic IDE functionality (syntax highlighting, etc.).

### Sublime Text 3

The **OpenJaiTools** package provides syntax highlighting, autocompletion,
goto-symbol, and a build system.

### Language Servers (LSP)

Multiple LSP implementations exist for OpenJai, compatible with Vim, Emacs,
VSCode, and other LSP-capable editors:

- `Pyromuffin/OpenJai-lsp`
- `Sl3dge78/OpenJai_lsp`
- `SogoCZE/OpenJails` (OpenJai LSP by Patrik Smělý)

---

## 24. Structs

A **struct** is a composite data type that groups multiple **fields** (member
variables) of potentially different types into a single entity. Structs are
OpenJai's primary mechanism for defining custom data types and are used internally
to define composite types like arrays and strings.

### Declaration

A struct is declared with `::` and the `struct` keyword:

```Jai
Person :: struct {
    name     : string;
    age      : int;
    location : Vector2;
}
```

- Struct names conventionally start with a capital letter. Use `_` to
  separate multiple parts (e.g., `Ice_Cream_Info`).
- The `struct` keyword is mandatory.
- Fields are declared as `field_name: type;`.
- When multiple fields share the same type, a shorthand is available:
  `x, y, z: float;`.
- All struct fields are **public** -- they can be read and modified from
  anywhere. There is no built-in mechanism for private fields. By convention,
  fields intended to be private are prefixed with `_`, but the compiler does
  not enforce this.
- A struct field can be of type `void` (takes up no space).
- A struct definition must occur in a **data scope** (see §13). A struct can
  also be declared in a local (imperative) scope.
- Declaring a struct does not allocate memory -- it defines a template. An
  **instance** is created by declaring a variable of the struct type.
- A struct **cannot** be cast to a `bool`.

### Field Initialization

When a struct variable is declared without explicit initialization, all fields
receive their **default zero values** (0 for numbers, `false` for bool, `""`
for string, `null` for pointers):

```Jai
v : Vector2;       // v.x == 0, v.y == 0
```

**Custom default values** can be specified in the struct definition:

```Jai
Vector2d :: struct {
    x : float = 1;
    y : float = 4;
}
```

If a field has a default value, its type can be inferred using `:=` notation
in the struct definition.

**Explicit non-initialization** (`---`) skips zero-initialization for
performance. The field may contain any leftover memory value (undefined
behavior to read before writing):

```Jai
Vector2un :: struct {
    x: float = ---;
    y: float = ---;
}
```

Default and uninitialized fields can be mixed within the same struct.

### Accessing Fields

Fields are accessed with **dot notation**: `v.x`, `bob.name`. Fields can be
read and written this way:

```Jai
bob.name = "Robert";      // assignment (no := needed; type already declared)
bob.location.x = 64.14;   // nested field access
```

The `.` operator **dereferences by default**, unlike C/C++ (no separate `->`
operator is needed for pointers to structs).

### Struct Literals

A struct variable can be initialized in a single expression using a **struct
literal**:

```Jai
vec2 := Vector2.{2.0, 6.28};
bob2 := Person.{"Robert", 42, Vector2.{64.139999, -21.92}};
```

The `TypeName.` prefix tells the compiler which struct type is being
constructed. When the type is already known from context, the prefix can be
omitted:

```Jai
vec3 : Vector2;
vec3 = .{2.0, 6.28};
```

Fields can be **named** in a struct literal, allowing reordering and omission
of fields with default values:

```Jai
vec4 := Vector2.{y = 6.28, x = 2.0};
```

**All values in a struct literal must be compile-time constants** -- variables
cannot be used.

To reset a struct to its default values: `john_doe := Person.{};`

### Printing Structs

`print` knows how to print structs, including nested structs. The output
format is `{field1, field2, ...}`:

```Jai
print("%\n", bob);   // => {"Robert", 42, {64.139999, -21.92}}
```

The `formatStruct` procedure (from `Basic`) provides additional control over
struct printing (see §10, Formatting Procedures).

### Nested Structs

A struct field can itself be a struct type, creating a **nested struct**:

```Jai
Person :: struct {
    name     : string;
    age      : int;
    location : Vector2;   // nested struct
}
```

Access nested fields by chaining dot notation: `bob.location.x`. Also see the
`using` keyword below for shortening nested access.

Structs can be defined inline within other structs:

```Jai
Broadcaster :: struct {
    subscriptions: [..]Subscription;

    Subscription :: struct {
        subscriber: *void;
        callback: (*void, *Event) -> ();
    }
}
```

### Structs on the Heap

Struct variables declared normally are allocated on the **stack**. To allocate
on the heap, use `New`:

```Jai
bob := New(Person);            // returns *Person
defer free(bob);
bob.name = "Robert";
bob.age = 42;
print("%\n", << bob);          // dereference to print values
```

The variable is now a **pointer** (`*Person`). Printing the variable directly
shows an address; dereference with `<<` to access the values.

Struct literals can be assigned to heap-allocated structs with dereference:

```Jai
<< ps = .{"Jim", 67};
```

Heap memory must be explicitly freed with `free`. The stack is limited in
size; use the heap when many struct instances are needed. For faster memory
management, prefer stack allocation where possible.

`Dynamic_New(T)` is like `New` but can be used when the type is not known at
compile time.

### Recursive Structs

A **recursive struct** has one or more fields of its own type. These fields
**must be pointers** -- a non-pointer self-reference creates a circular
dependency error:

```Jai
// Error: The program contains circular dependencies.
Node :: struct {
    owned_a: Node;     // NOT allowed
    value: int = 0;
}

// Correct: use pointers
Node :: struct {
    owned_a: *Node;    // OK
    value: int = 0;
}
```

Common recursive data structures:

**Linked list:**

```Jai
LinkedList :: struct {
    data: s64;
    next: *LinkedList;
}
```

**Double linked list:**

```Jai
LinkedList :: struct {
    first: *Node;
    last:  *Node;
}

Node :: struct {
    value: s64;
    prev:  *Node;
    next:  *Node;
}
```

**Tree:**

```Jai
Tree :: struct {
    data:  int;
    left:  *Tree;
    right: *Tree;
}
```

### Pointer to Struct

A pointer to a struct is created with the address-of operator:

```Jai
bob := Person.{"Robert", 42, Vector2.{64.139999, -21.92}};
rob := *bob;       // rob is *Person
```

The pointer declaration can be split:

```Jai
ptr: *Entity;      // declaration
ptr = *e;          // assignment
```

### The `using` Keyword with Structs

The `using` keyword imports a struct's namespace, allowing its fields to be
accessed without the full dot-notation path.

**In a struct definition** -- enables direct access to a contained struct's
fields:

```Jai
Person :: struct {
    name: string;
}

Patient :: struct {
    using pe: Person;     // import Person's namespace
    disease: string;
}

pat1 : Patient;
pat1.name = "Johnson";   // instead of pat1.pe.name
```

The identifier after `using` (e.g., `pe`) is not a keyword -- it can be any
name (e.g., `using person: Person`).

**In imperative scope** -- enables access to a variable's fields without the
variable name:

```Jai
using pat1;
print("%\n", name);      // instead of pat1.name
```

A variable can also be declared with `using`:

```Jai
using pat1: Patient;     // fields of pat1 available without prefix
```

`using` mimics **composition-based inheritance**: `Patient` behaves like a
subtype of `Person`, with direct access to the parent's fields. OpenJai uses
**composition instead of inheritance** -- there are no classes, no method
dispatch, no overriding.

A struct can have **multiple `using` fields**, composing several types into one:

```Jai
Rectangle :: struct { centerPosition: Vector2; size: Vector2; }
InputScheme :: struct { upButton: raylib.KeyboardKey; downButton: raylib.KeyboardKey; }

Pad :: struct {
    using rectangle: Rectangle;
    using input:     InputScheme;
    score:           int;
    velocity:        Vector2;
}

pad: Pad;
pad.centerPosition = ...;  // from Rectangle (via using)
pad.upButton = ...;        // from InputScheme (via using)
pad.score = 42;            // direct field
```

> **Favor composition over inheritance.**

**Handling name collisions** -- In large programs, `using` can cause
field-name collisions. Modifiers control which names are imported:

```Jai
using,except(length) position: Vector3_With_Length;    // exclude specific fields
using,only(w, y) orientation: Quaternion;              // include only specific fields
using,map(proc) field: SomeStruct;                     // remap duplicate names
```

### The `#as` Directive

`#as` extends `using` to enable **implicit casting** from a struct subtype to
a supertype.

Without `#as`, assigning a subtype to a supertype variable is a type mismatch
error:

```Jai
Patient :: struct {
    using as: Person;      // using without #as
    disease: string;
}

p1: Person;
p1 = pat1;                 // Error: Type mismatch: incompatible structs
```

With `#as`, the implicit cast is allowed:

```Jai
Employee :: struct {
    using #as p: Person;   // using WITH #as
    profession: string;
}

p1: Person;
p1 = emp1;                 // OK: implicit cast, retains only Person fields
```

The syntax `using #as p: Person;` can also be written as
`#as using p: Person;`.

`#as` can also be used **without `using`** on a struct field, enabling the
struct to implicitly cast to that field's type:

```Jai
Number :: struct {
    #as i: int;
    f: float = 3.14;
}

function :: (i: int) { print("i is %\n", i); }
num := Number.{42, 3.1415};
function(num);              // implicitly casts Number to int => prints "i is 42"
```

More than one field can be prefixed with `#as`.

**Entity system pattern** -- `#as` is commonly used to build game entity
hierarchies with a `type: Type` field as a runtime discriminator:

```Jai
Document :: struct {
    type:     Type;
    filename: string;
}

Video_File :: struct {
    using #as base: Document;
    duration:          float;
    width, height:     int;
    frames_per_second: u16;
}

Audio_File :: struct {
    using #as base: Document;
    duration:      float;
    sampling_rate: u32;
}
```

**Setting inherited field defaults** -- A child struct can set default values
for fields inherited through `using #as` by referencing them with the base
field name (e.g., `base.field = value`). This acts as a struct-level
initializer for the parent's fields:

```Jai
Executable_File :: struct {
    using #as base: Document;
    base.type = Executable_File;   // default value for inherited field
    is_a_rootkit := false;
}

exe: Executable_File;
// exe.type is already Executable_File without explicit assignment
```

**Implicit casting in procedure arguments** -- Because of `#as`, a subtype
can be passed where the base type is expected, both by value and by pointer:

```Jai
report :: (d: Document) {
    print("type %, filename '%'\n", d.type, d.filename);
}

v: Video_File;
v.type     = Video_File;
v.filename = "clip.mp4";
report(v);               // Video_File implicitly casts to Document (by value)

heap_vid: *Video_File = New(Video_File);
report(<< heap_vid);     // dereference pointer, then implicit cast by value
```

When passing by value, only the base struct's fields are retained (the
subtype-specific fields are sliced away). When passing by pointer, the full
subtype data remains accessible through casting.

**Runtime type dispatch and downcasting** -- A procedure that accepts a
pointer to the base type can inspect the `type` field and downcast to the
concrete subtype:

```Jai
full_report :: (doc: *Document) {
    if doc.type == {
        case Video_File;
        vid := cast(*Video_File) doc;
        print("video '%', %x% resolution\n",
              vid.filename, vid.width, vid.height);
        case Audio_File;
        aud := cast(*Audio_File) doc;
        print("audio '%', sampled at % Hz\n",
              aud.filename, aud.sampling_rate);
        case;
        print("Error: unknown document type!\n");
    }
}
```

This is a manual discriminated-union pattern -- the programmer maintains the
type tag and performs explicit casts. There is no compiler-enforced
exhaustiveness or automatic dispatch.

**Polymorphic factory procedures** -- A polymorphic procedure (see §10) can
serve as a factory for any type in a struct hierarchy, as long as the type
has the required fields:

```Jai
make_document :: ($T: Type, name: string) -> T {
    doc: T;
    doc.type     = T;
    doc.filename = name;
    return doc;
}

vid := make_document(Video_File, "clip.mp4");    // returns Video_File
aud := make_document(Audio_File, "song.wav");    // returns Audio_File
```

A heap-allocating variant uses `alloc(size_of(T))` instead of stack
allocation:

```Jai
heap_document :: ($T: Type, name: string) -> *T {
    doc: *T = alloc(size_of(T));
    doc.type     = T;
    doc.filename = name;
    return doc;
}

heap_vid := heap_document(Video_File, "clip.mp4");
defer free(heap_vid);
```

The `$T: Type` parameter is resolved at compile time; a separate specialized
procedure is compiled for each concrete type used. These factories work
because `using #as` ensures every subtype has the `type` and `filename`
fields from `Document`.

**Heterogeneous collections** -- Pointers to different subtypes can be stored
in a single array of base-type pointers, then dispatched at runtime:

```Jai
entities: [..] *Entity;
p := New(Player);
p.type = Player;
array_add(*entities, p);   // Player implicitly casts to *Entity
```

### Storage Management with `using`

The `using` keyword enables a hot/cold splitting pattern for
cache-sensitive data structures:

```Jai
Entity_Hot :: struct {
    // most-used fields, stored on stack
}

Entity_Cold :: struct {
    // less-used fields, stored on heap
}

Entity :: struct {
    using hot:  *Entity_Hot;
    using cold: *Entity_Cold;
}
```

Fields can be switched between hot and cold (e.g., per target platform)
without changing code that accesses them.

### Struct Alignment

The `#align` directive aligns struct member fields relative to the start of
the struct. If the start is correctly aligned and a member field has
`#align 64`, that field will also be 64-byte aligned. Valid values include
`#align 16`, `#align 32`, and `#align 64`. It also works for global variables
and stack declarations:

```Jai
Accumulator :: struct {
    accumulation: [2][256] s16 #align 64;
    computedAccumulation: s32;
} #no_padding

Object :: struct { member: int #align 64; }
global_var: [100] int #align 64;

big : [16] u8 #align 64;     // stack declaration with alignment
```

The `#no_padding` directive suppresses automatic padding bytes that the
compiler would otherwise insert for word-size alignment.

`#align` is used for SIMD operations and cache-sensitive data structures.
The start of the struct must be aligned correctly for field alignment to work.

### Making Inner Module Definitions Visible

When a module imports another module, the inner module's definitions are
in `#scope_module` and not visible to code importing the outer module. To
make them visible, use `using` with the import:

```Jai
using TestInside :: #import "TestInside";
```

Without the `using`, code importing the outer module gets
`Error: Undeclared identifier`.

### Struct Parameters

Structs can take **parameters**, including default values, to customize
their fields:

```Jai
A_Struct :: struct (param := "Hello") {
    x := OUTER_VALUE;    // can reference outer constants
    y := param;
}

a: A_Struct;                        // uses default param = "Hello"
b: A_Struct(param = "Sailor!");     // overrides param
print("%\n", a.param);              // parameters accessible as members
```

**Type parameters** enable polymorphic structs:

```Jai
Entity :: struct (Payload: Type) {
    payload: Payload;
}

thing: Entity(struct { name := "Volodimir"; typos := false; });
```

Passing `Type` as a struct parameter is an early form of polymorphism.

### Polymorphic Structs

A struct can declare **polymorphic parameters** using `$` prefixes (or typed
parameters) to make its fields generic over types and values:

```Jai
Vec :: struct ($T: Type, $N: s64) {
    values: [N] T;
}

Vec3 :: Vec(float, 3);       // T = float, N = 3
BigVec :: Vec(int, 1024);    // T = int, N = 1024

v1 := Vec3.{.[1,2,3]};
```

Polymorphic parameters must be **compile-time constants**. They can have
default values:

```Jai
TwoD :: struct (M: int = 3, N: int = 3) {
    array: [M][N] int;
}
```

#### Accessing Polymorphic Parameters

Polymorphic parameters are accessible as fields on instances of the struct:

```Jai
ps: PolyStruct(int);
print("ps type = %\n", ps.T);           // => ps type = s64
print("%\n", type_of(ps));              // => PolyStruct(T=s64)
```

#### Type Comparisons with Polymorphic Structs

When comparing types that involve polymorphic structs, the **complete type**
(struct type + concrete generic parameters) must be specified:

```Jai
assert(type_of(ps) == PolyStruct(int));  // OK
assert(ps.T == int);                      // OK
// assert(type_of(ps) == PolyStruct);     // Assertion failed!
```

The unparameterized `PolyStruct` is not the same type as `PolyStruct(int)`.

#### Generic Data Structures

Polymorphic structs are the standard way to define generic data structures:

```Jai
LinkedList :: struct (T: Type) {
    first: *Node(T);
    last:  *Node(T);
}

Node :: struct (T: Type) {
    value: T;
    prev:  *Node(T);
    next:  *Node(T);
}
```

Instantiation specifies the concrete type:

```Jai
lst := New(LinkedList(s64));
lst := New(LinkedList(string));
```

#### Partial Application with `#bake_arguments`

`#bake_arguments` can partially apply polymorphic struct parameters,
leaving the rest to be filled in at declaration time:

```Jai
TwoD :: struct (M: int, N: int) {
    array: [M][N] int;
}

TwoDb :: #bake_arguments TwoD(M = 5);

twod: TwoDb(N = 2);
print("its dimensions are (%, %)\n", twod.M, twod.N);
// => its dimensions are (5, 2)
```

#### Implementing Interfaces with Polymorphic Structs

Polymorphic structs combined with `using #as` and `#this` can implement
a trait/interface pattern:

```Jai
SomeTrait :: struct (
    type: Type,
    get: (a: type, int) -> int,
    set: (a: *type, int, int) -> ()
) {}

ExSomeTrait :: struct {
    using #as _t: SomeTrait(#this, ex_get, ex_set);
    data: [4] int;
}
```

The concrete struct `ExSomeTrait` implements the trait by providing its own
`ex_get` and `ex_set` functions via `using #as`. Trait functions can be
called through the struct instance (`f.get(f, 1)`) or through standalone
wrappers (`get(f, 1)`). Procedures accepting `*$X/SomeTrait` will accept
any struct that implements the trait.

### Anonymous Structs

An **anonymous struct** has no name (not bound with `::`):

```Jai
state: struct {
    a, b: int;
};
```

`state` is not a true struct type -- it is a variable whose type is an inline
anonymous struct. Useful for grouping data that only has one copy.

Anonymous structs can be used inside unions to create overlapping field names
(see also §25 for full union documentation):

```Jai
Vector3 :: struct {
    union {
        struct { x, y, z: float; }
        struct { r, g, b: float; }
        struct { s, t   : float; }
    }
}
```

### Member Procedures

Unlike classes in C++/Java, structs in OpenJai **do not have member functions**.
There is no concept of functions "belonging" to a struct. Functions can be
declared inside structs, but they only use the struct as a **namespace**:

```Jai
Obj :: struct {
    x: int;
    set_x :: (obj: *Obj, x: int) {
        obj.x = x;
    }
}

o: Obj;
// o.set_x(100);          // Error: Not enough arguments
Obj.set_x(*o, 100);       // namespace-qualified call
set_x(*o, 42);            // also works (struct namespace is in scope)
```

The struct instance must be passed **explicitly** as a parameter. Method
syntax (`o.set_x(100)`) is **not** supported. Declaring functions inside
structs is not recommended.

### Runtime Reflection with `type_info`

`type_info()` applied to a struct type returns a `Type_Info_Struct` value
that provides full runtime reflection capabilities:

```Jai
pinfo := type_info(Person);        // type is Type_Info_Struct
print("%\n", pinfo.name);          // => Person
```

#### Iterating Over Struct Members

The `.members` field is iterable with a `for` loop (see §18). Each member
provides:

| Field              | Description                                     |
|--------------------|-------------------------------------------------|
| `.name`            | The field name as a string.                     |
| `.type`            | Pointer to the field's `Type_Info`.             |
| `.offset_in_bytes` | The byte offset of the field within the struct. |
| `.notes`           | Array of annotation strings (see Annotations).  |
| `.flags`           | Field flags.                                    |

```Jai
for type_info(Person).members {
    print("% - % - offset %\n",
        it.name,
        type_to_string(it.type),
        it.offset_in_bytes);
}
// => name - string - 0
// => age - s64 - 16
// => location - Vector2 - 24
```

The `type_to_string` procedure converts a `*Type_Info` to a human-readable
type name string.

The `<< it.type` expression dereferences the type pointer to access the full
`Type_Info` struct, which includes `.type` (a `Type_Info_Tag` enum such as
`STRING`, `INTEGER`, `STRUCT`) and `.runtime_size`.

#### Looking Up a Specific Field

`get_field` retrieves information about a named field:

```Jai
member, offset := get_field(type_info(Person), "age");
print("% at offset %\n", << member, offset);
```

Runtime reflection is built into the language with full support for all types:
primitives, enums, structs, procedures, and more. It enables powerful
capabilities such as serialization and deserialization of structs.

#### Comparing Field Names Across Structs

Because `Type_Info_Struct.members` is a regular array, struct metadata can be
compared programmatically at runtime. For example, finding field names that two
unrelated structs have in common:

```Jai
Person :: struct {
    name:         string;
    address:      string;
    phone_number: [9] u8;
    year_born:    int;
    month_born:   int;
    day_born:     int;
}

Business :: struct {
    name:           string;
    annual_revenue: s64;
    stock_symbol:   string;
    phone_number:   [9] u8;
    address:        string;
    number_of_employees: int;
}

conflicting_names :: (a: *Type_Info_Struct, b: *Type_Info_Struct) -> [] string {
    results: [..] string;
    for ma: a.members {
        for mb: b.members {
            if ma.name == mb.name {
                array_add(*results, ma.name);
                continue ma;
            }
        }
    }
    return results;
}

conflicting := conflicting_names(type_info(Person), type_info(Business));
// => ["name", "address", "phone_number"]
```

The procedure accepts `*Type_Info_Struct` parameters (obtained via
`type_info()`), iterates each struct's `.members` array, and compares the
`.name` field of each member. The labeled `continue ma` (see §18, Named
continue) skips to the next member of the outer loop once a match is found,
avoiding duplicate entries.

### Copying Structs with `memcpy`

A struct can be copied byte-for-byte using `memcpy` (see §20, Preload
intrinsics). Use `size_of` on the struct type to determine how many bytes to
copy. A static byte array can serve as an intermediary buffer:

```Jai
Rectangle :: struct {
    x0: float;
    y0: float;
    x1: float;
    y1: float;
    color_name: string;
}

r := Rectangle.{10, 5, 50, 55, "chartreuse"};
t: Rectangle;

S :: size_of(Rectangle);
temporary: [S] u8;                  // byte buffer sized to the struct
memcpy(temporary.data, *r, S);      // struct → byte array
memcpy(*t, temporary.data, S);      // byte array → struct
// t is now {10, 5, 50, 55, "chartreuse"}
```

`temporary.data` yields a pointer to the array's underlying storage (see §27),
and `*r` / `*t` yield pointers to the struct instances. `size_of(Rectangle)`
is a compile-time constant, so it can be used to declare the array size.

### Annotations (Notes)

OpenJai supports declarative annotations (called **notes**) written with `@Name`
after a declaration. Notes can be attached to:

- **Structs**: `Person :: struct @Version9 { ... }`
- **Struct fields**: `location : Vector2;  @NoSerialize`
- **Procedures**: `generate_code :: () { ... } @RunWhenReady`

Notes are stored as strings in the `notes` array of the corresponding
`Type_Info_Struct` or `Type_Info_Struct_Member`. They are available at both
compile-time and run-time. Unlike Java or C# annotations, notes are not
structured -- they are simple string tags.

Multiple notes can be attached to a single declaration. A struct itself and
its individual fields can each carry their own notes:

```Jai
Person :: struct @Version9 {
    name     : string;
    age      : int;
    location : Vector2;  @NoSerialize
}

print("%\n", type_info(Person).notes);   // => ["Version9"]

for type_info(Person).members {
    print("% notes: %\n", it.name, it.notes);
}
// name notes: []
// age notes: []
// location notes: ["NoSerialize"]
```

Annotations are inspectable via runtime reflection and can be acted upon by
metaprograms at compile-time (e.g., to skip serialization for fields marked
`@NoSerialize`).

Notes are also used on enums (see §26, Enum Notes).

Common conventions in code comments and declarations:
`@TestProcedure`, `@test`, `@Incomplete`, `@Refactor`, `@Cleanup`,
`@Simplify`, `@Temporary`, `@pure`. User-defined notes are unlimited.

---

## 25. Unions

A **union** is a special memory-saving kind of struct. It is defined like a
struct, but using the `union` keyword instead of `struct`. A union's fields
share the same memory location -- only one field can be active (filled with
data) at any one time. The union's size equals the size of its largest field.

### Declaration

```Jai
T :: union {
    a: u16 = 0;
    b: float64 = 5.0;
    c: Type;
}
```

- Fields are declared the same way as in a struct.
- A union field can be of type `void`.
- The `using` keyword works with unions the same way it works with structs
  and enums (see §24).

### Behavior

When a value is assigned to one field, the values of all other fields become
undefined. Only the most recently assigned field contains valid data:

```Jai
t: T;
t.a = 100;
print("%\n", t.a);        // => 100
t.b = 3.0;
print("%\n", t.b);        // => 3.0
print("%\n", t.a);        // => gibberish (b has been assigned, a is invalid)
print("size: %\n", size_of(T));   // => 8 (size of the largest field, float64)
```

### Equivalent Struct Form with `#place`

A union can be equivalently written as a struct using the `#place` directive.
`#place field` tells the compiler to overlay the next field at the same memory
location as `field`:

```Jai
Ts :: struct {
    a: u16;
    #place a;
    b: float64;
    #place a;
    c: Type;
}
```

A `void` field can be used as the anchor for `#place`:

```Jai
Object :: struct {
    member: void;
    #place member;
    x: float;
    #place member;
    y: float;
    #place member;
    z: float;
}
```

### Anonymous Unions

An **anonymous union** has no type name (not bound with `::`):

```Jai
variable := union {
    x: int;
    y: int;
    z: int;
}
```

`variable` is not a true union type -- it is a variable whose type is an
inline anonymous union. Useful for grouping data that only has one copy.

Anonymous unions and anonymous structs can be nested to create overlapping
field names (see also §24, Anonymous Structs):

```Jai
Vector3 :: struct {
    union {
        struct { x, y, z: float; }
        struct { r, g, b: float; }
        struct { s, t   : float; }
    }
}
```

---

## 26. Enums

An **enum** (enumerator) is a type that defines a fixed set of named
constants. It is useful when a property can only take one of a limited number
of named values. Internally, each member is backed by an integer.

Both enums and unions are types. The `using` keyword to open up a namespace
(see §24) works for enums and unions as well as structs.

### Declaration

An enum is declared with `::` and the `enum` keyword:

```Jai
Compass_Direction :: enum {
    NORTH;      // 0
    SOUTH;      // 1
    EAST;       // 2
    WEST;       // 3
}
```

- Member names are conventionally `UPPER_SNAKE_CASE`.
- By default, members are backed by `s64` integers.
- Values start at 0 for the first member and auto-increment by 1.
- Enums are defined in a data scope (see §13).
- The OpenJai standard library makes heavy use of enums (e.g.,
  `Operating_System_Tag`, `Log_Level`, `Type_Info_Tag` in the `Preload`
  module).

### Backing Type

The default backing type is `s64`. A shorter integer type can be specified
after the `enum` keyword:

```Jai
Key_Code :: enum u32 {
    UNKNOWN;
    ARROW_LEFT;
    ARROW_RIGHT;
    ARROW_UP;
    ARROW_DOWN;
    SHIFT;
    ESCAPE;
}
```

### Accessing Values

Enum values are accessed with dot notation. When the enum type is known from
context, the short form `.MEMBER` can be used:

```Jai
dir1: Compass_Direction = .EAST;
dir1 = .SOUTH;
print("%\n", Compass_Direction.EAST);   // => EAST
```

Using a member that does not exist produces an error:

```
dir: Compass_Direction = .SOUTH_WEST;
// Error: 'SOUTH_WEST' is not a member of Compass_Direction.
```

A bare `.MEMBER` without a known type context produces an error:

```Jai
dir2 := .WEST;
// Error: This declaration is bound to a unary '.' dereference
// that was never resolved, so there is no way to know its type.
```

### Custom Integer Values

Members can be assigned custom integer values. Subsequent members
auto-increment from the last specified value:

```Jai
Log_Mode2 :: enum {
    NONE;            // 0
    MINIMAL;         // 1
    EVERYDAY :: 300; // 300
    VERBOSE;         // 301
}
```

Members can reference other constants (including outer-scope constants) and
other enum members:

```Jai
MIDDLE_VALUE :: 8;

Log_Mode3 :: enum {
    NONE;                      // 0
    MINIMAL :: NONE;           // 0 (same value as NONE)
    EVERYDAY :: MIDDLE_VALUE;  // 8
    VERBOSE;                   // 9
}
```

Each member can be given its own explicit value:

```Jai
Values :: enum {
    ONE :: 1;
    TWO :: 2;
    FIVE :: 5;
}
```

Enum variables can also be assigned raw integer values:

```Jai
log1 := Log_Mode3.MINIMAL;
log1 = 10;    // assigns the integer 10 directly
```

### Enum as a Namespace

Just like with structs, `using` can open an enum's namespace so members can
be used without the dot prefix:

```Jai
using Compass_Direction;
print("%\n", NORTH);          // instead of Compass_Direction.NORTH
```

Without `using`, referencing `NORTH` directly produces
`Error: Undeclared identifier 'NORTH'.`

### Anonymous Enums

An **anonymous enum** has no type name (not bound with `::`):

```Jai
state: enum {
    A;
    B;
};
```

`state` is not a true enum type (which would require `::`) -- it is a
variable whose type is an inline anonymous enum. Useful for an enum that only
has one copy.

### The `#specified` Directive

When members are added or removed from an enum, auto-incremented values shift,
which can introduce subtle bugs if code depends on specific integer values.
The `#specified` directive prevents this by requiring every member to have an
explicit integer value -- auto-increment is disabled:

```Jai
Operating_Systems :: enum u16 #specified {
    VMS             :: 1;
    ATT_UNIX        :: 2;
    WINDOWS         :: 3;
    GNU_SLASH_LINUX :: 4;
}
```

If a struct has an enum marked as `#specified`, it is safe to serialize that
enum member as an integer, or to serialize the whole struct as binary.

### `enum_flags`

A special variant of an enum where member values are successive powers of 2,
designed for bitmask/flag operations:

```Jai
Direction :: enum_flags u8 {
    EAST;   // == 1 == 0b0001
    NORTH;  // == 2 == 0b0010
    WEST;   // == 4 == 0b0100
    SOUTH;  // == 8 == 0b1000
}
```

- The backing type can be specified (e.g., `u8`), just like regular enums.
- Flags can be combined with the bitwise OR operator (`|`):

```Jai
d: Direction;
using Direction;
d = EAST | WEST;                  // multiple flags set
d = EAST | WEST | NORTH | SOUTH; // all flags set
```

- Individual flags can be masked out with bitwise AND and NOT:

```Jai
d &= ~SOUTH;    // clears the SOUTH flag, leaves others unchanged
// EAST | NORTH | WEST | SOUTH → EAST | NORTH | WEST
```

- Flags can be assigned from integer values and combined with arithmetic:

```Jai
e: Direction = .WEST | .EAST;
g: Direction = 1;                     // == EAST
h: Direction = Direction.WEST + 1;    // == EAST | WEST
```

### Enum Utility Procedures

Several built-in procedures are available for working with enums:

| Procedure              | Description                                            |
|------------------------|--------------------------------------------------------|
| `enum_range(T)`        | Returns two values (low, high) -- the integer range of enum `T`. |
| `enum_values_as_s64(T)`| Returns an array of all member values as `s64`.       |
| `enum_names(T)`        | Returns an array of all member names as strings.       |

```Jai
low, high := enum_range(Direction);
print("% to %\n", low, high);          // => 0 to 3

values := enum_values_as_s64(Direction);
print("%\n", values);                   // => [0, 1, 2, 3]

names := enum_names(Direction);
print("%\n", names);                    // => ["EAST", "NORTH", "WEST", "SOUTH"]
```

### The `.loose` Property

The `.loose` property on an enum type gives the underlying integer type:

```Jai
x: Direction;
y: Direction.loose;
log("%", type_of(x));    // => Direction
log("%", type_of(y));    // => s64
```

### Enum Notes

Enum declarations can carry **notes** (annotations), the same way structs can.
Notes are written as `@Name` directly on the enum declaration:

```Jai
An_Enum :: enum_flags @Hi @There {
    x :: 1;
}
```

---

## 27. Arrays

Arrays are a built-in data type in OpenJai for storing a series of items of the
same type, packed contiguously in memory for maximum performance. Arrays are
called a _homogeneous_ type because all items share the same type (though an
array of `Any` can hold heterogeneous data). Arrays are built into the
compiler, unlike C where arrays and pointers are conflated.

OpenJai supports three kinds of arrays:

```Jai
Array_Type :: enum u32 {
    FIXED     :: 0;
    VIEW      :: 1;
    RESIZABLE :: 2;
}
```

This enum is defined in the `Preload` module.

### Array Literals

An array literal creates a **static array** using the syntax
`type.[item1, ..., itemn]`:

```Jai
numbers := int.[1, 3, 5, 7, 9];
arr1 := float.[10.0, 20.0, 1.4, 10.0];
words := string.["The", "number", "is", "odd."];
emp := string.[];                               // empty array literal
```

- The type prefix is required: `.[1, 2, 3]` alone produces an error
  ("no way to know its type").
- An empty array literal has `.count` of 0 and `.data` guaranteed to be
  `null`.
- Enum values can be used: `Good_Fruit.[.APPLE, .GRAPE, .KIWI]`.

**Typing rules**: When passed to or returned from a procedure where the array
type is indicated, array literals can be untyped (e.g., `.[1, 2, 3]`).
Otherwise they must be typed. To return an empty array: `return .[]`.

**Read-only warning**: An array literal assigned to an array view (`[]type`)
is stored in the read-only `.rdata` section. Attempting to modify its elements
causes an access violation crash.

### Static Arrays

A **static** (fixed-size) array has its size known at compile time. It is
declared as:

```
arr_name : [count] type
```

Examples:

```Jai
a : [4] u32;           // 4 u32 integers
b : [30] float64;      // 30 float64s
arr1 : [50] int;       // 50 integers

N :: 100;
static_array : [N] int;   // size can be a compile-time constant
```

- Items are **default zero-initialized** (0 for numbers, `false` for bool,
  `null` for pointers, etc.).
- Items are accessed by index: `arr[i]` for reading, `arr[i] = value` for
  writing. Indices range from `0` to `arr.count - 1`.
- Every array has a `.count` field (number of items) and a `.data` field
  (pointer to the first item).
- The type of a static array is `[N] T` (e.g., `[5] s64`). The `[4]int` and
  `[5]int` types both have type `Type`.
- The size in bytes is `count * size_of(element_type)` (e.g., `[100]int` is
  800 bytes).
- An array of type `[N]Any` can hold items of different types, though each
  element must be assigned individually (not via array literal syntax).

#### Compile-Time and Run-Time Bounds Checking

OpenJai performs **bounds checking** on array accesses:

- **Compile-time**: When both the array size and the index are compile-time
  constants, the compiler checks bounds and reports an error:
  ```
  Error: Subscript is out of array bounds.
  (The attempted index is 100, but the highest valid index is 99.)
  ```

- **Run-time**: When the index is a variable, bounds checking happens at
  runtime. An out-of-bounds access causes a panic with a stack trace:
  ```
  Array bounds check failed.
  (The attempted index is 100, but the highest valid index is 99).
  ```

Array views are also bounds-checked at run-time.

#### The `#no_abc` Directive

The `#no_abc` directive disables array bounds checking for a procedure,
improving performance in production builds:

```Jai
proc1 :: () #no_abc { }
```

Alternatively, the `array_bounds_check` build option can be used to control
bounds checking globally.

#### Using an Array as a Boolean

A non-empty array evaluates as `true` in a boolean context; an empty array
evaluates as `false`:

```Jai
if arr2 {
    print("arr2 is NOT empty\n");
}
```

#### Allocating Static Arrays on the Heap

By default, static arrays are stack-allocated. To heap-allocate:

**Using `NewArray`** (from `Basic`):

```Jai
arr_heap := NewArray(4, float);
defer array_free(arr_heap);

arr_align := NewArray(500, int, alignment=64);   // 64-byte cache-aligned
```

`NewArray` accepts optional arguments for `initialized`, `allocator`, and
`alignment`. Free with `array_free`.

**Using `New`**:

```Jai
arr_heap2 := New([3] int);        // returns a pointer (*[3] int)
defer free(arr_heap2);
(<<arr_heap2)[0] = 42;            // dereference to access elements
print("%\n", << arr_heap2);       // dereference to print
```

`New` returns a pointer; elements must be accessed and printed via
dereferencing (`<<`).

### Dynamic Arrays

**Dynamic** (resizable) arrays have a size not known at compile time that can
grow at runtime. Their items and size metadata are stored on the heap via the
context's default allocator.

#### Declaration

```Jai
arrdyn : [..]int;          // dynamic array of integers
b : [..]string;            // dynamic array of strings
```

The syntax is `[..]type`. Memory must be explicitly freed:

```Jai
defer array_free(arrdyn);
```

#### Adding and Removing Items

```Jai
array_add(*arrdyn, 5);     // append 5
array_add(*arrdyn, 9);     // append 9

// array_add accepts multiple values at once:
array_add(*strings, "Hello", "Sailor", "!", "Hello", "Sailor", "!");

// Remove by value (inside a for loop only):
for arrdyn {
    if it == 5  remove it;
}
```

- `array_add` takes a **pointer** to the array (any operation that modifies
  an array requires a pointer). It accepts one or more values in a single
  call.
- `remove` works only inside a `for` loop. It performs an **unordered remove**
  (swaps the removed item with the last item, then removes the last element)
  in O(1) time. It does **not** work on fixed-size arrays.
- `array_add_if_unique` adds only if the item is not already present.
- `peek` returns the last item without removing it; `pop` returns and removes
  the last item.

#### Ordered Remove

The `remove` keyword inside `for` loops is fast (O(1)) but does **not**
preserve the order of remaining elements. To remove an element while keeping
the array in its original order, use `array_ordered_remove_by_index`:

```Jai
for s, sIndex : strings {
    if s == "Sailor" {
        array_ordered_remove_by_index(*strings, sIndex);
        sIndex -= 1;
    }
}
// Original: ["Hello", "Sailor", "!", "Hello", "Sailor", "!"]
// remove:               produces ["Hello", "!", "!", "Hello"]       (unordered)
// ordered_remove:       produces ["Hello", "!", "Hello", "!"]       (order preserved)
```

- `array_ordered_remove_by_index` takes a pointer to the array and the index
  of the element to remove. It shifts subsequent elements down to fill the
  gap, preserving order.
- When removing inside a `for` loop, the loop index must be manually
  decremented after removal (`sIndex -= 1`) to avoid skipping the element
  that shifted into the removed position.

#### Other Useful Procedures

| Procedure                        | Description                                              |
|----------------------------------|----------------------------------------------------------|
| `array_find`                     | Returns `true` if a value is found in the array.         |
| `array_copy`                     | Copies one array into another (`array_copy(*dest, src)` or `dest := array_copy(src)`). |
| `array_reset`                    | Empties a dynamic array.                                 |
| `array_reserve`                  | Pre-allocates capacity to avoid repeated reallocation.   |
| `array_free`                     | Frees the array's heap memory.                           |
| `array_ordered_remove_by_index`  | Removes an element by index, preserving order of remaining elements (see §27 Ordered Remove). |

**Performance note**: Repeated `array_add` calls cause repeated allocations.
Use `array_reserve` to pre-allocate when the approximate size is known:

```Jai
array_reserve(*arrdyn, 50);
for 1..50  array_add(*arrdyn, it);
```

#### Internal Definition

Defined in the `Preload` module as a struct (40 bytes):

```Jai
Resizable_Array :: struct {
    count      : s64;        // signed so that for 0..count-1 works
    data       : *void;
    allocated  : s64;        // how many bytes are currently reserved
    allocator  : Allocator;  // memory allocator for this array
}
```

### Array Views

An **array view** is a non-owning reference to an underlying array's memory.
It allocates no memory of its own and does not need to be freed.

#### Declaration

```Jai
static_array := int.[0, 1, 2, 3, 4, 5];
arrv : []int = static_array;         // view on a static array

a: [..] int;
for 1..7  array_add(*a, it);
v: [] int = a;                       // view on a dynamic array
```

The type is `[]type` (no size between the brackets). Static and dynamic
arrays are automatically cast to array views.

#### Internal Definition

Defined in the `Preload` module (16 bytes):

```Jai
Array_View_64 :: struct {
    count : s64;    // signed so that for 0..count-1 works
    data  : *u8;
}
```

#### Modifying Through a View

A view can be used to read and write the underlying array:

```Jai
arrv[3] = 42;
print("%\n", static_array);   // => [0, 1, 2, 42, 4, 5]
```

The `data` pointer and `count` fields can be manipulated to create a slice
(sub-view) of the underlying array:

```Jai
v.data += 2;
v.count = 3;
print("%\n", v);   // => [3, 4, 5]
```

This is pointer arithmetic -- be careful to stay within the bounds of the
underlying array. Exceeding bounds can read or overwrite adjacent memory.

#### Misuse with Dynamic Arrays

Taking an array view on a dynamic array and then resizing the dynamic array
is dangerous. `array_add` may move the dynamic array's memory, making the
view's `data` pointer stale (dangling):

```Jai
a: [..] int;
for 1..10  array_add(*a, it);
v: [] int = a;                 // view on a
for 1..10  array_add(*a, it); // a may have moved!
// v now points to freed memory -- reading v produces garbage
```

Only take a view on a dynamic array after the array will no longer be
resized. In general, holding a pointer into a dynamic array is unsafe because
the array can relocate when it grows.

### For-Loops over Arrays

The `for` loop works with all three array types (static, dynamic, view).
When iterating over an array, two implicit variables are available:

- **`it`** -- the value of the current item.
- **`it_index`** -- the index of the current item (starting from 0).

```Jai
for numbers  print("numbers[%] = %\n", it_index, it);
```

**Note**: `it_index` is only available when iterating over an array directly,
**not** when iterating over a range like `0..arr.count-1`.

#### Named Iteration Variables

Either or both implicit variables can be replaced with named variables:

```Jai
for n: static_array      print("% ", n);        // n replaces it
for value, index: arr     print("[%]=%", index, value);  // both replaced
```

When `it` is replaced by a named variable, `it` is no longer defined (and
vice versa).

#### Modifying Array Items by Pointer

The `it` variable is **read-only**. To modify array items during iteration,
iterate by pointer using `*`:

```Jai
for *elem: arr {
    val := <<elem;
    <<elem = val * val;
}
```

#### Reverse Iteration

The `<` modifier reverses iteration order:

```Jai
for < static_array  print("% ", it);   // prints items in reverse
```

### Multidimensional Arrays

Multidimensional arrays are declared by nesting array brackets:

```Jai
a2 : [4][4] float;          // 2D: 4x4 array of floats
b2 : [4][4][4] float;       // 3D: 4x4x4 array of floats

array3: [2][2] int = .[int.[1, 0], int.[0, 3]];
```

Like other static arrays, multidimensional arrays have a `.data` pointer to
their underlying contiguous memory. This can be used with low-level operations
like `memset`:

```Jai
M :: 128;
grid: [M][M] s8;
memset(grid.data, 0, size_of(#type [M][M] s8));  // zero the entire grid
```

Literal syntax for multidimensional arrays:

```Jai
luminance_color_ramp := ([3] float).[
    .[0,0,0],   // black
    .[0,0,1],   // blue
    .[0,1,1],   // cyan
    .[0,1,0],   // green
    .[1,1,0],   // yellow
    .[1,0,0],   // red
    .[1,0,1],   // magenta
    .[1,1,1]    // white
];
// type is [8] [3] float32
```

### Passing Arrays to Procedures

A procedure that takes an array parameter declares it as an **array view**:

```Jai
print_int_array :: (arr: [] int) {
    for arr  print("arr[%] = %\n", it_index, it);
}

add_numbers :: (numbers: [] int) -> int {
    sum := 0;
    for numbers  sum += it;
    return sum;
}
```

Both static and dynamic arrays are **automatically converted** to array views
when passed to a procedure with an array view parameter. This allows a single
procedure to work with arrays of any size and kind:

```Jai
static_array: [4] int = .[0, 1, 2, 3];
dynamic_array: [..] int;
// ...

print_int_array(static_array);     // static array auto-cast to view
print_int_array(dynamic_array);    // dynamic array auto-cast to view
sum := add_numbers(.[1, 2, 3, 4, 5]);  // literal auto-cast to view
```

Unlike C, arrays in OpenJai do **not** decay to bare pointers when passed to
procedures. The size information (`.count`) is always preserved, preventing
the class of bugs that arise from C's pointer-array conflation.

### Arrays of Pointers

A common pattern for game entities is an array of pointers to heap-allocated
struct instances:

```Jai
Dragon :: struct {
    serial_no: int;
    name: string;
    strength: u8;
}

NR_DRAGONS :: 10;
arr_dragons: [NR_DRAGONS] *Dragon;
defer { for arr_dragons  free(it); };

arr_dragons[1] = New(Dragon);
arr_dragons[1].serial_no = 123;
arr_dragons[1].name = "Dragon1";
```

Each array element is a pointer to a heap-allocated instance. Uninitialized
slots are `null`.

### Arrays of Structs

A static or dynamic array can hold struct instances directly (an
**array of structs**, sometimes abbreviated AOS):

```Jai
Vec2 :: struct {
    x: float = 1;
    y: float = 4;
}

va: [10] Vec2;
print("% %\n", va[7].x, va[7].y);    // => 1 4
for va  print("% % - ", it.x, it.y);  // it provides struct access
```

Struct fields can be accessed through `it` in a for-loop. The `---`
initializer can be used to leave struct array elements uninitialized:

```Jai
va2 : [10] Vec2 = ---;     // elements have undefined values
```

**Dynamic arrays of structs** -- `array_add` has a variant that adds a
default-initialized element and returns a pointer to it, allowing fields to
be filled in afterward:

```Jai
subscriptions: [..] Subscription;
sub1 := array_add(*subscriptions);   // returns *Subscription
sub1.subscriber = "John";
sub1.no_payments = 15;
```

### The `print` Procedure and Arrays

The `print` procedure (from `Basic`) is variadic:

```Jai
print :: (format_string: string, args: .. Any, to_standard_error := false) -> bytes_printed: s64
```

Because `args` is `..Any`, `print` can accept and display values of any type,
including arrays. Arrays are printed in bracket notation (e.g.,
`[1, 3, 5, 7, 9]`). See §10 for full details on `print` and variadic
procedures.

---

## 28. Strings

Strings in OpenJai are simple and performant. A string is an array view of bytes
(`[] u8`), not a class or opaque handle. For the internal definition and type
details, see §11.

### String Properties

#### Immutability and Bounds Checking

String literals are stored in read-only memory. Individual bytes can be read
via indexing (`str[i]` returns a `u8`), but writing to a literal crashes at
runtime:

```Jai
str := "Hello.";
print("%\n", str[5]);      // => 46 (ASCII for '.')
str[5] = #char "!";        // runtime crash: read-only memory
```

Out-of-bounds indexing triggers an `__array_bounds_check_fail` panic at
runtime.

#### Modifying String Data

To modify a string's content, copy it into mutable memory:

- **`sprint`**: allocate a mutable copy on the heap:
  ```Jai
  chg := sprint("%", str);     // heap-allocated, mutable
  chg[5] = #char "?";          // ok
  free(chg);
  ```
- **Stack copy** with `memcpy` and `to_string`:
  ```Jai
  SIZE :: "Hello.".count;
  mem : [SIZE] u8;
  memcpy(mem.data, str.data, str.count);
  chg := to_string(mem.data, mem.count);
  ```
- **`copy_string`**: convenience heap copy:
  ```Jai
  chg := copy_string(str);
  defer free(chg);
  chg[3] = #char "p";          // ok
  ```

#### Boolean Conversion

Non-empty strings implicitly convert to `true` in boolean contexts; the
empty string `""` converts to `false`:

```Jai
if str  print("not empty");
```

#### Multi-Line Strings

Multi-line strings (also called here-strings or doc-strings) use the
`#string` directive with a user-chosen delimiter:

```Jai
text := #string END
This is
  a multi-line
    string.
END;
```

All whitespace is preserved. No characters may appear between the
delimiter and the string content except a newline. Multi-line strings
can contain `%` markers for later substitution with `sprint` or a
string builder.

#### Looping Over Characters

A `for` loop cannot iterate a string directly. Two approaches:

```Jai
// By index:
for i: 0..str.count-1  print("% ", str[i]);

// By casting to [] u8:
for cast([] u8) str  print("% ", it);
```

Both iterate over raw bytes, not Unicode code points.

### String Builder

The most efficient way to build larger strings from several parts is
`String_Builder` (defined in `Basic`). It works incrementally with
internal buffering.

```Jai
builder: String_Builder;
defer free_buffers(*builder);
init_string_builder(*builder);

append(*builder, "One!");
append(*builder, "Two!");
append(*builder, "Three!");

print_to_builder(*builder, " ... number %, exclamation %.", 42, "wow");

len := builder_string_length(*builder);
s   := builder_to_string(*builder);
```

Key procedures:

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `init_string_builder` | `(*String_Builder)` | Initialize a builder. |
| `append` | `(*String_Builder, string)` | Append a string. |
| `append` | `(*String_Builder, *u8, s64)` | Append raw bytes with length. |
| `append` | `(*String_Builder, u8)` | Append a single byte. |
| `print_to_builder` | `(*String_Builder, string, ..Any) -> bool` | Append a formatted string. |
| `builder_string_length` | `(*String_Builder) -> s64` | Current accumulated length. |
| `builder_to_string` | `(*String_Builder, ...) -> string` | Convert buffer to a string. Accepts optional `allocator`, `extra_bytes_to_prepend`. |
| `free_buffers` | `(*String_Builder)` | Free the builder's internal memory. Use with `defer`. |

### Byte Operations

OpenJai has no `char` type; strings are `[] u8`. The following procedures
(from `Basic` unless noted) operate on individual bytes:

| Procedure | Module | Description |
|-----------|--------|-------------|
| `to_upper(u8) -> u8` | `Basic` | Convert ASCII letter to uppercase. |
| `to_lower(u8) -> u8` | `Basic` | Convert ASCII letter to lowercase. |
| `is_digit(u8) -> bool` | `Basic` | True if `0`--`9`. |
| `is_alpha(u8) -> bool` | `Basic` | True if ASCII letter. |
| `is_alnum(u8) -> bool` | `Basic` | True if letter or digit. |
| `is_space(u8) -> bool` | `Basic` | True if whitespace (space, tab, etc.). |
| `is_any(u8, string) -> bool` | `String` | True if the byte appears in the given string. |

### String Operations

These procedures are defined in `Basic` and `String` modules.

#### Conversions: Strings to Numbers

```Jai
string_to_int   :: (str: string) -> int, bool;
string_to_float :: (str: string) -> float, bool;
to_integer       :: (s: string) -> result: int, success: bool, remainder: string;
```

`string_to_int` and `string_to_float` return the parsed value and a
success flag. `to_integer` additionally returns the unparsed remainder.

The `parse_int` and `parse_float` procedures (using `parse_token`) are
more robust variants.

#### Conversions: Numbers to Strings

Use `sprint` or `tprint`:

```Jai
a := 4;
str := sprint("%", a);   // str is "4"
free(str);
```

For complex cases, use a `String_Builder`.

#### Comparisons

```Jai
equal         :: (a: string, b: string) -> bool #must;
equal_nocase  :: (a: string, b: string) -> bool #must;
compare       :: (a: string, b: string) -> int #must;    // like C strcmp
compare_nocase :: (a: string, b: string) -> int #must;
contains      :: (str: string, substring: string) -> bool #must;
contains      :: (s: string, char: u8) -> bool;
begins_with   :: (str: string, prefix: string) -> bool #must;
ends_with     :: (str: string, suffix: string) -> bool #must;
```

`compare` returns negative if `a < b`, zero if equal, positive if `a > b`.

#### Joining and Splitting

```Jai
join  :: (inputs: .. string, separator := "", before_first := false, after_last := false) -> string;
split :: (str: string, separator: string) -> [] string;
split_from_left :: (s: string, byte: u8) -> (found: bool, left: string, right: string);
```

Examples:

```Jai
join("a", "b", "c", "d");                      // => "abcd"
join(.. .["One", "Two"], separator = "::");     // => "One::Two"
split("Hello, Sailor! How?", " ");              // => ["Hello,", "Sailor!", "How?"]
```

The result of `split` is an array and can be iterated with `for`.

#### Searching

```Jai
find_index_from_left  :: (s: string, byte: u8) -> s64;
find_index_from_left  :: (s: string, substring: string) -> s64;
find_index_from_right :: (s: string, byte: u8) -> s64;
find_index_from_right :: (s: string, substring: string) -> s64;
```

#### Modifying

```Jai
trim_left, trim_right, trim       // remove leading/trailing whitespace
replace_chars :: (s: string, chars: string, replacement: u8);
replace       :: (s: string, old: string, new: string) -> (result: string, occurrences: int);
to_lower_in_place :: (s: string);
to_upper_in_place :: (s: string);
slice :: inline (s: string, index: s64, count: s64) -> string;
```

Examples:

```Jai
trim("\t  Hello!  \t");                // => "Hello!"
replace("Antwerpen", "n", "m");        // => "Amtwerpem"
slice("London", 2, 3);                 // => "ndo"
```

#### Copying

```Jai
copy_string :: (s: string) -> string;   // heap-allocated mutable copy; must be freed
```

### C Strings

OpenJai strings are **not** zero-terminated. A C string is a `*u8` pointing to
zero-terminated data.

To ease C interop, the compiler constructs constant OpenJai strings (e.g.,
`greeting :: "Hello"`) with a zero terminator, but the `count` does not
include it.

Key conversion procedures:

```Jai
to_c_string     :: (str: string) -> *u8;      // heap-allocates; must be freed
to_string       :: (c_str: *u8) -> string;     // wraps a C string as a OpenJai string
c_style_strlen  :: (ptr: *u8) -> int;
```

Example:

```Jai
str := "London";
c_str := to_c_string(str);
defer free(c_str);
print("%\n", c_style_strlen(c_str));   // => 6
original := to_string(c_str);          // => "London"
```

A C string's length can also be computed manually by walking the pointer
until a zero byte:

```Jai
len := 0;
while << c_str {
    len += 1;
    c_str += 1;    // pointer arithmetic
}
```

### Console Input

OpenJai has no built-in `readln` or `scanf`; console input uses platform-specific
APIs.

#### Linux

On Linux, use the `POSIX` module's `read` function (a C libc wrapper) with
`STDIN_FILENO`:

```Jai
#import "Basic";
#import "POSIX";

main :: () {
    buffer: [4096] u8;
    bytes_read := read(STDIN_FILENO, buffer.data, buffer.count - 1);
    str := to_string(buffer.data, bytes_read);
    print("Input: %\n", str);
}
```

`read` blocks until the user presses Enter. The bytes (excluding the
terminator) are stored in `buffer`, and `to_string(data, count)` wraps the
raw bytes as a OpenJai string.

#### Windows

On Windows, use the `Windows` module for types and `#system_library` /
`#foreign` to bind `ReadConsoleA` from `kernel32`:

```Jai
#import "Basic";
#import "Windows";

kernel32 :: #system_library "kernel32";

stdin: HANDLE;

ReadConsoleA :: (
    hConsoleHandle: HANDLE,
    buff: *u8,
    chars_to_read: s32,
    chars_read: *s32,
    lpInputControl := *void
) -> bool #foreign kernel32;

input :: () -> string {
    MAX_BYTES_TO_READ :: 1024;
    temp: [MAX_BYTES_TO_READ] u8;
    result: string = ---;
    bytes_read: s32;

    if !ReadConsoleA(stdin, temp.data, xx temp.count, *bytes_read)
        return "";

    result.data  = alloc(bytes_read);
    result.count = bytes_read;
    memcpy(result.data, temp.data, bytes_read);
    return result;
}

main :: () {
    stdin = GetStdHandle(STD_INPUT_HANDLE);
    str := input();
    print("Input: %\n", str);
}
```

The pattern is the same: read into a fixed `[] u8` buffer, then convert to a
string — either by wrapping with `to_string` or by copying with
`alloc`/`memcpy`.

### Storing Code in Strings

Code can be stored in a string for metaprogramming (see §26, §19). Because
code may contain backslashes and quotes, multi-line strings (`#string`) or
constant string declarations (`::`) are preferred over regular string
literals.

---

## 29. Debugging

OpenJai provides multiple facilities for diagnosing bugs at both compile time and
run time: a built-in crash handler, compile-time and run-time assertions,
a compile-time interactive debugger, byte-code inspection, and integration with
external debuggers.

### Crash Handler

When a OpenJai program crashes at run time, the `Runtime_Support_Crash_Handler`
module catches the exception and prints a stack trace showing the file and line
where the crash occurred:

```
The program crashed. Printing the stack trace:
handle_exception                  c:\OpenJai\modules\Runtime_Support_Crash_Handler.OpenJai:211
... (skipping OS-internal procedures)
main                              example.OpenJai:5
```

A useful defensive pattern is to place a deferred print as the very first
statement in `main`:

```Jai
main :: () {
    defer print("Program ended gracefully.\n");
    // ...
}
```

If this message does not appear, the program ended with a silent crash.

### Print Debugging

Locate a bug by adding `print` and `defer print` calls to suspect procedures:

```Jai
proc1 :: () {
    print("Entering proc1\n");
    defer print("Exiting proc1\n");
    print("var v is %\n", v);
}
```

For pointers, dereference with `<<`: `print("ptr points to %\n", <<ptr);`

Compile-time print debugging is also possible — check the value or type of a
variable in a hot code path without any run-time cost:

```Jai
#run print("value: %, type: %\n", var1, type_of(var1));
```

### Assert Debugging

Use `assert` (from `Basic`) to verify conditions at run time. When an assert
fails, it indicates something went wrong in the procedure where it executed.
See §10 for full `assert` details.

Asserts can be left in production code and disabled with
`ENABLE_ASSERT=false` (see §10, §20).

### Compile-Time Assertions (`#assert`)

The `#assert` directive performs a compile-time assertion:

```Jai
#assert condition "optional message";
```

If the condition is `false`, compilation stops with:

```
Error: Compile-time assertion failed. "message"
```

Compile-time and run-time asserts can be combined using `is_constant`:

```Jai
#if is_constant(y) {
    #assert(y != 0);      // compile-time check
} else {
    assert(y != 0);       // run-time check
}
```

### Compile-Time Interactive Debugger

Any OpenJai program can be debugged at compile time by adding `#run main();` to
the source file. If the program crashes during compile-time execution, the
compiler shows a stack trace and suggests the `-debugger` flag.

Start the interactive debugger with:

```
OpenJai -debugger program.OpenJai
```

On a crash, the debugger shows the crash line, the byte-code instruction, and
variable values, then drops to an interactive prompt (`>`).

**Debugger commands:**

| Command                   | Description                                    |
|---------------------------|------------------------------------------------|
| `c`, `cont`, `continue`  | Continue running without stopping each instruction. |
| `n`, `next`               | Execute the next instruction.                  |
| `q`, `quit`               | Quit the compiler (close all workspaces).      |
| `r`, `return`, `finish`   | Run until returning from the current procedure.|
| `v<number>` (e.g., `v5`) | Print the value of that variable number.       |
| `w`, `where`              | Show the current call stack.                   |
| `?`, `h`, `help`          | Print help text.                               |

### The `#dump` Directive

The `#dump` directive displays the generated byte code for a procedure at
compile time. Place it immediately before the procedure body:

```Jai
add :: (n: int, m: int) -> int #dump {
    return n + m;
}
```

Compiler output:

```
Disassembly of 'add' at example.OpenJai:3
- Stack size 0

-------- Basic Block 0 -------- defines v4-20 --------

           (no dominating)

   0|        binop   v4, v1 + v2
   1| return_value   v4 -> 1
   2|       return
```

### The `Debug` Module

The `Debug` module provides integration with external debuggers (e.g., Visual
Studio on Windows). Import and initialize it:

```Jai
Debug :: #import "Debug";

main :: () {
    Debug.init();
    // ...
}
```

**Key procedures:**

| Procedure                     | Description                                  |
|-------------------------------|----------------------------------------------|
| `Debug.init()`                | Initialize the debug module. Call at program start. |
| `Debug.attach_to_debugger()`  | Attach an external debugger to the running program at this point. |
| `Debug.breakpoint()`          | Trigger a breakpoint. The external debugger will stop here. |

`attach_to_debugger()` and `breakpoint()` can be placed anywhere in the code
to start a debug session at a specific point:

```Jai
Debug :: #import "Debug";

main :: () {
    n := 3;
    m := 7;
    Debug.attach_to_debugger();
    Debug.breakpoint();
    for 1..4 {
        n += 1;
        m += n * 2;
        if m == 37  Debug.breakpoint();  // conditional breakpoint
    }
}
```

When a breakpoint is hit, a dialog asks to attach the debugger. Once attached,
you can step through code (F10/F11 in Visual Studio), inspect locals, and set
additional breakpoints in the `.OpenJai` source.

On Windows, compiling produces both an executable and a `.pdb` file. When the
program crashes or hits a breakpoint with `Debug` initialized, the system
offers to attach a Just-In-Time debugger (e.g., Visual Studio).

### Natvis Support

For better display of OpenJai compound data structures (arrays, structs,
`Type_Info`, and Math module types) in Visual Studio's debugger, natvis
support files are provided in the compiler distribution at
`editor_support/msvc/OpenJai.natvis` and `OpenJai.natstepfilter`.

**Setup:**

1. Copy `OpenJai.natvis` and `OpenJai.natstepfilter` to
   `%USERPROFILE%\Documents\Visual Studio 2022\Visualizers\` (or the
   equivalent path for VS 2019).
2. Compile with the `-natvis` flag: `OpenJai program.OpenJai -natvis`

### Other Debugging Tools

- **WinDbg Preview** (Windows): Free from the Microsoft Store. Supports
  kernel-mode and user-mode debugging, crash dump analysis, and CPU register
  inspection. Can open `.OpenJai` source files for breakpoints and stepping.
- **Smash** (Linux/macOS): A debugger written in OpenJai:
  [github.com/rluba/smash](https://github.com/rluba/smash).
- The `Basic` module provides a built-in **memory-leak detector** (enabled via
  the `MEMORY_DEBUGGER` program parameter). See §15 Memory-Leak Detector for
  details.

### Compile-Time vs. Run-Time Debugging

Code can be run at compile time with `#run` and debugged there. There are
subtle differences between compile-time and run-time execution — for example,
string literals can be modified at compile time but not at run time. A run-time
bug may not reproduce at compile time, and vice versa.

---

## 30. The Context

A central concept in OpenJai is the **context** -- an implicit struct that is
passed to every procedure automatically (unless the procedure is marked
`#c_call` or `#no_context`). The context coordinates services across a program
by establishing conventions for memory allocation, logging, assertion handling,
stack tracing, and more. It ships with sensible defaults but can be overridden
at any scope boundary.

The context is accessible at runtime via the `context` keyword and is small
enough to fit entirely in cache memory in most cases. Each thread receives its
own `Context` (including a separate `Temporary_Storage`), so threads do not
need to synchronize over temporary allocations (see §38).

### What the Context Contains

1. A default memory allocator.
2. Logging functions, log level, and log data.
3. A pointer to temporary storage.
4. A cross-platform stack trace.
5. An assertion handler.
6. A thread index.

### `Context_Base`

The core of the context is `Context_Base`, defined in the `Preload` module:

```Jai
Context_Base :: struct {
    context_info:      *Type_Info_Struct;
    thread_index:       u32;
    allocator        := Allocator.{__default_allocator_proc, null};

    logger           := default_logger;
    logger_data:       *void;
    log_source_identifier: u64;
    log_level:          Log_Level;
    temporary_storage: *Temporary_Storage;
    dynamic_entries:   [16] Dynamic_Context_Entry;
    num_dynamic_entries: s32;
    stack_trace:       *Stack_Trace_Node;
    assertion_failed := default_assertion_failed;
    handling_assertion_failure := false;
}
```

Default implementations for `default_logger`, `default_assertion_failed`, and
`default_allocator` are declared inside `Context_Base` and delegate to
`#runtime_support` procedures.

The full `Context` type extends `Context_Base`. The `Basic` module adds a
`print_style` member (see Print Style below).

### Accessing the Context

The context is globally accessible via the `context` keyword:

```Jai
print("Thread index: %\n", context.thread_index);
print("Temp storage: %\n", <<context.temporary_storage);
```

The basic `alloc` procedure calls `context.allocator` to obtain memory. By
overriding the allocator in the context, memory management can be coordinated
between the compiler, libraries, and the developer.

### `#add_context`

The `#add_context` directive adds a user-defined field to the context:

```Jai
#add_context this_is_the_way := true;
```

Fields added with `#add_context` are accessed through `context`, not as bare
identifiers:

```Jai
if this_is_the_way { ... }            // Error: Undeclared identifier 'this_is_the_way'.
if context.this_is_the_way { ... }    // Correct
```

### `push_context`

`push_context` replaces the active context for the duration of a code block.
When the block exits, the previous context is restored:

```Jai
new_context: Context;
new_context.allocator.proc = my_allocator_proc;
new_context.allocator.data = null;

push_context new_context {
    // All code here -- including nested procedure calls -- uses new_context.
}
// Original context is restored here.
```

Common uses:

- Switch to an arena allocator (e.g., a `Pool`) for a section of code. All
  allocations inside the block (and any subroutines called) use the arena, and
  the arena can be freed in bulk afterward.
- Install a custom logger or assertion handler for a library call.

### `push_allocator`

The `push_allocator` macro changes only the allocator in the current context
for the current scope. When the scope exits, the previous allocator is
restored:

```Jai
push_allocator(temp);
// All allocations in this scope use temporary storage.
```

This is a convenience over creating an entirely new context when only the
allocator needs to change. It can be used inside or outside a `push_context`
block.

### `#no_context`

The `#no_context` directive marks a procedure as not receiving or using the
implicit context. Low-level procedures such as `write_string()` and
`debug_break()` in `Preload` use this directive:

```Jai
write_string :: (s: string) #no_context { ... }
```

### Logging

The `log()` procedure (from the `Basic` module) formats a message, then sends
it to `context.logger`. It automatically appends a newline.

```Jai
log :: (format_string: string, args: .. Any, loc := #caller_location,
        flags := Log_Flags.NONE, user_flags: u32 = 0)
```

`Log_Flags` is an enum defined in `Preload`.

A custom logger can be installed by assigning to `context.logger` and
`context.logger_data`, either directly or within a `push_context` block.

### Print Style

The context contains a `print_style` member with default formatters used by
`print`. `Print_Style` is a struct defined in `Basic/Print.OpenJai`; a variable
of this type is added to the context by the `Basic` module.

The print style includes default formatters for integers, floats, structs,
arrays, and pointers. These can be changed within a `push_context` block:

```Jai
new_context := context;
push_context new_context {
    format_int := *context.print_style.default_format_int;
    format_int.base = 16;
    for numbers  print("% ", it);   // prints in hexadecimal
}
// Outside the block, default base-10 formatting is restored.
```

### Stack Trace

The context contains a `stack_trace` field (`*Stack_Trace_Node`) that
maintains the program's function call stack at runtime. Stack traces work
cross-platform and record all active stack frames, including the procedure
name, source file, line number, call depth, and a hash.

Accessing the stack trace:

```Jai
node := context.stack_trace;
while node {
    if node.info {
        print("[%] at %:%. call depth %\n",
            node.info.name,
            node.info.location.fully_pathed_filename,
            node.line_number,
            node.call_depth);
    }
    node = node.next;
}
```

The `Basic` module provides `print_stack_trace` with similar functionality.

The address of the current procedure is available via
`context.stack_trace.info.procedure_address`. The `pack_stack_trace()`
procedure makes a copy of the stack trace that can be stored for later
examination.

Stack trace generation is controlled by the `build_options.stack_trace`
compile option (default: `true`). When enabled, every procedure call generates
code to push a `Stack_Trace_Node` onto the stack on entry and unlink it on
return. Stack traces are useful for profilers, memory debuggers, and crash
diagnostics. `Stack_Trace_Node` and related types are defined in `Preload`.

### Custom Allocator Example

A custom allocator procedure follows the `Allocator_Proc` signature and can
delegate to the default allocator:

```Jai
my_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64,
                      old_memory_pointer: *void, proc_data: *void) -> *void {
    result := context.default_allocator.proc(mode, size, old_size,
                                             old_memory_pointer, proc_data);
    return result;
}
```

Install it via `push_context`:

```Jai
new_context: Context;
new_context.allocator.proc = my_allocator_proc;
new_context.allocator.data = null;
push_context new_context {
    // allocations here use my_allocator_proc
}
```

### Checking Whether a Variable Is on the Stack

By adding a `stack_base` pointer to the context via `#add_context`, a program
can determine at runtime whether a variable lives on the stack or the heap.
The technique exploits the fact that consecutive stack variables have
decrementing addresses:

```Jai
#add_context stack_base: *void;

init_stack_checker :: () #expand {
    stack_value: u8;
    context.stack_base = *stack_value;
}

is_in_stack :: (pointer: *void) -> bool {
    assert(context.stack_base != null);
    stack_value: u8;
    return pointer > *stack_value && pointer < context.stack_base;
}
```

After calling `init_stack_checker()`, `is_in_stack` returns `true` for
stack-allocated variables and `false` for heap-allocated ones. Each thread has
its own stack, so `init_stack_checker()` must be called per thread.

### Context Size

The compiler flag `-context_size n` sets the size of the `Context` struct in
bytes (e.g., `-context_size 2048`). See §4 for compiler flags.

---

## 31. Metaprogramming

A _meta-program_ is a piece of code that alters (or "programs") an existing
program (another piece of code). In OpenJai, all meta-programming takes place at
compile time. The compiler provides the source code in AST format (Abstract
Syntax Tree) for modification. This capability is one of the main pillars of
the language.

OpenJai offers arbitrary compile-time execution with powerful meta-programming
features. The tool-set includes: macros, types as first-class values,
polymorphic procedures and data structures, a built-in build system, and
full understanding of the AST. Full type information is available at compile
time and also retained at runtime as static type information stored in the
type table (see §11, Type Information System).

### Running Code at Compile Time with `#run`

Any code -- a single expression, a block, or a procedure call -- can be run at
compile time with `#run`. See §19 for the full reference.

```Jai
#run proc1();                // run a procedure at compile time
result := #run proc2();      // capture the return value
PI :: #run compute_pi();     // compute a constant at compile time

#run {                       // run a code block at compile time
    print("compile-time only!");
    n := 108;
}

f1 :: ()  => 1000;
f2 :: (c) => c + 1;
a :: #run f1();              // a == 1000
b :: #run f2(a);             // b == 1001
```

`#run` can be used inside struct literals when a value must be computed:

```Jai
v: Vector3;
v = .{cast(float) #run sin(R22 * .5), 1, 0};
```

Summary of the difference between compile-time and run-time execution:

```Jai
proc1 :: () { ... }

#run proc1();   // running byte-code at compile time

main :: () {
    proc1();    // running native code at run-time
}
```

### The `#compile_time` Directive

`#compile_time` evaluates to `true` during compile-time execution and `false`
at run-time. It cannot be used as a constant.

```Jai
main :: () {
    print("#compile_time is %\n", #compile_time);
    // => #compile_time is false

    if #compile_time {
        #run print("compile time.\n");
    } else {
        print("not compile time.\n");
    }
}

#run main();  // => #compile_time is true
```

Use this when a procedure should behave differently at compile time vs
run-time.

### The `#no_reset` Directive

When global variables are modified during `#run`, their values are reset
(initialized to zeros) before the program runs. The `#no_reset` directive
tells the compiler to retain a global's compile-time value at run-time.

```Jai
#no_reset globvar := 0;
#run { globvar = 108; }

array: [4] int;
#no_reset arraynr: [4] int;

#run {
    array[0] = 1;   array[1] = 2;   array[2] = 3;   array[3] = 4;
    arraynr[0] = 1; arraynr[1] = 2; arraynr[2] = 3; arraynr[3] = 4;
}

main :: () {
    print("%\n", globvar);  // => 108  (retained because of #no_reset)
    print("%\n", array);    // => [0, 0, 0, 0]  (reset to zeros)
    print("%\n", arraynr);  // => [1, 2, 3, 4]  (retained because of #no_reset)
}
```

### Baking a Struct at Compile Time

A struct can be computed at compile time, stored as a `[] u8` via `#run`, and
restored at run-time. This pattern is sometimes called "baking a struct":

```Jai
Stock :: struct { x: int; }

st: Stock;
st_data :: #run store_as_u8(make_struct());

make_struct :: () -> Stock {
    return Stock.{12};
}

store_as_u8 :: (value: $T) -> [] u8 {
    array: [size_of(T)] u8;
    memcpy(*array, *value, size_of(T));
    return array;
}

restore_from_u8 :: (dest: *$T, data: [] u8) {
    memcpy(dest, data.data, size_of(T));
}

main :: () {
    print("%\n", st.x);        // => 0  (struct is zeroed at run-time)
    restore_from_u8(*st, st_data);
    print("%\n", st.x);        // => 12  (restored from baked data)
}
```

### Conditional Compilation with `#if`

`#if` evaluates a compile-time constant condition. If `true`, the following
block is compiled into the executable. If `false`, the block is not compiled
at all -- it is entirely excluded from the binary.

```Jai
#if OS == .WINDOWS {
    print("I'm on Windows!\n");
}

#if OS == .LINUX {
    print("I'm on Linux!\n");
}
```

The operating system is stored in the global compiler constant `OS` at the
start of compilation.

**Chaining:** `#if` supports `else` and `else #if` chains:

```Jai
#if CONSTANT == 0 {
} else #if CONSTANT == 1 {
} else {
    print("CONSTANT is %\n", CONSTANT);
}
```

There is no `#else` keyword; use plain `else` after `#if`.

**Inside enums and structs:** `#if` can conditionally include enum values or
struct fields:

```Jai
Log_Mode :: enum {
    NONE;
    MINIMAL;
    EVERYDAY;
    VERBOSE;

    #if ENABLE_EXTRA_MODES {
        VERY_VERBOSE;
        SECRET;
        TOP_SECRET;
    }
}

Person :: struct {
    name: string;
    age:  int;
    #if IS_PATIENT  disease := "common cold";
}
```

**Rules:**

- The condition must be a compile-time constant (including anything calculated
  with `#run`; can be verified with `is_constant`).
- All code in `#if` / `else` branches must be syntactically correct.
- `#if` / `else` blocks do **not** define their own scope (unlike `if` /
  `else`).
- `#if` blocks can be nested.

**One-line form `#ifx`:** For single expressions:

```Jai
name := #ifx OS == .WINDOWS then "Microsoft Windows"; else "Linux";
```

**Platform-specific loading:** A common pattern for platform-specific code:

```Jai
#if OS == .WINDOWS { #load "windows.OpenJai"; }
#if OS == .LINUX   { #load "linux.OpenJai"; }
#if OS == .MACOS   { #load "osx.OpenJai"; }
```

The same pattern works for conditional imports:

```Jai
#if OS == .WINDOWS {
    Windows_Resources :: #import "Windows_Resources";
    Ico_File :: #import "Ico_File";
}

#if OS == .MACOS {
    Bundler :: #import "MacOS_Bundler";
}
```

**Debug/release pattern:**

```Jai
DEBUG :: true;  // change to false for production
#if DEBUG {
    print(debug_info);
} else {
    // normal processing
}
```

Summary:

| Directive | Condition false                |
|-----------|-------------------------------|
| `if`      | Block is not _executed_        |
| `#if`     | Block is not _compiled_        |

### Inserting Code with `#insert`

The `#insert` directive inserts a piece of compile-time generated code
(represented as a string or `Code` value) at the insertion point. The inserted
code is validated as syntactically correct OpenJai during compilation.

#### Inserting Code Strings

```Jai
a := 1;
b := 2;
#insert "c := a + b;";      // inserts: c := a + b;
print("c is %\n", c);       // => c is 3

d :: "add(42, 8);";
x := 1 - #insert d;         // expression-level insert
print("x = %\n", x);        // => x = -49
```

Multi-line strings can also be inserted:

```Jai
my_code :: #string END
  a += 100;
  b += 100;
  c += 1000;
END;

#insert my_code;
```

#### Inserting Compile-Time Generated Strings

`#insert` combined with `#run` allows dynamically generated code to be
inserted at compile time:

```Jai
gen_code :: (v: int) -> string {
    return tprint("x *= %;", v);
}

main :: () {
    x := 3;
    #insert #run gen_code(3);                // inserts: x *= 3;
    print("%\n", x);                         // => 9

    #insert #run gen_code(factorial(3));      // inserts: x *= 6;
    print("%\n", x);                         // => 54
}
```

#### Using `#insert` with Compile-Time Parameters

Procedure parameters marked with `$` are known at compile time and can be
used with `#insert`:

```Jai
report :: ($header: string, $body: string, $footer: string, n: int) {
    #insert header;
    for 1..n {
        #insert body;
    }
    #insert footer;
}
```

Because `header`, `body`, and `footer` are compile-time constants (due to
`$`), they can be inserted as code blocks.

#### `#insert -> string`

The `#insert -> string` form is shorthand for `#insert #run () -> string { ... }();`.
It runs an anonymous lambda at compile time that returns a string, then inserts
the string as code. This is commonly used to generate struct contents:

```Jai
Matrix :: struct (N: int) {
    items: [N*N] float;
    #insert #run set_diagonals_to_1(N);
}

set_diagonals_to_1 :: (N: int) -> string {
    builder: String_Builder;
    for 0..N-1 {
        print_to_builder(*builder, "items[%] = 1;\n", it*N + it);
    }
    return builder_to_string(*builder);
}
```

This creates an identity matrix by generating initialization code like
`items[0] = 1; items[6] = 1; ...` at compile time. The generated string can
be inspected in `.build/.added_strings_w2.OpenJai`.

#### `#insert -> Code`

Similar to `#insert -> string`, but returns a typed `Code` value:

```Jai
#insert -> Code {
    return #code x = (x * 10) + 3495;
}
```

### Type Code and `#code`

The `#code` directive constructs a value of type `Code` from a code block or
expression. `Code` is a first-class type in OpenJai representing a piece of
source code:

```Jai
#code { x += 7 }           // a code block, type Code
#code a := Vector3.{1,2,3}; // a single statement, type Code
#code (a < b)               // an expression, type Code
```

`Code` values can be:

- Passed as procedure arguments (commonly with `$` to ensure compile-time
  availability).
- Inspected for their type via the `.type` field.
- Converted to AST structures defined in the `Compiler` module, manipulated,
  and resubmitted.
- Inserted into code with `#insert`.

```Jai
what_type :: ($c: Code) {
    T :: c.type;
    print("T is %\n", T);
}

what_type(2 + 3 + 4);        // => T is s64
what_type("Hello, Sailor!");  // => T is string
```

`#insert` can take a `Code` value directly:

```Jai
some_macro :: (body: Code) #expand {
    ...
    #insert body;
    ...
}
```

For non-constant code arguments, use `get_root_type` from the `Compiler`
module.

#### `#insert,scope()`

The `#insert,scope()` variant (formerly `#insert_internal`) inserts code into
a specific scope rather than the default scope. It lets you specify the scope
into which to insert the target `Code` or string by saying
`#insert,scope(target)`, where `target` is a `Code` that must be constant at
compile time. The scope where the `Code` lives is used as the enclosing scope
for the `#insert`, which determines how identifiers inside the inserted code
are resolved.

This is commonly used inside macros to let inserted code access the macro's
local variables:

```Jai
bubble_sort :: (arr: [] $T, compare_code: Code) #expand {
    for 0..arr.count-1 {
        for i: 1..arr.count-1 {
            a := arr[i-1];
            b := arr[i];
            if !(#insert,scope() compare_code) {
                t := arr[i];
                arr[i] = arr[i-1];
                arr[i-1] = t;
            }
        }
    }
}

main :: () {
    arr: [10] int = .[23, -89, 54, 108, 42, 7, -2500, 1024, 666, 0];
    bubble_sort(arr, #code (a <= b));
    // arr is now sorted; the inserted code (a <= b) can reference
    // the macro-local variables a and b thanks to #insert,scope()
}
```

The inserted code acts like a comparison function but without the performance
cost of function pointer callbacks.

### Inspecting Generated Code

The source code generated by `#insert` can be retrieved from the hidden
`.build` folder. For example, a `#insert -> string` that generates struct
fields produces an `.added_strings_w2.OpenJai` file in `.build` showing exactly
what code was inserted:

```
// Workspace: Target Program
//
// #insert text. Generated from example.OpenJai:10.
//
  name: [5] type_of(T.name);
  age: [5] type_of(T.age);
  is_cool: [5] type_of(T.is_cool);
```

### AST Inspection with `compiler_get_nodes`

The `compiler_get_nodes` procedure from the `Compiler` module converts a
`Code` value into its AST (Abstract Syntax Tree) nodes:

```Jai
compiler_get_nodes :: (code: Code) -> (root: *Code_Node, expressions: [] *Code_Node) #compiler;
```

It returns two values:

- **`root`** -- the root expression of the `Code`, which can be navigated
  recursively.
- **`expressions`** -- a flattened array of all expressions at all levels,
  making it easy to iterate over all nodes without recursive tree navigation.

`Code_Node` is a struct defined in the `Compiler` module. Each node has a
`.kind` field indicating the expression type (e.g., `.IDENT`, `.LITERAL`,
`.TYPE_INSTANTIATION`, `.DECLARATION`).

```Jai
#import "Basic";
#import "Compiler";
#import "Program_Print";

code :: #code a := Vector3.{1,2,3};

#run {
    builder: String_Builder;
    root, exprs := compiler_get_nodes(code);
    print_expression(*builder, root);
    s := builder_to_string(*builder);
    print("The code is: %\n", s);
    // => The code is: a := Vector3.{1, 2, 3}

    for expr, i: exprs {
        print("[%] % %\n", i, expr.kind, expr.node_flags);
    }
    // => [0] IDENT 0
    //    [1] TYPE_INSTANTIATION 0
    //    [2] LITERAL 0
    //    ...
    //    [6] DECLARATION ALLOWED_BY_CONTEXT
}
```

The `print_expression` procedure from the `Program_Print` module serializes
an AST node back into human-readable source form via a `String_Builder`.

The `code_of` procedure is another way to obtain a `Code` value from a piece
of code (in addition to `#code`).

### Modifying the AST at Compile Time

Code can be converted to AST nodes, modified in place, and converted back
to `Code` using `compiler_get_code`:

```Jai
compiler_get_code :: (root: *Code_Node) -> Code #compiler;
```

**Example: modifying literal values at compile time:**

```Jai
#import "Basic";
#import "Compiler";

factorial :: (x: int) -> int {
    if x <= 1 return 1;
    return x * factorial(x-1);
}

comptime_modify :: (code: Code) -> Code {
    root, expressions := compiler_get_nodes(code);

    for expr : expressions {
        if expr.kind == .LITERAL {
            literal := cast(*Code_Literal) expr;
            if literal.value_type == .NUMBER {
                literal._s64 *= factorial(literal._s64);
            }
        }
    }
    modified : Code = compiler_get_code(root);
    return modified;
}
```

This modifies the AST nodes in place (e.g., replacing the literal `3` with
`3 * factorial(3) = 18`), then converts the modified tree back to `Code`
with `compiler_get_code`.

A macro can use `#run` to apply the transformation and `#insert` the result:

```Jai
do_stuff :: (code: Code) #expand {
    new_code :: #run comptime_modify(code);
    #insert new_code;
}
```

**Searching for string literals in code:**

```Jai
root, expressions := compiler_get_nodes(code);
for expressions {
    if it.kind != .LITERAL continue;
    literal := cast(*Code_Literal) it;
    if literal.value_type != .STRING continue;
    // literal._string is accessible for reading or modification
}
modified := compiler_get_code(root);
```

### Converting Code to String

The combination of `compiler_get_nodes` and `print_expression` can convert
any `Code` value to its string representation:

```Jai
code_to_string :: (code: Code) -> string #expand {
    PP       :: #import "Program_Print";
    Compiler :: #import "Compiler";
    code_node := Compiler.compiler_get_nodes(code);
    builder: String_Builder;
    PP.print_expression(*builder, code_node);
    return builder_to_string(*builder, allocator=temp);
}

#run {
    code1 := #code a_constant :: 10;
    str := code_to_string(code1);
    print("This is the code: %\n", str);
    // => This is the code:  a_constant :: 10
}
```

There is also a `print_type_to_builder` procedure for printing type info to
a string builder.

### The `#caller_code` Directive

When used as the default value of a macro argument, `#caller_code` is set to
the `Code` of the procedure call that invoked the macro. This allows a macro
to inspect the call site at compile time:

```Jai
#import "Compiler";
#import "Program_Print";
#import "Basic";

get_variable_name :: (thing: int, call := #caller_code) -> string #expand {
    node := cast(*Code_Procedure_Call) compiler_get_nodes(call);
    builder: String_Builder;
    print_expression(*builder, node.arguments_unsorted[0].expression);
    return builder_to_string(*builder);
}

main :: () {
    a_constant :: 10;
    #run print("%", get_variable_name(a_constant));  // => a_constant
}
```

`compiler_get_nodes()` can be called on the `#caller_code` to inspect and
manipulate the arguments passed to the macro.

---

## 32. Macros

A macro is a way to insert code at compile time at the call site, similar to
an inlined procedure. Unlike C/C++ preprocessor macros, which are arbitrary
text substitution, OpenJai macros are:

- Controlled and well-supported by the compiler.
- Fully type-checked.
- Debuggable with standard debugging techniques.
- **Hygienic:** they do not cause accidental captures of identifiers from the
  environment and only modify outer variables when explicitly allowed.

Macros make certain kinds of meta-programming easier. Well-designed macros
allow you to raise the level of code abstraction by creating a mini-language
specific to your problem space. Poorly designed macros result in unmaintainable
code. Macros should be used as a last resort when procedures are insufficient.

### Declaration Syntax

A macro is defined by adding the `#expand` directive after the procedure
signature, before the body:

```Jai
proc1 :: () #expand {
    print("You are in proc1!");
}
```

Without `#expand`, this would be a regular procedure. With it, the code is
expanded (processed, transformed to real code, and inserted) at each call
site. Macros are called with the same syntax as procedures:

```Jai
main :: () {
    proc1();    // expands the macro at this call site
}
```

Macros can have parameters and return values, just like procedures:

```Jai
maxm :: (a: int, b: int) -> int #expand {
    if a > b then return a;
    return b;
}
```

A macro can also be polymorphic:

```Jai
swap :: (a: Code, b: Code) #expand {
    t := (#insert a);
    (#insert a) = (#insert b);
    (#insert b) = t;
}
```

### The Backtick (`` ` ``) -- Accessing Outer Scope

The backtick prefix (`` ` ``) on an identifier inside a macro denotes that
the variable must exist in the outer (caller's) scope. This is how macros
interact with the calling context:

```Jai
macro1 :: () #expand {
    a := "local";       // local to the macro, does not pollute outer scope
    `a += 10;           // refers to 'a' in the caller's scope
}

main :: () {
    a := 0;
    macro1();
    print("a is: %\n", a);    // => a is: 10
}
```

Rules for backtick references:

- If the backtick variable does not exist in the outer scope, the compiler
  emits `Error: Undeclared identifier 'a'` along with
  `Info: While expanding macro 'macro1' here...`.
- The backtick mechanism for looking up outer variables only works **one
  level up**.
- A variable without a backtick inside a macro is local to the macro and
  does not affect the outer scope.
- You only need to backtick a variable the **first** time you use it; after
  that it is known.

### Backtick with `defer`

A `defer` inside a macro scopes to the macro itself. A backtick `defer`
(`` `defer ``) scopes to the **caller**:

```Jai
macro2 :: () -> int #expand {
    if `b < `c {
        return 0;
    }
    defer print("Defer inside macro2\n");   // runs when macro scope ends
    // `defer print("...\n");               // would run when caller scope ends
    return 1;
}
```

### Backtick with `return`

A `` `return `` inside a macro causes the **enclosing procedure** (not just
the macro) to return:

```Jai
macfunc :: () -> string {
    macron :: () -> int #expand {
        if `a < `b {
            `return "Backtick return\n";    // returns from macfunc, not macron
        }
        return 1;                           // returns from macron
    }

    a := 0;
    b := 100;
    c := macron();
    return "none";    // never reached if macron uses `return
}
```

### Nested Macros

A macro can contain and call macros defined inside itself. The inner macro
must be defined before it is called:

```Jai
macro3 :: () #expand {
    nested_macro :: () #expand {
        print("This is a nested macro\n");
    }

    print("This is macro3\n");
    `c = 108;
    nested_macro();
}
```

There is a limit on how many macro calls can be generated inside another
macro.

### Recursive Macros

A macro can call itself recursively. `#if` (not runtime `if`) must be used
for the base case to avoid infinite expansion:

```Jai
factorial :: (n: int) -> int #expand {
    #if n <= 1 return 1;
    else {
        return n * factorial(n-1);
    }
}
```

The expansion limit is 1000 nested macro expansions. Using runtime `if`
instead of `#if` produces `Error: Too many nested macro expansions. (The
limit is 1000.)`

### Macros with `#insert`

Macros commonly take `Code` arguments and use `#insert` to insert them into
the expansion. `#insert` can be run recursively inside another `#insert`.

```Jai
macroi :: (c: Code) #expand {
    #insert c;
    #insert c;
    #insert c;
}

main :: () {
    va := Vector3.{1,2,3};
    code :: #code print("% - ", va);
    macroi(code);    // => {1, 2, 3} - {1, 2, 3} - {1, 2, 3} -
}
```

### Using a Macro as an Inner Procedure

Since inner (nested) procedures cannot access outer variables (see §10),
defining the inner procedure as a macro with backtick references provides
closure-like behavior:

```Jai
proc :: () {
    inner_proc :: () #expand {
        `x = 42;
    }

    x := 1;
    inner_proc();
    print("x is now %\n", x);    // => x is now 42
}
```

OpenJai does not support closures. This technique is the idiomatic way to
emulate closure behavior.

### Performance Measurement Macro

A practical macro pattern for timing code execution:

```Jai
perf_measure :: (code: Code) #expand {
    start_time := get_time();
    #insert code;
    elapsed := get_time() - start_time;
    print("Piece of code took % ms\n", elapsed * 1000);
}

main :: () {
    code :: #code print("Factorial 20 is %\n", factorial(20));
    perf_measure(code);
}
```

### Loop Unrolling with Macros

Loops can be unrolled through a mixture of `#insert` directives and macros:

```Jai
unroll_for_loop :: (a: int, b: int, body: Code) #expand {
    #insert -> string {
        builder: String_Builder;
        print_to_builder(*builder, "{\n");
        print_to_builder(*builder, "`it: int;\n");
        for i: a..b {
            print_to_builder(*builder, "it = %;\n", i);
            print_to_builder(*builder, "#insert body;\n");
        }
        print_to_builder(*builder, "}\n");
        return builder_to_string(*builder);
    }
}

main :: () {
    unroll_for_loop(0, 10, #code {
        print("% - ", it);    // => 0 - 1 - 2 - 3 - 4 - 5 - 6 - 7 - 8 - 9 - 10 -
    });
}
```

The generated code can be inspected in `.build/.added_strings_w2`.

### `for_expansion` Macros (Custom Iterators)

A `for_expansion` macro defines a custom `for` loop for a data structure.
This was the **primary reason** for introducing macros in OpenJai.

#### Signature

A `for_expansion` macro must have this signature:

```Jai
for_expansion :: (data: DataType, body: Code, flags: For_Flags) #expand
```

The three parameters are:

1. A pointer (or value) of the data structure to iterate over.
2. `body: Code` -- the body of the for loop, which is inserted via
   `#insert body`.
3. `flags: For_Flags` -- flags indicating pointer or reverse iteration.

The `For_Flags` enum is defined in the `Preload` module:

```Jai
For_Flags :: enum_flags u32 {
    POINTER :: 0x1;    // for-loop is done by pointer
    REVERSE :: 0x2;    // for-loop is a reverse for loop
}
```

Inside the macro, you must provide values for the implicit iteration
variables, prefixed with backticks:

- `` `it `` -- the current item value.
- `` `it_index `` -- the current index.

#### Basic Example: Singly-Linked List

```Jai
LinkedList :: struct {
    data: s64;
    next: *LinkedList;
}

for_expansion :: (list: *LinkedList, body: Code, flags: For_Flags) #expand {
    `it := list;
    `it_index := 0;
    while it {
        #insert body;
        it = it.next;
        it_index += 1;
    }
}

main :: () {
    // ... build linked list lst ...
    for lst {
        print("List item % is %\n", it_index, it.data);
    }
}
```

#### Named For-Expansions

A `for_expansion` may have any name. Named expansions are invoked with
`:name` syntax after `for`:

```Jai
looping :: (list: *LinkedList, body: Code, flags: For_Flags) #expand {
    `it := list;
    `it_index := 0;
    while it {
        #insert body;
        it = it.next;
        it_index += 1;
    }
}

for :looping lst {
    print("List item % is %\n", it_index, it.data);
}
```

The iteration variables `it` and `it_index` can also be renamed:

```Jai
for :looping v, n: lst {
    print("List item % is %\n", n, v.data);
}
```

Multiple named for-expansions can coexist for the same data structure:

```Jai
for :looping1 v, n: data_structure { ... }
for :looping2 v, n: data_structure { ... }
```

#### Doubly-Linked List with Reverse Iteration

```Jai
LinkedList :: struct (T: Type) {
    first: *Node(T);
    last:  *Node(T);
}

Node :: struct (T: Type) {
    value: T;
    prev: *Node(T);
    next: *Node(T);
}

for_expansion :: (list: LinkedList, body: Code, flags: For_Flags) #expand {
    `it := ifx flags == For_Flags.REVERSE  list.last  else  list.first;
    `it_index := ifx flags == For_Flags.REVERSE  2  else  0;
    while it {
        #insert body;
        if flags == For_Flags.REVERSE {
            it = it.prev;
            it_index -= 1;
        } else {
            it = it.next;
            it_index += 1;
        }
    }
}

for list  { print("% : %\n", it_index, << it); }    // forward
for < list { print("% : %\n", it_index, << it); }   // reverse
```

Use `#if` instead of runtime `if` on `For_Flags` to generate separate
compiled versions for forward and reverse iteration.

#### For-Expansion for Arrays

A `for_expansion` can be defined for arrays to add behavior (logging,
bounds checking, etc.) to every iteration:

```Jai
Player :: struct {
    name: string;
    score: u8;
}

players: [..]Player;

player_loop :: (_: *type_of(players), body: Code, flags: For_Flags) #expand {
    for `it, `it_index: players {
        print("inside macro player_loop!\n");
        if it_index >= players.count  break;
        #insert body;
    }
}

for :player_loop player, ix: players {
    print("Player % is %\n", ix, player);
}
```

#### For-Expansion Placement

A `for_expansion` macro can be defined locally inside a procedure or at
module scope. It can also be placed in a separate module and imported.

#### Step Iterator Example

A for-expansion macro can iterate with a custom step:

```Jai
Step_Iterator :: struct {
    min:  int;
    max:  int;
    step: int;
}

step_iterator :: (min: int, max: int, step: int) -> Step_Iterator {
    return .{ min, max, step };
}

for_expansion :: (iterator: Step_Iterator, body: Code, flags: For_Flags) #expand {
    iteration_count := -1;
    for i: iterator.min..iterator.max {
        iteration_count += 1;
        if iteration_count % iterator.step != 0  continue;
        `it       := i;
        `it_index := void;
        #insert body;
    }
}

main :: () {
    for step_iterator(0, 10, 2) {
        print("% - ", it);    // => 0 - 2 - 4 - 6 - 8 - 10 -
    }
}
```

---

## 33. The `#modify` Directive

The `#modify` directive inserts code between the header and body of a
polymorphic procedure or struct. It runs at compile time each time a call to
that procedure is resolved or a struct is instantiated.

### Execution Steps

1. The polymorph types (`$T`, etc.) are resolved by matching.
2. The body of `#modify` runs. Inside it, `T` is **not** constant -- it can
   be changed.
3. `#modify` returns a `bool`:
   - `true` -- the type is accepted; the procedure compiles or the struct is
     defined.
   - `false` -- generates a compile-time error; the procedure does not compile
     or the struct is not defined. An optional error message string can be
     returned as a second value.

### Forcing a Type

`#modify` can force a polymorph type to a specific concrete type:

```Jai
proc1 :: (a: $T)
#modify {
    T = s64;
    return true;
}
{
    print("a is %, of type %\n", a, T);
}

main :: () {
    var_s8: s8 = 1;
    proc1(var_s8);    // => a is 1, of type s64
}
```

The conversion is implicit for compatible types. Incompatible types (e.g.,
`bool`) produce a type mismatch error unless autocast (`xx`) is applied.

### Changing Multiple Generic Types

```Jai
proc2 :: (a: $A, b: $B, c: $C)
#modify {
    if B == A then B = C;
    return true;
}
{ ... }
```

### Type Restriction

`#modify` can restrict which types are accepted by inspecting `Type_Info`:

```Jai
do_something :: (T: Type) -> bool {
    t := cast(*Type_Info) T;
    if t.type == .INTEGER  return true;
    if t.type == .ENUM     return true;
    if t.type == .POINTER  return true;
    return false;
}

proc :: (dest: *$T, value: T)
#modify { return do_something(T); }
{
    dest := value;
}
```

### Calling a Macro from `#modify`

`#modify` can call a macro to perform the check. The macro uses `` `return ``
to return from the `#modify` block:

```Jai
ModifyRequire :: (t: Type, kind: Type_Info_Tag) #expand {
    `return (cast(*Type_Info)t).type == kind, tprint("T must be %", kind);
}

poly_proc :: (t: $T) #modify ModifyRequire(T, .ENUM) {}

poly_proc(SomeEnum.ASD);    // OK
// poly_proc(123);           // Error: #modify returned false: T must be ENUM
```

### `#modify` on Structs

`#modify` can enforce constraints on struct parameters:

```Jai
Holder :: struct (N: int, T: Type)
#modify { if N < 8  N = 8;  return true; }
{
    values: [N] T;
}

main :: () {
    b: Holder(3, float);
    assert(b.N >= 8);    // N was clamped to 8
}
```

Constraints between multiple parameters:

```Jai
Bitmap :: struct (Width: s16, Height: s16)
#modify { return Width >= Height, "Width of a Bitmap must be >= Height."; }
{
    pixels: [Width*Height] u32;
}

// gateway: Bitmap(512, 1024);
// Error: #modify returned false: Width of a Bitmap must be >= Height.
```

### Widening Types to Prevent Overflow

`#modify` can change the return type to avoid overflow for small integer
types:

```Jai
sum2 :: (a: [] $T) -> $R
#modify {
    R = T;
    ti := cast(*Type_Info) T;
    if ti.type == .INTEGER {
        info := cast(*Type_Info_Integer) T;
        if info.runtime_size < 4 {
            if info.signed  R = s32;
            else            R = u32;
        }
    }
    return true;
}
{
    result: R = 0;
    for a  result += it;
    return result;
}

main :: () {
    u8s := u8.[1, 4, 9, 16, 25, 36, 49, 64, 81];
    print("sum2 of u8s %\n", sum2(u8s));    // => 285 (correct, not truncated)
}
```

### Widening All Numeric Types to 64-bit

```Jai
#modify {
    if T == {
        case s8;  T = s64;
        case s16; T = s64;
        case s32; T = s64;
        case s64; // no change

        case u8;  T = u64;
        case u16; T = u64;
        case u32; T = u64;
        case u64; // no change

        case float32; T = float64;
        case float64; // no change

        case; return false, "Unsupported argument type to multiply_add.";
    }
    return true;
}
```

### Error Messages

When `#modify` returns `false`, an optional second return value provides a
message displayed in the compiler error:

```
Error: #modify returned false: Unsupported argument type to multiply_add.
```

---

## 34. Metaprogramming Applications

This section collects practical patterns that combine OpenJai's metaprogramming
features (`#insert`, `#code`, compile-time execution, type introspection) to
solve common programming problems.

### SOA (Struct of Arrays) Transformation

SOA (Structure of Arrays) is a data layout that groups each field of a struct
into its own contiguous array, rather than using the conventional AOS (Array
of Structures) layout. SOA can dramatically improve cache performance for
operations that iterate over a single field across many objects.

OpenJai provides built-in support for data-oriented design through `#insert` and
compile-time type introspection. The following polymorphic struct uses
`type_info` to automatically generate an SOA layout from any struct:

```Jai
SOA :: struct(T: Type, count: int) {
    #insert -> string {
        builder: String_Builder;
        defer free_buffers(*builder);
        t_info := type_info(T);
        for fields: t_info.members {
            print_to_builder(*builder, "  %1: [%2] type_of(T.%1);\n", fields.name, count);
        }
        result := builder_to_string(*builder);
        return result;
    }
}
```

Given a struct like `Person :: struct { name: string; age: int; is_cool: bool; }`,
instantiating `SOA(Person, 5)` generates a struct equivalent to:

```Jai
// generated struct layout:
//   name:    [5] string;
//   age:     [5] int;
//   is_cool: [5] bool;
```

**Converting AOS to SOA:**

```Jai
soa_person: SOA(Person, 5);

arrp := Person.[
    Person.{"Ivo", 66, true}, Person.{"Dolf", 42, false},
    Person.{"Laura", 28, true}, Person.{"Gabriel", 30, true},
    Person.{"Denise", 63, false}
];

for arrp {
    soa_person.name[it_index] = it.name;
    soa_person.age[it_index] = it.age;
    soa_person.is_cool[it_index] = it.is_cool;
}
```

### Generating Code for Each Struct Member

A common pattern uses `type_info` at compile time to generate code for every
member field of a struct. This enables generic serialization, deserialization,
and similar operations without hand-writing per-field code:

```Jai
for_each_member :: ($T: Type, format: string) -> string {
    builder: String_Builder;
    defer free_buffers(*builder);

    struct_info := cast(*Type_Info_Struct) T;
    assert(struct_info.type == Type_Info_Tag.STRUCT);

    for struct_info.members {
        if it.flags & .CONSTANT continue;
        print_to_builder(*builder, format, it.name);
    }

    return builder_to_string(*builder);
}
```

**Example: generic serialization:**

```Jai
serialize_structure :: (s: $T, builder: *String_Builder) -> success: bool {
    #insert #run for_each_member(T, "if !serialize(s.%1, builder) return false;\n");
    return true;
}
```

For a `Player :: struct { status: u16; health: int; }`, this generates:

```Jai
if !serialize(s.status, builder) return false;
if !serialize(s.health, builder) return false;
```

### Type-Tagged Unions

A type-tagged union wraps a `union` in a struct with a `tag` field that
tracks the currently active type. This is built at compile time using
`#insert -> string` and struct parameters:

```Jai
Tag_Union :: struct(fields: [] string, types: []Type) {
    tag: Type;
    #insert -> string {
        builder: String_Builder;
        defer free_buffers(*builder);
        count := fields.count - 1;
        print_to_builder(*builder, "union {\n");
        for i: 0..count {
            print_to_builder(*builder, "  %1: %2;\n", fields[i], types[i]);
        }
        print_to_builder(*builder, "}\n");
        result := builder_to_string(*builder);
        return result;
    }
}
```

The `set` procedure uses `#insert -> string` and the `/Tag_Union` type
constraint (see §10, Restricting Polymorphic Types) to update both the tag
and the union field:

```Jai
set :: (u: *$Tag/Tag_Union, value: $T) {
    #insert -> string {
        count := u.fields.count - 1;
        for i: 0..count {
            if T == Tag.types[i] {
                code :: #string END
                   u.tag = type_of(value);
                   u.% = value;
                END
                return sprint(code, Tag.fields[i]);
            }
        }
        assert(false, "Invalid value: %\n", T);
        return "";
    }
}
```

Usage:

```Jai
fields :: string.["int_a", "float_b", "string_c"];
types  :: Type.[int, float, string];

tag_union: Tag_Union(fields, types);
set(*tag_union, 10);           // tag becomes s64
set(*tag_union, 3.14);         // tag becomes float32
set(*tag_union, "James Bond"); // tag becomes string
// set(*tag_union, true);      // compile-time error: Invalid value: bool
```

### Creating Code for a List of Types

A macro can apply a code snippet to each type in a variadic list of types,
using `#insert -> string` and `#insert,scope()`:

```Jai
create_code_for_each_type :: (code: Code, $types: ..Type) #expand {
    #insert -> string {
        builder: String_Builder;
        for types {
            print_to_builder(*builder, "{\n");
            print_to_builder(*builder, "  T :: %1;\n", it);
            print_to_builder(*builder, "  #insert, scope() code;\n");
            print_to_builder(*builder, "}\n");
        }
        return builder_to_string(*builder);
    }
}

main :: () {
    snippet :: #code {
        t: T;
        print("value: '%'\n", t);
    };

    create_code_for_each_type(snippet, float32, bool, int, string);
    // => value: '0'
    //    value: 'false'
    //    value: '0'
    //    value: ''
}
```

---

## 35. File I/O

OpenJai provides file I/O through the `File` module (with additional utilities in
`File_Utilities`, `File_Async`, and `File_Watcher`). Because of OS differences,
the `File` module often has separate Windows and Unix variants of its
procedures.

### Importing

```Jai
#import "File";
```

### Whole-File Operations

The simplest way to read or write files:

```Jai
// Write a string to a file (creates the file if it doesn't exist)
success := write_entire_file("path/to/file.txt", some_string);

// write_entire_file can also accept a *String_Builder

// Read an entire file into a string
text, success := read_entire_file("path/to/file.txt");
```

`read_entire_file` returns two values: the file contents as a `string` and a
`bool` indicating success.

### File Handle Operations

For more control (appending, partial reads/writes), use file handles:

```Jai
// Open a file
file, success := file_open("path/to/file.txt", for_writing=true, keep_existing_content=true);
```

**`file_open` signature:**

```Jai
file_open :: (name: string, for_writing := false, keep_existing_content := false, log_errors := true) -> File, bool
```

The first return value is a `File` handle (a file handle on Windows or a
pointer to a file on Unix, defined in `windows.OpenJai` / `unix.OpenJai`). The second
is a success `bool`.

**File positioning and length:**

```Jai
length := file_length(file);          // get file size
file_set_position(file, offset);      // seek to a position
```

To append to an existing file, open with `keep_existing_content=true`, get the
file length, then set the position to the end before writing.

**Writing to a file handle:**

```Jai
success := file_write(*file, "text to append");
```

**Reading from a file handle:**

```Jai
file_read :: (f: File, vdata: *void, bytes_to_read: s64) -> (success: bool, bytes_read: s64)
```

To read into a buffer:

```Jai
length := file_length(file);
buffer := cast(*u8) alloc(length);
success := file_read(file, buffer, length);

// Construct a string from the buffer
data: string;
data.data = buffer;
data.count = length;
```

**Closing a file:**

```Jai
file_close(*file);
```

Use `defer` immediately after a successful open to ensure cleanup:

```Jai
file, success := file_open("path/to/file.txt");
if !success return;
defer file_close(*file);
```

### Directory Operations

```Jai
make_directory_if_it_does_not_exist("dirname");
delete_directory("dirname");
```

### File Existence and Management

```Jai
if file_exists("path/to/file.txt") { ... }
file_move(old_name, new_name);     // rename a file
file_delete("path/to/file.txt");   // delete a file
```

### Copying Files (File_Utilities)

The `File_Utilities` module provides `copy_file`:

```Jai
#import "File_Utilities";

copy_file("source/path.txt", "dest/path.txt");
```

### Directory Traversal (File_Utilities)

The `File_Utilities` module provides `visit_files` for recursive directory
traversal. It takes a visitor procedure that is called for each file or
directory found:

```Jai
#import "File_Utilities";

visitor :: (using info: *File_Visit_Info, user_data: string) {
    if short_name == user_data {
        success := delete_directory(full_name);
        descend_into_directory = false;   // don't recurse into deleted dir
    }
}

complete := visit_files(
    start_path,
    recursive = true,
    user_data,
    visitor,
    visit_files = false,
    visit_directories = true
);
```

The `File_Visit_Info` struct (defined in `File_Utilities`) provides fields
including `short_name`, `full_name`, and the control flag
`descend_into_directory`. The `visit_files` procedure returns a `bool`
indicating whether traversal completed without error.

### Path Utilities

Path-related utilities are spread across several modules:

**From `System`:**

```Jai
#import "System";
exe_path := get_path_of_running_executable();
// e.g., "D:/project/build/myprogram.exe"
```

**From `String`:**

```Jai
#import "String";
dir := path_strip_filename(exe_path);
// e.g., "D:/project/build/"
is_abs := is_absolute_path(some_path);
```

The `String` module contains many `path_*` routines for extracting filenames,
extensions, and other path components.

**From `Basic`:**

```Jai
cwd := get_working_directory();
set_working_directory(new_path);
```

### Error Handling Pattern

File operations typically return a `bool` for success. The conventional
patterns:

```Jai
// Pattern 1: if/else
text, success := read_entire_file("file.txt");
if success {
    // use text
} else {
    print("Error reading file.\n");
}

// Pattern 2: early return
text, success := read_entire_file("file.txt");
if !success return;

// Pattern 3: assert
text, success := read_entire_file("file.txt");
assert(success, "Error. Cannot read file.\n");
```

When `read_entire_file` fails, a diagnostic like the following is printed:

```
Could not open file "assets/example.txt": code 2, The system cannot find the file specified.
```

---

## 36. Inline Assembly

OpenJai supports inline assembly through the `#asm` directive for situations
requiring ultimate performance, custom CPU instructions, SIMD parallelism, or
explicit control over code generation. Currently only the x86-64 platform is
supported.

The `#bytes` directive is a related facility that inserts individual bytes into
the program as raw machine code, which could be used to build a custom
assembler.

### `#asm` Blocks

An inline assembly block is introduced with `#asm`:

```Jai
#asm {
    // assembly instructions here
}
```

Statements inside the block follow the form:

```
mnemonic operand, operand, operand, ...
```

where the mnemonic is an x86-64 instruction name (e.g., `add`, `mov`, `mul`)
and operands are variable names, register names, or literal values. The
mnemonics are identical to the official Intel/AMD mnemonics.

Multiple `#asm` blocks may appear throughout OpenJai code.

### Scoping and Variable Interaction

An `#asm` block does **not** define a new scope. OpenJai variables defined in the
enclosing scope are visible inside the block and can be modified:

```Jai
count := 10;
#asm {
    add count, 17;
}
print("%\n", count);  // => 27
```

Variables declared inside an `#asm` block are **not** visible to OpenJai code
outside the block. A variable declared in an `#asm` block cannot be redeclared
in the surrounding OpenJai scope.

### Register Variables

Variables in `#asm` blocks are stored in general-purpose registers (GPRs). The
compiler implements automatic register allocation, so you can use familiar
high-level variable names:

```Jai
#asm {
    var1: gpr;           // explicit declaration
    mov.q var1, 17;      // assign 17

    mov var2: gpr, 10;   // declare and assign (verbose)
    mov var3:, 10;       // declare and assign (inferred type)

    add count, var1;     // use with OpenJai variables
}
```

### Named `#asm` Blocks and Cross-Block References

`#asm` blocks can be named, allowing register variables to be referenced across
blocks:

```Jai
block_1 :: #asm { pxor x:, x; }
block_2 :: #asm { movdqu y:, block_1.x; }
```

Cross-block referencing keeps registers alive across the procedure. LLVM
optimizations may spill them if needed.

### Operand Size Suffixes

Since register names like `ax`/`eax`/`rax` are not used directly, operand sizes
are specified by appending a suffix to the mnemonic:

| Suffix | Size                     | Notes                        |
|--------|--------------------------|------------------------------|
| `.b`   | 8-bit (byte)             |                              |
| `.w`   | 16-bit (word)            |                              |
| `.d`   | 32-bit (double-word)     |                              |
| `.q`   | 64-bit (quad-word)       | Default for scalar ops       |
| `.x`   | 128-bit (xmmword)        | SSE                          |
| `.y`   | 256-bit (ymmword)        | AVX                          |
| `.z`   | 512-bit (zmmword)        | AVX-512                      |

In 64-bit mode, `.q` is the default implicit size for scalar operations. For
vector operations, the default depends on the feature set (`.x` for SSE, `.y`
for AVX, `.z` for AVX-512).

### Data Types

| Type   | Description                                                    |
|--------|----------------------------------------------------------------|
| `gpr`  | General-purpose register. Pool: 8 (32-bit) or 16 (64-bit). Can be pinned with `gpr.a` etc. |
| `imm8` | 8-bit immediate value. (Also `imm16`, `imm32`, `imm64` by size.) |
| `mem`  | Memory operand (e.g., `lea.q [EAX], rax`).                    |
| `str`  | Stack register. Pool: 8. Legacy, used by FPU and MMX.         |
| `vec`  | Vector register for SIMD. Pool: 8 (32-bit), 16 (64-bit pre-AVX-512), 32 (64-bit post-AVX-512). |
| `omr`  | Op-mask register. Only available with AVX-512.                 |

### Registers and Pinning

The allowed register names are: `a`, `b`, `c`, `d`, `sp`, `bp`, `si`, `di`,
or an integer 0--15 (representing SIMD registers `xmm0`--`xmm15`).

The `===` operator pins a variable to a specific register:

```Jai
#asm {
    t: gpr === a;         // pin t to register a (rax)
    u: gpr === c;         // pin u to register c (rcx)
    v: vec === 9;         // pin v to xmm9/ymm9/zmm9
    mov w: gpr === 15, 10; // inline declaration with pinning
}
```

OpenJai variables can also be pinned for instructions that require specific
registers:

```Jai
x: u64 = 197589578578;
y: u64 = 895173299817;
z: u64 = ---;

#asm {
    x === a;  // mul requires operand in register a
    z === d;  // mul puts high bits in register d
    mul z, x, y;
}
```

### Memory Operands

Memory operands use bracket syntax with the format
`[base + index * scale + displacement]`:

- **base** -- required, must be a `gpr`
- **index** -- optional, usually a `gpr` (can be `vec` for some instructions)
- **scale** -- only valid with index; must be 1, 2, 4, or 8 (default 1)
- **displacement** -- optional, a signed 8-bit or 32-bit integer byte offset

The ordering is rigid: `base + index * scale + displacement`.

```Jai
array: [32] u8;
pointer := array.data;
#asm {
    mov a:, [pointer];         // load from pointer
    mov i:, 10;
    mov a,  [pointer + 8];     // with displacement
    mov a,  [pointer + i*1];   // with index and scale
}
```

### Feature Flags

x86 does not have a single instruction set; feature flags indicate which
instruction sets are available. Feature flags can be specified at two levels:

**Global build level:** Set feature bits on
`build_options.machine_options.x86_features.leaves` via `enable_feature` in
`Machine_X64`.

**Per-block level:** List feature flags after `#asm`:

```Jai
#asm AVX, AVX2 {
    // AVX and AVX2 instructions available here
}
```

Per-block flags add to global flags.

Common feature flags include: `AVX`, `AVX2`, `AVX512F`, `MMX`, `SSE3`, and
others listed in the `x86_Feature_Flag` enum in `Machine_X64`.

**Runtime checking:** Use `get_cpu_info()` and `check_feature()` from
`Machine_X64` to detect available instruction sets at runtime:

```Jai
#import "Machine_X64";

cpu_info := get_cpu_info();
if check_feature(cpu_info.feature_leaves, x86_Feature_Flag.AVX2) {
    #asm AVX2 {
        pxor v1:, v1, v1;
    }
} else {
    // fallback path
}
```

### SIMD Operations

SIMD (Single Instruction, Multiple Data) processes multiple data elements in
parallel. The operand size suffix determines the vector width:

```Jai
// SSE: 4 x float32 in parallel (.x = 128-bit)
array := float32.[1, 2, 3, 4];
ptr := array.data;
#asm {
    v: vec;
    movups.x v, [ptr];
    addps.x v, v;
    movups.x [ptr], v;
}
// array is now [2, 4, 6, 8]

// AVX: 8 x float32 in parallel (.y = 256-bit)
array2 := float32.[1, 2, 3, 4, 5, 6, 7, 8];
ptr2 := array2.data;
#asm AVX {
    v2: vec;
    movups.y v2, [ptr2];
    addps.y v2, v2, v2;
    movups.y [ptr2], v2;
}
// array2 is now [2, 4, 6, 8, 10, 12, 14, 16]
```

### Macros and `#asm`

Inline assembly registers can be passed to macro arguments using the `__reg`
type. No additional `mov` instructions are generated; the compiler binds
names to the same underlying register allocation:

```Jai
add_regs :: (c: __reg, d: __reg) #expand {
    #asm {
        add c, d;
    }
}

main :: () {
    #asm {
        mov a:, 10;
        mov b:, 7;
    }
    add_regs(a, b);
    // b now contains 17
}
```

Registers cannot be passed to regular (non-macro) procedures.
`#asm` blocks do not return values.

### Compile-Time Execution

`#asm` blocks can run at compile time like any other OpenJai code. The code is
compiled to machine code once and runs at native speed:

```Jai
do_some_work :: (a: int, b: int) -> int {
    #asm { add a, b; }
    return a;
}

A :: #run do_some_work(10, 13);  // A == 23
```

### Current Limitations

- Only x86-64 is supported (other instruction sets planned for the future).
- No goto, jump, or branch instructions.
- No NOP (no-operation) instruction.
- No call instructions; functions cannot be called from within an `#asm` block.
- `#asm` blocks do not return values.

Use OpenJai for control flow (jumps, branches, function calls) around `#asm`
blocks.

### The `Machine_X64` Module

The `Machine_X64` module provides useful routines for 64-bit Intel/AMD x86
machines:

- `prefetch` -- begins a memory fetch before the data is needed
  (e.g., `prefetch(array.data, Prefetch_Hint.T0)`).
- `mfence` -- memory fence; serializes all prior load/store instructions.
- `pause` -- spin-loop hint.
- `get_cpu_info` -- retrieves CPU information and checks feature flag support.
- `x86_Feature_Flag` -- enum listing all available feature flags.

### Standard Library Usage

Inline assembly is used in several standard modules:

- `Basic` -- Apollo Time internals.
- `Atomics` -- e.g., `lock_xchg` for `atomic_swap`.
- `Bit_Operations` -- bit manipulation routines.
- `Runtime_Support` -- low-level runtime support.

---

## 37. Integrated Build System

OpenJai has a built-in build system. There are no external build tools -- no
makefiles, no CMake, no Ninja. The compiler itself is the build system, and
build configuration is written in OpenJai. All you need to compile a OpenJai project
is the OpenJai compiler.

A **meta-program** (conventionally named `build.OpenJai` or `first.OpenJai`) is a OpenJai
program that runs at compile time and communicates with the compiler to control
how the target program is built. The meta-program has access to:

- Syntax trees representing every procedure.
- The types of all variables and all expressions.
- Information about which declaration each identifier binds to.

Most build-system procedures are defined in the `Compiler` module.

### Three Ways to Build

1. **Use the default metaprogram:**
   `OpenJai main.OpenJai -optional_flags`
   The `Default_Metaprogram` translates command-line flags into build options.

2. **Write a custom build program:**
   `OpenJai build.OpenJai`
   The build program is itself a metaprogram that adds the target source files
   and configures compilation.

3. **Replace the default metaprogram with a module:**
   `OpenJai main.OpenJai -- meta Build`
   The `Build` module (in `OpenJai/modules` or a custom module directory) replaces
   `Default_Metaprogram`. Use `-- import_dir "path"` to specify a custom
   module directory.

The compiler accepts either `--` or `---` as the delimiter for hardcoded
compiler arguments.

### Workspaces

A `Workspace` is defined in module `Preload` as: `Workspace :: s64;`

Each workspace represents a completely separate compilation environment. One
workspace does not affect another. When the compiler starts:

- **Workspace 1** -- created for the default metaprogram.
- **Workspace 2** -- created for the target program (the file on the
  command line).

A build metaprogram creates additional workspaces for each program it builds:

```Jai
#import "Basic";
#import "Compiler";

build :: () {
    w2 := get_current_workspace();
    print("The current workspace is %\n", w2);  // => 2

    w3 := compiler_create_workspace();
    if !w3 {
        print("Workspace creation failed.\n");
        return;
    }
    print("The workspace w3 is %\n", w3);       // => 3
}
```

- `get_current_workspace()` returns the current workspace. Returns `0` at
  run-time.
- `compiler_create_workspace()` creates a new workspace. Can only be called
  at compile time. Returns a `Workspace` value (or `0` on failure). An
  optional string argument names the workspace:
  `compiler_create_workspace("Workspace 4")`.

A build file can instantiate multiple workspaces to build different kinds of
binaries (executables, static/dynamic libraries). Each build is completely
separate from all the others.

### Source File Location Directives

Several directives provide file location information, usable both at run-time
and during compilation:

| Directive            | Description |
|----------------------|-------------|
| `#file`              | The complete path (including filename) of the current source file. |
| `#line`              | The line number where this directive appears. |
| `#filepath`          | The path to the current file, without the filename. Can be a remote filepath. |
| `#location(code)`    | Given a `Code` value, extracts the full path and line number of that code. |
| `#caller_location`   | Used as a default parameter value; provides the line number from where a procedure is called. |

```Jai
add :: (x: int, y: int, loc := #caller_location) -> int {
    print("add was called from line %.\n", loc.line_number);
    return x + y;
}

main :: () {
    print("In file % line %\n", #file, #line);
    print("Filepath is %\n", #filepath);
    loc := #location(code);
    print("Code at %:%\n", loc.fully_pathed_filename, loc.line_number);
    add(2, 4);
}
```

When using or setting file paths in OpenJai, always use the forward slash `/` as
the path separator, even on Windows.

### A Minimal Build File

#### Compiling with `add_build_file`

```Jai
#import "Basic";
#import "Compiler";

build :: () {
    w := compiler_create_workspace();
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    target_options := get_build_options(w);
    target_options.output_executable_name = "program";
    set_build_options(target_options, w);

    add_build_file(tprint("%/main.OpenJai", #filepath), w);

    set_build_options_dc(.{do_output=false});
}

main :: () {}

#run build();
```

The build process:

1. **Create a workspace** with `compiler_create_workspace()`.
2. **Get build options** with `get_build_options(w)`, which returns a
   `Build_Options` struct.
3. **Configure options** (e.g., set the output executable name).
4. **Write options back** with `set_build_options(target_options, w)`.
5. **Add source files** with `add_build_file("path/to/file.OpenJai", w)`. The
   path can be constructed with `tprint` and `#filepath`. The compiler
   automatically builds any files included with `#load`.
6. **Suppress build-program output** with
   `set_build_options_dc(.{do_output=false})`. The `_dc` suffix means
   "During Compile." Without this line, the build program itself also
   produces an executable.

To also suppress generated string output, add:
`set_build_options_dc(.{write_added_strings=false});`

The meta-program `build.OpenJai` must have an empty `main :: () {}` to avoid a
"No entry point" compiler error.

The use of a `build()` function is not mandatory -- a build file can simply
be a `#run { ... }` block.

#### Compiling with `add_build_string`

Instead of adding source files, the target program can be provided as a
string:

```Jai
#import "Basic";
#import "Compiler";

TARGET_PROGRAM_TEXT :: #string DONE
#import "Basic";

main :: () {
    print("This program was built with a meta-program.\n");
}
DONE

build :: () {
    w := compiler_create_workspace();
    target_options := get_build_options(w);
    target_options.output_executable_name = "build_string";
    set_build_options(target_options, w);
    add_build_string(TARGET_PROGRAM_TEXT, w);
    set_build_options_dc(.{do_output=false});
}

main :: () {}

#run build();
```

`add_build_string` adds a string as a piece of code to the program. The
first argument is the code string, the second is the workspace. The code
string can be generated by meta-programming at compile time. The program can
be split across multiple strings with multiple `add_build_string` calls.

### The `#placeholder` Directive

`#placeholder` tells the compiler that a particular symbol will be
defined/generated by the compile-time meta-program:

```Jai
#import "Basic";

#placeholder TRUTH;

#run {
    #import "Compiler";
    options := get_build_options();
    add_build_string("TRUTH :: true;", -1);
}

main :: () {
    print("TRUTH is %, is it a constant? %\n", TRUTH, is_constant(TRUTH));
    // => TRUTH is true, is a constant? true
}
```

The workspace argument `-1` indicates the current workspace. Note that
`#import "Compiler"` can be placed inside a `#run` block.

### Build Options (`Build_Options`)

The `Build_Options` struct (defined in the `Compiler` module) contains
approximately 45 configurable options for controlling compilation. Options are
retrieved with `get_build_options(w)`, modified, and written back with
`set_build_options(target_options, w)`.

Build options can be printed for inspection:

```Jai
format := *context.print_style.default_format_struct;
format.use_newlines_if_long_form = true;
format.indentation_width = 4;
print("Build_Options for Workspace % are: %\n", w, target_options);
```

All build scripting is done within the language itself, in the same
environment as the rest of the code. This makes the build process
**cross-platform** and **consistent**.

#### Optimization Level

Set with the `set_optimization` procedure:

```Jai
set_optimization(*target_options, Optimization_Type.DEBUG, true);
set_optimization(*target_options, Optimization_Type.OPTIMIZED);
```

`Optimization_Type` enum values (from the `Compiler` module):

| Value                    | Description |
|--------------------------|-------------|
| `DEBUG` (0)              | Debug build (default). |
| `VERY_DEBUG` (1)         | Extra debug facilities. |
| `OPTIMIZED` (2)          | Release optimization. |
| `VERY_OPTIMIZED` (3)     | Aggressive optimization. |
| `OPTIMIZED_SMALL` (4)    | Optimize for size. |
| `OPTIMIZED_VERY_SMALL` (5) | Aggressively optimize for size. |

Optimized builds take ~10x longer to compile than debug builds, but produce
executables ~2x faster. Optimization automatically turns off all runtime
checks and enables LLVM code-production optimizations.

Most optimization settings in `Build_Options` are automatically configured by
`set_optimization` -- in a normal program, `set_optimization` is sufficient.

- Enable bytecode inlining: `target_options.enable_bytecode_inliner = true;`
- Stop generating `.pdb` files: `target_options.emit_debug_info = .NONE;`

#### Output Type

`target_options.output_type` controls what is produced:

| Value              | Description |
|--------------------|-------------|
| `.EXECUTABLE`      | Default. Produces an executable. |
| `.DYNAMIC_LIBRARY` | Produces a dynamic library (`.dll` / `.so`). |
| `.STATIC_LIBRARY`  | Produces a static library. |
| `.OBJECT_FILE`     | Produces an object file. |
| `.NO_OUTPUT`       | No output. |

#### Output Executable Name

`target_options.output_executable_name` sets the filename of the output
executable (no extension).

#### Output Path

`target_options.output_path` sets the directory where the executable and
other compiler artifacts (e.g., `.pdb`) are written.

The `set_build_file_path` procedure also sets the output directory:
`set_build_file_path("./");` (current folder is the default).

#### Import Path

To import modules from a directory other than the standard `OpenJai/modules`:

```Jai
import_path: [..] string;
array_add(*import_path, ..target_options.import_path);
array_add(*import_path, "d:\\OpenJai\\my_modules");
target_options.import_path = import_path;
```

#### Backend

`target_options.backend` selects the code-generation backend:

| Value   | Description |
|---------|-------------|
| `.LLVM` | LLVM backend (default). Slower compilation, optimized output. |
| `.X64`  | Custom x64 backend. Fastest compilation, no optimization. |

#### Stack Traces and Crash Backtraces

- `target_options.stack_trace` -- `true` by default. Set to `false` for
  release builds.
- `target_options.backtrace_on_crash` -- `.ON` by default.

#### Runtime Checks

```Jai
target_options.array_bounds_check = .ON;          // .OFF / .ON / .ALWAYS
target_options.cast_bounds_check  = .FATAL;        // .FATAL / .NONFATAL
target_options.null_pointer_check = .ON;
target_options.relative_pointer_bounds_check = .ON;
```

These checks increase robustness and are enabled by default. Turn them `.OFF`
for performance in production when confident in correctness.

#### Storageless Type Info

```Jai
target_options.runtime_storageless_type_info = true;
```

When `true`, the type table is not available at run-time, reducing executable
size. You can still use `Type_Info` and the `type_info` function, but the
full type table data is not included. Default is `false`. Useful for embedded
systems.

#### Dead Code Elimination

```Jai
target_options.dead_code_elimination = .ALL;   // default: dead code is eliminated
target_options.dead_code_elimination = .NONE;  // disable DCE
```

By default, code that is never called at run-time is not compiled. A
procedure that would produce a compile error when called produces no error if
it is never called. Dead code elimination can also be disabled with the
`-no_dce` command-line option.

#### LLVM and x64 Backend Options

`target_options.llvm_options` provides fine-grained control over the LLVM
backend:

```Jai
target_options.llvm_options.enable_tail_calls = false;
target_options.llvm_options.enable_loop_unrolling = false;
target_options.llvm_options.enable_slp_vectorization = false;
target_options.llvm_options.enable_loop_vectorization = false;
target_options.llvm_options.verify_input = false;
target_options.llvm_options.verify_output = false;
target_options.llvm_options.merge_functions = false;
```

The LLVM optimization level (`-O1`, `-O2`, `-O3`) is set via:
`target_options.llvm_options.code_gen_optimization_level = 2;`

`X64_Options` exists for the x64 backend but requires deeper knowledge of
that backend.

#### Suppressing Compiler Messages

```Jai
target_options.text_output_flags = 0;
```

This disables most text output from the compiler for a cleaner build.

### Debug and Release Build Pattern

A single build file can contain both debug and release configurations:

```Jai
#import "Basic";
#import "Compiler";

build_debug :: () {
    // debug compile options ...
}

build_release :: () {
    // release compile options ...
}

main :: () {}

#run build_debug();
// #run build_release();
```

To build for release, either change the `#run` call or use the command line:
`OpenJai build.OpenJai -run build_release()`

### Replacing the Default Metaprogram

To use a custom metaprogram module (e.g., named `Build`):

1. Create a module directory `Build/` containing `module.OpenJai`.
2. `module.OpenJai` must contain a `build()` procedure and `#run build()`. It
   should **not** contain a `main` procedure.
3. Place the module in `OpenJai/modules` or a custom directory.

Invoke it with:

```
OpenJai main.OpenJai -- meta Build
```

Or with a custom module directory:

```
OpenJai main.OpenJai -- import_dir "d:/OpenJai/my_modules" meta Build
```

The `Minimal_Metaprogram` module in the standard distribution can serve as a
starting point. If using plugins, refer to `Default_Metaprogram` for the
plugin callback structure (see §4, Plugins).

### Compiler Message Loop

The compiler message loop gives the meta-program direct access to the
compiler's internal events during compilation. This is used for inspecting
code, enforcing coding standards, generating code, and taking actions based on
compilation results.

#### Setting Up the Message Loop

To intercept compiler messages for a workspace, call
`compiler_begin_intercept(w)` before adding source files and
`compiler_end_intercept(w)` after the message loop completes:

```Jai
#import "Basic";
#import "Compiler";

build :: () {
    w := compiler_create_workspace();
    if !w { print("Workspace creation failed.\n"); return; }

    target_options := get_build_options(w);
    target_options.output_executable_name = "program";
    set_build_options(target_options, w);

    compiler_begin_intercept(w);
    add_build_file(tprint("%/main.OpenJai", #filepath), w);
    message_loop();
    compiler_end_intercept(w);
}

message_loop :: () {
    while true {
        message := compiler_wait_for_message();
        if !message break;
        if message.kind == {
            case .COMPLETE;
                break;
        }
    }
}

main :: () {}

#run build();
```

- `compiler_begin_intercept(w)` -- starts receiving compiler messages from
  workspace `w`.
- `compiler_wait_for_message()` -- blocks until the next compiler message is
  available. Returns a `*Message`.
- `compiler_end_intercept(w)` -- stops receiving messages for workspace `w`.

#### Message Kinds

Each message has a `kind` field. The possible values:

| Kind            | Description |
|-----------------|-------------|
| `.FILE`         | A source code file was loaded. Cast to `*Message_File` to access `fully_pathed_filename`. |
| `.IMPORT`       | A module was imported. Cast to `*Message_Import` to access `module_name`, `module_type`, `fully_pathed_filename`. Each module is imported only once regardless of how many `#import` statements reference it. |
| `.PHASE`        | The compiler entered a new compilation phase. Cast to `*Message_Phase` to access the `phase` field. See "Compilation Phases" below. |
| `.TYPECHECKED`  | Code has passed typechecking. Cast to `*Message_Typechecked` to access `declarations`, `structs`, and `all` (an array of all typechecked items). |
| `.DEBUG_DUMP`   | A crash occurred during compilation. Cast to `*Message_Debug_Dump` to access `dump_text`. |
| `.ERROR`        | An error occurred during compilation. |
| `.COMPLETE`     | Compilation is finished. Cast to `*Message_Complete` to access `error_code` (0 on success). Always `break` out of the message loop on this message. |

To cast a message to its specific type:

```Jai
message_file := cast(*Message_File) message;
message_phase := cast(*Message_Phase) message;
message_typechecked := cast(*Message_Typechecked) message;
message_complete := cast(*Message_Complete) message;
```

#### Compilation Phases

The `.PHASE` message's `phase` field is an enum:

```Jai
phase: enum u32 {
    ALL_SOURCE_CODE_PARSED        :: 0;
    TYPECHECKED_ALL_WE_CAN        :: 1;
    ALL_TARGET_CODE_BUILT         :: 2;
    PRE_WRITE_EXECUTABLE          :: 3;
    POST_WRITE_EXECUTABLE         :: 4;
    READY_FOR_CUSTOM_LINK_COMMAND :: 5;
}
```

Key uses:

- **`TYPECHECKED_ALL_WE_CAN`** -- all typechecking is complete. To use OpenJai
  as a type-checker only (no compilation), exit after this phase. To generate
  code based on typechecked results (e.g., from notes), generate it after this
  phase using `add_build_string`.
- **`PRE_WRITE_EXECUTABLE`** -- occurs after all typecheck data is received
  but before the `.COMPLETE` message. Use this phase to output information
  gathered during compilation (avoids overlap with the compiler's own
  diagnostic output).
- **`POST_WRITE_EXECUTABLE`** -- occurs after the executable is written. The
  `Message_Phase` struct has `executable_write_failed` (bool),
  `executable_name` (string), and `linker_exit_code` fields available in
  this phase.

### Compile-Time Command-Line Arguments

Arguments after the `-` separator on the `OpenJai` command line are passed to the
meta-program as **compile-time command-line arguments**. They are accessed
through `Build_Options.compile_time_command_line`, which is an `[] string`:

```Jai
target_options := get_build_options(w);
args := target_options.compile_time_command_line;
```

For the command `OpenJai build.OpenJai - run`, `args` contains:
`["build.OpenJai", "-", "run"]`

A space is required between `-` and the arguments. Without it, the compiler
interprets the text as a flag (e.g., `-run` is a compiler flag, not a
metaprogram argument).

#### Pattern: Conditional Run on Success

```Jai
#import "Process";

success := false;
run_on_success := false;

build :: () {
    w := compiler_create_workspace();
    if !w return;

    target_options := get_build_options(w);
    for target_options.compile_time_command_line {
        if it == "run" then run_on_success = true;
    }
    target_options.output_executable_name = "myprogram";
    set_build_options(target_options, w);

    compiler_begin_intercept(w);
    add_build_file("main.OpenJai", w);
    while true {
        message := compiler_wait_for_message();
        if !message break;
        if message.kind == .COMPLETE {
            mc := cast(*Message_Complete) message;
            success = mc.error_code == 0;
            break;
        }
    }
    compiler_end_intercept(w);

    if success && run_on_success {
        run_command(target_options.output_executable_name);
    }
}
```

Invoke with: `OpenJai build.OpenJai - run`

The `Process` module provides `run_command` for executing external programs.

#### Pattern: Debug/Release Build Selection

```Jai
build_debug :: (w: Workspace) {
    target_options := get_build_options(w);
    target_options.backend = .X64;
    set_optimization(*target_options, Optimization_Type.DEBUG, true);
    set_build_options(target_options, w);
}

build_release :: (w: Workspace) {
    target_options := get_build_options(w);
    target_options.backend = .LLVM;
    set_optimization(*target_options, Optimization_Type.VERY_OPTIMIZED);
    set_build_options(target_options, w);
}

#run {
    w := compiler_create_workspace("workspace");
    if !w return;
    target_options := get_build_options(w);
    for arg: target_options.compile_time_command_line {
        if arg == {
            case "debug";   build_debug(w);
            case "release"; build_release(w);
        }
    }
    add_build_file("main.OpenJai", w);
}
```

Invoke with: `OpenJai build.OpenJai - debug` or `OpenJai build.OpenJai - release`

Recommended settings:

- **Debug:** `backend = .X64` and `Optimization_Type.DEBUG`. The x64 backend
  is faster to compile. Debug builds include line-number crash reports and
  array bounds checking but have runtime overhead.
- **Release:** `backend = .LLVM` and `Optimization_Type.VERY_OPTIMIZED`. The
  LLVM backend is slower to compile but produces heavily optimized code.
  Release builds omit debug information.

### Enforcing Coding Standards

The compiler message loop can enforce project-specific coding rules at compile
time. During the `.TYPECHECKED` phase, code declarations and subexpressions
can be inspected programmatically. Violations are reported with
`compiler_report`, which emits a compiler error with source location:

```Jai
compiler_report("Too many levels of pointer indirection.\n", location);
```

The `make_location` procedure extracts a source location from a
`Code_Declaration` for use with `compiler_report`.

Example: enforcing the MISRA 17.5 rule (no more than 2 levels of pointer
indirection):

```Jai
misra_checks :: (message: *Message) {
    check_pointer_level :: (decl: *Code_Declaration) {
        type := decl.type;
        pointer_level := 0;
        while type.type == .POINTER {
            pointer_level += 1;
            p := cast(*Type_Info_Pointer) type;
            type = p.pointer_to;
        }
        if pointer_level > 2 {
            compiler_report("Too many levels of pointer indirection.\n",
                make_location(decl));
        }
    }

    if message.kind != .TYPECHECKED return;
    code := cast(*Message_Typechecked) message;
    for code.declarations {
        check_pointer_level(it.expression);
    }
    for tc: code.all {
        expr := tc.expression;
        if expr.enclosing_load {
            if expr.enclosing_load.enclosing_import.module_type != .MAIN_PROGRAM
                continue;
        }
        for tc.subexpressions {
            if it.kind == .DECLARATION {
                check_pointer_level(cast(*Code_Declaration) it);
            }
        }
    }
}
```

The check is injected into the message loop:

```Jai
while true {
    message := compiler_wait_for_message();
    if !message break;
    misra_checks(message);
    if message.kind == .COMPLETE break;
}
```

The `enclosing_load.enclosing_import.module_type` check restricts enforcement
to the main program, skipping imported modules.

### Generating LLVM Bitcode

To produce LLVM bitcode (`.bc` files) alongside the executable:

```Jai
target_options.llvm_options.output_bitcode = true;
```

By default, bitcode is written to the `.build` folder. Change the output
location with:

```Jai
target_options.intermediate_path = #filepath;   // same directory as source
target_options.intermediate_path = "path/to/dir";
```

The bitcode can be converted to assembly with LLVM's `llc`:

```
llc < your_bitcode.bc > output.asm
as output.asm
```

### Using Notes in the Build Process

Notes (annotations like `@fruit`) attached to procedures or structs (see §15)
are visible during compilation in the `.TYPECHECKED` message. The
meta-program can inspect them via `decl.expression.notes` and generate code
accordingly.

```Jai
case .TYPECHECKED;
    typechecked := cast(*Message_Typechecked) message;
    for decl: typechecked.declarations {
        for note: decl.expression.notes {
            if equal(note.text, "fruit") {
                array_add(*procs, copy_string(decl.expression.name));
            }
        }
    }
```

After the `TYPECHECKED_ALL_WE_CAN` phase, collected information can be used
to generate new code with `add_build_string`:

```Jai
case .PHASE;
    phase := cast(*Message_Phase) message;
    if phase.phase == .TYPECHECKED_ALL_WE_CAN {
        code := generate_main_procedure();
        add_build_string(code, w);
    }
```

This pattern enables generating entire procedures (such as a `main` that
calls all `@fruit`-annotated procedures in alphabetical order) from metadata
attached to declarations.

Iterating over typechecked structs is also possible with
`message_typechecked.structs`, which can be used to find all subclasses of
a base type.

### Building Dynamic Libraries

To build a dynamic library (`.dll` on Windows, `.so` on Linux), set the
output type:

```Jai
target_options.output_type = .DYNAMIC_LIBRARY;
target_options.output_executable_name = "dynlib";
```

Functions exported from the dynamic library must use `#program_export`:

```Jai
#program_export
dll_func :: () #no_context {
    write_string("Hello Sailor!\n");
}
```

If the library will be called from another language (not OpenJai), also add
`#c_call` and push a fresh context inside the function body.

To use the dynamic library from another OpenJai program, declare the library with
`#library,no_static_library` and the function with `#elsewhere`:

```Jai
dynlib :: #library,no_static_library "dynlib";
dll_func :: () #no_context #elsewhere dynlib;

main :: () {
    dll_func();
}
```

- `#library,no_static_library` -- declares a dynamic library without
  requiring a static import library (`.lib`).
- `#elsewhere` -- declares that the procedure's implementation exists in the
  specified library, not in the current compilation unit.

A build file can build both the dynamic library and the executable that uses
it by creating separate workspaces:

```Jai
build :: () {
    // Build the DLL
    {
        w := compiler_create_workspace();
        options := get_build_options(w);
        options.output_type = .DYNAMIC_LIBRARY;
        options.output_executable_name = "dynlib";
        set_build_options(options, w);

        compiler_begin_intercept(w);
        add_build_file("dynlib.OpenJai", w);
        while true {
            message := compiler_wait_for_message();
            if !message break;
            if message.kind == .COMPLETE {
                mc := cast(*Message_Complete) message;
                if mc.error_code != .NONE {
                    print("DLL compilation failed.\n");
                    return;
                }
                break;
            }
        }
        compiler_end_intercept(w);
    }

    // Build the executable
    {
        w := compiler_create_workspace();
        options := get_build_options(w);
        options.output_executable_name = "main_program";
        set_build_options(options, w);
        add_build_file("main.OpenJai", w);
    }

    set_build_options_dc(.{do_output=false});
}
```

### Adding Binary Data to the Executable

The `add_global_data` procedure bakes binary data into the final executable
at compile time. This is useful for distributing standalone executables that
do not require external data files:

```Jai
main :: () {
    data :: #run add_global_data(
        xx read_entire_file("pixel.png"),
        .READ_ONLY,
    );
    print("Embedded data size: %\n", data.count);
}
```

- The first argument is the data as `[] u8`.
- The second argument is a `Data_Segment_Index` (e.g., `.READ_ONLY`).
- Data can be baked into different data segments if needed.
- The `xx` operator autocasts the data to the expected `[] u8` type.

Data can also be constructed from hex string literals joined at compile time:

```Jai
data :: #run add_global_data(
    xx join("\x01\x02\x03", "\x04\x05\x06"),
    .READ_ONLY,
);
```

### Bindings Generation

The `Bindings_Generator` module automates the creation of OpenJai FFI bindings
from C/C++ header files (see also §6). The generated output contains only
OpenJai declarations (procedure signatures, struct definitions, enum definitions)
-- not translated function bodies. OpenJai calls the compiled C/C++ code through
`#foreign`.

#### Basic Usage

```Jai
#import "Bindings_Generator";

generate_bindings :: () -> bool {
    opts: Generate_Bindings_Options;
    array_add(*opts.libpaths, ".");
    array_add(*opts.libnames, "mylib");
    array_add(*opts.source_files, "mylib.h");
    array_add(*opts.system_include_paths, GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH);
    array_add(*opts.extra_clang_arguments, "-x", "c++", "-DWIN32_LEAN_AND_MEAN");
    return generate_bindings(opts, "output.OpenJai");
}
```

`Generate_Bindings_Options` fields include:

| Field                    | Description |
|--------------------------|-------------|
| `libpaths`               | Directories to search for libraries. |
| `libnames`               | Library names to link against. |
| `source_files`           | C/C++ header files to process. |
| `include_paths`          | Additional include directories for headers. |
| `system_include_paths`   | System include directories. Use `GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH`. |
| `extra_clang_arguments`  | Extra arguments passed to the clang parser (e.g., `-x c++`). |
| `strip_flags`            | Flags controlling what to strip from the output (e.g., `.INLINED_FUNCTIONS`). |
| `header`                 | A string prepended to the output file (e.g., type definitions for missing types). |

The output file (e.g., `windows.OpenJai`) is auto-generated and overwritten on
each generation. Platform-specific output files are typically named by OS
(`windows.OpenJai`, `linux.OpenJai`, `macos.OpenJai`) and conditionally loaded with
`#if OS == .WINDOWS { #load "windows.OpenJai"; }`.

#### Building C++ Libraries

The `BuildCpp` module provides `build_cpp_dynamic_lib` for compiling C++
source into a dynamic library as part of the build:

```Jai
#import "BuildCpp";
success := build_cpp_dynamic_lib("cpp_library", "cpp_library.cpp", debug=true);
```

#### Setting Workspace Failure Status

If bindings generation or library compilation fails, use
`compiler_set_workspace_status(.FAILED)` to signal failure:

```Jai
if !generate_bindings() {
    compiler_set_workspace_status(.FAILED);
    return;
}
```

#### Bytecode Inlining

Bytecode inlining can be enabled for improved performance:

```Jai
target_options.enable_bytecode_inliner = true;
```

---

## 38. Concurrency (Threads)

OpenJai exposes OS-level threading through the `Thread` module, providing
platform-independent thread routines, mutexes, semaphores, and a thread-group
facility.

Each thread receives its own `Context`, including a separate
`Temporary_Storage`, so threads do not need to synchronize over temporary
allocations. The `context.thread_index` field distinguishes threads (the main
thread is index 0).

### Creating and Running Threads

A thread is represented by the `Thread` struct (defined in the `Thread`
module). Create, initialize, start, and clean up a thread as follows:

```Jai
#import "Thread";

thread_proc :: (thread: *Thread) -> s64 {
    // ... do work ...
    return 0;
}

main :: () {
    thread1 := New(Thread);
    thread_init(thread1, thread_proc);
    defer { thread_deinit(thread1); free(thread1); }
    thread_start(thread1);
    while !thread_is_done(thread1) { }
}
```

Key procedures:

- **`thread_init`** -- initializes thread data (does **not** start it):
  ```
  thread_init :: (thread: *Thread, proc: Thread_Proc,
                  temporary_storage_size: s32 = 16384,
                  starting_storage: *Temporary_Storage = null) -> bool
  ```
  The `Thread_Proc` type is `(thread: *Thread) -> s64`.

- **`thread_start`** -- begins execution: `thread_start :: (thread: *Thread)`
- **`thread_is_done`** -- returns whether a thread has finished.
- **`thread_deinit`** -- cleans up thread resources; call before `free`.
- **`sleep_milliseconds`** -- suspends the calling thread for the given
  duration.

### Thread Groups

A `Thread_Group` launches a pool of threads that process work items
asynchronously. Only one procedure (the `Thread_Group_Proc`) executes across
all threads in the group.

```
Thread_Group_Proc :: #type (group: *Thread_Group, thread: *Thread,
                            work: *void) -> Thread_Continue_Status;
```

`Thread_Continue_Status` values:

| Value       | Effect                         |
|-------------|--------------------------------|
| `.CONTINUE` | Thread continues to run        |
| `.STOP`     | Thread terminates              |

Thread-group procedures:

- **`init`** -- initializes the group:
  ```
  init :: (group: *Thread_Group, num_threads: s32,
           group_proc: Thread_Group_Proc, enable_work_stealing := false)
  ```
- **`start`** -- starts all threads: `start :: (group: *Thread_Group)`
- **`add_work`** -- enqueues a work item:
  ```
  add_work :: (group: *Thread_Group, work: *void, logging_name := "")
  ```
- **`get_completed_work`** -- retrieves completed work items as a list of
  `*void` pointers (cast back to the original work struct).
- **`shutdown`** -- stops all threads; call before program exit.

The `logging` field on `Thread_Group` controls debug output
(`thread_group.logging = true` enables verbose work-assignment tracing).
Work stealing can be enabled via `enable_work_stealing` at init time.

#### Passing Data to and from Threads

Define a struct for both input and output. Pass a pointer to it via
`add_work`, cast it back inside the `Thread_Group_Proc`, and write results
into the struct:

```Jai
Work :: struct {
    count:  int;
    result: int;
}

thread_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    w := cast(*Work) work;
    sum := 0;
    for i: 0..w.count  sum += i;
    w.result = sum;
    return .CONTINUE;
}
```

Retrieve results with `get_completed_work` in the main thread.

#### Polling for Partial Results

```Jai
work_remaining := NUM_WORK_ITEMS;
while work_remaining > 0 {
    sleep_milliseconds(10);
    results := get_completed_work(*thread_group);
    for results { /* process */ }
    work_remaining -= results.count;
    reset_temporary_storage();
}
```

#### Determining Thread Count

Use `get_number_of_processors()` from the `System` module. On Windows and
Linux the value reports hyper-threads, so divide by 2. Reserve one thread for
the main thread and start at least 2:

```Jai
#import "System";

num_cpus := get_number_of_processors();
#if (OS == .WINDOWS) || (OS == .LINUX)  num_cpus /= 2;
num_threads := max(num_cpus - 1, 2);
```

### Mutexes

A `Mutex` (mutual exclusion object) serializes access to shared resources.
The `Mutex` struct is provided by the `Thread` module.

```Jai
mutex1: Mutex;

init(*mutex1, "Critical");
{
    lock(*mutex1);
    defer unlock(*mutex1);
    // ... critical section ...
}
```

Key procedures: `init`, `lock`, `unlock`.

#### Mutex Ordering

Mutexes can be assigned a numeric order as a third argument to `init`:

```Jai
init(*mutex_A, "A", 1);
init(*mutex_B, "B", 2);
init(*mutex_C, "C", 3);
```

When the `Thread` module is imported with `DEBUG=true`, the runtime enforces
that mutexes are locked in strictly **descending** order (e.g., 3 then 2 then
1). Locking in ascending order triggers an assertion failure:

```
Attempt to lock mutexes out of order.
While we had already locked 'B' at order 2 ...
We tried to lock 'C' at order 3 ...
Lock order must strictly decrease, so this is invalid.
```

Mutexes with no explicit order (default -1) are not checked. Out-of-order
unlocking is also detected. This ordering discipline prevents deadlocks,
since deadlocks require two mutexes to be acquired in opposite order by
different threads.

*(Note: the `DEBUG` parameter was temporarily disabled starting from beta
v0.1.055b.)*

---

## 39. Process Management

The `Process` module provides procedures for starting, ending, writing to, and
reading from OS processes. Usage requires `#import "Process";`.

### Running a Command

The `run_command` procedure starts a process and optionally captures its output:

```Jai
run_command :: (args: .. string, working_directory := "", capture_and_return_output := false,
    print_captured_output := false, timeout_ms := -1,
    arg_quoting := Process_Argument_Quoting.QUOTE_IF_NEEDED) ->
    (process_result: Process_Result, output_string := "", error_string := "", timeout_reached := false);
```

All parameters except `args` have default values. Return values need not be
captured. Simplest usage:

```Jai
run_command("./my_program");
```

### Creating a Process

For more control, `create_process` creates a process handle that can be
written to and read from:

```Jai
create_process :: (process: *Process, args: .. string, working_directory := "",
    capture_and_return_output := false, arg_quoting := Process_Argument_Quoting.QUOTE_IF_NEEDED,
    kill_process_if_parent_exits := true) -> success: bool;
```

Usage pattern:

```Jai
process: Process;
if !create_process(*process, "my_command") {
    print("Error creating process, exiting...\n");
    exit(-1);
}
```

### Writing to a Process

```Jai
write_to_process :: (process: *Process, data: [] u8) -> success: bool, bytes_written: int;
```

Writes an array of bytes to a process's standard input.

### Reading from a Process

```Jai
read_from_process :: (process: *Process, output_buffer: [] u8, error_buffer: [] u8, timeout_ms := -1)
    -> success: bool, output_bytes: int, error_bytes: int;
```

Reads from a process's standard output and standard error into separate
buffers. An optional timeout (in milliseconds) controls how long to wait;
`-1` means wait indefinitely.

---

## 40. Graphics and Multimedia

OpenJai's standard distribution includes modules for graphics, windowing, input
handling, UI, and audio. These provide bindings to established libraries (SDL2,
OpenGL, Direct3D, GLFW, Vulkan) as well as OpenJai-native higher-level frameworks
(Simp, GetRect).

### Available Graphics Bindings

The distribution includes bindings for:

- **OpenGL** (`GL` module) -- cross-platform graphics API
- **SDL2** (`SDL` module) -- cross-platform windowing, input, and graphics
- **GLFW** (`glfw` module) -- lightweight OpenGL/Vulkan windowing (removed
  after v0.1.027)
- **Direct3D 11/12** (`d3d11`, `d3d12` modules) -- Windows graphics APIs
- **Vulkan** -- successor to OpenGL
- **ImGui**, **nvt**, **stb_image** and other stb_ libraries
- **Metal** module (untested)

OpenGL is platform-independent but requires a platform library (SDL, GLFW,
etc.) to create a window and OpenGL context.

### Window_Creation Module

The `Window_Creation` module provides platform-independent window creation:

```Jai
#import "Window_Creation";

window := create_window(width, height, "Window Title");
```

`create_window` accepts `width: s32`, `height: s32`, and `window_name: string`
parameters (among others) and returns a `Window_Type` handle.

Additional procedures:

| Procedure | Description |
|-----------|-------------|
| `create_window` | Creates a platform window and returns a `Window_Type` handle. |
| `get_window_resizes` | Returns an iterable of resize events; each has `.window`, `.width`, `.height` fields. |
| `get_render_dimensions` | Returns `(width, height)` for a given window. |
| `get_mouse_pointer_position` | Returns mouse cursor position for a given window. Accepts a `Window_Type` and an optional boolean parameter. Usage: `mouse_x, mouse_y := get_mouse_pointer_position(win, true);` |

### Input Module

The `Input` module provides platform-independent keyboard and mouse input:

```Jai
#import "Input";

update_window_events();     // poll OS for new events
for events_this_frame {     // iterate over events this frame
    if it.type == .QUIT  ...
    if it.type == .KEYBOARD {
        if it.key_pressed  ...
        if it.key_code == .ESCAPE  ...
    }
}
```

Event types include `.QUIT` and `.KEYBOARD`. Keyboard events have
`key_pressed` (whether the key was pressed vs released) and `key_code` fields.

Known key codes include:

- Arrow keys: `.ARROW_UP`, `.ARROW_DOWN`, `.ARROW_LEFT`, `.ARROW_RIGHT`
- `.ESCAPE`
- Mouse buttons (exposed as keyboard events): `.MOUSE_BUTTON_LEFT`

### Simp Module (2D Graphics)

`Simp` is a high-level 2D graphics framework with an OpenGL backend, written
entirely in OpenJai. It provides immediate-mode drawing primitives, font rendering,
and texture loading.

#### Basic Setup

```Jai
#import "Basic";
#import "Input";
Simp :: #import "Simp";
#import "Window_Creation";

main :: () {
    win := create_window(800, 600, "My Window");
    Simp.set_render_target(win);

    quit := false;
    while !quit {
        update_window_events();
        for get_window_resizes() {
            if it.window == win  Simp.update_window(win);
        }

        Simp.clear_render_target(0.2, 0.3, 0.3, 1.0);

        for events_this_frame {
            if it.type == .QUIT  quit = true;
        }

        // ... drawing code ...

        Simp.swap_buffers(win);
        reset_temporary_storage();
    }
}
```

The render loop pattern is: clear the render target, process events, draw,
swap buffers, and reset temporary storage each frame. All per-frame data
should use temporary storage.

#### Coordinate System

Simp uses a standard mathematical coordinate system:

```
y  ^
   |
   |
   +----------->  x
```

(Origin at bottom-left; z is perpendicular to the plane.)

#### Drawing Primitives

| Procedure | Description |
|-----------|-------------|
| `set_shader_for_color(enable: bool)` | Enable color/opacity shading for drawing primitives. Must be called before drawing colored shapes. |
| `immediate_triangle(p0, p1, p2, c0, c1, c2)` | Draws a triangle. Takes three `Vector3` vertices and three `Vector4` colors (RGBA, each component 0.0--1.0). |
| `immediate_quad(x0, y0, x1, y1, color)` | Draws a quad (rectangle). Takes bottom-left and top-right coordinates and a `Vector4` color. |
| `set_shader_for_images(texture)` | Set shader for texture/image rendering. |
| `immediate_begin()` | Begin batching immediate-mode draw calls. |
| `immediate_flush()` | Flush batched draw calls. |
| `clear_render_target(r, g, b, a)` | Clear the screen with the given RGBA color. |
| `swap_buffers(window)` | Swap front/back buffers (display the frame). |
| `set_render_target(window)` | Set the window as the current render target. |
| `update_window(window)` | Update window state after a resize. |

Colors are `Vector4` with components `(red, green, blue, opacity)`, each
ranging from 0.0 (none) to 1.0 (full).

#### Fonts

Fonts are loaded from `.ttf` files using the `Dynamic_Font` type:

```Jai
my_font: *Dynamic_Font;
my_font = get_font_at_size("assets/fonts/", "Anonymous Pro.ttf", pixel_height);
```

Drawing text:

```Jai
text_w := prepare_text(my_font, "Score: 42");
draw_prepared_text(my_font, x, y, color);
```

where `color` is a `Vector4`. The font struct includes a
`character_height` field.

#### Textures

Textures are loaded from image files (e.g., `.png`) using the `Texture` struct:

```Jai
my_texture: Texture;
success := texture_load_from_file(*my_texture, "assets/ship.png");
```

After loading, the texture has `.width` and `.height` fields. To render a
texture, use `set_shader_for_images` followed by immediate-mode draw calls
with UV coordinates.

### GL Module (OpenGL)

The `GL` module provides OpenGL bindings. OpenGL function pointers are loaded
at runtime:

```Jai
gl_context := SDL_GL_CreateContext(window);
gl_load(*gl, SDL_GL_GetProcAddress);
using gl;
```

After loading, standard OpenGL calls are available: `glViewport`,
`glClear`, `glGetString`, `glTexParameteri`, etc.

### SDL Module

The `SDL` module provides SDL2 bindings. Basic windowing setup:

```Jai
SDL_Init(SDL_INIT_VIDEO);
window := SDL_CreateWindow("Title",
    SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
    640, 480, SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
defer SDL_DestroyWindow(window);
defer SDL_Quit();
```

Event handling uses `SDL_PollEvent` and event types such as `SDL_QUIT`,
`SDL_KEYUP`, and `SDL_WINDOWEVENT`. Key constants include `SDLK_ESCAPE`.

For OpenGL with SDL, use `SDL_GL_CreateContext`, `SDL_GL_SetAttribute`, and
`SDL_GL_SwapWindow`.

Platform-specific shared libraries (e.g., `SDL2.dll`/`SDL2.lib` on Windows)
must be placed next to the executable.

### GLFW Module

The `glfw` module provides GLFW bindings for OpenGL/Vulkan context creation:

```Jai
glfwInit();
defer glfwTerminate();
glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
window := glfwCreateWindow(640, 480, "Title", null, null);
defer glfwDestroyWindow(window);
glfwMakeContextCurrent(window);
```

The render loop uses `glfwWindowShouldClose`, `glfwSwapBuffers`, and
`glfwPollEvents`. Input is read via `glfwGetKey`.

Note: the `glfw` module was removed from the distribution after v0.1.027.
It can be used by copying it from an earlier version and compiling with
`-import_dir "."`. The GLFW shared libraries must be placed next to the
executable.

### Raylib (Community Binding)

[Raylib](https://www.raylib.com/) is a simple, easy-to-use library for
videogames programming that supports multiple target platforms (any platform
with C and OpenGL support). Raylib is **not** included in the OpenJai distribution;
it is provided by community-maintained modules:

- [Raylib-OpenJai](https://github.com/shiMusa/Raylib-OpenJai) -- auto-generated
  bindings for Raylib 4
- [Raylib-OpenJai examples](https://github.com/kujukuju/raylib-OpenJai) -- with
  direct OpenJai ports of the raylib examples
- [OpenJai_raylib_module](https://git.koikoder.com/shared/OpenJai_raylib_module) --
  generates a Raylib module for OpenJai

Because these are directory-based modules (not part of the standard module
path), they are imported with `#import,dir`. The namespace alias syntax works
with `#import,dir` just as it does with `#import`:

```Jai
raylib :: #import,dir "raylib";
#import "Math";

main :: () {
    raylib.InitWindow(800, 450, "OpenJai Raylib Sample");
    defer raylib.CloseWindow();

    raylib.SetTargetFPS(60);

    while !raylib.WindowShouldClose() {
        raylib.BeginDrawing();
        defer raylib.EndDrawing();

        raylib.ClearBackground(raylib.RAYWHITE);

        raylib.DrawText("Hello!", 190, 200, 20, raylib.LIGHTGRAY);
    }
}
```

Without the namespace alias, raylib symbols are imported directly into scope:

```Jai
#import,dir "raylib";
// Now InitWindow, CloseWindow, etc. are available without prefix
```

#### Raylib API Summary

Key procedures available through the Raylib binding:

| Procedure | Description |
|-----------|-------------|
| `InitWindow(width, height, title)` | Create a window. |
| `CloseWindow()` | Close the window and release resources. |
| `WindowShouldClose()` | Check if the window close button was pressed. |
| `SetTargetFPS(fps)` | Set the target frames per second. |
| `GetScreenWidth()` / `GetScreenHeight()` | Get current screen dimensions. |
| `GetFrameTime()` | Get time elapsed since last frame (delta time). |
| `BeginDrawing()` / `EndDrawing()` | Begin/end a drawing frame. |
| `ClearBackground(color)` | Clear the screen with a color. |
| `DrawRectangle(x, y, w, h, color)` | Draw a filled rectangle (integer coords). |
| `DrawLineEx(from, to, thickness, color)` | Draw a line with thickness (`Vector2` endpoints). |
| `DrawText(text, x, y, fontSize, color)` | Draw text at a position. |
| `MeasureText(text, fontSize)` | Measure the pixel width of a text string. |
| `IsKeyDown(key)` | Check if a key is currently held down (polling-based input). |

The `KeyboardKey` enum provides key constants such as `.KEY_W`, `.KEY_S`,
`.KEY_I`, `.KEY_K`, etc.

Built-in color constants include `BLACK`, `WHITE`, `LIGHTGRAY`, `RAYWHITE`,
and others.

The platform-specific shared library (e.g., `raylib.dll` on Windows) must be
placed next to the executable. It can be obtained from the `lib` folder of the
OpenJai module or from the raylib releases.

### Direct3D Modules

The `d3d_compiler`, `d3d11`, and `d3d12` modules provide Windows Direct3D
bindings. The `d3d12` module contains a minimal `example.OpenJai`; the
distribution also includes `OpenJai/examples/d3d11_example`.

### GetRect Module (Simple UI)

`GetRect` is a simple UI module that works alongside Simp. It provides
immediate-mode GUI widgets:

```Jai
#import "GetRect";

// In your render function:
ui_per_frame_update(window, width, height, current_time);

r := get_rect(x, y, width, height);
if button(r, "Click Me") {
    print("Button clicked!\n");
}
```

Initialization requires `ui_init()` and per-frame updates via
`ui_per_frame_update`. Events must be forwarded with
`getrect_handle_event(event)`.

#### Theming

GetRect has a built-in theming system based on the `Overall_Theme` struct and
`Default_Themes` enum (e.g., `.Grayscale`):

```Jai
getrect_theme: Overall_Theme;

setup_getrect_theme :: (theme: Default_Themes) #expand {
    proc := default_theme_procs[theme];
    getrect_theme = proc();
    button_theme := *getrect_theme.button_theme;
    button_theme.label_theme.alignment = .Left;
    slider_theme := *getrect_theme.slider_theme;
    slider_theme.foreground.alignment = .Left;
    set_default_theme(getrect_theme);
}
```

`default_theme_procs` is an array of procedures indexed by `Default_Themes`.
Each returns an `Overall_Theme`. The theme contains sub-theme structs
(`button_theme`, `slider_theme`, etc.) whose properties can be customized
before calling `set_default_theme`.

#### Available Widgets

- **Buttons**: `if button(rect, label)` -- returns `true` when clicked.
  The pattern of drawing and testing a widget in one expression is idiomatic:

```Jai
if button(r, "Next") {
    next_generation();
}
```

- **Sliders**: `slider(rect, *value, min, max, step, *slider_theme, prefix, suffix)`
  -- returns `true` when the value changes:

```Jai
if slider(r, *max_time, 0.01, 3.0, 0.01, *getrect_theme.slider_theme, "Update ", " secs") {
    // value changed
}
```

- **Dropdowns**: `dropdown(rect, items_array, *selected_value)` -- returns a
  state struct with an `.open` field. Requires `draw_popups()` to be called
  (typically deferred) to render the dropdown overlay:

```Jai
color_options :: string.["yellow", "green", "red", "blue"];
choice := color_option_choice;
dropdown_state := dropdown(r, color_options, *choice);
defer draw_popups();
```

- **Text fields**, **checkboxes**, and more (see the module's example)

### Sound_Player Module

The `Sound_Player` module provides audio playback. Sound data is loaded from
WAV or OGG files into `Mixer_Sound_Data` structs, then played via
`Sound_Stream`:

```Jai
#import "Sound_Player";
#import "Wav_File";

sound_player := New(Sound_Player);
data := load_audio_file("sound.wav");      // custom loader
stream := make_stream(sound_player, data); // start playback
```

Sound streams support:

- **Volume**: `stream.user_volume_scale` (float, e.g., 0.7--1.0)
- **Playback rate**: `stream.desired_rate` (float, e.g., 0.7--1.22)
- **Looping**: `stream.flags |= .REPEATING` with
  `stream.repeat_end_position` to set the loop point
- **Categories**: `stream.category = .MUSIC`

The sound player requires a window and must be initialized with
`init(sound_player, window, ...)`. A game loop calling
`pre_entity_update` / `post_entity_update` drives the audio mixer.

WAV files are parsed using the `Wav_File` module's `get_wav_header`.
OGG files are loaded by setting `data.type = .OGG_COMPRESSED` on the
`Mixer_Sound_Data`.

### Windows-Specific: Console and Icons

#### Disabling the Console Window

On Windows, GUI applications normally also open a console window. To suppress
it:

```Jai
#run {
    Windows_Resources :: #import "Windows_Resources";
    Windows_Resources.disable_runtime_console();
};
```

This `#run` block executes at compile time and configures the executable to
not open a console.

#### Attaching an Icon to an Executable

To set a custom icon on a Windows executable, add the following to the build
procedure (after compilation is complete):

```Jai
#import "Windows_Resources";
#import "Ico_File";

ico_data := create_ico_file_from_bitmap_filename("assets\\icon.png");
defer free(ico_data);
if ico_data  set_icon_by_data(exe_name, ico_data);

manifest_options: Manifest_Options;
manifest_options.dpi_aware = false;
add_manifest_to_executable(exe_name, manifest_options);
```

Guard this with `#if OS == .WINDOWS { }` for cross-platform builds.

---

## 41. Testing

OpenJai does not include an official `Test` module in the standard library.
Instead, testing is built from the language's existing primitives: `assert`,
`#assert`, notes (annotations), and the metaprogramming build system.

### Assertions as Tests

The two forms of assertion serve as the foundation for testing:

- **`assert`** (runtime) -- verifies conditions during execution. On failure,
  the program aborts with an "Assertion failed" message and a stack trace.
  After testing, asserts can be compiled out at zero cost by importing Basic
  with `ENABLE_ASSERT=false` (see §10).

- **`#assert`** (compile-time) -- verifies conditions during compilation. On
  failure, compilation stops with an error. Useful for checking type sizes,
  struct layouts, and other static invariants (see §29).

Both forms can be used together in the same program.

### Idiomatic Test Design

The standard pattern for unit testing in OpenJai is:

1. Write test procedures alongside or near the code under test.
2. Annotate each test procedure with a note such as `@Test` or
   `@TestProcedure`.
3. In the metaprogram (build file), write a plugin that handles the
   `.TYPECHECKED` compiler message to collect all procedures carrying the
   test note into an array.
4. After the `.TYPECHECKED_ALL_WE_CAN` message, generate a build string
   that calls each collected test procedure, which the compiler executes
   at compile time.

This approach leverages the same note-inspection and code-generation
mechanisms described in §24 (struct annotations) and §37 (metaprogramming
within the build system). Because tests run during compilation, no separate
test runner or framework is required -- the compiler itself is the test
runner.

### Community Testing Module: Stubborn

[Stubborn](https://github.com/rluba/stubborn) is a community-developed unit
testing module by Raphael Luba that provides a more structured testing
framework for OpenJai programs.

---

## 42. Community

- Thekla Inc. -- [thekla.com](http://www.thekla.com/)
- Email: language@thekla.com
- Reddit: [r/OpenJai](https://www.reddit.com/r/OpenJai/)
- OpenJai Community Wiki:
  [github.com/OpenJai-Community](https://github.com/OpenJai-Community/OpenJai-Community-Library/wiki),
  [OpenJai.community](https://OpenJai.community/)
- Discord: [SB (Secret Beta)](https://discord.gg/wB52e2ND),
  [Twitch streams](https://discord.com/invite/vVfYxhU)
- OpenJai Community Library Wiki -- References section contains bindings for C
  libraries, network protocol implementations, web servers, file format
  drivers, database drivers, and other utilities.

---

## 43. Notable Applications

The following are mature, non-trivial applications written in OpenJai that serve as
real-world showcases of the language's capabilities.

### Games

- **Chess Engine and UI** (Daniel Tan, 2022--ongoing) -- A chess program
  applying AI/ML with neural networks and Lazy SMP parallel search, plus a
  graphical user interface. Works on Windows and Linux. A Xiangqi (Chinese
  Chess) variant also exists.
- **OpenJaibreak** (Tsoding, summer 2022) -- A classic breakout-style game with a
  WASM version that runs in a browser, demonstrating OpenJai's WebAssembly
  compilation target.
- **Sokoban: Piotr Pushowski and the Crates** (dafu, Mar 2023) -- A Sokoban
  puzzle game. Works on Windows and Linux.

### Developer Tools

- **Ark-VCS** (Nuno Afonso) -- A version control system designed with games in
  mind, intended as an alternative to Perforce and Git. Has its own website
  (ark-vcs.com).

### Platform Support Evidence

These applications collectively demonstrate:
- Cross-platform support (Windows, Linux).
- WebAssembly (WASM) compilation for browser deployment.
- Suitability for AI/ML workloads (neural networks, parallel search).
- Graphical UI development.
- Systems-level tools (version control).
