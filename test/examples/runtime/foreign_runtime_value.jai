#import "Basic";

__openjai_get_time_seconds :: () -> float64 #foreign;

main :: () {
    seconds := __openjai_get_time_seconds();
    print("foreign-time:%\n", seconds >= 0.0);
}
