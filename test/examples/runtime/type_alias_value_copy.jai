#import "Basic";

Handle :: int;

next_handle: Handle = 1;

next :: () -> Handle {
    result := next_handle;
    next_handle += 1;
    return result;
}

#run {
    a := next();
    b := next();
    c := next();

    print("alias-copy:% % % %\n", a, b, c, next_handle);
}

main :: () {}
