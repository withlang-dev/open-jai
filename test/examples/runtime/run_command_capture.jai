#import "Basic";
#import "Process";

#run {
    result, output, error, timeout := run_command("printf 'captured stdout'; printf 'captured stderr' 1>&2", capture_and_return_output=true);
    print("result:% output:% error:% timeout:%\n", result, output, error, timeout);
}

main :: () {}
