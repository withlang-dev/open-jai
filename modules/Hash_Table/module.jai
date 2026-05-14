#scope_export;

Table :: struct($K: Type, $V: Type) {
    keys: [..] K;
    values: [..] V;
    count: int;
}

init :: (table: *Table($K, $V), capacity := 0) {
    if capacity > 0 {
        array_reserve(*table.keys, capacity);
        array_reserve(*table.values, capacity);
    }
    table.count = table.keys.count;
}

deinit :: (table: *Table($K, $V)) {
    array_free(table.keys);
    array_free(table.values);
    table.count = 0;
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
    table.count = table.keys.count;
}

table_set :: (table: *Table($K, $V), key: K, value: V) {
    table_add(table, key, value);
}

table_find :: (table: *Table($K, $V), key: K) -> bool, V {
    for table.keys {
        if it == key {
            return true, table.values[it_index];
        }
    }

    result: V;
    return false, result;
}

table_find_pointer :: (table: *Table($K, $V), key: K) -> *V {
    for table.keys {
        if it == key return *table.values[it_index];
    }
    return null;
}

table_contains :: (table: *Table($K, $V), key: K) -> bool {
    ok, _ := table_find(table, key);
    return ok;
}

table_remove :: (table: *Table($K, $V), key: K) -> bool, V {
    for table.keys {
        if it == key {
            value := table.values[it_index];
            array_ordered_remove_by_index(*table.keys, it_index);
            array_ordered_remove_by_index(*table.values, it_index);
            table.count = table.keys.count;
            return true, value;
        }
    }
    result: V;
    return false, result;
}
