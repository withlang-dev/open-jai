# Enable `utils/stress.jai`

`utils/stress.jai` is to be treated as a compiler and runtime specification.
The goal is not to add compatibility shims for this file. The goal is to make
OpenJai implement the language and module semantics that every line of this file
requires.

The file has two different kinds of content:

- Lines 1-41342 are Jai source that must parse, resolve, typecheck, compile,
  link, and run.
- Lines 41343-63366 are the `EXPECTED_OUTPUT :: #string ...` reference blob.
  Those lines must be preserved byte-for-byte as string data, including the NUL
  byte currently present in the file.

Current observed baseline:

```text
./out/bootstrap/bin/openjai utils/stress.jai --check
utils/stress.jai:159:26: error: invalid numeric literal suffix
        nan32   : float32 = 0h7fbf_ffff;
                             ^
```

That first failure hides many later gaps. The implementation order below should
therefore be gate-based: remove one real language/runtime gap, add focused
tests, then rerun the stress file to discover the next concrete failure.

## Status Legend

- **OK**: expected to parse and run today, subject to later golden-output
  verification.
- **Partial**: some examples in the range probably work, but the range depends
  on semantics that are incomplete or placeholder-backed.
- **Missing**: the range depends on a feature or module OpenJai does not
  currently implement correctly.
- **Data**: not executable Jai, but still part of the specification.

## Line Coverage Ledger

Every line in `utils/stress.jai` is covered by one of these rows. Comments and
blank lines inherit the status of the surrounding range because they define the
intended semantics and reference behavior.

