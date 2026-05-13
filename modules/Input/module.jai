#import "Basic";

#scope_export;

Window_Type :: s64;

Input_Event_Type :: enum {
    QUIT;
    KEYBOARD;
}

Key_Code :: enum {
    ESCAPE;
    MOUSE_BUTTON_LEFT;
    ARROW_UP;
    ARROW_DOWN;
    ARROW_LEFT;
    ARROW_RIGHT;
}

Window_Event :: struct {
    type: Input_Event_Type;
    key_pressed: bool;
    key_code: Key_Code;
}

Window_Resize :: struct {
    window: Window_Type;
    width: int;
    height: int;
}

events_this_frame: [..] Window_Event;
window_resizes_this_frame: [..] Window_Resize;

update_window_events :: () {
    array_reset(*events_this_frame);
    array_reset(*window_resizes_this_frame);
}

get_window_resizes :: () -> [..] Window_Resize {
    return window_resizes_this_frame;
}

get_mouse_pointer_position :: () -> float, float, bool {
    return 0.0, 0.0, false;
}

get_mouse_pointer_position :: (window: Window_Type, client_area := false) -> float, float {
    return 0.0, 0.0;
}
