#import "Basic";
#import "Windows";

#run {
    h: HANDLE = GetStdHandle(STD_INPUT_HANDLE);
    print("windows:% % % %\n", h, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE);
}

main :: () {}