| Lines | Status | Requirement | Compiler change needed |
| --- | --- | --- | --- |
| 1-23 | OK | File-level description and expected-output contract. | None beyond keeping this file as an acceptance test. |
| 24-41 | Missing | Imports for `Basic`, `Compiler`, `Math`, `Sort`, `Random`, `String`, `Bit_Array`, `Hash_Table`, `File`, `Base64`, `Bucket_Array`, `Unicode`, `Pool`, `Flat_Pool`, `Hash`, `Crc`, `md5`, and `xxHash`. | Replace placeholder import acceptance with real module discovery, namespace binding, typechecking, and codegen. Add or port all missing modules: `Bit_Array`, `Base64`, `Bucket_Array`, `Unicode`, `Hash`, `Crc`, `md5`, `xxHash`, `IntroSort`, `RadixSort`, and `Atomics`. |
| 42 | Missing | Separator before local helper declarations. | Covered by the surrounding import/module-loading requirement. |
| 43-98 | Partial | Basic struct declarations, string constants, simple procs, `null`, pointer comparison, and formatted printing. | Verify struct layout and string ABI. Remove any placeholder-backed print or pointer behavior. |
| 99 | Partial | Separator before numeric tests. | Covered by the surrounding runtime-source requirement. |
| 100-172 | Missing | Numeric scalar types, exact integer widths, default initialization, `---`, constants, `0h` IEEE-754 bit-pattern float literals, numeric separators, compile-time literal range checks, `size_of`, and type equality. | Implement full numeric literal scanner and parser, including `0h` float bit patterns and underscore validation. Lower `s8/u8/s16/u16/s32/u32/s64/u64` as real widths with correct load/store/sign/zero extension. Add checked compile-time literal coercion. |
| 173 | Missing | Separator before cast tests. | Covered by the numeric/cast requirement. |
| 174-208 | Partial | `cast`, `cast,no_check`, integer widening/narrowing, signedness, float-int conversions. | Implement the complete cast matrix in sema and codegen: checked casts, `no_check`, `trunc`, `no_widen`, force/bit reinterpret where specified, and runtime traps for checked narrowing failures. |
| 209-210 | Partial | Separator before boolean tests. | Covered by the surrounding runtime-source requirement. |
| 211-245 | Partial | Bool operators, truthiness through `!`, and short-circuit `&&`/`||`. | Lower `&&` and `||` as control flow with short-circuit side-effect preservation instead of eager binary operators. Define bool coercion from numeric values exactly. |
| 246-247 | Partial | Separator before array tests. | Covered by the surrounding runtime-source requirement. |
| 248-349 | Partial | Fixed arrays, slices, resizable arrays, array literals, `array_add`, insertion/removal, `for`, `for *`, `for <`, `for *<`, range loops, string iteration, pointer arithmetic, bounds checks. | Implement array storage layouts and copy/view semantics, dynamic-array runtime helpers, all for-loop forms, pointer iteration, static/dynamic bounds checks, and array formatting. |
| 350-351 | Partial | Separator before string tests. | Covered by the surrounding runtime-source requirement. |
| 352-433 | Partial | Strings, escapes, `#string`, `sprint`, `tprint`, `String_Builder`, content equality, `formatInt`, `formatFloat`, `formatStruct`. | Finish escape decoding including decimal escapes and embedded NULs. Implement string runtime ABI, builder operations, format structs and all formatting options (`digits_per_comma`, `comma_string`, padding, float modes, long-form struct output). |
| 434-435 | Partial | Separator before struct tests. | Covered by the surrounding runtime-source requirement. |
| 436-529 | Partial | Struct defaults, compound member declarations, anonymous nested structs, `using`, `#as using`, designated literals, implicit `#as` conversions. | Implement container field binding, default initialization order, anonymous type identity, `using` lookup, `#as` layout/implicit conversion, and struct printing/copying. |
| 530-594 | Partial | Multi-return procedures, named returns, default arguments, variadic-like calls, named/reordered args. | Implement full procedure signature model: multi-return ABI, named return storage, call-site default materialization, named argument matching/reordering, and diagnostics for bad calls. |
| 595-661 | Missing | Polymorphic procs, `$T`, `$$T`, pointer parameters, `#modify` constraints. | Implement polymorphic specialization cache, baked value/type parameters, constraint execution, and diagnostics that quote the failing constraint. |
| 662-696 | Missing | Polymorphic structs and nested polymorphic member types. | Implement parameterized container type identity, layout instantiation, field access, literal construction, and reuse of specializations. |
| 697-761 | Partial | Enums, enum values, enum names, enum_flags bitsets and printing. | Implement enum storage/range checking, unqualified enum literals from context, enum_flags operators, `enum_range`, `enum_names`, `enum_values_as_s64`, and formatting. |
| 762-852 | Partial | `if`, `ifx`, if-case-like patterns, `while`, `break`, `continue`, and `defer`. | Implement structured control-flow lowering, correct `defer` stack behavior across branches/loops/returns, and `ifx` as a typed expression. |
| 853-887 | Partial | Address-of, dereference, pointer assignment, pointer casts, null checks. | Finish lvalue/address model, typed pointer loads/stores, pointer arithmetic, pointer comparisons, and illegal pointer diagnostics. |
| 888-919 | Missing | Temporary storage, allocator context, `reset_temporary_storage`, `push_allocator`. | Implement the real allocator ABI, context allocator fields, temporary allocator lifetime, and allocator proc dispatch. |
| 920-960 | Partial | Top-level `#run`, `#if`, `#assert`, compile-time constants. | Generalize compile-time VM execution to ordinary code, structs, arrays, strings, pointers, and host intrinsics. Make `#assert` use compile-time bool semantics with exact source diagnostics. |
| 961-1003 | Missing | Operator overloading. | Implement operator declaration resolution, overload sets, user-defined operator calls, commutativity/symmetric rules, and overload diagnostics. |
| 1004-1048 | Partial | `Type` values, `type_of`, type comparisons, type printing. | Make `Type` a first-class compile-time/runtime value with stable ids, equality, printing, and type-expression lowering. |
| 1049-1076 | Missing | `Any` and runtime type introspection. | Implement `Any` layout, typed boxing/unboxing, `type_info` handles, runtime access to reflected type metadata, and safe casts from `Any`. |
| 1077-1107 | Missing | Custom for-expansions with `Code`, `For_Flags`, and `#expand`. | Implement iterator expansion protocol: pass caller body as `Code`, bind `it`/`it_index`, honor flags, and splice generated body with correct scope. |
| 1108-1152 | Missing | Tagged unions / memory overlays via `#place`. | Implement explicit placement fields, overlapping storage layout, alignment, field access, and diagnostics for illegal overlaps. |
| 1153-1173 | Missing | Distinct types and variant conversions. | Implement `#type,distinct` and `#type,isa`, preserving representation while enforcing distinct type identities and explicit conversions. |
| 1174-1190 | Partial | Procedure overloading. | Implement robust overload sets, ranking, ambiguity diagnostics, and interaction with polymorphic specializations. |
| 1191-1221 | Partial | Runtime `assert` and Math basics. | Implement assert handler/context behavior and complete Math module functions with deterministic formatting. |
| 1222-1254 | Partial | Multi-return destructuring and ignored values. | Finish tuple/multi-result ABI, destructuring assignment, arity checks, and `_` ignore handling. |
| 1255-1310 | Missing | `Hash_Table` module. | Implement hash table data structure, hash/equality hooks, iteration, insertion, lookup, removal, and printing helpers. |
| 1311-1347 | Partial | `#caller_location`, source path/line info, context/logger. | Implement `Source_Code_Location`, caller/callee source capture, context logger fields, and formatted source-location printing. |
| 1348-1451 | Partial | Deep print formatting, overflow behavior, bit operations, compile-time string literal behavior. | Complete format parser, integer overflow/wrapping rules, bitwise lowering by width/signedness, and string literal escape/source storage rules. |
| 1452-1493 | Partial | `#char` and character literals. | Implement byte/rune semantics for `#char`, error on empty/multi-byte where appropriate, and interactions with `u8`. |
| 1494-1531 | Partial | Printing all primitive/container types and defer ordering in loops. | Finish formatting of arrays/slices/structs/enums/flags/Type/Any and nested defer lowering. |
| 1532-1568 | Missing | `#procedure_of_call` and body-level `#insert`. | Implement call-site procedure capture and general `#insert` parse/splice in statement/expression/declaration/lvalue contexts. |
| 1569-1598 | Missing | SOA-style overlays through `#place`. | Same placement/layout work as lines 1108-1152, plus array field offsets and aliasing semantics. |
| 1599-1648 | Partial | Procedure types in structs, callbacks, and `ifx`. | Implement procedure pointer ABI, assignment/call through fields, and typed ifx result merging. |
| 1649-1784 | Partial | Math, Sort, Random, String module functions. | Replace module placeholders with actual implementations and runtime calls. Verify deterministic random output and sort comparators. |
| 1785-1823 | Missing | `Bit_Array` module. | Add `Bit_Array` module with storage, indexing, iteration, count, mutation, and formatting behavior. |
| 1824-1915 | Missing | Reflection-driven serialization and print quirks. | Implement `Type_Info_Struct`, member metadata, nested format escaping, and reflection iteration. |
| 1916-1938 | Missing | `Code` values, `#code`, repeated `#insert`, string-built code. | Build real `Code` AST values with provenance, type, capture scope, and parse/splice round-trip. |
| 1939-2003 | Partial | Defer with returns, `#bake_arguments`, recursion. | Finish defer on early return, baked partial procedures, and recursive procedure resolution/codegen. |
| 2004-2100 | Missing | Nested procs, closures over compile-time constants, generic stack, `using` on params/locals. | Implement nested procedure declarations, capture rules, generic method-like procs, and `using` lookup propagation. |
| 2101-2210 | Missing | `#place` offsets, distinct/isa, `#symmetric`, macro expansion. | Implement explicit offsets, symmetric operator search, and macro expansion with backtick-generated identifiers. |
| 2210-2421 | Partial | Apollo_Time, multiple assignment, range endpoints, custom iterators, memory ops, strings, dynamic-array public layout. | Finish Apollo_Time 128-bit semantics, tuple assignment, range inclusivity/exclusivity, `memcpy`/`memset`, slice operations, and real dynamic-array layout. |
| 2422-2533 | Partial | Summary and main dispatch through every test. | Once all called sections are supported, this should compile/run without special cases. |
| 2534 | Missing | Separator before extras 2. | Covered by the following extras/module-loading requirement. |
| 2535-6381 | Missing | Extras 2: file I/O, vector/matrix/quaternion math, hashing, CRC, xxHash, md5, Base64, Unicode, IntroSort/RadixSort, Bucket_Array, Pool/Flat_Pool, process API surface, parsers, JSON-like printing, polymorphic containers. | Port/implement missing modules and strengthen generic algorithms, file runtime, allocator runtimes, and reflection. |
| 6382-6444 | Missing | Separator and preamble before extras 3. | Covered by the following extras/polymorphism requirement. |
| 6445-10582 | Missing | Extras 3: advanced polymorphics, variadics, spread args, baked constants, tagged unions, code insertion, nested loops, custom data structures, reflection recursion, compiler build API surface, `xx`, `#add_context`, `#module_parameters`, notes. | Implement variadic `..Any`, spread lowering, baked compile-time values, note storage/reflection, context extension, module parameter binding, and real compiler API types. |
| 10583-10673 | Missing | Separator and preamble before extras 4. | Covered by the following formatting/conversion/macro requirement. |
| 10674-15977 | Missing | Extras 4: exhaustive formatting, integer conversion matrix, macros, large enum_flags, struct layout, print edge cases, sort/string edge cases. | Complete formatting subsystem, integer conversion semantics, macro/insert pipeline, enum_flags, and broad standard module coverage. |
| 15978-16201 | Partial | Separator and preamble before extras 5. | Covered by the following algorithmic-runtime requirement. |
| 16202-21158 | Partial | Extras 5: mostly algorithmic runtime stress with recursion, arrays, strings, backtracking, DP, fixed-point math, atomics, hashing. | After core arrays/strings/loops/procs are correct, these lines should mostly run. Missing pieces include BigInt-like dynamic arrays, atomics, and deterministic format output. |
| 21159-21279 | Missing | Separator and preamble before extras 6. | Covered by the following reflection/generic-runtime requirement. |
| 21280-25667 | Missing | Extras 6: reflection sweep, generic serializer/equality, binary blobs, enum operations, polymorphic cross-products, compile-time table generation. | Implement full reflection metadata for every type kind, binary memory operations, generic `Any` traversal, and robust compile-time constant generation. |
| 25668-25740 | Missing | Separator and preamble before extras 7/8. | Covered by the following large-runtime/macro/operator requirement. |
| 25741-34607 | Missing | Extras 7/8: large builders, defer matrices, using patterns, many custom iterators, operator-overloaded complex/rational/matrix/polynomial types, huge `#insert` coverage, symbol tables, parsers, graph/tree algorithms. | This is a stress layer for already-correct core features. Required compiler work is full operator overload dispatch, iterator expansion, dynamic arrays, hash tables, macro insertion, and builder performance/correctness. |
| 34608-34660 | Missing | Separator and preamble before extras 9. | Covered by the following exhaustive-cast/reflection/FFI requirement. |
| 34661-36812 | Missing | Extras 9-11: exhaustive casts, reflection catalogs, compiler_get_nodes, libc foreign bindings, atomics, scope directives, `#add_context`, module parameters, notes, copy semantics, default args. | Implement exact cast semantics, complete type_info catalogs, real `compiler_get_nodes`, FFI ABI/linking, atomic intrinsics, scope visibility, context extension, notes, copy semantics, and default-arg lowering. |
| 36813-36814 | Missing | Separator before compile-time diagnostic metaprogram. | Covered by the diagnostic-catalog requirement. |
| 36815-41342 | Missing | Compile-time diagnostic catalog. The metaprogram creates sub-workspaces, feeds source strings, intercepts messages, resets workspace status, and expects deterministic diagnostics. | Implement workspace creation, build-string/file scheduling, compiler message queues, intercept loop, workspace status transitions, and a comprehensive semantic diagnostic suite. Every source string must be compiled by the real compiler, not pattern-matched. |
| 41343-63366 | Data | Reference output `#string` with a custom delimiter and embedded bytes. | Lexer/parser must preserve large here-strings byte-for-byte, including NUL, CR/LF behavior, delimiter recognition, and storage without truncation. |

