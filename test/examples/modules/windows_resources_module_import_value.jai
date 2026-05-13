#import "Basic";

#run {
    Windows_Resources :: #import "Windows_Resources";
    Windows_Resources.disable_runtime_console();
    print("windows-resources:%\n", Windows_Resources.gl);
}

main :: () {}
