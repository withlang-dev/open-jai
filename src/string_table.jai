// Port of bootstrap/src/string_table.zig.

String_Id :: int;

String_Table :: struct {
    count: int;
}

string_table_init :: () -> String_Table {
    table: String_Table;
    table.count = 0;
    return table;
}

string_table_intern :: (table: *String_Table, value: string) -> String_Id {
    table.count += 1;
    return table.count;
}

