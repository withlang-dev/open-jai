# OpenJai Bootstrap Compiler — Implementation Notes

This document describes the high-level plan to implement the bootstrap compiler
for OpenJai. The compiler is written in Zig and lives in `./bootstrap/`. The Zig
compiler's architecture (`.reference/zig/src/`) serves as structural
inspiration while the OpenJai language specification (`docs/open_jai_spec.md`)
is the authoritative source for language semantics.

---

## 1. Scope of the Bootstrap Compiler

The bootstrap compiler is **not** the final self-hosting OpenJai compiler. Its
purpose is to compile enough of the language to build the standard library and
eventually a self-hosting compiler written in OpenJai itself.

### What the Bootstrap Must Support

Every feature exercised by the programs in `./examples/` must compile and run
correctly. At minimum this includes:

- All primitive types, strings, pointers (Spec §11)
- Constants and variables with all four declaration forms (Spec §12)
- Procedures with default arguments, named arguments, variadic args, multiple
  return values, `#must` (Spec §10)
- Polymorphic procedures and structs with `$T` type variables (Spec §10, §24)
- Operator overloading (Spec §10)
- Structs with `using`, `#as`, default values, nested structs, annotations
  (Spec §24)
- Unions with `#place` (Spec §25)
- Enums including `enum_flags`, `#specified`, backing types (Spec §26)
- All three array kinds: static, dynamic, array views (Spec §27)
- Control flow: `if`/`else`, `if`-`case`, `ifx`, `while`, `for` with ranges
  and arrays, `break`/`continue` with labels, `defer` (Spec §17, §18)
- The `#run` directive and compile-time execution (Spec §19, §31)
- `#if` conditional compilation (Spec §31)
- `#insert` and `#code` for metaprogramming (Spec §31)
- Macros with `#expand`, backtick references, `for_expansion` (Spec §32)
- The context system: implicit context, `push_context`, `push_allocator`,
  `#add_context`, `#no_context`, `#c_call` (Spec §30)
- `#import` and `#load` with module parameters (Spec §20)
- `#foreign`, `#system_library`, `#library` for FFI (Spec §6)
- Type information system and runtime reflection (Spec §11)
- The integrated build system: workspaces, `Build_Options`, compiler message
  loop (Spec §37)
- `#string` multi-line literals, `#char`, escape sequences (Spec §16)
- Type variants with `#type,distinct` and `#type,isa` (Spec §11)
- `#bake_arguments` and `#bake_constants` (Spec §10)
- `#modify` directive for polymorphic constraints (Spec §33)
- `#asm` inline assembly blocks (Spec §36) — initially stub, full support later
- SOA transforms (Spec §34) — via metaprogramming, not a compiler primitive
- Memory management: `alloc`, `free`, `New`, temporary storage (Spec §15)
- Annotations (`@Name`) on structs, fields, procedures, enums (Spec §24)
- Scope directives: `#scope_file`, `#scope_export`, `#scope_module` (Spec §13)
- Threading primitives (Spec §38) — runtime library concern, compiler must
  support the context-per-thread model

### What Can Be Deferred

- Full LLVM backend optimization passes (start with debug-quality codegen)
- WebAssembly target
- The complete standard library (only `Preload`, `Runtime_Support`, and `Basic`
  are needed initially)
- Plugins and the full `Default_Metaprogram` (Spec §4)
- Visual debugger integration, natvis support (Spec §29)
- The `Bindings_Generator` module (Spec §37)
- Advanced linker features (incremental linking, LTO)

---

## 2. Architecture Overview

The original Jai compiler (Spec §4, Chapter 4) defines a clear pipeline:

> Source code → AST → **Byte-code** → Machine code
>
> (via LLVM IR, or directly via x64 backend)

**Bytecode is the compiler's primary intermediate representation.** The
front-end (parser + semantic analysis) produces an AST which is then lowered
to an internal bytecode. This bytecode serves **two purposes**:

