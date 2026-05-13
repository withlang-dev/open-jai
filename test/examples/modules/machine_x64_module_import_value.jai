#import "Basic";
#import "Machine_X64";

#run {
    cpu_info := get_cpu_info();
    check := check_feature(cpu_info.feature_leaves, x86_Feature_Flag.AVX2);
    direct := has_feature(x86_Feature_Flag.AVX2);
    print("machine-x64:% %\n", check, direct);
}

main :: () {}
