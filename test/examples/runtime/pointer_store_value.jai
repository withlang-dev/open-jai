#import "Basic";

set_u32 :: (p: *u32) {
    p.* = xx 7;
}

set_int :: (p: *int) {
    p.* = 9;
}

set_bool :: (p: *bool) {
    p.* = true;
}

#run {
    a: u32;
    b: int;
    c: bool;

    set_u32(*a);
    set_int(*b);
    set_bool(*c);

    b = 11;
    print("ptrstore:% % %\n", a, b, c);
}

main :: () {}
