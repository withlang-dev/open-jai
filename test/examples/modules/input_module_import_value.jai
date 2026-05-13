#import "Basic";
#import "Input";

#run {
    array_add(*events_this_frame, Window_Event.{.KEYBOARD, true, .ESCAPE});
    array_add(*window_resizes_this_frame, Window_Resize.{12, 640, 480});

    event_count_before := events_this_frame.count;
    resize_count_before := get_window_resizes().count;
    event := events_this_frame[0];
    resize := get_window_resizes()[0];

    update_window_events();

    x, y, success := get_mouse_pointer_position();
    wx, wy := get_mouse_pointer_position(12, true);

    print("input:% % % % % % % % % %\n",
        event_count_before,
        resize_count_before,
        event.type == .KEYBOARD,
        event.key_pressed,
        event.key_code == .ESCAPE,
        resize.width,
        resize.height,
        events_this_frame.count,
        get_window_resizes().count,
        success);
}

main :: () {}
