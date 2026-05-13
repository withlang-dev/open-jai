#scope_export;

Table :: struct($K: Type, $V: Type) {
    keys: [..] K;
    values: [..] V;
}

table_add :: (table: *Table($K, $V), key: K, value: V) {
    for table.keys {
        if it == key {
            table.values[it_index] = value;
            return;
        }
    }

    array_add(*table.keys, key);
    array_add(*table.values, value);
}

table_find :: (table: *Table($K, $V), key: K) -> V, bool {
    for table.keys {
        if it == key {
            return table.values[it_index], true;
        }
    }

    result: V;
    return result, false;
}

table_remove :: (table: *Table($K, $V), key: K) {
    for table.keys {
        if it == key {
            array_ordered_remove_by_index(*table.keys, it_index);
            array_ordered_remove_by_index(*table.values, it_index);
            return;
        }
    }
}
