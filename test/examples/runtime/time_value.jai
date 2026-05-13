#import "Basic";

#run {
    wall := current_time_consensus();
    monotonic := current_time_monotonic();
    calendar := to_calendar(wall, .UTC);
    calendar_text := calendar_to_string(calendar);

    print("time:% % % % % % %\n",
        wall.low > 0,
        monotonic.low > 0,
        get_time() > 0.0,
        seconds_since_init() >= 0.0,
        to_float64_seconds(1000000000) == 1.0,
        calendar.year >= 2020,
        calendar_text != "");
}

main :: () {}
