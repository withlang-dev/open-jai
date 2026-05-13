#scope_export;

compare_floats :: (a: float, b: float) -> s64 {
    if a < b return -1;
    if a > b return 1;
    return 0;
}

compare_strings :: (a: string, b: string) -> s64 {
    return compare(a, b);
}

quick_sort :: (array: [] $T, comparator: $Comparator) {
}

bubble_sort :: (array: [] $T, comparator: $Comparator) {
}
