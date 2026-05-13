#import "POSIX";

#run {
    print("posix:% % %\n", STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO);
}

main :: () {}
