#import "Basic";

code :: #code value := 99;

caller_line :: (loc := #caller_location) -> int {
    return loc.line_number;
}

validate :: () -> int {
    loc := #location(code);
    assert(contains(loc.fully_pathed_filename, "source_location_value.jai"));
    assert(loc.line_number == 3);
    observed := caller_line();
    assert(observed == 13);
    return observed + loc.line_number;
}

RESULT :: #run validate();

main :: () {
    print("%\n", RESULT);
}
