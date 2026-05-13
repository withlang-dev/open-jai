#import "Basic";
#import "String";

#run {
    builder: String_Builder;
    init_string_builder(*builder);
    defer free_buffers(*builder);

    append(*builder, "open");
    print_to_builder(*builder, "-%", "jai");

    text := builder_to_string(*builder);
    print("string:% % % % % %\n",
        text == "open-jai",
        builder_string_length(*builder) == 8,
        begins_with(text, "open"),
        find_index_from_right(text, "i") == 7,
        is_digit(#char "7"),
        join(.. .["a", "b"], separator = "-") == "a-b");
}

main :: () {}
