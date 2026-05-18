#import "Basic";
#import "Random";

main :: () {
    // Random numbers: 
    print("A random integer: %\n", random_get()); // => A random integer:...
    print("A random float between 0 and 1: %\n", random_get_zero_to_one()); // => A random float between 0 and 1:...
    print("A random float between 0 and 100: %\n", random_get_within_range(0, 100)); // => A random float between 0 and 100:...

    r := random_seed(current_time_monotonic().low);

    print("\nA random integer: %\n", random_get()); // => A random integer:...
    print("A random float between 0 and 1: %\n", random_get_zero_to_one()); // => A random float between 0 and 1:...
    print("A random float between 0 and 100: %\n", random_get_within_range(0, 100)); // => A random float between 0 and 100:...

}

/*
A random integer: 1137526400306752306
A random float between 0 and 1: 0.709799
A random float between 0 and 100: 75.796494

A random integer: 16108974926811509810
A random float between 0 and 1: 0.603063
A random float between 0 and 100: 65.397636 
*/