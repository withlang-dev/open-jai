#scope_export;

Run_Command_Result :: struct {
    exit_code: s64;
    standard_output: string;
    standard_error: string;
    timed_out: bool;
}

run_command :: (
    command: string,
    capture_and_return_output := false
) -> (exit_code: s64, standard_output: string, standard_error: string, timed_out: bool) {
    return 0, "", "", false;
}

thread_is_done :: () -> bool {
    return true;
}

shutdown :: () {
}
