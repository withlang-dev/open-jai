#scope_export;

Process_Result_Type :: enum s32 {
    UNSTARTED        :: 0;
    STILL_RUNNING    :: 1;
    FAILED_TO_LAUNCH :: 2;
    EXITED           :: 3;
    SIGNALED         :: 4;
}

Process_Result :: struct {
    type:      Process_Result_Type;
    exit_code: s32;
    signal:    s32;
}

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