Coverage audit: the ledger above intentionally covers all lines 1-63366. This
can be mechanically checked by expanding the ranges in the first column and
verifying that no line number in `utils/stress.jai` is absent.

## Source-Derived Inventory

This inventory is generated from the current `utils/stress.jai` source and is
part of the spec. Items that appear only inside diagnostic snippets still matter:
they must parse far enough to produce the intended diagnostic, or fail at the
correct lexer/parser boundary.

### Imported Modules

All `#import` strings appearing anywhere in the file:

```text
Atomics
Base64
Basic
Basic.jai
Bit_Array
Bucket_Array
Compiler
Crc
Definitely_Not_A_Real_Module_xyz
File
Flat_Pool
Hash
Hash_Table
IntroSort
Math
Nonexistent_Module_XYZ
Pool
Process
RadixSort
Random
Sort
String
Unicode
md5
xxHash
```

The intentionally nonexistent names are part of the diagnostic catalog, not
runtime dependencies. They must produce real import/load diagnostics when the
metaprogram compiles those snippets.

### Directives

All directive tokens appearing anywhere in the file:

```text
#add_context
#align
#as
#assert
#bake_arguments
#c_call
#caller_location
#char
#code
#compile_time
#compiler
#complete
#directive
#expand
#foreign
#foreign_system_library
#frobnicate
#if
#import
#insert
#load
#modify
#module_parameters
#must
#no_aoc
#not_a_real_directive
#not_a_real_directive_for_testing
#overlay
#place
#procedure_of_call
#run
#scope_export
#scope_file
#scope_module
#specified
#string
#symmetric
#system_library
#through
#totally_made_up_directive
#type
```

