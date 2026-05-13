#import "Process";

#run {
    result, output, error, timed_out := run_command("printf process-module", capture_and_return_output=true);
    print("process:% % % %\n", result, output, error, timed_out);
}

main :: () {}

