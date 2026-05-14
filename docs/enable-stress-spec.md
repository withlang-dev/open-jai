# `utils/stress.jai` Implementation Specification

`docs/enable-stress.md` defines the source audit and acceptance ledger for
`utils/stress.jai`. This document defines the compiler, runtime, standard
module, and test-runner implementation required to make that audit pass for
real.

The stress file is not a compatibility shim target. It is a language and
runtime conformance target. Passing it means OpenJai parses, resolves,
typechecks, executes compile-time code, lowers native code, links runtime
support, runs diagnostics, and produces the expected output through ordinary
compiler behavior.

## Non-Negotiable Rules

1. No placeholder imports, symbols, values, modules, procedures, compiler API
   values, runtime values, or diagnostics.
2. No implicit `any` fallback for known language features.
3. No compile-through acceptance for unsupported semantics.
4. Unsupported syntax or semantics must fail loudly at the earliest correct
   phase with a real diagnostic.
5. Every output path must write under `out/`.
6. All accepted code must flow through the same compiler pipeline used for
   ordinary user programs.
7. The diagnostic catalog in `utils/stress.jai` must compile snippets through
   real workspaces. It must not match snippet text.

## Acceptance Definition

`utils/stress.jai` is enabled only when these commands succeed:

```sh
out/bootstrap/bin/openjai utils/stress.jai --check
out/bootstrap/bin/openjai utils/stress.jai -o out/stress
out/stress
```

The build/run harness must also compare combined compile-time diagnostics and
runtime output against the `EXPECTED_OUTPUT` `#string` blob byte-for-byte,
normalizing only source paths or platform text explicitly marked
non-deterministic by the stress source.

## Compiler Architecture Required

The bootstrap compiler must expose these internal layers as real implementation
boundaries:

```text
source files and build strings
  -> lexer
  -> parser
  -> structured AST
  -> declaration collection
  -> module/import resolver
  -> type resolver and semantic analysis
  -> compile-time bytecode generation
  -> compile-time VM and compiler-host intrinsics
  -> macro/code-tree rewriting
  -> final semantic validation
  -> native IR/codegen
  -> runtime manifest selection
  -> target linker
  -> executable under out/
```

Each layer must reject unsupported constructs. It may not preserve opaque text
past the layer that should understand that text.

### Phase Ownership

| Phase | Owns | Must Not Own |
| --- | --- | --- |
| Lexer | tokens, literal spelling, source slices, byte-preserving `#string` payloads | semantic suffix validation beyond token form |
| Parser | structured AST and syntax errors | typed fallback nodes for valid-but-unimplemented syntax |
| Resolver | scopes, imports, declarations, overload sets, namespace lookup | fabricated declarations for unknown names |
| Sema | types, layouts, conversions, lvalues, constants, diagnostics | runtime lowering decisions |
| CT VM | ordinary compile-time execution of bytecode | compiler workspace state except through intrinsics |
| Host intrinsics | compiler APIs, workspaces, code trees, filesystem/process APIs used at compile time | arbitrary user procedure execution |
| Codegen | native ABI, runtime symbol references, control flow, data sections | semantic recovery |
| Runtime | allocation, printing, files, process, atomics, platform ABI | compiler diagnostics |

## Zig Implementation Model

Zig is not a language-spec source for Jai syntax or behavior. It is the
implementation model for compiler architecture, data ownership, deterministic
diagnostics, target handling, runtime objects, and standard-module
implementation. OpenJai should follow the same shapes closely where they solve
the same engineering problem.

All references in this section point at the checked-in source tree under
`.reference/zig`.

### Compiler Pipeline References

| OpenJai Work Item | Zig Source To Follow | Design To Carry Into OpenJai |
| --- | --- | --- |
| Literal and string frontend | `.reference/zig/lib/std/zig/tokenizer.zig`, `.reference/zig/lib/std/zig/number_literal.zig:1`, `.reference/zig/lib/std/zig/string_literal.zig:1`, `.reference/zig/lib/std/unicode.zig:15` | Keep tokenization separate from numeric/string semantic parsing. Return structured literal parse errors instead of accepting opaque spellings. Preserve source spelling for diagnostics and normalize only after a literal parser has validated base, underscores, suffixes, escapes, and UTF-8 rules. |
| Structured AST coverage | `.reference/zig/lib/std/zig/Ast.zig:17`, `.reference/zig/lib/std/zig/Ast.zig:29`, `.reference/zig/lib/std/zig/Ast.zig:120`, `.reference/zig/lib/std/zig/Ast.zig:145` | Store AST as compact node/token arrays with typed indices and explicit source locations. Parser output must be structured nodes, token ranges, and extra-data lists. Do not carry raw text placeholders after parsing. |
| Parser-to-IR lowering | `.reference/zig/lib/std/zig/AstGen.zig:1`, `.reference/zig/lib/std/zig/AstGen.zig:19`, `.reference/zig/lib/std/zig/AstGen.zig:53`, `.reference/zig/lib/std/zig/AstGen.zig:58`, `.reference/zig/lib/std/zig/Zir.zig` | Add a distinct lowered compile-time IR between AST and semantic analysis. It should own imports discovered from syntax, source hashing, stable references, and extra-data payloads. Jai-specific constructs such as `#run`, `#insert`, notes, directives, and polymorphic parameters should lower into explicit IR instructions rather than being interpreted directly from parser nodes. |
| Module loading and package graph | `.reference/zig/src/Package/Module.zig:1`, `.reference/zig/src/Package/Module.zig:45`, `.reference/zig/src/Package/Module.zig:87`, `.reference/zig/src/Compilation.zig:1849` | Model modules as explicit package records with root paths, dependency maps, inherited target/optimization options, and fully qualified names. Imports must resolve through the graph; unknown modules are errors, not generated placeholder modules. |
| Type/value interning | `.reference/zig/src/InternPool.zig:1`, `.reference/zig/src/InternPool.zig:38`, `.reference/zig/src/InternPool.zig:133`, `.reference/zig/src/Type.zig:1`, `.reference/zig/src/Value.zig:1` | Use one canonical intern pool for types, values, declarations, namespaces, and stable source references. Type and value handles should be compact indices, not ad hoc boxed variants spread through Sema, VM, and codegen. |
| Scalar type classification | `.reference/zig/src/Type.zig:26`, `.reference/zig/src/Type.zig:114`, `.reference/zig/src/Value.zig:59` | Give every type a classification such as no-value, one-value, runtime, partially compile-time, or fully compile-time. This avoids implicit `any` fallback and makes compile-time-only constructs reject at the correct phase. |
| Semantic analysis | `.reference/zig/src/Sema.zig:1`, `.reference/zig/src/Sema.zig:41`, `.reference/zig/src/Sema.zig:90`, `.reference/zig/src/Sema.zig:131`, `.reference/zig/src/Air.zig:1` | Sema consumes the lowered IR and produces analyzed IR. It owns type checking, compile-time control flow, lvalue/rvalue classification, safety checks, and constant evaluation requests. Codegen consumes analyzed IR only. |
| Compile-time execution | `.reference/zig/src/Sema.zig:164`, `.reference/zig/src/Value.zig:134`, `.reference/zig/src/InternPool.zig:1` | Compile-time execution should use interned typed values and tracked compile-time allocations. Compiler-host intrinsics are explicit calls from Sema/CT VM, not fake runtime functions returning numeric sentinels. |
| Native IR and codegen | `.reference/zig/src/Air.zig:37`, `.reference/zig/src/codegen/llvm.zig:1`, `.reference/zig/src/codegen/llvm.zig:39`, `.reference/zig/src/codegen/llvm.zig:54` | Lower semantically checked functions to a target-independent analyzed IR before backend codegen. Target triples, feature legalization, ABI lowering, and runtime symbol references belong in backend-specific codegen. |
| Linking and target artifacts | `.reference/zig/src/link.zig:34`, `.reference/zig/src/link/Elf.zig:23`, `.reference/zig/src/link/MachO.zig`, `.reference/zig/src/link/Coff.zig`, `.reference/zig/src/Compilation.zig:2871` | Treat linking as a first-class compiler subsystem with target-specific link objects, diagnostics, and output-cache directories. All intermediate and final artifacts must live under `out/`. |
| Diagnostics | `.reference/zig/src/link.zig:34`, `.reference/zig/src/Compilation.zig:3928` | Diagnostics must be structured messages with notes and deterministic ordering. Collection, sorting, and rendering are separate from detection. Workspace diagnostics must not depend on hash-map iteration order. |
| Golden and behavior testing | `.reference/zig/test/behavior/nan.zig:7`, `.reference/zig/test/behavior/type_info.zig:12`, `.reference/zig/test/behavior/atomics.zig:13` | Add behavior tests next to each feature. For bit-pattern float literals, reflection, and atomics, copy Zig's testing strategy: validate actual bits, type metadata shape, and generated atomic operations rather than only compile success. |

