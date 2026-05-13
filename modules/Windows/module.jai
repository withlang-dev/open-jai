#scope_export;

HANDLE :: s64;

STD_INPUT_HANDLE  :: -10;
STD_OUTPUT_HANDLE :: -11;
STD_ERROR_HANDLE  :: -12;

GetStdHandle :: (standard_handle: s64) -> HANDLE {
    return 0;
}
