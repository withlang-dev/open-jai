#import "File_Utilities";

#run {
    source := "out/test_file_utilities_source.txt";
    destination := "out/test_file_utilities_destination.txt";

    write_entire_file(source, "copied");
    copied := copy_file(source, destination);
    contents, ok := read_entire_file(destination);

    print("file-utilities:% % %\n", copied, ok, contents);
}

main :: () {}