### Standard Library References

OpenJai standard modules should be implemented as Jai modules backed by the
runtime ABI, but their data structures and algorithms should follow Zig's
library designs where the same facility exists.

| OpenJai Module/Facility | Zig Source To Follow | Required Design |
| --- | --- | --- |
| Dynamic arrays and builders | `.reference/zig/lib/std/array_list.zig:22`, `.reference/zig/lib/std/array_list.zig:101`, `.reference/zig/lib/std/fmt.zig:31` | Dynamic arrays own `items`, `capacity`, and allocator. Builders are append-only dynamic arrays with explicit allocator ownership and formatted append routines. |
| Hash tables | `.reference/zig/lib/std/hash_map.zig:46`, `.reference/zig/lib/std/hash_map.zig:120` | Implement unmanaged and managed forms. Hash/equality context must be explicit so string keys, pointer keys, and structural keys do not require compiler magic. |
| Bit arrays | `.reference/zig/lib/std/bit_set.zig:700`, `.reference/zig/lib/std/bit_set.zig:731` | Store bit count separately from word capacity. Provide resize, set, unset, toggle, count, and iterator operations over stable packed storage. |
| Base64 | `.reference/zig/lib/std/base64.zig:1`, `.reference/zig/lib/std/base64.zig:20`, `.reference/zig/lib/std/base64.zig:101`, `.reference/zig/lib/std/base64.zig:167` | Separate alphabets, encoders, decoders, and error reporting. Standard and URL-safe encodings must not share hidden global state. |
| Hash algorithms | `.reference/zig/lib/std/hash/fnv.zig:10`, `.reference/zig/lib/std/hash/crc.zig:1`, `.reference/zig/lib/std/hash/xxhash.zig:9`, `.reference/zig/lib/std/crypto/md5.zig:30` | Expose streaming state and one-shot helpers. Algorithm constants and finalization must be data-driven and covered by known-vector tests. |
| Unicode | `.reference/zig/lib/std/unicode.zig:15`, `.reference/zig/lib/std/unicode.zig:39`, `.reference/zig/lib/std/unicode.zig:98`, `.reference/zig/lib/std/unicode.zig:187` | Validate UTF-8 with explicit error kinds, encode/decode codepoints by sequence length, and reject surrogate/too-large codepoints. |
| Allocators and pools | `.reference/zig/lib/std/heap.zig:12`, `.reference/zig/lib/std/heap/ArenaAllocator.zig:1`, `.reference/zig/lib/std/heap/ArenaAllocator.zig:46`, `.reference/zig/lib/std/heap/memory_pool.zig:24`, `.reference/zig/lib/std/heap/memory_pool.zig:63` | Make allocator a runtime interface. Arena, temporary, pool, and flat-pool allocators own lifecycle and reset/deinit behavior. Standard modules must not call platform allocation directly. |
| Filesystem | `.reference/zig/lib/std/fs.zig` | File APIs operate through explicit handles and path buffers, with platform-specific errors converted into stable OpenJai errors. |
| Process execution | `.reference/zig/lib/std/process.zig:30`, `.reference/zig/lib/std/process.zig:65` | Process APIs explicitly model args, environment, cwd, stdio, exit status, and captured output. Compile-time `run_command` uses the same runtime process layer through host intrinsics. |
| Atomics | `.reference/zig/lib/std/atomic.zig:8`, `.reference/zig/lib/std/atomic.zig:24`, `.reference/zig/lib/std/atomic.zig:52`, `.reference/zig/test/behavior/atomics.zig:40` | Atomic operations lower to target atomic instructions through typed wrappers. Memory order must be part of the API and validated in sema. |

## Source Model

### Files And Workspaces

The compiler must represent source as `Source_File` records:

```text
id
workspace_id
display_path
canonical_path
contents bytes
line table
origin: disk | build_string | generated_insert | test_snippet
```

Build strings are first-class source files. They must preserve text exactly,
including embedded NUL bytes when they are inside a string literal payload.

Workspaces are first-class compiler objects:

```text
Workspace {
    id: u32
    status: enum
    root_files: []Source_File_Id
    pending_files: []Source_File_Id
    imports: module graph
    declarations: declaration table
    diagnostics: queue
    build_options: Build_Options
    intercept: Intercept_State
}
```

Workspace 1 is the default metaprogram workspace. Workspace 2 is the target
program workspace. Additional workspaces are created by
`compiler_create_workspace`.

## Lexer Specification

### Numeric Literals

The lexer must tokenize:

- decimal integers and floats
- binary integers
- octal integers
- hexadecimal integers
- `0h` IEEE-754 float bit-pattern literals
- suffixes for integer and float widths where Jai syntax permits them
- underscores between digits

`0h` literals are not hexadecimal integers. They are bit-pattern floating-point
literal syntax. The parser/sema layer decides the destination width:

```jai
nan32 : float32 = 0h7fbf_ffff;
nan64 : float64 = 0h7fff_ffff_ffff_ffff;
```

Rules:

- `0h` followed by 8 hex digits can coerce to `float32`.
- `0h` followed by 16 hex digits can coerce to `float64`.
- Underscores are allowed only between digits.
- A bit-pattern literal assigned to a non-float destination is a semantic
  error unless an explicit bit-cast form is used.
- Invalid suffixes and malformed underscores produce lexer/parser diagnostics
  with the literal source range.

### String And Character Literals

The lexer must preserve both decoded value and source spelling for string
literals:

```text
String_Token {
    spelling_range
    decoded_bytes
    delimiter_kind
    preserves_cr: bool
}
```

Supported forms:

- ordinary quoted strings
- escaped quotes and slashes
- `\n`, `\r`, `\t`, `\0`
- decimal byte escapes
- hexadecimal byte escapes where syntax permits
- `#char` byte/rune conversion
- `#string DELIM ... DELIM`
- `#string,cr DELIM ... DELIM`

The `EXPECTED_OUTPUT` block in `utils/stress.jai` is a byte-preservation test.
The lexer must not use C-string APIs or truncate at NUL.

### Directive Tokens

All `#name` tokens are lexed uniformly. Validity is checked later. Unknown
directives in executable source produce diagnostics; they are not accepted as
comments or inert attributes.

## Parser Specification

The parser must create structured AST nodes for every syntactic form accepted
by the stress file.

