#import "Basic";

#scope_export;

GENERATOR_DEFAULT_SYSTEM_INCLUDE_PATH :: "/usr/include";

Binding_Generator_Strip_Flags :: enum_flags {
    INLINED_FUNCTIONS;
}

Generate_Bindings_Options :: struct {
    libpaths: [..] string;
    libnames: [..] string;
    include_paths: [..] string;
    source_files: [..] string;
    system_include_paths: [..] string;
    extra_clang_arguments: [..] string;
    strip_flags: Binding_Generator_Strip_Flags;
    header: string;
}

generate_bindings :: (options: Generate_Bindings_Options, output_filename: string) -> bool {
    return false;
}
