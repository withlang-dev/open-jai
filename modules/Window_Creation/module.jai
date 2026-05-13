#import "Basic";
#import "Input";

#scope_export;

Window_Record :: struct {
    window: Window_Type;
    width: int;
    height: int;
    name: string;
}

windows: [..] Window_Record;
next_window: Window_Type = 1;

create_window :: (width: int, height: int, window_name: string) -> Window_Type {
    window := next_window;
    next_window += 1;

    array_add(*windows, Window_Record.{window, width, height, window_name});
    return window;
}

get_render_dimensions :: (window: Window_Type) -> int, int {
    for windows {
        if it.window == window {
            return it.width, it.height;
        }
    }

    return 0, 0;
}
