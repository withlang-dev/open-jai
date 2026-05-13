#scope_export;

#import "File";

copy_file :: (source: string, destination: string) -> bool {
    contents, ok := read_entire_file(source);
    if !ok {
        return false;
    }

    return write_entire_file(destination, contents);
}

visit_files :: (start_path: string, recursive: bool, user_data: $User_Data, visitor: $Visitor, visit_files := true, visit_directories := false) -> bool {
    return false;
}
