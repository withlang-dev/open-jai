#scope_file;

hidden_module_value :: () -> int {
    return 11;
}

#scope_export;

module_value :: () -> int {
    return hidden_module_value() + 6;
}
