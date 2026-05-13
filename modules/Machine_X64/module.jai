#scope_export;

Feature_Leaves :: [12]s64;

CPU_Info :: struct {
    feature_leaves: Feature_Leaves;
}

x86_Feature_Flag :: enum {
    INVALID;
    MMX;
    SSE;
    SSE2;
    SSE3;
    SSSE3;
    SSE4_1;
    SSE4_2;
    AVX;
    AVX2;
    AVX512F;
}

Feature :: x86_Feature_Flag;

get_cpu_info :: () -> CPU_Info {
}

check_feature :: (feature_leaves: Feature_Leaves, flag: x86_Feature_Flag) -> bool {
}

has_feature :: (flag: x86_Feature_Flag) -> bool {
}