### Required AST Node Families

```text
Ast_File
Ast_Import
Ast_Declaration
Ast_Procedure
Ast_Procedure_Type
Ast_Block
Ast_If
Ast_Ifx
Ast_For
Ast_While
Ast_Switch
Ast_Defer
Ast_Return
Ast_Assignment
Ast_Call
Ast_Directive_Call
Ast_Insert
Ast_Expand
Ast_Code_Literal
Ast_Type_Expression
Ast_Struct
Ast_Union
Ast_Enum
Ast_Array_Type
Ast_Slice_Type
Ast_Pointer_Type
Ast_Polymorphic_Parameter
Ast_Baked_Parameter
Ast_Using_Declaration
Ast_Place_Directive
Ast_Foreign_Directive
Ast_Inline_Assembly
Ast_Note
```

Opaque parse nodes are allowed only for invalid syntax that is already being
reported as a diagnostic. Valid syntax used by stress must be represented by a
typed AST node.

### Declarations

The parser must support:

- `name :: value`
- `name : Type`
- `name := value`
- compound field declarations: `x, y, z: float`
- procedures with named returns
- procedures returning multiple values
- default arguments
- named arguments at call sites
- baked and polymorphic parameters
- procedure notes such as `@TestProcedure`
- declaration directives such as `#foreign`, `#compiler`, `#scope_file`

### Statements And Expressions

The parser must support:

- lvalues with field/index/pointer chains
- compound assignments
- multi-assignment and destructuring
- ranges and range endpoint variants
- `ifx` expression syntax
- all `for` forms used by the source
- `for *`, `for <`, `for *<`, reverse and pointer iteration forms
- `#insert` in expression, lvalue, statement, declaration, and block contexts
- `#insert -> string` and `#insert -> Code`
- `#expand`
- inline assembly blocks

### Error Recovery

The diagnostic catalog requires the parser to continue after local errors.
Recovery rules must be deterministic:

- after declaration errors, recover at a top-level declaration boundary
- after statement errors, recover at `;`, newline block boundary, or `}`
- after expression errors, produce an error expression and continue typing only
  enough to suppress cascades
- invalid directives report the directive source span

## Resolver And Module Loading Specification

### Module Discovery

Imports are resolved by real module discovery:

```text
#import "Name"        -> modules/Name/module.jai or configured import path
#import "Name.jai"    -> direct file or module alias when present
Alias :: #import "X"  -> namespace value bound to imported module X
```

The resolver must distinguish:

- real modules
- direct source files
- intentionally missing imports in diagnostic workspaces
- user-provided import paths from `Build_Options.import_path`

Unknown imports outside diagnostic snippets are errors.

### Symbol Model

Every visible symbol must be one of:

```text
Declaration
Procedure overload set
Module namespace
Enum namespace
Struct member
Compile-time constant
Compiler intrinsic
Explicit #placeholder declaration
```

The resolver must not invent symbols because a name appears to be from a known
Jai module. Standard modules must provide real declarations.

### Scopes

Required scopes:

- global file scope
- module scope
- procedure local scope
- block scope
- struct/enum member scope
- macro capture scope
- inserted-code scope
- workspace scope

`using` and `#as using` add promoted lookup candidates without erasing the
underlying field ownership. Ambiguous promoted lookups must report ambiguity.

## Type System Specification

### Canonical Types

The compiler must have canonical type nodes for:

```text
void
bool
s8 u8 s16 u16 s32 u32 s64 u64
int uint
float32 float64
string
Type
Any
Code
Code_Node and subtypes
Source_Code_Location
Workspace
Build_Options
Compiler_Message and subtypes
pointer(T)
fixed_array(T, N)
slice(T)
dynamic_array(T)
procedure(params, returns, calling_convention)
struct(instance_id)
enum(instance_id)
enum_flags(instance_id)
polymorphic_instance(base, args)
distinct(base)
isa(base)
```

Each type has:

```text
id
kind
size
alignment
runtime_tag
print_name
layout info
type_info emission state
```

### Integer And Float Semantics

Integer operations are width-aware:

- loads and stores preserve declared width
- signed operations sign-extend
- unsigned operations zero-extend
- comparisons use signedness from operand type
- shifts check shift amount where language rules require it
- implicit widening is allowed where Jai allows it
- implicit narrowing is rejected
- explicit casts use the complete cast matrix

Float operations use declared precision. `0h` literals materialize exact
bit-patterns without decimal parsing.

### Conversion Matrix

Sema must implement:

- implicit numeric widening
- explicit numeric narrowing
- checked casts
- `cast,no_check`
- truncating casts
- pointer casts
- bit reinterpret casts where the syntax permits
- `xx` auto-cast
- `#as` implicit aggregate conversions
- distinct and `isa` conversions
- `Any` boxing/unboxing
- enum and enum_flags conversions

Every conversion path must have a diagnostic for invalid use.

### Aggregates

Struct layout must implement:

- field order
- default initializers
- anonymous nested structs
- `using`
- `#as using`
- `#align`
- `#place`
- overlapping storage
- explicit offsets
- no-padding/specification directives used by stress
- copy semantics

Unions and overlay-style layouts must share storage exactly as declared.

### Procedures

Procedure types include:

```text
parameters
return values
named return values
calling convention
default arguments
baked parameters
polymorphic parameters
using parameters
variadic marker
notes
```

Required behavior:

- named and reordered arguments
- default argument materialization
- multi-return ABI
- destructuring assignment
- procedure pointer values
- procedure fields in structs
- recursive procedures
- nested procedures
- legal captures
- `#must` result-use enforcement

### Polymorphism

Polymorphic specialization keys must include:

```text
base declaration id
type arguments
baked value arguments
calling convention
constraint environment
```

`#modify` constraints execute in compile-time context. Constraint failure is a
semantic diagnostic tied to the specialization call site and the constraint
source.

### Overload Resolution

Overload resolution must rank candidates by:

1. exact type match
2. implicit widening
3. contextual enum literal match
4. `#as` conversion
5. polymorphic specialization viability
6. default argument viability

Ambiguous calls are errors. Operator overloads use the same candidate engine,
with additional support for `#symmetric` and commutative search rules.

## Compile-Time Execution Specification

### Values

Compile-time values must be typed. Required value variants:

```text
Void
Bool
Integer(width, signedness)
Float(width)
String(bytes)
Pointer(address model)
Array(elements)
Slice(base, count)
Dynamic_Array(header, storage)
Struct(type, fields)
Enum(type, value)
Enum_Flags(type, bits)
Procedure_Ref
Type_Ref
Any(type, value)
Code
Code_Node_Ref
Source_Code_Location
Workspace_Ref
Build_Options
Compiler_Message
Global_Data_Handle
Null
Undef
```

Unknown values are not valid success states.

### VM

The compile-time VM must execute ordinary bytecode for:

- arithmetic
- comparisons
- control flow
- calls
- recursion
- arrays/slices
- structs
- strings
- pointer-like handles
- dynamic array operations
- allocator operations where used by compile-time code

Unsupported runtime-only operations reached at compile time produce real
diagnostics.

### Host Intrinsics

Compiler APIs are host intrinsics, not fake Jai procedures. Dispatch is based
on a typed intrinsic id after normal overload resolution.

Required host intrinsic families:

- compiler workspace APIs
- build options APIs
- compiler message APIs
- code-tree APIs
- source-location APIs
- global data and data segment APIs
- file/process APIs used by metaprograms
- run-command API

Intrinsics validate argument types, workspace state, and phase availability.

## Code And Macro Specification

### Code Values

`#code` creates:

