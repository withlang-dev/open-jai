#import "Basic";
#import "Debug";

#run {
    init();
    attach_to_debugger();
    breakpoint();
    print("debug:direct\n");
}

main :: () {}
