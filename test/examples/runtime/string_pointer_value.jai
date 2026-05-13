#import "Basic";
#import "String";

#run {
    source := "alpha";
    from_parts := to_string(source.data, source.count);
    c_string := to_c_string("beta");
    from_c := to_string(c_string);
    copied := copy_string(from_parts);
    parsed_int, parsed_int_ok := string_to_int("42");
    failed_int, failed_int_ok := string_to_int("abc");
    parsed_float, parsed_float_ok := string_to_float("3.5");

    print("strings:% % % % % % % % % % % % %\n",
        from_parts == "alpha",
        from_c == "beta",
        copied == "alpha",
        trim("\t  ok  \n") == "ok",
        compare("abc", "abc") == 0,
        contains("Antwerp", "Ant"),
        begins_with("Antwerp", "Ant"),
        find_index_from_left("London", "on") == 1,
        find_index_from_right("London", "on") == 4,
        slice("London", 2, 3) == "ndo",
        parsed_int_ok && parsed_int == 42 && !failed_int_ok && failed_int == 0,
        parsed_float_ok && parsed_float == 3.5,
        to_string(copied.data, copied.count) == "alpha");
}

main :: () {}
