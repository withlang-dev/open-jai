#import "Basic";
#import "Random";

#run {
    random_seed(12345);
    first := random_get();
    unit := random_get_zero_to_one();
    ranged := random_get_within_range(10, 20);

    random_seed(12345);
    same_first := random_get();

    print("random:% % %\n", first == same_first, unit >= 0 && unit < 1, ranged >= 10 && ranged < 20);
}

main :: () {}