```text
Code {
    id
    root_node_id
    classification: expression | statement | block | declaration
    type: Type_Ref or void
    source_location
    capture_scope_id
}
```

The root node points into an editable code-tree arena. Code values preserve
provenance and lexical scope.

### Code_Node Family

The compiler must expose real typed nodes:

```text
Code_Node {
    kind
    node_flags
    type
    source_location
}

Code_Literal {
    base: Code_Node
    _s64
    _u64
    _f64
    _string
}

Code_Procedure_Call {
    base: Code_Node
    procedure_expression
    arguments_unsorted
}

Code_Declaration {
    base: Code_Node
    name
    expression
    declaration
}
```

Only fields actually present on a node subtype may be accessed. Invalid casts
or field accesses are diagnostics.

### Round Trip

`compiler_get_nodes(code)` returns:

- `root: *Code_Node`
- `expressions: [] *Code_Node`

Traversal order is source-order preorder unless a spec example requires a more
specific order. `compiler_get_code(root)` serializes the current edited tree
back to a `Code` value. `print_expression` and `code_to_string` serialize the
same tree, not placeholder ids.

### Macro Expansion

`#expand` runs a macro procedure at compile time:

1. Resolve the macro call normally.
2. Bind `$` compile-time parameters.
3. Capture `Code` parameters from caller syntax.
4. Supply default `#caller_code` and `#caller_location` arguments.
5. Execute the macro in compile-time VM/host context.
6. Parse and splice `#insert` results in the requested context.
7. Re-run resolution and sema on inserted AST.

`#insert,scope()` resolves identifiers against the captured scope of the
inserted `Code` value. `#insert,scope(target)` resolves against the supplied
target scope.

Generated identifiers, including backtick-generated names, must be unique,
stable, printable, and source-locatable.

## Runtime Specification

The runtime is defined in `docs/open_jai_runtime.md`; stress adds these
mandatory services:

### Core ABI

Generated code must lower to stable runtime symbols for:

- process startup and shutdown
- printing
- formatting
- string allocation/copy/compare
- dynamic array reserve/add/insert/remove
- allocator dispatch
- temporary storage
- assert/panic
- type_info access
- Any boxing helpers
- file and process module calls
- atomics
- global data handles

All required runtime objects are selected through the runtime manifest. Missing
runtime symbols are link errors, not accepted unresolved externals.

### Data Layouts

The compiler and runtime must agree on layouts for:

```text
string
slice
dynamic array
Any
Type
Type_Info_*
Context
Allocator
String_Builder
Source_Code_Location
File handles
Process handles
Atomic values
```

Layouts are target-specific only where pointer size or ABI alignment requires
it.

### Platform Support

Darwin and Linux are required first-class targets. The implementation must keep
Linux compatibility while fixing host behavior. OS calls route through selected
runtime backends, not through runtime kernel probing.

Inline assembly is a compiler/codegen feature. Linux raw-syscall runtime
assembly can depend on the same target assembly model used by user `#asm`.

## Standard Module Specification

The following modules must be real Jai modules or compiler-provided modules
with real declarations and implementations:

```text
Basic
Compiler
Math
Sort
Random
String
Bit_Array
Hash_Table
File
Base64
Bucket_Array
Unicode
Pool
Flat_Pool
Hash
Crc
md5
xxHash
IntroSort
RadixSort
Atomics
Process
```

Each module contract below is a required public surface for the stress target.
The compiler may implement primitives such as `size_of` and `type_info` as
intrinsics, but they still enter user code through real declarations and typed
semantic entities. Module functions must be ordinary callable declarations
unless explicitly marked as compiler intrinsics.

### Basic Module Contract

`Basic` is the default user-facing prelude for the stress file. It must export
the primitive aliases, runtime types, context, allocator, formatting, dynamic
array, reflection, memory, and assertion APIs listed here.

Required constants and configuration globals:

```jai
ENABLE_ASSERT: bool;
MEMORY_DEBUGGER: bool;
VISUALIZE_MEMORY_DEBUGGER: bool;
TEMP_ALLOCATOR_POISON_FREED_MEMORY: bool;
```

Required runtime/context types:

```jai
Context :: struct {
    allocator: Allocator;
    temp_allocator: Allocator;
    assert_handler: Assert_Handler;
    logger: Logger;
    thread_index: int;
}

Allocator :: struct {
    proc: *void;
    data: *void;
}

Assert_Handler :: distinct *void;  // concrete representation may change, but it is a typed value
Logger :: distinct *void;          // concrete representation may change, but it is a typed value

String_Builder :: struct {
    data: *u8;
    count: int;
    allocated: int;
    allocator: Allocator;
}
```

Required global values:

```jai
context: Context;
temp: Allocator;
__command_line_arguments: [] string;
```

Required allocation and memory functions:

```jai
alloc       :: (size: int, allocator: Allocator = context.allocator) -> *void;
free        :: (ptr: *void, allocator: Allocator = context.allocator);
resize      :: (ptr: *void, old_size: int, new_size: int, allocator: Allocator = context.allocator) -> *void;
memset      :: (ptr: *void, value: u8, count: int) -> *void;
memcpy      :: (dst: *void, src: *void, count: int) -> *void;
memcmp      :: (a: *void, b: *void, count: int) -> int;
push_allocator :: (allocator: Allocator);
reset_temporary_storage :: ();
```

Required printing and formatting functions:

```jai
print            :: (fmt: string, args: ..Any);
sprint           :: (fmt: string, args: ..Any, allocator: Allocator = context.allocator) -> string;
tprint           :: (fmt: string, args: ..Any) -> string;
print_to_builder :: (builder: *String_Builder, fmt: string, args: ..Any);

init_string_builder :: (builder: *String_Builder, allocator: Allocator = context.allocator);
append              :: (builder: *String_Builder, value: string);
builder_to_string   :: (builder: *String_Builder) -> string;
free_string_builder :: (builder: *String_Builder);

to_string    :: (data: *u8, count: int) -> string;
formatInt    :: (value: $T, base: int = 10, minimum_digits: int = 0,
                 digits_per_comma: int = 0, comma_string: string = ",") -> FormatInt;
formatFloat  :: (value: $T, width: int = -1, trailing_width: int = -1,
                 zero_removal: bool = true, mode: Format_Float_Mode = .DEFAULT) -> FormatFloat;
formatStruct :: (value: $T, use_long_form_if_more_than_this_many_members: int = -1,
                 use_newlines_if_long_form: bool = false) -> FormatStruct;
```

Required formatting types:

```jai
FormatInt :: struct {
    value: Any;
    base: int;
    minimum_digits: int;
    digits_per_comma: int;
    comma_string: string;
    padding: u8;
}

FormatFloat :: struct {
    value: Any;
    width: int;
    trailing_width: int;
    zero_removal: bool;
    mode: Format_Float_Mode;
    positive_number_prefix: enum { NONE; PLUS; SPACE; };
}

FormatStruct :: struct {
    value: Any;
    draw_type_name: bool;
    use_long_form_if_more_than_this_many_members: int;
    use_newlines_if_long_form: bool;
}

FormatArray :: struct {
    value: Any;
    separator: string;
    begin_string: string;
    end_string: string;
    stop_printing_after_this_many_elements: int;
}
```

Required dynamic-array functions:

```jai
array_add                       :: (array: *[..] $T, value: T) -> *T;
array_insert_at                 :: (array: *[..] $T, value: T, index: int);
array_unordered_remove_by_index :: (array: *[..] $T, index: int);
array_ordered_remove_by_index   :: (array: *[..] $T, index: int);
array_find                      :: (array: [] $T, value: T) -> (found: bool, index: int);
array_copy                      :: (array: [] $T, allocator: Allocator = context.allocator) -> [..] T;
array_view                      :: (array: [..] $T) -> [] T;
array_free                      :: (array: [..] $T);
```

