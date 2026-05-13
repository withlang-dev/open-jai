#scope_export;

String_Builder :: struct {
    data: *u8;
    count: int;
    allocated: int;
}

sprint :: (format: string, args: ..Any) -> string #foreign;
tprint :: (format: string, args: ..Any) -> string #foreign;
to_string :: (value: Any) -> string #foreign;
to_string :: (data: *u8, count: int) -> string #foreign;
to_c_string :: (value: string) -> *u8 #foreign;
copy_string :: (value: string) -> string #foreign;

init_string_builder :: (builder: *String_Builder) #foreign;
free_buffers :: (builder: *String_Builder) #foreign;
append :: (builder: *String_Builder, value: Any) -> bool #foreign;
print_to_builder :: (builder: *String_Builder, format: string, args: ..Any) -> bool #foreign;
builder_string_length :: (builder: *String_Builder) -> int #foreign;
builder_to_string :: (builder: *String_Builder, allocator := temp) -> string #foreign;

compare :: (a: string, b: string) -> int #foreign;
compare_strings :: (a: string, b: string) -> int #foreign;
equal :: (a: string, b: string) -> bool #foreign;
contains :: (haystack: string, needle: string) -> bool #foreign;
begins_with :: (haystack: string, prefix: string) -> bool #foreign;
split :: (value: string, separator: string) -> [] string #foreign;
trim :: (value: string) -> string #foreign;
join :: (values: ..string, separator := "", before_first := false, after_last := false) -> string #foreign;
find_index_from_left :: (haystack: string, needle: string) -> int #foreign;
find_index_from_right :: (haystack: string, needle: string) -> int #foreign;
string_to_int :: (value: string) -> int, bool #foreign;
string_to_float :: (value: string) -> float64, bool #foreign;
parse_int :: (value: *string) -> int, bool #foreign;
to_integer :: (value: string) -> int, bool, int #foreign;
replace :: (value: string, old: string, new: string) -> string #foreign;
slice :: (value: string, start: int, count: int) -> string #foreign;
path_strip_filename :: (path: string) -> string #foreign;
c_style_strlen :: (value: *u8) -> int #foreign;

to_upper :: (c: int) -> int {
    if c >= #char "a" && c <= #char "z" return c - 32;
    return c;
}

to_lower :: (c: int) -> int {
    if c >= #char "A" && c <= #char "Z" return c + 32;
    return c;
}

is_digit :: (c: int) -> bool {
    return c >= #char "0" && c <= #char "9";
}

is_alpha :: (c: int) -> bool {
    return (c >= #char "a" && c <= #char "z") || (c >= #char "A" && c <= #char "Z");
}

is_alnum :: (c: int) -> bool {
    return is_alpha(c) || is_digit(c);
}

is_space :: (c: int) -> bool {
    return c == #char " " || c == #char "\t" || c == #char "\n" || c == #char "\r";
}

is_any :: (c: int, set: string) -> bool {
    for set {
        if it == c return true;
    }

    return false;
}
