#import "Basic";

make_calendar :: () -> Calendar {
    now := current_time_consensus();
    return to_calendar(now, .UTC);
}

CAL :: #run make_calendar();

main :: () {
    print("calendar:% %\n", CAL.year >= 2020, CAL.time_zone == 0);
}