The made-up directives are diagnostic requirements. They must not be accepted as
opaque syntax.

### Compiler And Build APIs

Compiler/build identifiers used by the stress file:

```text
add_build_file
add_build_string
add_data_segment
add_global_data
compiler_begin_intercept
compiler_create_workspace
compiler_end_intercept
compiler_get_nodes
compiler_modify_procedure
compiler_set_workspace_status
compiler_wait_for_message
```

All of these must be host-backed compiler APIs with typed compile-time values.
None may be implemented through numeric placeholders or `any` fallbacks.

### High-Signal Qualified Namespaces

The file contains more than one thousand field accesses, so this list records
the namespaces that represent module/API obligations rather than ordinary
struct fields:

```text
Atomics.*
Basic.*
Basic_ns.*
Crc.*
File_Caps.*
File_Modes.*
Flat_Pool_Mod.*
Hash.*
Hash_Table.*
IntroSort.*
Pool_Mod.*
Process_Mod.*
Radix.*
Sort.*
String.*
Type_Info_Tag.*
Unicode.*
xxHash / xxh aliases
```

The full field-access set should be regenerated during implementation when a
new category of member access fails. Ordinary field accesses are covered by the
aggregate-layout and reflection gates.

### Runtime Section Families

The runtime half contains these section families:

