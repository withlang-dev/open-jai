#import "Basic";
#import "Compiler";

code :: #code value := 99;

caller_line :: (loc := #caller_location) -> int {
    return loc.line_number;
}

round_trip_location :: (loc: Source_Code_Location) -> Source_Code_Location {
    return loc;
}

validate :: () -> int {
    loc := #location(code);
    loc = round_trip_location(loc);
    assert(contains(loc.fully_pathed_filename, "source_location_value.jai"));
    assert(loc.line_number == 4);
    observed := caller_line();
    assert(observed == 19);
    return observed + loc.line_number;
}

RESULT :: #run validate();

main :: () {
    print("%\n", RESULT);
}
