#import "Basic";

choose_type :: () -> Type {
    return string;
}

Chosen_Type :: #run choose_type();

#run {
    print("type:%\n", type_to_string(Chosen_Type));
}

main :: () {}