- Core sections `1-68`, lines 101-2533.
- Extras 2 sections `100-159`, lines 2535-6381.
- Extras 3 sections `200-284`, lines 6382-10582.
- Extras 4 sections `400, 404, 409, 411, 413, 415, 420-424, 462-466, 471-472,
  485-490, 492-499`, lines 10583-15977.
- Extras 5 sections `500, 510, 515, 520, 522, 527, 529-601`, lines
  15978-21158.
- Extras 6 sections `600-656`, lines 21159-25667.
- Extras 7/8 sections `700-710, 714-772`, lines 25668-34607.
- Extras 9 sections `900-940`, lines 34608-36206.
- Extras 10 sections `1000-1006`, lines 36207-36507.
- Extras 11 sections `1100-1108`, lines 36508-36812.

Each family is intentionally broad and cross-cutting. The section numbers are
stable handles for focused implementation tests as support grows.

## Feature Gates

### Gate 1: Parser And Lexer Completeness

Required for lines 1-41342 to get past initial syntax:

- Numeric literal grammar:
  - decimal, binary, octal, hex integers
  - underscore placement validation
  - `0h` IEEE-754 bit-pattern float literals for 32-bit and 64-bit targets
  - invalid literal diagnostics from the error catalog
- String grammar:
  - normal escapes, hex escapes, decimal escapes, `\0`
  - large `#string DELIM ... DELIM` forms
  - CR-preserving `#string,cr` forms
  - embedded NUL preservation
- Full declaration grammar:
  - compound field declarations (`x, y, z: float`)
  - struct member notes
  - directives on fields and declarations
  - procedure types and procedure pointer fields
  - multiple returns, named returns, default args, variadics, baked params
- Control grammar:
  - all `for` modifiers and named iterator forms
  - `ifx then else`
  - switch/if-case patterns where used
- Directive grammar:
  - `#run -> T`, `#insert -> string`, `#insert -> Code`
  - `#expand`, `#modify`, `#bake_arguments`, `#procedure_of_call`
  - `#place`, `#as`, `#scope_file`, `#scope_export`, `#scope_module`
  - `#foreign`, `#c_call`, `#add_context`, `#module_parameters`

