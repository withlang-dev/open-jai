#import "BuildCpp";

#run {
    linked := cpp_link_library("openjai-test");
    print("build-cpp:%\n", linked);
}

main :: () {}