1. **Compile-time execution:** The bytecode interpreter runs `#run`
   directives, `#if` conditions, macro expansions, and the build metaprogram
   during compilation (Spec §4.2: "the compiler contains a byte-code
   interpreter").
2. **Input to the backends:** Both the LLVM backend and the x64 backend
   consume this bytecode to produce machine code (Spec §4.4: "the back-end
   converts the internal byte-code to produce the executable machine code").

This is different from Zig's architecture where ZIR/AIR serve as the IR and
comptime evaluation happens inline during semantic analysis. In OpenJai, the
bytecode is a fully general instruction stream that can represent the entire
program.

Inspired by the Zig compiler's modular structure (`Compilation.zig`, `Sema.zig`,
`InternPool.zig`, codegen backends, linker), the OpenJai bootstrap compiler
follows a similar modular design adapted to this bytecode-centric architecture.

```
Source Files
    │
    ▼
┌──────────┐
│  Lexer   │  Tokenize UTF-8 source into token stream
└────┬─────┘
     │
     ▼
┌──────────┐
│  Parser  │  Recursive-descent → AST (Spec §4: "hand-written recursive
└────┬─────┘  descent top-down parser")
     │
     ▼
┌──────────────────┐
│  Name Resolution │  Multi-pass: resolve all identifiers, no forward
│  & Declaration   │  declaration needed (Spec §4, §8)
│  Collection      │
└────┬─────────────┘
     │
     ▼
┌──────────────────┐
│  Type Checking   │  Type inference, polymorphic instantiation, operator
│  & Semantic      │  overload resolution, #modify hooks
│  Analysis (Sema) │
└────┬─────────────┘
     │
     ▼
┌──────────────────┐
│  Bytecode        │  Lower typed AST → internal bytecode (the compiler's
│  Generation      │  primary IR). Every procedure in the program is compiled
│  (Front-end)     │  to bytecode. (Spec §4.3: "the AST and byte-code boxes
└────┬─────────────┘  form the front-end")
     │
     ├──────────────────────────────┐
     │                              │
     ▼                              ▼
┌──────────────────┐   ┌──────────────────┐
│  Bytecode        │   │  Backend:        │
│  Interpreter     │   │  Code Generation │
│  (Compile-Time)  │   │                  │
│                  │   │  Bytecode →      │
│  Executes #run,  │   │  LLVM IR →       │
│  #if, #insert,   │   │  machine code    │
│  build system.   │   │  (or Bytecode →  │
│  Results feed    │   │  x64 directly)   │
│  back into the   │   │                  │
│  front-end.      │   │  (Spec §4.4)     │
└──────────────────┘   └────┬─────────────┘
                            │
                            ▼
                  ┌──────────────────┐
                  │  Linker          │  Invoke platform linker (LLD on
                  └──────────────────┘  Linux/macOS, link.exe on Windows)
```

**Timing breakdown** (Spec §4.5):
```
Front-end time (parse + sema + bytecode gen) + Backend time (LLVM or x64) = Compiler time
Compiler time + Link time = Total time
```

### Key Architectural Differences from Zig

| Aspect | Zig Compiler | OpenJai Bootstrap |
|--------|-------------|-------------------|
| Primary IR | ZIR (untyped) → AIR (typed) | **Bytecode** — a single IR that is both executed by the compile-time interpreter and consumed by backends |
| IR between parse and codegen | Two IRs: ZIR then AIR | AST → Bytecode (one lowering step; AST kept alive for metaprogramming) |
| Compile-time execution | Comptime evaluation inline in Sema | Dedicated bytecode interpreter executing the same bytecode the backends consume (Spec §4.2) |
| Name resolution | Single-pass with lazy evaluation | Multi-pass: collect all declarations first, then resolve (Spec §4: "multiple passes to find all definitions") |
| Metaprogramming | Comptime functions operating on types | AST-level code generation via `#insert`, `#code`, macros; results re-enter the front-end (Spec §31, §32) |
| Build system | External `build.zig` | Integrated: build programs are OpenJai code run via `#run` in the bytecode interpreter (Spec §37) |
| Threading model | Parallel sema + codegen per function | Job-based compilation (Spec §4: "compiler runs multi-threaded as a kind of job system") — sequential in bootstrap, parallel later |

---

## 3. Directory Structure

```
bootstrap/
├── build.zig              # Zig build script for the compiler itself
├── src/
│   ├── main.zig           # Entry point, CLI argument parsing (cf. zig/src/main.zig)
│   ├── Compilation.zig    # Top-level compilation orchestration (cf. zig/src/Compilation.zig)
│   │
│   ├── lexer.zig          # Tokenizer
│   ├── Token.zig          # Token types and data
│   │
│   ├── parser.zig         # Recursive-descent parser → AST
│   ├── Ast.zig            # AST node definitions
│   │
│   ├── resolve.zig        # Multi-pass name resolution and declaration collection
│   ├── Sema.zig           # Semantic analysis: type checking, inference, poly instantiation
│   │                        (cf. zig/src/Sema.zig)
│   ├── type_check.zig     # Type compatibility, casting rules, operator resolution
│   │
│   ├── InternPool.zig     # Interned types and values (cf. zig/src/InternPool.zig)
│   ├── Type.zig           # Type representation and queries (cf. zig/src/Type.zig)
│   ├── Value.zig          # Compile-time value representation (cf. zig/src/Value.zig)
│   │
│   ├── Bytecode.zig       # Bytecode instruction set definition (the compiler's
│   │                        primary IR — consumed by both the interpreter and backends)
│   ├── bytecode_gen.zig   # Lower typed AST → bytecode (front-end output)
│   ├── vm.zig             # Bytecode interpreter for compile-time execution (#run,
│   │                        #if, build metaprogram). Executes the same bytecode
│   │                        that backends consume. (cf. Spec §4.2)
│   │
│   ├── codegen/
│   │   ├── llvm.zig       # Bytecode → LLVM IR → machine code (cf. zig/src/codegen/llvm.zig)
│   │   └── x86_64.zig     # Bytecode → x64 machine code directly (later)
│   │
│   ├── link.zig           # Linker invocation (cf. zig/src/link.zig)
│   │
│   ├── Module.zig         # Module representation and import resolution
│   ├── Workspace.zig      # Workspace management (Spec §8, §37)
│   ├── Context.zig        # Context struct layout computation (Spec §30)
│   ├── TypeInfo.zig       # Runtime type information generation (Spec §11)
│   │
│   ├── diagnostics.zig    # Error and warning reporting
│   └── target.zig         # Target platform detection and configuration
│
├── lib/
│   ├── Preload.zig        # Compiler-provided Preload module (Spec §20)
│   └── RuntimeSupport.zig # Runtime_Support module skeleton
│
└── tests/
    ├── lexer_test.zig
    ├── parser_test.zig
    ├── sema_test.zig
    └── ...
```

---

## 4. Phase 1: Lexer (`lexer.zig`, `Token.zig`)

### Token Categories

The lexer must recognize the following token categories derived from the
spec:

**Keywords:** `if`, `else`, `then`, `ifx`, `for`, `while`, `return`, `break`,
`continue`, `defer`, `using`, `struct`, `union`, `enum`, `enum_flags`, `cast`,
`xx`, `inline`, `no_inline`, `null`, `true`, `false`, `void`, `it`,
`it_index`, `push_context`, `operator`, `case`, `size_of`, `type_of`,
`type_info`, `is_constant`, `interface`

**Directives:** `#run`, `#if`, `#ifx`, `#else`, `#import`, `#load`,
`#insert`, `#code`, `#expand`, `#char`, `#string`, `#foreign`,
`#system_library`, `#library`, `#type`, `#scope_file`, `#scope_export`,
`#scope_module`, `#as`, `#place`, `#align`, `#no_padding`, `#specified`,
`#through`, `#complete`, `#must`, `#this`, `#procedure_name`, `#deprecated`,
`#assert`, `#dump`, `#symmetric`, `#poke_name`, `#compile_time`, `#no_reset`,
`#no_abc`, `#no_context`, `#c_call`, `#add_context`, `#asm`, `#bytes`,
`#intrinsic`, `#program_export`, `#elsewhere`, `#runtime_support`, `#bake_arguments`,
`#bake_constants`, `#modify`, `#module_parameters`, `#type_info_none`,
`#type_info_procedures_are_void_pointers`, `#placeholder`, `#compiler`,
`#file`, `#line`, `#filepath`, `#location`, `#caller_location`,
`#caller_code`, `#procedure_of_call`, `#no_reset`

**Operators and punctuation:** `::`, `:=`, `:`, `=`, `==`, `!=`, `<`, `<=`,
`>`, `>=`, `+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`, `~`, `<<`, `>>`, `<<<`,
`>>>`, `&&`, `||`, `!`, `+=`, `-=`, `*=`, `/=`, `..`, `.`, `,`, `;`, `(`,
`)`, `{`, `}`, `[`, `]`, `->`, `=>`, `$`, `$$`, `@`, `---`, `.*`

**Literals:** Integer (decimal, hex `0x`, binary `0b`, with `_` separators),
float (decimal, scientific `e`, hex float `0h`), string (with escape
sequences), `#string` multi-line strings, `#char` character literals

**Identifiers:** Unicode-aware, support backslash-space continuation
(Spec §14)

**Comments:** `//` line comments, `/* */` block comments with nesting
(Spec §9)

### Design Notes

- **Inspiration:** Zig's lexer lives in `std.zig.Tokenizer`. Ours is
  similar but must handle `#` directives as first-class tokens, `::` vs `:=`
  disambiguation, `<<` as both shift-left and dereference, and `.*` postfix
  dereference.
- **Source locations:** Every token carries file, line, column, and byte offset
  for error reporting (Spec §21: error messages include file path, line number,
  column).
- **`#string` literals** require special handling: the lexer reads the
  delimiter token, then scans verbatim until the delimiter appears again at the
  start of a line.
- **Shebang:** On Linux, skip a leading `#!` line (Spec §19).

---

## 5. Phase 2: Parser (`parser.zig`, `Ast.zig`)

### AST Design

The AST must preserve enough structure for:

1. Compile-time inspection via `#code` and `compiler_get_nodes` (Spec §31)
2. Macro expansion via `#insert` (Spec §31, §32)
3. `#modify` hooks that can inspect and transform type parameters (Spec §33)
4. Runtime type information generation (Spec §11)
5. Error reporting with precise source locations

Each AST node stores:
- Node kind (enum)
- Source location (file, line, column)
- Type annotation slot (filled during sema)
- Child node indices (stored in a flat array, Zig-style)

### Key AST Node Kinds

```
// Declarations
DeclConstant          // name :: value  or  name : type : value
DeclVariable          // name := value  or  name : type = value  or  name : type
DeclProcedure         // name :: (params) -> ret { body }
DeclStruct            // Name :: struct (params) { fields }
DeclEnum              // Name :: enum backing_type { members }
DeclUnion             // Name :: union { fields }
DeclOperator          // operator + :: (a, b) -> c { body }
DeclModule            // from #import
DeclUsing             // using expr

// Expressions
ExprLiteral           // integer, float, string, bool, null
ExprIdent             // identifier reference
ExprBinary            // a op b
ExprUnary             // op a  or  a op (postfix)
ExprCall              // f(args)
ExprIndex             // a[i]
ExprField             // a.b
ExprDeref             // <<a  or  a.*
ExprAddressOf         // *a
ExprCast              // cast(T) x  or  xx x
ExprStructLiteral     // Type.{fields}
ExprArrayLiteral      // Type.[items]
ExprLambda            // (params) => expr  or  (params) { body }
ExprIfx               // ifx cond then a else b
ExprType              // #type (int) -> int
ExprCode              // #code { ... }
ExprRun               // #run expr
ExprInsert            // #insert expr
ExprThis              // #this
ExprProcedureName     // #procedure_name()
ExprBakeArgs          // #bake_arguments proc(a=val)
ExprBakeConstants     // #bake_constants proc(T=type)
ExprProcedureOfCall   // #procedure_of_call proc(args)

// Statements
StmtReturn            // return values
StmtIf                // if cond { } else { }
StmtIfCase            // if var == { case val; ... }
StmtWhile             // while cond { }
StmtFor               // for range/array { }
StmtDefer             // defer stmt
StmtAssign            // lhs = rhs  or  lhs += rhs
StmtBlock             // { stmts }
StmtBreak             // break [label]
StmtContinue          // continue [label]
StmtPushContext       // push_context expr { }
StmtUsing             // using expr;

// Directives (top-level)
DirImport             // #import "Module"
DirLoad               // #load "file.jai"
DirScopeFile          // #scope_file
DirScopeExport        // #scope_export
DirScopeModule        // #scope_module
DirAddContext         // #add_context field: Type
DirForeign            // #foreign lib
DirSystemLibrary      // #system_library "name"
DirLibrary            // #library "path"
DirModuleParameters   // #module_parameters(...)
DirIf                 // #if condition { }
DirAssert             // #assert condition
DirPokeName           // #poke_name Module name
DirPlaceholder        // #placeholder name
```

### Parsing Strategy

The parser is a hand-written recursive-descent parser (as specified in
Spec §4). Key parsing challenges:

1. **`::` vs `:=` vs `:`** — The parser must look ahead after an identifier
   to determine whether a declaration is a constant (`::`) , variable (`:=`),
   or typed declaration (`: Type`).

2. **`<<` ambiguity** — `<<` can be the dereference operator or the
   shift-left operator. Context disambiguates: prefix position = dereference,
   infix position = shift-left.

3. **`*` ambiguity** — `*` is both multiplication and address-of/pointer-type.
   Prefix = address-of or pointer type, infix = multiplication.

4. **Procedure vs lambda** — `(params) -> ret { body }` after `::` is a
   procedure declaration; `(params) => expr` is a lambda. The `=>` token
   disambiguates.

5. **Struct literals** — `Type.{...}` requires recognizing the `Type.`
   prefix. When the type is omitted (`.{...}`), the parser emits an anonymous
   struct literal that sema resolves from context.

6. **`#if` at file scope** — `#if` can appear at the data scope level
   (conditional compilation) or in imperative scope (conditional execution).
   Both parse to the same node; sema distinguishes them.

7. **Multi-line `#string`** — The parser delegates back to the lexer for the
   raw string content.

---

## 6. Phase 3: Name Resolution (`resolve.zig`)

OpenJai requires **no forward declarations** (Spec §4, §8). The compiler must
find all definitions before resolving references. This is done in multiple
passes:

### Pass 1: Declaration Collection

Walk all files in the compilation unit and collect every top-level declaration
into a symbol table organized by scope:

- **Application scope** (global, exported)
- **Module scope** (per-module, `#scope_module`)
- **File scope** (per-file, `#scope_file`)

Each declaration records: name, kind (const/var/proc/struct/enum/union),
source location, and the AST node index.

### Pass 2: Import Resolution

Process `#import` and `#load` directives:

- `#import "Module"` — locate the module on the import path, parse it, and
  collect its exported declarations into the importing scope (or a named
  namespace if `Math :: #import "Math"`).
- `#load "file.jai"` — parse the file and merge its declarations into the
  loading file's scope.
- Handle `#import,file`, `#import,dir`, `#import,string` variants (Spec §20).
- Process module parameters `#module_parameters(...)` (Spec §20).

### Pass 3: Identifier Resolution

For each identifier reference in the AST, resolve it to a declaration by
searching scopes in order (Spec §20):

1. Current local scope (innermost block)
2. Enclosing local scopes (outward through blocks)
3. Current file scope
4. Application (global) scope
5. Imported module scopes

Handle `using` by importing the struct/enum/module namespace into the
current scope. Handle `#poke_name` by injecting names into module scopes.

### Circular Dependency Detection

Since declarations can reference each other in any order, the resolver must
detect circular dependencies (e.g., a struct that non-pointer-contains itself)
and report them (Spec §24: "The program contains circular dependencies").

### Comparison to Zig

Zig uses a single-pass lazy evaluation model where each declaration is
analyzed on demand. OpenJai's multi-pass approach is simpler conceptually but
requires collecting all declarations up front. This is closer to how many
game-oriented compilers work and aligns with the spec's description.

---

## 7. Phase 4: Semantic Analysis (`Sema.zig`, `type_check.zig`)

This is the largest and most complex phase, analogous to Zig's `Sema.zig`
(1.48 MB in the Zig compiler). It performs:

### 7.1 Type Inference and Checking

- Infer types for `:=` declarations (Spec §12)
- Check type compatibility for assignments, function arguments, return values
- Enforce strong typing rules (Spec §11): no implicit int↔float, no
  implicit int↔bool (except via `cast`)
- Handle implicit widening (e.g., `s8` → `s64`) (Spec §11)
- Process `cast()`, `cast,no_check()`, `cast,trunc()`, and `xx` autocast
  (Spec §11)
- Check truthiness rules for `if`/`while` conditions (Spec §17)

### 7.2 Polymorphic Instantiation

When a polymorphic procedure or struct is used with concrete types:

1. Match `$T` type variables against call-site arguments (Spec §10)
2. Apply `#modify` hooks if present (Spec §33)
3. Create a specialized copy of the AST with concrete types substituted
4. Type-check the specialized copy
5. Cache instantiations: same type arguments → same compiled procedure
   (Spec §10: "a particular procedure is compiled only once for any given
   combination of type variables")

Handle complex positions: `$T` in array types (`[] $T`), pointer types
(`*$T`), dynamic arrays (`[..] $T`), array sizes (`[$N] $T`) (Spec §10).

Handle `$T/Base` restricted polymorphism and `$T/interface Struct` structural
typing (Spec §10).

### 7.3 Overload Resolution

When multiple procedures share a name (Spec §10):

1. Collect all overloads visible in scope
2. For each candidate, check if arguments match (type-compatible)
3. Select the "smallest and closest fit"
4. Report ambiguity if multiple candidates match equally

### 7.4 Operator Overload Resolution

For binary/unary operators on user-defined types (Spec §10):

1. Look up `operator +` (or other operator) declarations
2. Match argument types, considering `#symmetric`
3. Desugar `a + b` into a call to the resolved operator procedure

### 7.5 Context System Analysis

- Verify that `#c_call` procedures do not call context-dependent procedures
  without `push_context` (Spec §30)
- Track `#no_context` procedures
- Compute the context struct layout including `#add_context` fields (Spec §30)
- Validate `push_context` and `push_allocator` usage

### 7.6 `using` and `#as` Processing

- Flatten `using` fields: make the inner struct's fields accessible at the
  outer level (Spec §24)
- Handle `using,except(...)`, `using,only(...)`, `using,map(...)` modifiers
- Process `#as` for implicit casting between struct types (Spec §24)
- Build the implicit cast graph for overload resolution

### 7.7 Struct Layout Computation

- Compute field offsets with natural alignment
- Handle `#align` directives (Spec §24)
- Handle `#no_padding` (Spec §24)
- Handle `#place` for union-like overlays (Spec §25)
- Compute `size_of` for every type

### 7.8 Array Type Analysis

- Static arrays `[N]T`: size must be compile-time constant (Spec §27)
- Dynamic arrays `[..]T`: struct with data, count, allocated, allocator
  (Spec §27)
- Array views `[]T`: struct with data and count (Spec §27)
- Validate index types, bounds checking insertion (Spec §27)

### 7.9 Enum Analysis

- Assign backing values (auto-increment or explicit) (Spec §26)
- Handle `enum_flags` power-of-2 assignment (Spec §26)
- Validate `#specified` enums have all values explicit (Spec §26)
- Type-check enum operations

---

## 8. Phase 5: Bytecode Generation and Compile-Time Execution

Bytecode is the **central intermediate representation** of the OpenJai
compiler. The front-end (lexer + parser + sema) produces a typed AST, which
is then lowered to bytecode. This bytecode is:

1. **Executed at compile time** by the bytecode interpreter for `#run`,
   `#if`, `#insert`, `#code`, macros, and the build metaprogram (Spec §4.2).
2. **Consumed by the backends** (LLVM or x64) to produce machine code
   (Spec §4.4).

This is architecturally distinct from Zig, where comptime evaluation happens
inline during semantic analysis and AIR is a separate IR consumed only by
backends. In OpenJai, a single bytecode representation serves both roles.

### 8.1 Bytecode Generator (`bytecode_gen.zig`)

Lowers the entire typed AST to bytecode — not just `#run` targets, but
**every procedure in the program**. The bytecode must support:

- All arithmetic and logical operations on primitive types
- String operations
- Struct and array construction and field access
- Procedure calls (including polymorphic — instantiate at compile time)
- Control flow: if/else, while, for, break, continue
- Memory allocation (compile-time heap for `New`, `alloc`)
- Type manipulation: `type_of`, `size_of`, `type_info`, `is_constant`
- Returning values to the compiler (for constant folding and code generation)

### 8.2 Bytecode Instruction Set (`Bytecode.zig`)

The bytecode instruction set is the compiler's primary IR. It must be rich
enough for efficient interpretation by the VM **and** straightforward
lowering by the LLVM and x64 backends. Key instructions:

```
// Arithmetic
ADD, SUB, MUL, DIV, MOD, NEG
// Comparison
EQ, NE, LT, LE, GT, GE
// Logical
AND, OR, NOT
// Bitwise
BAND, BOR, BXOR, BNOT, SHL, SHR, ROL, ROR
// Memory
LOAD, STORE, ALLOC, FREE
LOAD_FIELD, STORE_FIELD
LOAD_INDEX, STORE_INDEX
// Control flow
JUMP, JUMP_IF, JUMP_IF_NOT
CALL, RETURN
// Type operations
TYPE_OF, SIZE_OF, TYPE_INFO, IS_CONSTANT
CAST, CAST_NO_CHECK
// Constants
LOAD_CONST_INT, LOAD_CONST_FLOAT, LOAD_CONST_STRING, LOAD_CONST_BOOL
LOAD_NULL, LOAD_VOID
// Struct/Array
MAKE_STRUCT, MAKE_ARRAY
// Special
PRINT         // for compile-time print() support
INSERT_CODE   // feed generated code back to the compiler
```

### 8.3 Bytecode Interpreter (`vm.zig`)

Executes bytecode at compile time (Spec §4.2: "the compiler contains a
byte-code interpreter"). The same bytecode instruction set is used for
compile-time execution and as input to the backends — the interpreter and the
LLVM/x64 backends are two different consumers of the same IR.

Key capabilities:

- **Value representation:** Tagged union of all OpenJai primitive types, plus
  compound types (structs, arrays, strings, pointers, types, procedures, Code).
- **Compile-time heap:** A separate memory arena for allocations made during
  `#run`. These are discarded after compilation unless `#no_reset` is used
  (Spec §31).
- **Procedure calls:** The VM maintains a call stack with frames. It must
  handle recursive calls and polymorphic dispatch.
- **Code generation feedback:** When `#insert` is evaluated, the VM produces
  a string or `Code` value that the compiler feeds back into the parser and
  sema pipeline. The results "are funneled back into the source code, and
  then the compiler continues as normal" (Spec §4.2).
- **Type table access:** The VM can call `get_type_table()` and
  `type_info()` to inspect the program's types at compile time (Spec §11).
- **Compiler API:** The VM must implement the compiler-facing procedures:
  `compiler_create_workspace`, `compiler_begin_intercept`,
  `compiler_wait_for_message`, `compiler_end_intercept`, `add_build_file`,
  `add_build_string`, `get_build_options`, `set_build_options`,
  `compiler_report`, `compiler_set_type_info_flags` (Spec §37).

### 8.4 Interaction with the Compilation Pipeline

Bytecode generation and compile-time execution interleave with parsing and
semantic analysis. The front-end does **not** finish before the bytecode
interpreter starts — `#run` directives trigger immediate bytecode generation
and execution, and their results can produce new source code that re-enters
the front-end:

```
Parse file
    │
    ├─── Collect declarations (multi-pass name resolution)
    │
    ├─── Sema: type-check all code
    │
    ├─── For each #run / #if / #insert encountered during sema:
    │        │
    │        ▼
    │    ┌─────────────────────────┐
    │    │  1. Compile target      │
    │    │     expression to       │
    │    │     bytecode            │
    │    │  2. Execute bytecode    │
    │    │     in VM               │
    │    │  3. If #insert: feed    │◄──┐
    │    │     result string/Code  │   │
    │    │     back into parser    │   │
    │    │  4. Parse + sema new    │───┘
    │    │     AST nodes           │
    │    └─────────────────────────┘
    │
    ├─── After all #run / metaprogramming is resolved:
    │    compile remaining procedures to bytecode
    │
    ▼
Complete bytecode for entire program → hand off to backend
```

This loop can iterate: a `#run` can `#insert` code that contains another
`#run`. The compiler must detect infinite loops (Spec §32: "limit is 1000
nested expansions" for macros; similar limits needed for `#run`/`#insert`
cycles).

### 8.5 `#if` Conditional Compilation

`#if` (Spec §31) evaluates a condition at compile time. If false, the
enclosed code is **not compiled at all** — it is excluded from the binary.
This requires:

1. Evaluate the condition expression in the bytecode VM
2. If true, include the AST subtree in compilation
3. If false, skip the entire subtree (do not type-check, do not codegen)

`#if` conditions must be compile-time constants. Common patterns:
`#if OS == .WINDOWS`, `#if DEBUG`, `#if VERBOSE`.

### 8.6 `#code` and AST Manipulation

The `#code` directive (Spec §31) captures a code block or expression as a
value of type `Code`. This value can be:

- Passed to macros via `#insert code` (Spec §32)
- Inspected with `compiler_get_nodes` which returns the AST as a tree of
  `Code_Node` structs
- Modified at the AST level and converted back with `compiler_get_code`
- Used with `#caller_code` in macros to capture the call-site expression

The VM must represent `Code` values as references to AST subtrees and
implement the node inspection/modification API.

---

## 9. Bytecode as the Primary IR

Unlike Zig's two-IR pipeline (ZIR → AIR), the OpenJai compiler uses a
**single bytecode IR** that sits between the front-end and the backends.
There is no separate "OIR" or "AIR" — the bytecode IS the IR.

This matches the original Jai compiler architecture (Spec §4.3, §4.4):

> "The AST and byte-code boxes form the front-end."
> "The back-end converts the internal byte-code to produce the executable
> machine code."

### 9.1 Bytecode Lowering Rules

The bytecode generator (`bytecode_gen.zig`) traverses the typed AST and
produces bytecode instructions. Key lowering rules:

- **`defer`:** Transform into explicit cleanup blocks at scope exits, ordered
  LIFO (Spec §15)
- **`for` loops:** Lower to index-based loops with bounds checking
  (Spec §18). For arrays: `for arr` → `i = 0; while i < arr.count { it =
  arr.data[i]; body; i += 1; }`
- **`if`-`case`:** Lower to a chain of comparisons or a jump table
  (Spec §17). Handle `#through` fall-through.
- **Multiple return values:** Lower to struct returns or register pairs
  depending on count and size
- **`using` field access:** Already resolved by sema into direct field
  offsets
- **Implicit context passing:** Every non-`#c_call`, non-`#no_context`
  procedure receives the context as a hidden first parameter
- **`push_context`:** Save current context, set new context, execute body,
  restore old context
- **Temporary storage access:** `context.temporary_storage` field access
- **Bounds checking:** For array access `arr[i]`, insert
  `if i >= arr.count then panic("index out of bounds")` unless `#no_abc`
  is set or the `array_bounds_check` build option is disabled (Spec §27)
- **Cast checking:** For `cast(T) v`, insert range check unless
  `cast,no_check` (Spec §11)

### 9.2 Bytecode Design Considerations

The bytecode instruction set must be general enough to:

1. Be **interpretable** efficiently by the compile-time VM
2. Be **lowerable** to LLVM IR by the LLVM backend
3. Be **lowerable** to x64 machine code by the x64 backend

This means the bytecode operates at a level above machine instructions but
below source-level constructs. It should be register-based (closer to LLVM
IR and machine registers) rather than stack-based, to make backend lowering
straightforward.

Each procedure's bytecode is stored independently and referenced by the
intern pool. The backends iterate over procedures and lower their bytecode
to the target format.

---

## 10. Phase 6: Code Generation (Backends)

The backends consume the bytecode IR produced by the front-end and produce
machine code. This is the "back-end" in the Jai architecture (Spec §4.4):

> "Two compiler backends exist: an x64 and an LLVM backend."

### 10.1 LLVM Backend (`codegen/llvm.zig`)

The primary/default backend (Spec §4.4: "the LLVM backend is the default").
Corresponding to Zig's `codegen/llvm.zig` (224 KB in the Zig compiler). Uses
LLVM's C API via Zig's `@cImport`.

**LLVM IR generation from bytecode:**

- Map bytecode types to LLVM types (integers, floats, pointers, structs, arrays)
- Map bytecode instructions to LLVM instructions
- Generate function prologues/epilogues with context parameter
- Generate runtime type information as LLVM global constants (Spec §11)
- Generate the type table as a global array of `Type_Info` pointers
- Emit debug information (DWARF) for debug builds (Spec §4)
- Apply optimization level from `Build_Options` (Spec §37):
  - `DEBUG` / `VERY_DEBUG`: no optimization
  - `OPTIMIZED`: LLVM `-O2`
  - `VERY_OPTIMIZED`: LLVM `-O3`
  - `OPTIMIZED_SMALL` / `VERY_SMALL`: LLVM `-Os` / `-Oz`

**Key implementation decisions:**

- Use LLVM 18+ (or whatever version ships with Zig's bundled LLVM)
- OpenJai strings → LLVM `{i64, ptr}` (count + data pointer)
- OpenJai arrays → LLVM structs matching the internal layout
- OpenJai context → LLVM struct passed as first argument
- OpenJai `Any` → LLVM `{ptr, ptr}` (type_info pointer + value pointer)

### 10.2 x64 Backend (`codegen/x86_64.zig`)

A simpler, faster backend for development builds (Spec §4.4: "fast, but
naive code generation, without any code optimization"). Can be implemented
after the LLVM backend is functional.

This backend converts bytecode directly to x64 machine code without going
through LLVM. It follows the pattern of Zig's architecture-specific backends
(`codegen/x86_64/CodeGen.zig`): bytecode → machine code bytes.

### 10.3 Runtime Type Information Generation

The compiler must generate the type table (Spec §11) as static data in the
binary:

- For each type used in the program, create a `Type_Info` struct (or
  specialized variant: `Type_Info_Integer`, `Type_Info_Struct`, etc.)
- Populate `Type_Info_Struct.members` with field metadata including names,
  types, offsets, flags, and annotations
- Store procedure type information (`Type_Info_Procedure.argument_types`,
  `.return_types`)
- Handle `#type_info_none` and `#type_info_procedures_are_void_pointers`
  to suppress type info generation (Spec §11)
- Generate `_type_table` as a global array accessible via `get_type_table()`

---

## 11. Phase 7: Linking (`link.zig`)

The bootstrap compiler invokes the platform linker externally (not a built-in
linker like some of Zig's backends).

| Platform | Linker | Notes |
|----------|--------|-------|
| Linux    | `lld` (bundled) | ELF output |
| macOS    | `lld` (bundled) or system `ld` | Mach-O output |
| Windows  | `link.exe` (MSVC) | PE/COFF output, requires Windows SDK |

**Linking steps:**

1. Collect object files from LLVM codegen
2. Add system libraries from `#system_library` declarations
3. Add user libraries from `#library` declarations
4. Link `Runtime_Support` and `Preload` object files
5. Set entry point to `__system_entry_point` (Spec §8)
6. Produce the final executable (or dynamic library if
   `output_type = .DYNAMIC_LIBRARY`)

---

## 12. Type and Value Interning (`InternPool.zig`)

Following Zig's `InternPool.zig` pattern, all types and compile-time values
are interned (deduplicated) in a global pool. This enables:

- O(1) type equality checks (compare pool indices)
- Efficient polymorphic instantiation caching
- Memory-efficient representation of the type table
- Thread-safe access (important for future parallel compilation)

### Type Representation

Each type is a 32-bit index into the intern pool. The pool stores:

- Primitive types (bool, integers, floats, void, string, Type, Code, Any)
- Pointer types (`*T`)
- Array types (`[N]T`, `[]T`, `[..]T`)
- Struct types (with field info, parameters, flags)
- Enum types (with backing type, member values)
- Union types
- Procedure types (argument types + return types + calling convention flags)
- Type variants (`#type,distinct`, `#type,isa`)
- Polymorphic type variables (unresolved `$T`)

### Value Representation

Compile-time known values are also interned:

- Integer constants (arbitrary precision for `s128`/`u128`)
- Float constants
- String constants (deduplicated, stored in a string table)
- Bool constants
- Null
- Struct literals (aggregates of interned values)
- Array literals
- Enum values
- Type values (types-as-values, since `Type` is first-class in OpenJai)
- Procedure references

---

## 13. Module System (`Module.zig`)

### Module Loading

When the compiler encounters `#import "ModuleName"`:

1. Search the import path for `ModuleName.jai` or `ModuleName/module.jai`
   (Spec §20)
2. Parse the module's source files
3. Process `#module_parameters` declarations
4. Apply module parameter values from the import site
5. Resolve the module's internal imports and loads
6. Collect exported declarations
7. Handle named imports (`Math :: #import "Math"`) by creating a namespace
8. Handle `using` on imports

### Preload Module

The `Preload` module is special (Spec §20): it is implicitly loaded for
every compilation. It defines:

- `Type_Info` and all specialized variants
- `Allocator`, `Allocator_Proc`, `Allocator_Mode`
- `Context_Base`
- `Temporary_Storage`
- `Source_Code_Location`
- `Array_View_64`, `Resizable_Array`
- Intrinsics: `memcpy`, `memcmp`, `memset`
- `string` type definition (`Newstring`)
- `Any` type definition (`Any_Struct`)
- `Operating_System_Tag` enum

The bootstrap compiler must provide a Zig implementation of these definitions
that generates the correct memory layouts.

### Runtime_Support Module

Defines `__system_entry_point`, `__jai_runtime_init`, `__jai_runtime_fini`,
and `__program_main` (Spec §8). The bootstrap compiler either:

- Compiles a minimal `Runtime_Support.jai` written in OpenJai (preferred)
- Or provides a Zig-implemented runtime startup (for initial bootstrapping)

---

## 14. Workspace and Build System (`Workspace.zig`)

### Workspace Management

The compiler manages multiple workspaces (Spec §8, §37):

- **Workspace 1:** Reserved for the metaprogram
- **Workspace 2:** The target program
- **Workspace 3+:** Additional workspaces created by the build metaprogram

Each workspace has:
- Its own set of source files
- Its own `Build_Options`
- Its own symbol table and type information
- Independent compilation

### Build Options

The `Build_Options` struct (Spec §37) contains ~45 configuration fields:

- `optimization_level`: DEBUG, OPTIMIZED, etc.
- `output_type`: EXECUTABLE, DYNAMIC_LIBRARY, STATIC_LIBRARY, OBJECT_FILE
- `output_executable_name`
- `output_path`
- `import_path`: array of module search directories
- `backend`: LLVM or X64
- `array_bounds_check`: runtime bounds checking
- `cast_bounds_check`: runtime cast checking
- `stack_trace`: include stack trace info
- `dead_code_elimination`: enable DCE
- `emit_debug_info`: generate debug symbols

### Compiler Message Loop

The build metaprogram communicates with the compiler through a message
loop (Spec §37):

```
compiler_begin_intercept(workspace)
while true {
    message := compiler_wait_for_message()
    // process message
    if message.kind == .COMPLETE break
}
compiler_end_intercept(workspace)
```

Message kinds: `.FILE`, `.IMPORT`, `.PHASE`, `.TYPECHECKED`,
`.DEBUG_DUMP`, `.ERROR`, `.COMPLETE`

The bootstrap compiler must implement this as a coroutine-like interface
between the VM (running the build metaprogram) and the compilation pipeline.

---

## 15. Error Reporting (`diagnostics.zig`)

### Error Format

The compiler stops at the first error (Spec §21) and reports:

```
filename.jai:line:column: Error: message
    source line
    ^^^^^^^^  (underline the relevant span)
```

### Error Categories

- **Lexer errors:** Invalid characters, unterminated strings, invalid escape
  sequences
- **Parser errors:** Unexpected tokens, malformed declarations
- **Name resolution errors:** Undeclared identifiers, duplicate declarations,
  circular dependencies
- **Type errors:** Type mismatches, invalid casts, missing arguments
- **Polymorph errors:** Failed type matching, `#modify` rejection
- **Compile-time errors:** `#assert` failures, `#run` panics, division by zero
- **Overload errors:** Ambiguous overloads, no matching overload

### Design Notes

- Use Zig's `std.debug` for stack trace generation in the compiler itself
- Store source text in memory for error context display
- Support `-no_color` flag for plain-text output (Spec §4)
- Support `-msvc_format` for Visual Studio message format (Spec §4)

---

## 16. Implementation Phases and Milestones

### Phase A: Foundation (Weeks 1-4)

**Goal:** Parse and type-check simple programs (hello world, arithmetic,
basic control flow).

1. Implement lexer with all token types
2. Implement parser for core declarations (variables, constants, procedures)
   and statements (if, while, for, return, assignments)
3. Implement basic name resolution (single file, no imports)
4. Implement type checking for primitive types, basic inference
5. Implement bytecode generation for trivial programs
6. Implement LLVM backend: bytecode → LLVM IR → machine code
7. Implement linker invocation
8. **Milestone:** Compile and run `hello_world.jai` equivalent

### Phase B: Type System (Weeks 5-8)

**Goal:** Full type system support.

1. Structs with fields, default values, nested structs, `using`
2. Enums with backing types, `enum_flags`, `#specified`
3. Unions with `#place`
4. All three array types (static, dynamic, views)
5. Pointers with dereference (`<<`, `.*`), address-of (`*`), null
6. String type and string operations
7. Type aliases, `#type`, type variants (`#type,distinct`, `#type,isa`)
8. The `Any` type
9. `cast()`, `cast,no_check()`, `xx`
10. **Milestone:** Compile struct/enum/array examples

### Phase C: Procedures (Weeks 9-12)

**Goal:** Complete procedure support including polymorphism.

1. Default arguments, named arguments
2. Multiple return values, `#must`
3. Variadic arguments (`..`)
4. Procedure types and function pointers
5. Local procedures and lambdas
6. Operator overloading
7. Procedure overloading
8. Polymorphic procedures with `$T`
9. `#bake_arguments` and `#bake_constants`
10. `#modify` directive
11. Inlining (`inline`, `no_inline`)
12. **Milestone:** Compile polymorphic and higher-order function examples

### Phase D: Compile-Time Execution (Weeks 13-18)

**Goal:** Working `#run`, `#if`, and basic metaprogramming. At this point the
bytecode generator from Phase A is already producing bytecode for regular
procedures (consumed by the LLVM backend). Phase D extends it with the
bytecode **interpreter** so that `#run` can execute bytecode at compile time.

1. Bytecode interpreter (VM) — execute the same bytecode that backends consume
2. `#run` directive — execute procedures at compile time via the VM
4. `#if` conditional compilation
5. `#assert` compile-time assertions
6. `#insert` code insertion (string form)
7. `#code` and Code type
8. Compile-time constant folding using VM results
9. `#compile_time`, `#no_reset`
10. **Milestone:** Compile programs using `#run` and `#if`

### Phase E: Macros and Metaprogramming (Weeks 19-22)

**Goal:** Full macro and metaprogramming support.

1. `#expand` macros with backtick references
2. `for_expansion` custom iterators
3. `#insert` with `Code` values and scope modifiers
4. AST node inspection via `compiler_get_nodes`
5. AST modification and `compiler_get_code`
6. `#caller_code`
7. `#procedure_of_call`
8. **Milestone:** Compile macro-heavy examples

### Phase F: Module System and Context (Weeks 23-26)

**Goal:** Full module system and context support.

1. `#import` and `#load` with module search paths
2. Module parameters (`#module_parameters`)
3. Scope directives (`#scope_file`, `#scope_export`, `#scope_module`)
4. Named imports and `using` on imports
5. Implement `Preload` module
6. Implement `Runtime_Support` module
7. Context system: implicit passing, `push_context`, `push_allocator`
8. `#add_context`, `#no_context`, `#c_call`
9. Temporary storage
10. `#foreign`, `#system_library`, `#library` for FFI
11. **Milestone:** Compile programs with `#import "Basic"` and FFI

### Phase G: Build System and Runtime (Weeks 27-30)

**Goal:** Integrated build system and runtime type information.

1. Workspace management
2. `Build_Options` struct and configuration
3. Compiler message loop
4. `add_build_file`, `add_build_string`
5. `#placeholder` directive
6. Runtime type information generation (type table)
7. `type_info()`, `get_type_table()` runtime support
8. Annotations (`@Name`) in type info
9. Memory-leak detector integration point
10. **Milestone:** Build programs using custom `build.jai` files

### Phase H: Polish and Completeness (Weeks 31-36)

**Goal:** Pass all examples, performance tuning, edge cases.

1. `#asm` inline assembly blocks
2. `#as` implicit casting with struct hierarchies
3. `using,except`, `using,only`, `using,map`
4. `#string` multi-line literals in all positions
5. `#deprecated` warnings
6. `#dump` bytecode display
7. All `Build_Options` flags
8. `-release` optimization mode
9. Cross-platform testing (Linux, macOS, Windows)
10. Error message quality pass
11. **Milestone:** All `./examples/` programs compile and run correctly

---

## 17. Testing Strategy

### Unit Tests

Each compiler phase has its own test suite:

- **Lexer tests:** Token stream verification for edge cases (nested comments,
  `#string`, escape sequences, Unicode identifiers)
- **Parser tests:** AST structure verification for all syntax constructs
- **Sema tests:** Type inference, polymorphic instantiation, overload
  resolution
- **VM tests:** Bytecode execution correctness
- **Codegen tests:** Generated LLVM IR verification

### Integration Tests

The `./examples/` directory serves as the integration test suite. Each
example must:

1. Compile without errors
2. Run and produce expected output
3. Exit with code 0

A test runner script compiles each example and compares output against
expected results (stored in `.expected` files or inline comments).

### Regression Tests

Every bug fix gets a corresponding test case to prevent regression.

### Compile-Time Execution Tests

Dedicated tests for `#run`, `#if`, `#insert`, `#code` that verify:

- Compile-time computed constants have correct values
- `#if false` code is excluded from the binary
- `#insert`-generated code is correctly parsed and type-checked
- Circular `#run`/`#insert` loops are detected and reported

---

## 18. Key Design Decisions

### 18.1 Why Zig for the Bootstrap?

- Zig has no hidden control flow or allocations — important for a compiler
- Zig's `comptime` and generics enable clean data structure design
- Zig has a mature LLVM backend that we can reference and learn from
- Zig's standard library is minimal and systems-oriented — good fit
- Zig cross-compiles easily to all target platforms
- Zig's error handling model (error unions) is explicit and safe

### 18.2 AST + Bytecode: Two Representations

OpenJai requires **two** representations of the program to coexist:

1. **The AST** must remain available and modifiable throughout compilation
   because metaprogramming (`#code`, `compiler_get_nodes`, `#insert`)
   operates at the AST level. Unlike Zig, which can discard AST nodes after
   generating ZIR, we must keep the AST alive.

2. **The bytecode** is the compiler's primary IR, consumed by both the
   compile-time interpreter and the backends (Spec §4). Every procedure is
   lowered to bytecode after type checking.

The tradeoff is higher memory usage (both AST and bytecode in memory) but
full compatibility with the spec's architecture and metaprogramming API.

### 18.3 Bytecode as the Central IR

The spec explicitly describes bytecode as the intermediate representation
between the front-end and backends (Spec §4.3: "the AST and byte-code boxes
form the front-end"; Spec §4.4: "the back-end converts the internal
byte-code to produce the executable machine code"). We follow this design
faithfully:

- The bytecode is the **single IR** consumed by both the compile-time
  interpreter (`vm.zig`) and the code generation backends (`codegen/llvm.zig`,
  `codegen/x86_64.zig`)
- There is no separate "OIR" or "AIR" — the bytecode IS the IR
- The bytecode instruction set must be rich enough for efficient
  interpretation AND straightforward lowering to LLVM IR / machine code
- Bytecode executes faster than AST walking for compile-time execution
- Bytecode is a natural serialization format for cached compile-time results

### 18.4 Sequential Before Parallel

The spec describes the compiler as a "multi-threaded job system" (Spec §4).
The bootstrap compiler starts **single-threaded** for simplicity. Parallelism
can be added later following Zig's pattern of per-thread `InternPool` shards
and parallel sema/codegen.

### 18.5 LLVM First, x64 Later

The LLVM backend is the default in OpenJai (Spec §4) and covers all target
platforms. The x64 backend is a development-speed optimization that can be
implemented after the compiler is functional.

---

## 19. Dependencies

| Dependency | Purpose | Version |
|-----------|---------|---------|
| Zig | Compiler implementation language | 0.14+ |
| LLVM C API | Primary code generation backend | 18+ (bundled with Zig) |
| LLD | Linker (Linux/macOS) | Bundled with LLVM |
| Platform SDK | Windows linking | MSVC build tools |

No other external dependencies. The compiler is self-contained.

---

## 20. Reference Mapping: Spec Sections → Compiler Components

| Spec Section | Compiler Component |
|---|---|
| §4 (Compiler) | `main.zig`, `Compilation.zig` |
| §6 (C Interop) | `Sema.zig` (FFI type checking), `link.zig` (library linking) |
| §8 (Program Structure) | `resolve.zig`, `Module.zig`, `Workspace.zig` |
| §9 (Comments) | `lexer.zig` |
| §10 (Procedures) | `parser.zig`, `Sema.zig` (polymorphism, overloading) |
| §11 (Types) | `Type.zig`, `InternPool.zig`, `TypeInfo.zig` |
| §12 (Constants/Variables) | `parser.zig`, `resolve.zig` |
| §13 (Scoping) | `resolve.zig` |
| §14 (Naming) | `lexer.zig` (identifier rules) |
| §15 (Memory) | `bytecode_gen.zig` (defer lowering), runtime library |
| §16 (Expressions/Literals) | `lexer.zig`, `parser.zig` |
| §17 (Branching) | `parser.zig`, `bytecode_gen.zig` |
| §18 (Loops) | `parser.zig`, `bytecode_gen.zig` |
| §19 (Directives) | `lexer.zig`, `parser.zig`, `Sema.zig` |
| §20 (Modules) | `Module.zig` |
| §21 (Compilation) | `Compilation.zig`, `diagnostics.zig` |
| §24 (Structs) | `parser.zig`, `Sema.zig`, `Type.zig` |
| §25 (Unions) | `parser.zig`, `Sema.zig`, `Type.zig` |
| §26 (Enums) | `parser.zig`, `Sema.zig`, `Type.zig` |
| §27 (Arrays) | `parser.zig`, `Sema.zig`, `Type.zig`, `bytecode_gen.zig` |
| §29 (Debugging) | `diagnostics.zig`, `vm.zig` (compile-time debugger) |
| §30 (Context) | `Context.zig`, `bytecode_gen.zig`, `Sema.zig` |
| §31 (Metaprogramming) | `bytecode_gen.zig`, `Bytecode.zig`, `vm.zig` |
| §32 (Macros) | `Sema.zig` (macro expansion), `vm.zig` |
| §33 (#modify) | `Sema.zig` |
| §34 (SOA/Meta Applications) | `vm.zig` (metaprogramming support) |
| §36 (Inline Assembly) | `bytecode_gen.zig`, `Bytecode.zig`, `codegen/llvm.zig` |
| §37 (Build System) | `Workspace.zig`, `vm.zig` (compiler API) |
| §38 (Threading) | Runtime library, `Context.zig` |
