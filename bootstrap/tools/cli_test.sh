#!/usr/bin/env bash
#
# CLI flag test suite for the OpenJai bootstrap compiler.
#
# Usage:
#   cli_test.sh <compiler> <runtime>
#
# Tests every CLI flag documented in docs/open_jai_spec.md.
# Exit code: 0 if all pass, 1 if any fail.

set -uo pipefail

COMPILER="${1:?usage: cli_test.sh <compiler> <runtime>}"
RUNTIME="${2:?usage: cli_test.sh <compiler> <runtime>}"

# Resolve to absolute paths before any cwd changes.
COMPILER="$(cd "$(dirname "$COMPILER")" && pwd)/$(basename "$COMPILER")"
RUNTIME="$(cd "$(dirname "$RUNTIME")" && pwd)/$(basename "$RUNTIME")"

PASS=0
FAIL=0
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# --- Helpers ---

pass() { PASS=$((PASS + 1)); printf "PASS  %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "FAIL  %s\n      %s\n" "$1" "$2"; }

# Create a minimal .jai source that compiles and runs.
MINIMAL="$TMPDIR/minimal.jai"
cat > "$MINIMAL" << 'JAI'
main :: () {
    x := 1;
}
JAI

# A source that prints something at runtime.
HELLO="$TMPDIR/hello.jai"
cat > "$HELLO" << 'JAI'
main :: () {
    print("hello world\n");
}
JAI

# A source with a deliberate error.
ERROR_SRC="$TMPDIR/error.jai"
cat > "$ERROR_SRC" << 'JAI'
main :: () {
    x := undefined_symbol;
}
JAI

# Compile helper — returns 0 on success.
compile() {
    "$COMPILER" "$@" -runtime "$RUNTIME" 2>&1
}

# --- Tests ---

# -version
test_version() {
    local out
    out=$(compile -version 2>&1) || true
    if echo "$out" | grep -q "OpenJai"; then
        pass "-version"
    else
        fail "-version" "expected 'OpenJai' in output, got: $out"
    fi
}

# -help
test_help() {
    local out
    out=$(compile -help 2>&1) || true
    if echo "$out" | grep -q "Available Command-Line Arguments"; then
        pass "-help"
    else
        fail "-help" "expected help text header"
    fi
}

# -? (alias for -help)
test_help_question() {
    local out
    out=$(compile '-?' 2>&1) || true
    if echo "$out" | grep -q "Available Command-Line Arguments"; then
        pass "-?"
    else
        fail "-?" "expected help text header"
    fi
}

# No arguments → error
test_no_args() {
    local out
    out=$("$COMPILER" 2>&1) || true
    if echo "$out" | grep -q "no input file specified"; then
        pass "no arguments"
    else
        fail "no arguments" "expected 'no input file specified', got: $out"
    fi
}

# Unknown flag → rejected
test_unknown_flag() {
    local out
    out=$("$COMPILER" -bogus_flag "$MINIMAL" 2>&1) || true
    if echo "$out" | grep -q "unrecognized option"; then
        pass "unknown flag rejected"
    else
        fail "unknown flag rejected" "expected 'unrecognized option', got: $out"
    fi
}

# -check (compile without linking)
test_check() {
    local out
    out=$(compile "$MINIMAL" -check 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-check"
    else
        fail "-check" "expected exit 0, got $rc: $out"
    fi
}

# -check does not produce a binary
test_check_no_binary() {
    local bin="$TMPDIR/check_nope"
    compile "$MINIMAL" -check -exe "$bin" >/dev/null 2>&1 || true
    if [ ! -f "$bin" ]; then
        pass "-check no binary produced"
    else
        fail "-check no binary produced" "binary was created at $bin"
    fi
}

# -add injects a declaration
test_add() {
    local src="$TMPDIR/test_add.jai"
    cat > "$src" << 'JAI'
main :: () {
    x := MY_INJECTED_CONST;
}
JAI
    local out
    out=$(compile "$src" -add "MY_INJECTED_CONST :: 42;" -exe "$TMPDIR/test_add_bin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-add code injection"
    else
        fail "-add code injection" "compile failed: $out"
    fi
}

# Multiple -add
test_add_multiple() {
    local src="$TMPDIR/test_add_multi.jai"
    cat > "$src" << 'JAI'
main :: () {
    a := CONST_A;
    b := CONST_B;
}
JAI
    local out
    out=$(compile "$src" -add "CONST_A :: 1;" -add "CONST_B :: 2;" -exe "$TMPDIR/test_add_multi_bin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-add multiple"
    else
        fail "-add multiple" "compile failed: $out"
    fi
}

# -run executes code at compile time
test_run() {
    local out
    out=$(compile "$MINIMAL" -run 'print("from_run\n")' -exe "$TMPDIR/test_run_bin" 2>&1)
    if echo "$out" | grep -q "from_run"; then
        pass "-run compile-time execution"
    else
        fail "-run compile-time execution" "expected 'from_run' in output, got: $out"
    fi
}

# Multiple -run
test_run_multiple() {
    local out
    out=$(compile "$MINIMAL" -run 'print("A")' -run 'print("B")' -exe "$TMPDIR/test_run_multi_bin" 2>&1)
    if echo "$out" | grep -q "A" && echo "$out" | grep -q "B"; then
        pass "-run multiple"
    else
        fail "-run multiple" "expected A and B in output, got: $out"
    fi
}

# -msvc_format changes error location format
test_msvc_format() {
    local out
    out=$(compile "$ERROR_SRC" -msvc_format -exe "$TMPDIR/nope" 2>&1) || true
    if echo "$out" | grep -qE '\([0-9]+,[0-9]+\): error:'; then
        pass "-msvc_format"
    else
        fail "-msvc_format" "expected file(line,col): error: format, got: $out"
    fi
}

# Default error format (not msvc) — strip ANSI codes before checking
test_default_error_format() {
    local out
    out=$(compile "$ERROR_SRC" -exe "$TMPDIR/nope" 2>&1) || true
    local stripped
    stripped=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g')
    if echo "$stripped" | grep -qE ':[0-9]+:[0-9]+: error:'; then
        pass "default error format (file:line:col)"
    else
        fail "default error format (file:line:col)" "expected file:line:col: error: format, got: $stripped"
    fi
}

# -no_color suppresses ANSI escape codes
test_no_color() {
    local out
    out=$(compile "$ERROR_SRC" -no_color -exe "$TMPDIR/nope" 2>&1) || true
    if echo "$out" | grep -q $'\x1b'; then
        fail "-no_color" "ANSI escape codes found in output"
    else
        pass "-no_color"
    fi
}

# Default has ANSI color codes
test_default_color() {
    local out
    out=$(compile "$ERROR_SRC" -exe "$TMPDIR/nope" 2>&1) || true
    if echo "$out" | grep -q $'\x1b'; then
        pass "default has ANSI colors"
    else
        fail "default has ANSI colors" "no ANSI escape codes found"
    fi
}

# -verbose prints configuration header
test_verbose() {
    local out
    out=$(compile "$MINIMAL" -verbose -exe "$TMPDIR/test_verbose_bin" 2>&1)
    if echo "$out" | grep -q "options.output_path" && \
       echo "$out" | grep -q "options.output_executable_name" && \
       echo "$out" | grep -q "Input files:"; then
        pass "-verbose config header"
    else
        fail "-verbose config header" "missing expected verbose fields, got: $out"
    fi
}

# -verbose shows token/node counts
test_verbose_phases() {
    local out
    out=$(compile "$MINIMAL" -verbose -exe "$TMPDIR/test_verbose_bin" 2>&1)
    if echo "$out" | grep -q "verbose: lexed" && \
       echo "$out" | grep -q "verbose: parsed"; then
        pass "-verbose phase info"
    else
        fail "-verbose phase info" "missing lexed/parsed lines, got: $out"
    fi
}

# -verbose shows add/run strings when present
test_verbose_add_run() {
    local out
    out=$(compile "$MINIMAL" -verbose -add "X :: 1;" -run 'print("hi")' -exe "$TMPDIR/test_verbose_ar" 2>&1)
    if echo "$out" | grep -q 'Add strings:' && \
       echo "$out" | grep -q 'Run strings:'; then
        pass "-verbose shows add/run strings"
    else
        fail "-verbose shows add/run strings" "missing Add/Run strings, got: $out"
    fi
}

# -verbose shows linked message
test_verbose_linked() {
    local out
    out=$(compile "$MINIMAL" -verbose -exe "$TMPDIR/test_verbose_link" 2>&1)
    if echo "$out" | grep -q "verbose: linked"; then
        pass "-verbose linked message"
    else
        fail "-verbose linked message" "missing 'verbose: linked', got: $out"
    fi
}

# -quiet suppresses compile-time print output
test_quiet() {
    local out
    out=$(compile "$MINIMAL" -quiet -run 'print("should_not_appear\n")' -exe "$TMPDIR/test_quiet_bin" 2>&1)
    if echo "$out" | grep -q "should_not_appear"; then
        fail "-quiet suppresses #run print" "output was not suppressed"
    else
        pass "-quiet suppresses #run print"
    fi
}

# -quiet and -verbose can coexist
test_quiet_verbose() {
    local out
    out=$(compile "$MINIMAL" -quiet -verbose -exe "$TMPDIR/test_qv_bin" 2>&1)
    if echo "$out" | grep -q "options.output_path"; then
        pass "-quiet + -verbose coexist"
    else
        fail "-quiet + -verbose coexist" "verbose header missing under -quiet, got: $out"
    fi
}

# -release compiles successfully
test_release() {
    local out
    out=$(compile "$MINIMAL" -release -exe "$TMPDIR/test_release_bin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-release compiles"
    else
        fail "-release compiles" "exit $rc: $out"
    fi
}

# -release_debug compiles successfully
test_release_debug() {
    local out
    out=$(compile "$MINIMAL" -release_debug -exe "$TMPDIR/test_rd_bin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-release_debug compiles"
    else
        fail "-release_debug compiles" "exit $rc: $out"
    fi
}

# -report_poly accepted (no-op)
test_report_poly() {
    local out
    out=$(compile "$MINIMAL" -report_poly -exe "$TMPDIR/test_rp_bin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-report_poly accepted"
    else
        fail "-report_poly accepted" "exit $rc: $out"
    fi
}

# -no_cwd suppresses cwd change message
test_no_cwd() {
    local out
    out=$(compile "$MINIMAL" -verbose -no_cwd -exe "$TMPDIR/test_nocwd" 2>&1)
    if echo "$out" | grep -q "Changing working directory"; then
        fail "-no_cwd" "cwd change message present despite -no_cwd"
    else
        pass "-no_cwd suppresses cwd change"
    fi
}

# Default changes working directory (verbose shows it for non-cwd-local files)
test_default_cwd() {
    local src="$TMPDIR/subdir/test_cwd.jai"
    mkdir -p "$TMPDIR/subdir"
    cp "$MINIMAL" "$src"
    local out
    out=$(compile "$src" -verbose -exe "$TMPDIR/test_cwd_bin" 2>&1)
    if echo "$out" | grep -q "Changing working directory"; then
        pass "default cwd change"
    else
        fail "default cwd change" "no cwd change message for file in subdirectory"
    fi
}

# -exe sets output name
test_exe() {
    local bin="$TMPDIR/custom_name"
    compile "$MINIMAL" -exe "$bin" >/dev/null 2>&1
    if [ -f "$bin" ]; then
        pass "-exe sets output name"
    else
        fail "-exe sets output name" "binary not found at $bin"
    fi
}

# -- help shows developer options
test_dev_help() {
    local out
    out=$("$COMPILER" "$MINIMAL" -- help 2>&1) || true
    if echo "$out" | grep -q "Developer options:"; then
        pass "-- help"
    else
        fail "-- help" "expected 'Developer options:', got: $out"
    fi
}

# --- also works as developer options delimiter
test_triple_dash() {
    local out
    out=$("$COMPILER" "$MINIMAL" --- help 2>&1) || true
    if echo "$out" | grep -q "Developer options:"; then
        pass "--- help"
    else
        fail "--- help" "expected 'Developer options:', got: $out"
    fi
}

# -- with unknown option → error
test_dev_unknown() {
    local out
    out=$("$COMPILER" "$MINIMAL" -- bogus_dev_opt 2>&1) || true
    if echo "$out" | grep -q "unrecognized developer option"; then
        pass "-- unknown developer option"
    else
        fail "-- unknown developer option" "expected rejection, got: $out"
    fi
}

# -- import_dir accepted (put -runtime before -- so it's not parsed as a dev option)
test_dev_import_dir() {
    local out
    out=$("$COMPILER" "$MINIMAL" -exe "$TMPDIR/test_idir" -runtime "$RUNTIME" -- import_dir /tmp 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-- import_dir"
    else
        fail "-- import_dir" "exit $rc: $out"
    fi
}

# -- meta accepted (no-op)
test_dev_meta() {
    local out
    out=$("$COMPILER" "$MINIMAL" -exe "$TMPDIR/test_meta" -runtime "$RUNTIME" -- meta SomeProgram 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-- meta"
    else
        fail "-- meta" "exit $rc: $out"
    fi
}

# -- no_jobs accepted (no-op)
test_dev_no_jobs() {
    local out
    out=$("$COMPILER" "$MINIMAL" -exe "$TMPDIR/test_nj" -runtime "$RUNTIME" -- no_jobs 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-- no_jobs"
    else
        fail "-- no_jobs" "exit $rc: $out"
    fi
}

# - separates metaprogram arguments (compiler ignores everything after -)
test_dash_separator() {
    local out
    out=$("$COMPILER" "$MINIMAL" -exe "$TMPDIR/test_dash" -runtime "$RUNTIME" - some random metaprogram args 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "- metaprogram separator"
    else
        fail "- metaprogram separator" "exit $rc: $out"
    fi
}

# -no_dce accepted (no-op)
test_no_dce() {
    local out
    out=$(compile "$MINIMAL" -no_dce -exe "$TMPDIR/test_nodce" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-no_dce accepted"
    else
        fail "-no_dce accepted" "exit $rc: $out"
    fi
}

# -no_check accepted (no-op)
test_no_check() {
    local out
    out=$(compile "$MINIMAL" -no_check -exe "$TMPDIR/test_nocheck" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-no_check accepted"
    else
        fail "-no_check accepted" "exit $rc: $out"
    fi
}

# -no_check_bindings accepted (no-op)
test_no_check_bindings() {
    local out
    out=$(compile "$MINIMAL" -no_check_bindings -exe "$TMPDIR/test_nocb" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-no_check_bindings accepted"
    else
        fail "-no_check_bindings accepted" "exit $rc: $out"
    fi
}

# -no_inline accepted (no-op)
test_no_inline() {
    local out
    out=$(compile "$MINIMAL" -no_inline -exe "$TMPDIR/test_noinline" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-no_inline accepted"
    else
        fail "-no_inline accepted" "exit $rc: $out"
    fi
}

# -no_split accepted (no-op)
test_no_split() {
    local out
    out=$(compile "$MINIMAL" -no_split -exe "$TMPDIR/test_nosplit" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-no_split accepted"
    else
        fail "-no_split accepted" "exit $rc: $out"
    fi
}

# -no_backtrace_on_crash accepted (no-op)
test_no_backtrace() {
    local out
    out=$(compile "$MINIMAL" -no_backtrace_on_crash -exe "$TMPDIR/test_nobt" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-no_backtrace_on_crash accepted"
    else
        fail "-no_backtrace_on_crash accepted" "exit $rc: $out"
    fi
}

# -natvis accepted (no-op)
test_natvis() {
    local out
    out=$(compile "$MINIMAL" -natvis -exe "$TMPDIR/test_natvis" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-natvis accepted"
    else
        fail "-natvis accepted" "exit $rc: $out"
    fi
}

# -debugger accepted (no-op)
test_debugger() {
    local out
    out=$(compile "$MINIMAL" -debugger -exe "$TMPDIR/test_debugger" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-debugger accepted"
    else
        fail "-debugger accepted" "exit $rc: $out"
    fi
}

# -debug_for accepted (no-op)
test_debug_for() {
    local out
    out=$(compile "$MINIMAL" -debug_for -exe "$TMPDIR/test_df" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-debug_for accepted"
    else
        fail "-debug_for accepted" "exit $rc: $out"
    fi
}

# -very_debug accepted (no-op)
test_very_debug() {
    local out
    out=$(compile "$MINIMAL" -very_debug -exe "$TMPDIR/test_vd" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-very_debug accepted"
    else
        fail "-very_debug accepted" "exit $rc: $out"
    fi
}

# -llvm accepted (default backend, no-op)
test_llvm() {
    local out
    out=$(compile "$MINIMAL" -llvm -exe "$TMPDIR/test_llvm" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-llvm accepted"
    else
        fail "-llvm accepted" "exit $rc: $out"
    fi
}

# -context_size accepted
test_context_size() {
    local out
    out=$(compile "$MINIMAL" -context_size 2048 -exe "$TMPDIR/test_cs" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-context_size accepted"
    else
        fail "-context_size accepted" "exit $rc: $out"
    fi
}

# -plug accepted (no-op)
test_plug() {
    local out
    out=$(compile "$MINIMAL" -plug SomePlugin -exe "$TMPDIR/test_plug" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-plug accepted"
    else
        fail "-plug accepted" "exit $rc: $out"
    fi
}

# -plugin alias accepted
test_plugin_alias() {
    local out
    out=$(compile "$MINIMAL" -plugin SomePlugin -exe "$TMPDIR/test_plugin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-plugin alias accepted"
    else
        fail "-plugin alias accepted" "exit $rc: $out"
    fi
}

# -import_dir accepted
test_import_dir() {
    local out
    out=$(compile "$MINIMAL" -import_dir /tmp -exe "$TMPDIR/test_idir2" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
        pass "-import_dir accepted"
    else
        fail "-import_dir accepted" "exit $rc: $out"
    fi
}

# -add + -run combined
test_add_and_run() {
    local src="$TMPDIR/test_add_run.jai"
    cat > "$src" << 'JAI'
main :: () {
    x := INJECTED;
}
JAI
    local out
    out=$(compile "$src" -add "INJECTED :: 99;" -run 'print("combined\n")' -exe "$TMPDIR/test_ar_bin" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ] && echo "$out" | grep -q "combined"; then
        pass "-add + -run combined"
    else
        fail "-add + -run combined" "exit $rc: $out"
    fi
}

# -msvc_format + -no_color interaction
test_msvc_no_color() {
    local out
    out=$(compile "$ERROR_SRC" -msvc_format -no_color -exe "$TMPDIR/nope" 2>&1) || true
    if echo "$out" | grep -qE '\([0-9]+,[0-9]+\): error:' && ! echo "$out" | grep -q $'\x1b'; then
        pass "-msvc_format + -no_color"
    else
        fail "-msvc_format + -no_color" "unexpected format: $out"
    fi
}

# Produced binary actually runs
test_binary_runs() {
    local bin="$TMPDIR/test_runs_bin"
    compile "$HELLO" -exe "$bin" >/dev/null 2>&1
    local out
    out=$("$bin" 2>&1)
    if echo "$out" | grep -q "hello world"; then
        pass "compiled binary runs correctly"
    else
        fail "compiled binary runs correctly" "expected 'hello world', got: $out"
    fi
}

# -release binary runs
test_release_binary_runs() {
    local bin="$TMPDIR/test_release_runs"
    compile "$HELLO" -release -exe "$bin" >/dev/null 2>&1
    local out
    out=$("$bin" 2>&1)
    if echo "$out" | grep -q "hello world"; then
        pass "-release binary runs correctly"
    else
        fail "-release binary runs correctly" "expected 'hello world', got: $out"
    fi
}

# --- Run all tests ---

test_version
test_help
test_help_question
test_no_args
test_unknown_flag
test_check
test_check_no_binary
test_add
test_add_multiple
test_run
test_run_multiple
test_msvc_format
test_default_error_format
test_no_color
test_default_color
test_verbose
test_verbose_phases
test_verbose_add_run
test_verbose_linked
test_quiet
test_quiet_verbose
test_release
test_release_debug
test_report_poly
test_no_cwd
test_default_cwd
test_exe
test_dev_help
test_triple_dash
test_dev_unknown
test_dev_import_dir
test_dev_meta
test_dev_no_jobs
test_dash_separator
test_no_dce
test_no_check
test_no_check_bindings
test_no_inline
test_no_split
test_no_backtrace
test_natvis
test_debugger
test_debug_for
test_very_debug
test_llvm
test_context_size
test_plug
test_plugin_alias
test_import_dir
test_add_and_run
test_msvc_no_color
test_binary_runs
test_release_binary_runs

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
