#import "System";

#run {
    exe_path := get_path_of_running_executable();
    cpus := get_number_of_processors();
    print("system:% %\n", exe_path != "", cpus > 0);
}

main :: () {}