Deliverable: `openjai utils/stress.jai --check` must advance beyond line 159
without accepting any unsupported syntax as inert text.

### Gate 2: Real Module Loading

The import lines are part of the spec. A successful compiler must not resolve
them through implicit placeholders.

Required changes:

- Module discovery must load `modules/<Name>/module.jai` and aliases such as
  `Md5 :: #import "md5"`.
- Missing modules used by stress must be added or ported:
  `Bit_Array`, `Base64`, `Bucket_Array`, `Unicode`, `Hash`, `Crc`, `md5`,
  `xxHash`, `IntroSort`, `RadixSort`, and `Atomics`.
- Imported declarations must be real declarations with sema-visible signatures.
- Namespaces must support qualified access (`Basic_ns.MEMORY_DEBUGGER`,
  `Atomics.atomic_write`, aliases such as `xxHash.XXH64_*`).

Deliverable: every import and qualified module reference in lines 24-41,
2547-2555, and the later extras resolves to a real symbol.

### Gate 3: Scalar Type System And Lowering

Stress relies on exact scalar behavior, not all-values-are-i64 behavior.

Required changes:

- Store/load integer values using their declared width.
- Preserve signedness for comparisons, division, modulo, casts, shifts, and
  formatting.
- Implement implicit widening rules and reject implicit narrowing.
- Implement checked casts and `xx` auto-cast semantics.
- Implement wrapping/overflow behavior only where the language specifies it.
- Implement `size_of`, `type_of`, and type equality for primitives and
  compound types.

Deliverable: sections 1, 2, 29, 30, 1100, and 900-904 produce the reference
output without special cases.

### Gate 4: Runtime ABI For Strings, Arrays, Allocators, Files

Required changes:

- String layout: count/data, equality by content, byte indexing, slicing,
  iteration, and conversion to C strings for FFI.
- Fixed array layout and copying.
- Slice layout and header-copy semantics.
- Resizable array layout, allocator ownership, growth, insert/remove/find/copy.
- Allocator/context ABI including temporary storage and `push_allocator`.
- File runtime for `File` module and low-level file open/read/write/seek APIs.

Deliverable: sections 4, 5, 13, 65-67, 100-101, 246, 249, 907, and the file
and container-heavy extras run with correct output.

### Gate 5: Procedure Model

Required changes:

- Multi-return ABI and destructuring.
- Named returns.
- Default args and named/reordered args.
- Procedure types as values and fields.
- Function pointer calls.
- Recursive procedures.
- Nested procedures with legal capture semantics.
- Variadic `..Any` procedures and spread `..` calls.
- `#must` result-consumption diagnostics.

Deliverable: sections 7, 24, 38, 49-52, 155-156, 224, 230, 252, 937, 940,
1108, and the procedure-error catalog all pass.

### Gate 6: Polymorphism And Containers

Required changes:

- `$T` type parameters and `$$N` baked values.
- Specialization cache keyed by types and baked values.
- Polymorphic struct layout and method-like procedure use.
- `#modify` constraints executing at compile time.
- Polymorphic overload resolution and diagnostics.

Deliverable: sections 8, 9, 52, 120-122, 140, 147, 149, 158, 200-203, 471,
605-606, 641, 646, 718, 721, 770, 929, and their diagnostic counterparts pass.

### Gate 7: Aggregate Layout And Reflection

Required changes:

- Struct defaults and copy semantics.
- Anonymous struct identity.
- `using` and `#as using` field promotion.
- `#place` storage overlays and explicit offsets.
- Unions and tagged union idioms.
- Distinct and `isa` type variants.
- Full `type_info` for primitives, structs, enums, arrays, pointers,
  procedures, Type, Any, and polymorphic instantiations.
- Notes storage and reflection.

Deliverable: sections 6, 17, 19, 20, 37, 45, 54-55, 124, 134, 214, 226-227,
256, 600-604, 914-915, 933, 1103, and 1105 pass.

### Gate 8: Formatting And Builders

Required changes:

- `print`, `sprint`, `tprint`, `print_to_builder`.
- `String_Builder` allocation, append, length, reset/free.
- `FormatInt`, `FormatFloat`, `FormatStruct`, `FormatArray`.
- Array/struct/enum/flags/Type/Any printing.
- Width, padding, comma grouping, float modes, shortest/scientific behavior.
- Format-string diagnostics for argument count/type mismatch.