Required reflection and type functions:

```jai
size_of     :: ($T: Type) -> int;              // compiler intrinsic
size_of     :: (value: $T) -> int;             // compiler intrinsic
type_of     :: (value: $T) -> Type;            // compiler intrinsic
type_info   :: ($T: Type) -> *Type_Info;       // compiler intrinsic
type_to_string :: (t: Type) -> string;

enum_names          :: ($T: Type) -> [] string;
enum_values_as_s64  :: ($T: Type) -> [] s64;
enum_values_as_enum :: ($T: Type) -> [] T;
enum_range          :: ($T: Type) -> (lo: T, hi: T);
```

Required reflection layouts:

```jai
Type_Info :: struct {
    type: Type_Info_Tag;
    runtime_size: int;
    name: string;
}

Type_Info_Tag :: enum {
    VOID; BOOL; INTEGER; FLOAT; POINTER; ARRAY; STRUCT; ENUM;
    PROCEDURE; TYPE; ANY; STRING;
}

Type_Info_Struct :: struct {
    using base: Type_Info;
    members: [] Type_Info_Struct_Member;
    parameters: [] Type_Info_Parameter;
}

Type_Info_Struct_Member :: struct {
    name: string;
    type: Type;
    offset_in_bytes: int;
    notes: [] Note;
}

Type_Info_Array :: struct {
    using base: Type_Info;
    array_type: enum { FIXED; VIEW; RESIZABLE; };
    element_type: Type;
    array_count: int;
}

Type_Info_Enum :: struct {
    using base: Type_Info;
    names: [] string;
    values_as_s64: [] s64;
    internal_type: Type_Info_Integer;
    enum_type_flags: Enum_Type_Flags;
}
```

Required scalar helpers:

```jai
min   :: (a: $T, b: T) -> T;
max   :: (a: $T, b: T) -> T;
clamp :: (x: $T, lo: T, hi: T) -> T;
abs   :: (x: $T) -> T;
```

Required assertions:

```jai
assert :: (condition: bool, fmt: string = "", args: ..Any);
```

### Compiler Module Contract

`Compiler` must expose typed compile-time values and host-backed intrinsics.

Required types:

```jai
Workspace :: distinct int;

Build_Options :: struct {
    output_executable_name: string;
    output_path: string;
    output_type: Output_Type;
    backend: Backend;
    import_path: [..] string;
    compile_time_command_line: [] string;
    do_output: bool;
    debug_info: bool;
    optimization_level: Optimization_Level;
}

Source_Code_Location :: struct {
    fully_pathed_filename: string;
    line_number: int;
    character_number: int;
}

Message :: struct {
    kind: Message_Kind;
    location: Source_Code_Location;
    text: string;
    workspace: Workspace;
}

Message_Kind :: enum {
    FILE; IMPORT; PHASE; TYPECHECKED; DEBUG_DUMP; ERROR; COMPLETE;
}

Compile_Phase :: enum {
    TYPECHECKED_ALL_WE_CAN;
    PRE_WRITE_EXECUTABLE;
    POST_WRITE_EXECUTABLE;
}
```

Required code-tree types are defined in the `Code And Macro Specification`
section and must be exported by this module:

```jai
Code;
Code_Node;
Code_Literal;
Code_Procedure_Call;
Code_Declaration;
```

Required workspace and build APIs:

```jai
compiler_create_workspace :: (name: string = "") -> Workspace;
get_current_workspace     :: () -> Workspace;

get_build_options    :: (workspace: Workspace = get_current_workspace()) -> Build_Options;
set_build_options    :: (options: Build_Options, workspace: Workspace = get_current_workspace());
set_build_options_dc :: (args: ..Any);
set_optimization     :: (level: Optimization_Level, workspace: Workspace = get_current_workspace());

add_build_file   :: (path: string, workspace: Workspace = get_current_workspace());
add_build_string :: (source: string, workspace: Workspace = get_current_workspace());
add_data_segment :: (name: string, data: [] u8, workspace: Workspace = get_current_workspace());
add_global_data  :: (name: string, data: [] u8, workspace: Workspace = get_current_workspace()) -> Global_Data_Handle;
```

Required intercept/message APIs:

```jai
compiler_begin_intercept       :: (workspace: Workspace);
compiler_wait_for_message      :: () -> *Message;
compiler_end_intercept         :: (workspace: Workspace);
compiler_set_workspace_status  :: (status: Workspace_Status, workspace: Workspace);
compiler_report                :: (message: string, location: Source_Code_Location);
make_location                  :: (decl: *Code_Declaration) -> Source_Code_Location;
```

Required code-tree APIs:

```jai
compiler_get_nodes       :: (code: Code) -> (root: *Code_Node, expressions: [] *Code_Node);
compiler_get_code        :: (root: *Code_Node) -> Code;
compiler_modify_procedure :: (proc: *Code_Declaration, replacement: Code);
code_to_string           :: (code: Code) -> string;
print_expression         :: (builder: *String_Builder, root: *Code_Node);
```

Required process/host API used by build scripts and diagnostics:

```jai
run_command :: (command: string, args: [] string = .[]) -> Process_Result;
```

All `Compiler` procedures above are illegal at runtime unless the official
semantics explicitly allow runtime use. Runtime calls must produce diagnostics,
not null workspaces or fake messages.

### Math Module Contract

`Math` must provide scalar math plus the vector, matrix, quaternion, and fixed
point helpers used by stress.

Required scalar functions:

```jai
sqrt  :: (x: $T) -> T;
sin   :: (x: $T) -> T;
cos   :: (x: $T) -> T;
tan   :: (x: $T) -> T;
asin  :: (x: $T) -> T;
acos  :: (x: $T) -> T;
atan  :: (x: $T) -> T;
atan2 :: (y: $T, x: T) -> T;

floor :: (x: $T) -> T;
ceil  :: (x: $T) -> T;
round :: (x: $T) -> T;
trunc :: (x: $T) -> T;

pow   :: (x: $T, y: T) -> T;
exp   :: (x: $T) -> T;
log   :: (x: $T) -> T;
log2  :: (x: $T) -> T;
log10 :: (x: $T) -> T;

abs   :: (x: $T) -> T;
min   :: (a: $T, b: T) -> T;
max   :: (a: $T, b: T) -> T;
clamp :: (x: $T, lo: T, hi: T) -> T;
```

Required aggregate types and operations:

```jai
Vector2 :: struct { x, y: float; }
Vector3 :: struct { x, y, z: float; }
Vector4 :: struct { x, y, z, w: float; }

Matrix3 :: struct {
    _11, _12, _13: float;
    _21, _22, _23: float;
    _31, _32, _33: float;
}

Matrix4 :: struct {
    _11, _12, _13, _14: float;
    _21, _22, _23, _24: float;
    _31, _32, _33, _34: float;
    _41, _42, _43, _44: float;
}

Quaternion :: struct { x, y, z, w: float; }
```

For each vector type, the module must support construction, field access,
addition, subtraction, scalar multiplication/division, dot product, length,
normalization, and deterministic formatting through `print`.

For matrices/quaternions, the module must support identity construction,
multiplication, transform helpers used by stress, and field names such as
`_11`, `_12`, `_21`, and so on.

### Sort And IntroSort Module Contracts

Required `Sort` functions:

```jai
quick_sort  :: (array: [] $T, compare: (a: T, b: T) -> int);
bubble_sort :: (array: [] $T, compare: (a: T, b: T) -> int = default_compare);
```

Required `IntroSort` functions:

```jai
intro_sort :: (array: [] $T, compare: (a: T, b: T) -> int);
```

Sorts must operate on array views in place, support empty and single-element
views, call user comparators, and preserve deterministic ordering for equal
items when the algorithm contract requires it.

### Random Module Contract

Required functions:

```jai
random_seed             :: (seed: u64);
random_get              :: () -> u64;
random_get_within_range :: (lo: int, hi: int) -> int;
```

The generator must be deterministic for a fixed seed and match the stress
reference stream.

### String Module Contract

Required functions:

```jai
split                 :: (s: string, separator: u8) -> [..] string;
split                 :: (s: string, separator: string) -> [..] string;
join                  :: (parts: ..string, separator: string = "") -> string;
contains              :: (s: string, needle: string) -> bool;
replace               :: (s: string, needle: string, replacement: string) -> string;
trim                  :: (s: string) -> string;
find_index_from_left  :: (s: string, needle: string) -> int;
find_index_from_right :: (s: string, needle: string) -> int;
```

String functions operate on byte strings. They must preserve embedded NULs,
return `-1` for not-found indexes where stress expects it, and allocate through
the active allocator unless a function exposes an allocator argument.

### Bit_Array Module Contract

Required type and functions:

```jai
Bit_Array :: struct {
    bits: [..] u64;
    nbits: int;
}

bit_array_init   :: (array: *Bit_Array, bit_count: int);
bit_array_free   :: (array: *Bit_Array);
bit_array_get    :: (array: *Bit_Array, index: int) -> bool;
bit_array_set    :: (array: *Bit_Array, index: int, value: bool = true);
bit_array_clear  :: (array: *Bit_Array, index: int);
bit_array_count  :: (array: *Bit_Array) -> int;
bit_array_reset  :: (array: *Bit_Array);
```

Indexing must bounds-check in checked builds.

### Hash_Table Module Contract

Required type and functions:

```jai
Table :: struct($K: Type, $V: Type) {
    count: int;
}

init           :: (table: *Table($K, $V));
deinit         :: (table: *Table($K, $V));
table_add      :: (table: *Table($K, $V), key: K, value: V);
table_set      :: (table: *Table($K, $V), key: K, value: V);
table_find     :: (table: *Table($K, $V), key: K) -> *V;
table_contains :: (table: *Table($K, $V), key: K) -> bool;
```

The table must support `for value, key: table` iteration. Iteration order need
not be sorted, but it must be deterministic for a given process and insertion
sequence. Stress sorts gathered keys where sorted output is required.

### File Module Contract

Required enums and flags:

```jai
File_Modes :: enum_flags u32 {
    READ; WRITE; APPEND; BINARY; EXEC; HIDDEN;
}
```

Required functions:

```jai
make_directory_if_it_does_not_exist :: (path: string) -> bool;
write_entire_file                   :: (path: string, data: [] u8) -> bool;
write_entire_file                   :: (path: string, data: string) -> bool;
read_entire_file                    :: (path: string, log_errors: bool = true) -> (data: [..] u8, success: bool);
delete_file                         :: (path: string) -> bool;
```

All filesystem output used by tests must be redirected under `out/` by the
test harness or by build options. The module itself implements normal path
semantics.

### Base64 Module Contract

Required functions:

```jai
base64_encode    :: (data: [] u8) -> string;
base64_encode    :: (data: string) -> string;
base64_decode    :: (text: string) -> (out: [..] u8, ok: bool);
base64url_encode :: (data: [] u8) -> string;
base64url_encode :: (data: string) -> string;
base64url_decode :: (text: string) -> (out: [..] u8, ok: bool);
```

Invalid input returns `ok=false` without partial successful output.

### Bucket_Array Module Contract

Required types and functions:

```jai
Bucket_Array :: struct($T: Type) {
    count: int;
    all_buckets: [..] *void;
    unfull_buckets: [..] *void;
}

Bucket_Location :: struct {
    bucket_index: int;
    item_index: int;
}

bucket_array_init   :: (array: *Bucket_Array($T));
bucket_array_reset  :: (array: *Bucket_Array($T));
bucket_array_add    :: (array: *Bucket_Array($T), value: T) -> (location: Bucket_Location, ptr: *T);
bucket_array_find   :: (array: *Bucket_Array($T), location: Bucket_Location) -> *T;
bucket_array_remove :: (array: *Bucket_Array($T), location: Bucket_Location);
```

Locations remain valid until the item is removed or the array is reset.

### Unicode Module Contract

Required types and functions:

```jai
Unicode_Result :: enum {
    CONVERSION_OK;
    SOURCE_EXHAUSTED;
    TARGET_EXHAUSTED;
    SOURCE_ILLEGAL;
}

character_utf32_to_utf8 :: (codepoint: u32, out: *u8) -> (bytes_written: int, result: Unicode_Result);
character_utf8_to_utf32 :: (data: *u8, count: int) -> (codepoint: u32, bytes_read: int, result: Unicode_Result);
utf8_next_character     :: (s: *string) -> (codepoint: u32, result: Unicode_Result);
```

UTF-8 decoding must reject overlong encodings, surrogate codepoints, invalid
continuation bytes, and codepoints above `0x10FFFF`.

### Pool And Flat_Pool Module Contracts

Required `Pool` surface:

```jai
Pool :: struct {
    // Backing storage, block list, cursor, and allocator fields are real
    // module-private fields. They are not compiler placeholders.
}

get     :: (pool: *Pool, size: int) -> *void;
reset   :: (pool: *Pool);
release :: (pool: *Pool);
```

Required `Flat_Pool` surface:

```jai
Flat_Pool :: struct {
    // Backing storage, cursor, capacity, and allocator fields are real
    // module-private fields. They are not compiler placeholders.
}

get   :: (pool: *Flat_Pool, size: int) -> *void;
reset :: (pool: *Flat_Pool);
fini  :: (pool: *Flat_Pool);
```

Returned memory is aligned at least to pointer alignment and remains live until
`reset`, `release`, or `fini` according to the module type.

### Hash, Crc, md5, And xxHash Module Contracts

Required `Hash` functions:

```jai
sdbm_hash  :: (data: *u8, count: int) -> u64;
fnv1a_hash :: (data: *u8, count: int) -> u64;
get_hash   :: (value: $T) -> u64;
```

Required `Crc` function:

```jai
crc64 :: (data: string) -> u64;
```

Required `md5` function:

```jai
md5 :: (data: string) -> string;
```

Required `xxHash` types and functions:

```jai
XXH32_state_t :: struct {
    seed: u32;
    total_len: u64;
    state: [4] u32;
    buffer: [16] u8;
    buffer_count: u32;
}

XXH64_state_t :: struct {
    seed: u64;
    total_len: u64;
    state: [4] u64;
    buffer: [32] u8;
    buffer_count: u32;
}

XXH32_reset  :: (state: *XXH32_state_t, seed: u32);
XXH32_update :: (state: *XXH32_state_t, data: *u8, count: u32);
XXH32_digest :: (state: *XXH32_state_t) -> u32;

XXH64_reset  :: (state: *XXH64_state_t, seed: u64);
XXH64_update :: (state: *XXH64_state_t, data: *u8, count: u32);
XXH64_digest :: (state: *XXH64_state_t) -> u64;
```

The hash outputs must match the reference values embedded in stress.

### RadixSort Module Contract

Required type and functions:

