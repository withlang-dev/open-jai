// Public runtime surface for OpenJai tests.
//
// Test procedures are ordinary zero-argument procedures tagged with
// @TestProcedure. The bootstrap test runner discovers those notes through the
// compiler parser and records ordinary assert calls while executing tests.

Test_Result :: enum {
    PASS;
    FAIL;
}

Test_Case :: struct {
    file: string;
    procedure: string;
    result: Test_Result;
    assert_count: int;
}