Deliverable: sections 28, 33, 46, 62, 132, 210, 225, 400, 404, 409, 411,
422-424, 486-498, 700-701, 719, 904, 916, and the format-error catalog pass.

### Gate 9: Macros, Code Values, And Compile-Time Execution

Required changes:

- `#run` ordinary VM execution with structs, arrays, strings, `Any`, `Type`,
  pointers, and host intrinsics.
- `Code` and `Code_Node` as real compile-time values.
- `#code` capture with scope/provenance/type.
- `compiler_get_nodes` stable traversal.
- `compiler_get_code`, `code_to_string`, `print_expression`.
- `#expand` macro invocation and body substitution.
- `#insert` in statement, declaration, expression, and lvalue contexts.
- `#insert -> string`, `#insert -> Code`, and generated identifiers.

Deliverable: sections 14, 18, 35-36, 47, 57, 206, 218-219, 264-265, 462-464,
818, 831, 849, 1005, and macro/code diagnostics pass.

### Gate 10: Compiler Workspaces And Diagnostics

The compile-time half is a full compiler API test, not merely a string table.

Required changes:

- `compiler_create_workspace`.
- `add_build_string`, `add_build_file`, and generated-source scheduling.
- `compiler_begin_intercept`, `compiler_wait_for_message`,
  `compiler_end_intercept`.
- Message object layout and kinds.
- Workspace status management.
- Deterministic phase scheduler.
- Diagnostics for all negative snippets in lines 36850-41342.

Deliverable: compiling `utils/stress.jai` emits the expected diagnostic catalog
and still produces/runs the runtime executable when the metaprogram resets
failing workspaces as intended.

### Gate 11: FFI, Atomics, Inline Assembly

Required changes:

- `#foreign` and `#c_call` ABI lowering for libc functions used by stress.
- Target-aware system library linkage.
- Procedure pointer vs data pointer diagnostics.
- Atomic intrinsics: read/write/add/compare-and-swap with correct return
  values and memory behavior.
- Inline assembly parsing and lowering. Broken inline assembly in the error
  catalog must produce diagnostics.

Deliverable: sections 1003, 1004, 574, CH diagnostics, and AB diagnostics pass.

### Gate 12: Golden Harness

Once the file compiles and runs:

- Build `utils/stress.jai` to an executable under `out/`.
- Capture compile-time diagnostics and runtime stdout/stderr deterministically.
- Extract `EXPECTED_OUTPUT` byte-for-byte.
- Diff the combined output against `EXPECTED_OUTPUT`.
- Add `make stress` or a test-runner target only after the run is deterministic
  enough to be useful in CI.

## Diagnostic Catalog Requirements

Lines 36850-41342 contain complete source snippets inside `#string` literals.
These snippets are not comments. The metaprogram must feed them to the compiler
as independent workspaces. The compiler must produce real diagnostics for each
class:

- A: undeclared names and redeclarations.
- B: type mismatches and numeric range failures.
- C: procedure call and return arity/type failures.
- D: constants and invalid reassignment.
- E: pointer and dereference failures.
- F: invalid operators for strings/bools/non-indexable values.
- G: control-flow misuse.
- H/I/J/K: polymorphic, struct, enum, and array errors.
- L/M: lexer/parser and directive errors.
- N-R: overloads, variants, formatting, and operator errors.
- S-T: for-loop and bake-argument errors.
- U-CQ: deeper semantic and syntax diagnostics, including inline assembly,
  context misuse, notes/directives, imports/loads, workspace misuse, and
  excessive allocation/assertion cases.

Implementation rule: do not match snippets by text. Each snippet must go
through the same parse, resolve, sema, compile-time execution, and diagnostic
pipeline as a normal user program.

## Acceptance Criteria

The stress file is enabled only when all of the following are true:

1. `openjai utils/stress.jai --check` succeeds after running the diagnostic
   metaprogram.
2. `openjai utils/stress.jai -o out/stress` produces an executable under
   `out/`.
3. `out/stress` runs to completion.
4. The combined compile-time diagnostics and runtime output match
   `EXPECTED_OUTPUT` byte-for-byte after normalizing only platform paths that
   the stress file explicitly marks as non-deterministic.
5. No implicit placeholder symbols, `any` fallbacks, or compile-through stubs
   are used to pass any line.
