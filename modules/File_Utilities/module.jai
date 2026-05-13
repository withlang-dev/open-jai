#scope_export;

#import "File";

copy_file :: (source: string, destination: string) -> bool {
    return false;
}

visit_files :: (start_path: string, recursive: bool, user_data: $User_Data, visitor: $Visitor, visit_files := true, visit_directories := false) -> bool {
    return false;
}
