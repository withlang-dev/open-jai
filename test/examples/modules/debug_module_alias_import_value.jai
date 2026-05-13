#import "Basic";

Debug :: #import "Debug";

#run {
    Debug.init();
    Debug.attach_to_debugger();
    Debug.breakpoint();
    print("debug:alias\n");
}

main :: () {}
