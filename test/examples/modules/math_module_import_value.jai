#import "Basic";
#import "Math";

half_pi_sine :: #run sin(PI * .5);

#run {
    v2 := make_vector2(1, 2);
    v3 := make_vector3(3, 4, 5);
    v4 := make_vector4(6, 7, 8, 9);

    print(
        "math:% % % % % % % %\n",
        v2.x,
        v3.z,
        v4.w,
        min(5, 3),
        max(5, 3),
        clamp(8, 1, 4),
        abs(-7),
        half_pi_sine
    );
}

main :: () {}
