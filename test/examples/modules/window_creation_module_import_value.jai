#import "Basic";
#import "Window_Creation";

#run {
    first := create_window(800, 600, "First");
    second := create_window(window_name = "Second", width = 320, height = 240);

    first_width, first_height := get_render_dimensions(first);
    second_width, second_height := get_render_dimensions(second);
    missing_width, missing_height := get_render_dimensions(9999);

    print("window:% % % % % % % %\n",
        first,
        second,
        first_width,
        first_height,
        second_width,
        second_height,
        missing_width,
        missing_height);
}

main :: () {}
