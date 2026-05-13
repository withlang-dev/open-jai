#import "Basic";
#import "Compiler";

make_location_value :: () -> Source_Code_Location {
    return #caller_location;
}

LOC :: #run make_location_value();

main :: () {
    print("run-loc:% %\n", contains(LOC.fully_pathed_filename, "source_location_run_value.jai"), LOC.line_number > 0);
}
