#import "Basic";
#import "File";

#run {
    make_directory_if_it_does_not_exist("out/test-runtime");
    path := "out/test-runtime/comptime_file_handle.txt";
    write_entire_file(path, "alpha");

    file, opened := file_open(path, for_writing=true, keep_existing_content=true);
    original_length := file_length(file);
    positioned := file_set_position(file, original_length);
    wrote := file_write(*file, " beta");
    file_close(*file);

    reader, read_opened := file_open(path);
    final_length := file_length(reader);
    buffer := cast(*u8) alloc(final_length);
    read := file_read(reader, buffer, final_length);
    file_close(*reader);

    text := to_string(buffer, final_length);
    print("file-handles:% % % % % % %\n",
        opened,
        original_length == 5,
        positioned,
        wrote,
        read_opened,
        read,
        text == "alpha beta");
    free(buffer);
}

main :: () {}
