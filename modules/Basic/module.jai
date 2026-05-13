#scope_export;

#module_parameters(MEMORY_DEBUGGER := false);

#import "String";
#import "Math";
#import "Random";
#import "File";
#import "System";

Apollo_Time :: struct {
    low: s64;
}

Allocator_Mode :: enum {
    ALLOCATE;
    RESIZE;
    FREE;
    FREE_ALL;
}

Allocator_Proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory_pointer: *void, proc_data: *void) -> *void;

Allocator :: struct {
    proc: Allocator_Proc;
    data: *void;
}

Temporary_Storage :: struct {
    data: *void;
    size: s64;
    occupied: s64;
    total_bytes_occupied: s64;
}

Format_Int :: struct {
    base: s64;
    minimum_digits: s64;
}

Format_Float :: struct {
    width: s64;
    trailing_width: s64;
}

Format_Struct :: struct {
    draw_type_name: bool;
}

Print_Style :: struct {
    default_format_int: *Format_Int;
    default_format_float: *Format_Float;
    default_format_struct: *Format_Struct;
}

Context :: struct {
    allocator: Allocator;
    default_allocator: Allocator;
    temporary_storage: Temporary_Storage;
    print_style: Print_Style;
    stack_base: *void;
    stack_trace: *void;
    this_is_the_way: bool;
}

Type_Info_Tag :: enum {
    INTEGER;
    FLOAT;
    STRUCT;
    POINTER;
    ARRAY;
    PROCEDURE;
    ENUM;
    ANY;
    VARIANT;
}

Type_Info :: struct {
    type: Type_Info_Tag;
    runtime_size: s64;
}

Type_Info_Struct_Member :: struct {
    name: string;
    type: Type;
    offset_in_bytes: s64;
    flags: s64;
}

Type_Info_Struct :: struct {
    using info: Type_Info;
    name: string;
    members: [..] Type_Info_Struct_Member;
}

Type_Info_Integer :: struct {
    using info: Type_Info;
    signed: bool;
}

Type_Info_Pointer :: struct {
    using info: Type_Info;
    points_to: Type;
}

Type_Info_Procedure :: struct {
    using info: Type_Info;
    argument_types: [] Type;
}

Any :: #type any;

temp: Allocator;
context: Context;

print :: (format: string, args: ..Any) -> s64 #foreign;
log :: (format: string, args: ..Any) -> s64 #foreign;
assert :: (condition: bool, message := "", args: ..Any) #foreign;
exit :: (status: s64) #foreign;

swap :: (a: *$T, b: *T) #foreign;
memcpy :: (dest: *void, source: *void, count: s64) -> *void #foreign;
memset :: (dest: *void, value: s64, count: s64) -> *void #foreign;

alloc :: (size: s64, allocator := context.allocator) -> *void #foreign;
free :: (ptr: *void) #foreign;
NewArray :: ($T: Type, count: s64, allocator := context.allocator, alignment := 0) -> [] T #foreign;
NewArray :: (count: s64, $T: Type, allocator := context.allocator, alignment := 0) -> [] T #foreign;

push_allocator :: (allocator: Allocator) #foreign;
reset_temporary_storage :: () #foreign;
talloc_string :: (count: s64) -> string #foreign;
make_leak_report :: () -> string #foreign;
log_leak_report :: () #foreign;
get_capabilities :: (allocator: Allocator) -> (caps: bool, name: string) #foreign;

formatInt :: (value: s64, base := 10, minimum_digits := 0) -> string #foreign;
formatFloat :: (value: float64, width := 0, trailing_width := 6, zero_removal := true, mode := 0) -> string #foreign;
formatStruct :: (
    value: Any,
    use_long_form_if_more_than_this_many_members := 5,
    separator_between_name_and_value := " = ",
    short_form_separator_between_fields := ", ",
    long_form_separator_between_fields := "; ",
    begin_string := "{",
    end_string := "}",
    indentation_width := 4,
    use_newlines_if_long_form := false,
    draw_type_name := false
) -> string #foreign;

current_time_consensus :: () -> Apollo_Time #foreign;
current_time_monotonic :: () -> Apollo_Time #foreign;
to_calendar :: (time: Apollo_Time, local_time := true) -> Calendar #foreign;
calendar_to_string :: (calendar: Calendar) -> string #foreign;
get_time :: () -> float64 #foreign;
seconds_since_init :: () -> float64 #foreign;
sleep_milliseconds :: (milliseconds: s64) #foreign;
to_float64_seconds :: (time: Apollo_Time) -> float64 #foreign;

get_field :: (info: *Type_Info_Struct, name: string) -> *Type_Info_Struct_Member #foreign;
type_to_string :: (type: Type) -> string #foreign;
enum_range :: ($T: Type) -> (low: s64, high: s64) #foreign;
enum_values_as_s64 :: ($T: Type) -> [] s64 #foreign;
enum_names :: ($T: Type) -> [] string #foreign;

array_add :: (array: *[..]$T) -> *T #foreign;
array_add :: (array: *[..]$T, value: T) -> *T #foreign;
array_free :: (array: [..]$T) #foreign;
array_reset :: (array: *[..]$T) #foreign;
array_reserve :: (array: *[..]$T, capacity: s64) #foreign;
array_ordered_remove_by_index :: (array: *[..]$T, index: s64) #foreign;
array_find :: (array: [..]$T, value: T) -> bool #foreign;
array_copy :: (array: [..]$T) -> [..]T #foreign;
peek :: (array: [..]$T) -> T #foreign;
pop :: (array: *[..]$T) -> T #foreign;

get_command_line_arguments :: () -> [] string #foreign;

advance :: (value: *string, count: s64) #foreign;
log_error :: (format: string, args: ..Any) #foreign;
