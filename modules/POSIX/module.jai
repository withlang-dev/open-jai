#scope_export;

STDIN_FILENO  :: 0;
STDOUT_FILENO :: 1;
STDERR_FILENO :: 2;

read :: (fd: s64, buffer: *u8, byte_count: s64) -> s64 {
    return -1;
}
