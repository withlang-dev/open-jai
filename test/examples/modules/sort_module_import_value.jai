#import "Basic";
#import "Sort";

#run {
    numbers := float.[8, 108, 42, 5, 3.14, 17, -5, -272];
    words := string.["the", "quick", "brown", "fox", "jumped", "over", "the", "lazy", "dog"];

    quick_sort(numbers, compare_floats);
    bubble_sort(words, compare_strings);

    print("sort:% %\n", numbers, words);
}

main :: () {}