```jai
RadixSort :: struct {
    ranks: [..] u32;
    scratch: [..] u32;
}

sort           :: (state: *RadixSort, data: *u32, count: u32);
rank           :: (state: *RadixSort, index: u32) -> u32;
free_resources :: (state: *RadixSort);
```

`rank` returns the rank mapping produced by the most recent `sort`.

### Process Module Contract

Required types:

```jai
Process_Result_Type :: enum {
    UNSTARTED;
    STILL_RUNNING;
    FAILED_TO_LAUNCH;
    EXITED;
    SIGNALED;
}

Process_Result :: struct {
    type: Process_Result_Type;
    exit_code: s32;
    signal: s32;
}

Process_Argument_Quoting :: enum {
    QUOTE_IF_NEEDED;
    NEVER_QUOTE;
}
```

The runtime process execution API used by `run_command` must return this
layout. The stress runtime section checks type sizes and enum values without
launching child processes.

### Atomics Module Contract

Required functions:

```jai
atomic_read  :: (ptr: *$T) -> T;
atomic_write :: (ptr: *$T, value: T);
atomic_add   :: (ptr: *$T, value: T) -> T;
```

Supported `T` includes at least `s32`, `u32`, `s64`, and `u64`. `atomic_add`
returns the previous value. Operations lower to target atomics, not locks,
when the target supports them.

## Diagnostics Specification

The diagnostic catalog in the stress file creates independent workspaces for
invalid snippets. The compiler must provide stable diagnostic kinds for:

- lexer errors
- parser errors
- import/load errors
- unresolved names
- redeclarations
- invalid directives
- type mismatches
- range errors
- bad casts
- invalid lvalues
- pointer misuse
- bad calls
- return arity/type errors
- overload ambiguity
- polymorphic constraint failures
- invalid struct/enum/array operations
- invalid `#insert` and `#expand`
- format string errors
- invalid FFI declarations
- invalid inline assembly
- workspace misuse
- allocation/assertion failures at compile time

Diagnostic objects must include:

```text
kind
severity
message
primary location
secondary locations
workspace id
phase
```

Human-readable wording can evolve, but stress matching requires the same
stable output once the golden harness is enabled.

## Implementation Slices

Implementation must proceed in slices that each end with tests. A slice is
complete only when it removes a real gap and does not add placeholders.

### Slice 1: Literal And String Front End

- implement full numeric tokenization and `0h` bit-pattern semantics
- implement underscore diagnostics
- implement byte-preserving `#string`
- add lexer/parser tests
- rerun `openjai utils/stress.jai --check`

Zig design source:

- `.reference/zig/lib/std/zig/tokenizer.zig`
- `.reference/zig/lib/std/zig/number_literal.zig:1`
- `.reference/zig/lib/std/zig/string_literal.zig:1`
- `.reference/zig/lib/std/unicode.zig:15`
- `.reference/zig/test/behavior/nan.zig:7`

Implementation detail:

- Add a Jai literal parser module instead of baking all decisions into token
  classification. It returns a structured result with literal kind, radix,
  exact integer bits or exact float bit-pattern payload, suffix/type request,
  normalized digits, and a typed error.
- `0h` literals are bit-pattern literals. Assignment/cast context decides
  whether the payload becomes `float32`, `float64`, an integer bit value, or a
  diagnostic. NaN tests must assert exact bit equality, following Zig's
  behavior tests.
- `#string` payloads preserve bytes exactly until string literal validation is
  explicitly requested by sema.

Expected result: stress advances past the current line 159 blocker.

### Slice 2: Structured AST Coverage

- convert parser output to compact typed AST nodes
- add token ranges and source spans to every node
- replace parser opaque nodes for valid syntax with real node tags
- add AST snapshot tests for stress syntax forms
- rerun `openjai utils/stress.jai --check`

Zig design source:

- `.reference/zig/lib/std/zig/Ast.zig:17`
- `.reference/zig/lib/std/zig/Ast.zig:29`
- `.reference/zig/lib/std/zig/Ast.zig:120`
- `.reference/zig/lib/std/zig/Ast.zig:145`

Implementation detail:

- Follow Zig's node-array design: token stream, node tag array, node data array,
  and extra-data array. Jai AST nodes should reference token indices and
  extra-data spans rather than owning nested allocations per syntax form.
- Valid Jai constructs used by stress, including directives, notes, local
  imports, backtick identifiers, polymorphic parameter lists, `using`, and
  multi-return forms, must have explicit AST tags.
- Parse recovery may produce error nodes only after recording a diagnostic.
  Error nodes are not allowed in successful compilation.

Expected result: parser coverage is structural and later phases no longer need
to inspect raw source text for stress constructs.

### Slice 3: Real Module Loading

- remove placeholder import success paths for stress modules
- add missing module skeletons with real declarations
- require unresolved APIs to fail loudly
- add import/namespace tests

Zig design source:

- `.reference/zig/src/Package/Module.zig:1`
- `.reference/zig/src/Package/Module.zig:45`
- `.reference/zig/src/Package/Module.zig:87`
- `.reference/zig/src/Compilation.zig:1849`
- `.reference/zig/lib/std/zig/AstGen.zig:53`

Implementation detail:

- Add a real module graph with canonical root path, display path, source files,
  dependency map, imported names, and inherited build options.
- `#import` lowers into import records during AST-to-IR lowering. Resolver then
  loads and indexes the imported module before name lookup.
- Missing modules or symbols produce structured diagnostics. No placeholder
  declarations or global compiler API fallbacks are permitted.

Expected result: import section and qualified module references resolve only to
real declarations.

### Slice 4: Scalar Sema And Lowering

- implement exact integer widths
- implement cast matrix
- implement bool short-circuit lowering
- implement primitive formatting
- add runtime tests for sections 1-3

Zig design source:

- `.reference/zig/src/InternPool.zig:1`
- `.reference/zig/src/Type.zig:1`
- `.reference/zig/src/Type.zig:26`
- `.reference/zig/src/Type.zig:114`
- `.reference/zig/src/Value.zig:1`
- `.reference/zig/src/Sema.zig:1`
- `.reference/zig/src/Air.zig:37`

Implementation detail:

- Move scalar type/value identity into interned handles. Sema operates on
  interned types and values, not strings or parser tags.
- Implement a scalar cast table with signedness, width, float/int conversion,
  pointer/integer restrictions, constant range checks, and runtime conversion
  lowering.
- Lower boolean short-circuit operators into control-flow IR before bytecode or
  native codegen. Do not model them as eager binary operations.
- Formatting of primitive values goes through the Basic formatting API and the
  runtime string builder, following Zig's split between formatting parser and
  writer.

Expected result: numeric, cast, and bool sections compile and run.

### Slice 5: Arrays, Strings, Allocators

- implement fixed arrays, slices, dynamic arrays
- implement string ABI and builders
- implement temporary allocator and context allocator switching
- add runtime tests for sections 4-5 and allocator sections

Zig design source:

- `.reference/zig/lib/std/array_list.zig:22`
- `.reference/zig/lib/std/array_list.zig:101`
- `.reference/zig/lib/std/fmt.zig:31`
- `.reference/zig/lib/std/heap.zig:12`
- `.reference/zig/lib/std/heap/ArenaAllocator.zig:1`
- `.reference/zig/lib/std/heap/ArenaAllocator.zig:46`
- `.reference/zig/lib/std/heap/memory_pool.zig:24`

Implementation detail:

- Define stable ABI layouts for `[]T`, `[N]T`, `string`, dynamic arrays, and
  builders. Codegen and runtime must agree on pointer/count/capacity fields.
