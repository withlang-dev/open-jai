#scope_export;

File :: struct {
    handle: s64;
}

File_Visit_Info :: struct {
    short_name: string;
    full_name: string;
    descend_into_directory: bool;
}

make_directory_if_it_does_not_exist :: (path: string, recursive := false) -> bool {
    return true;
}

delete_directory :: (path: string) -> bool {
    return true;
}

file_exists :: (path: string) -> bool {
    return false;
}

set_working_directory :: (path: string) -> bool {
    return true;
}

get_working_directory :: () -> string {
    return "";
}

write_entire_file :: (path: string, contents: string) -> bool {
    return true;
}

read_entire_file :: (path: string, log_errors := true) -> (contents: string, success: bool) {
    return "", false;
}

file_open :: (path: string, for_writing := false, keep_existing_content := false) -> (file: File, success: bool) {
    return File.{}, false;
}

file_close :: (file: *File) -> bool {
    return true;
}

file_length :: (file: File) -> s64 {
    return 0;
}

file_set_position :: (file: File, position: s64) -> bool {
    return true;
}

file_write :: (file: *File, data: string) -> bool {
    return true;
}

file_read :: (file: File, buffer: *u8, byte_count: s64) -> bool {
    return true;
}
