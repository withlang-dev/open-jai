#import "Basic";

// OpenJai test framework entry point.
//
// The bootstrap runner discovers zero-argument procedures tagged
// @TestProcedure under test/examples and dynamically adds compile-success
// coverage for examples/**/*.jai. The public test style intentionally stays
// ordinary Jai: write procedures, tag them, and use assert or expect_* helpers.

#load "framework/test_runtime.jai";
#load "framework/compiler_expect.jai";

main :: () {
    print("OpenJai test driver source. Run `make test-jai` to execute the suite.\n");
}