- Dynamic arrays follow Zig's `ArrayList` ownership model: allocator, items,
  capacity, append/insert/resize, and conversion to owned slice.
- Allocators are runtime interfaces. Temporary allocator, context allocator,
  arena, pool, and flat-pool modules must call the allocator interface rather
  than platform allocation directly.

Expected result: array/string-heavy early sections run without runtime hacks.

### Slice 6: Procedures And Polymorphism

- implement multi-return/default/named args
- implement procedure pointer calls
- implement polymorphic procs and structs
- implement `#modify`
- add runtime and diagnostic tests

Zig design source:

- `.reference/zig/lib/std/zig/AstGen.zig:58`
- `.reference/zig/src/Sema.zig:41`
- `.reference/zig/src/Sema.zig:90`
- `.reference/zig/src/Sema.zig:131`
- `.reference/zig/src/Air.zig:1`

Implementation detail:

- Lower procedure declarations to IR with explicit parameter descriptors,
  default argument expressions, named argument maps, return tuple layout, call
  convention, and compile-time parameter flags.
- Instantiate polymorphic procedures and structs through a memoized
  specialization table keyed by interned type/value arguments, matching Zig's
  Sema memoization approach.
- `#modify` participates in declaration lowering and specialization. It is not
  a post-hoc text rewrite.

Expected result: sections 7-9 and procedure diagnostics pass.

### Slice 7: Aggregates, Enums, Reflection

- implement `using`, `#as using`, `#place`
- implement enums and enum_flags
- implement `Any` and `type_info`
- add reflection/output tests

Zig design source:

- `.reference/zig/src/InternPool.zig:38`
- `.reference/zig/src/InternPool.zig:133`
- `.reference/zig/src/Type.zig:26`
- `.reference/zig/src/Value.zig:27`
- `.reference/zig/test/behavior/type_info.zig:12`

Implementation detail:

- Aggregate layout is a semantic product with interned field names, field
  types, offsets, alignments, default values, notes, and namespace links.
- `using` fields add lookup projections while preserving the actual field
  layout. Ambiguity is a resolver error.
- `Any` and `type_info` are generated from the same interned type metadata used
  by Sema and codegen. Reflection tests assert shape and field values, not just
  successful calls.

Expected result: aggregate/reflection sections pass and module generic code can
use type metadata.

### Slice 8: Compile-Time VM And Macros

- implement typed compile-time values
- implement compiler-host intrinsic dispatch
- implement `Code`, `Code_Node`, `#code`, `#expand`, `#insert`
- add code-tree mutation and macro tests

Zig design source:

- `.reference/zig/src/Sema.zig:164`
- `.reference/zig/src/Value.zig:134`
- `.reference/zig/src/InternPool.zig:1`
- `.reference/zig/lib/std/zig/AstGen.zig:58`
- `.reference/zig/lib/std/zig/Zir.zig`

Implementation detail:

- CT execution values are typed interned values plus tracked compile-time
  allocations. `Code`, `Code_Node`, workspaces, messages, locations, and
  handles are first-class CT value kinds.
- Host intrinsics are explicit compiler calls with typed signatures and phase
  permissions. Unsupported compiler APIs produce diagnostics at the call site.
- `#code` captures AST plus source provenance and capture scope. `#insert`
  parses/splices through the same AST and IR path used for ordinary source.
  `#insert,scope` resolves identifiers against the captured scope, not the
  insertion caller by accident.

Expected result: macro/code sections and their diagnostics pass.

### Slice 9: Runtime And Standard Modules

- complete runtime objects and manifest selection
- implement file/process/atomics
- port/finish missing standard modules
- add module behavioral tests

Zig design source:

- `.reference/zig/src/Compilation.zig:1849`
- `.reference/zig/src/codegen/llvm.zig:39`
- `.reference/zig/src/codegen/llvm.zig:54`
- `.reference/zig/lib/std/fs.zig`
- `.reference/zig/lib/std/process.zig:30`
- `.reference/zig/lib/std/atomic.zig:8`
- `.reference/zig/lib/std/hash_map.zig:46`
- `.reference/zig/lib/std/bit_set.zig:700`
- `.reference/zig/lib/std/base64.zig:1`
- `.reference/zig/lib/std/unicode.zig:15`

Implementation detail:

- Runtime selection is target-driven. The compiler emits a runtime manifest
  containing required symbols, object files, platform syscall layer, allocator
  entry points, panic/assert hooks, start code, and module support objects.
- Platform-specific file, process, time, threading, and atomic operations are
  behind runtime interfaces. Modules call those interfaces through stable Jai
  declarations.
- Standard modules must be real Jai code where possible and runtime-backed only
  for platform primitives. Data structures follow the Zig library ownership
  models listed in this spec.

Expected result: extras 2-11 run through ordinary module code.

### Slice 10: Workspaces And Diagnostic Catalog

- implement workspaces and intercept scheduler
- implement build string/file APIs
- implement compiler messages
- compile diagnostic snippets through real workspaces
- add catalog tests

Zig design source:

- `.reference/zig/src/Compilation.zig:2871`
- `.reference/zig/src/Compilation.zig:3928`
- `.reference/zig/src/link.zig:34`
- `.reference/zig/src/Package/Module.zig:1`

Implementation detail:

- Workspaces are independent compilation graphs with source files, module
  graph, build options, diagnostics, pending jobs, and intercept state.
- `add_build_string` creates real source records and schedules them in the
  target workspace. Diagnostic catalog snippets compile through this path.
- Message queues use structured objects and deterministic order. Rendering is a
  final step, following Zig's error-bundle/diagnostic separation.

Expected result: lines 36815-41342 produce the expected diagnostic stream.

### Slice 11: Golden Stress Harness

- add `make stress` after deterministic behavior exists
- build executable under `out/stress`
- capture compile-time and runtime output
- extract `EXPECTED_OUTPUT`
- byte-compare output

Zig design source:

- `.reference/zig/src/Compilation.zig:2871`
- `.reference/zig/src/Compilation.zig:3928`
- `.reference/zig/test/behavior/nan.zig:7`
- `.reference/zig/test/behavior/atomics.zig:13`
- `.reference/zig/test/behavior/type_info.zig:12`

Implementation detail:

- The harness runs through the public compiler executable and captures
  compile-time diagnostics, compile-time prints, runtime stdout, runtime stderr,
  and exit status.
- Golden comparison is byte-for-byte after only explicitly documented
  normalizations, such as absolute path prefixes. It is not a substring or
  regex matcher.
- The harness is a gate in `make test` only after all earlier slices are green;
  until then, slice-local tests are the gate.

Expected result: the stress file is a gating test.

## Test Requirements

Each implementation slice must add tests in one or more of:

```text
bootstrap/src/test_main.zig
test/examples/
utils/
```

Required test classes:

- parser unit tests for syntax forms
- sema tests for valid and invalid programs
- bytecode/VM tests for compile-time execution
- runtime behavior tests that execute generated binaries
- module tests using `@TestProcedure`
- diagnostic workspace tests
- golden output tests

Compile-only tests are not sufficient for features that have runtime or
compile-time behavior.

## Current First Failure

The current observed stress failure is:

```text
utils/stress.jai:159:26: error: invalid numeric literal suffix
        nan32   : float32 = 0h7fbf_ffff;
                             ^
```

The first implementation slice must fix this by implementing `0h` float
bit-pattern literals, not by accepting this spelling as an untyped placeholder.

## Completion State

This spec is complete when every feature above has:

1. a real compiler/runtime/module implementation,
2. focused tests,
3. a passing stress run,
4. no placeholder-backed success path,
5. no root-level output artifacts.
