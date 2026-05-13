#import "Basic";

#scope_export;

Rect :: struct {
    x: float64;
    y: float64;
    w: float64;
    h: float64;
}

Alignment :: enum {
    Left;
    Center;
    Right;
}

Default_Themes :: enum {
    Grayscale;
}

Label_Theme :: struct {
    alignment: Alignment;
}

Button_Theme :: struct {
    label_theme: Label_Theme;
}

Slider_Foreground_Theme :: struct {
    alignment: Alignment;
}

Slider_Theme :: struct {
    foreground: Slider_Foreground_Theme;
}

Overall_Theme :: struct {
    button_theme: Button_Theme;
    slider_theme: Slider_Theme;
}

Dropdown_State :: struct {
    open: bool;
}

Default_Theme_Proc :: #type () -> Overall_Theme;

getrect_theme: Overall_Theme;
default_theme_procs :: Default_Theme_Proc.[default_grayscale_theme];

default_grayscale_theme :: () -> Overall_Theme {
    theme: Overall_Theme;
    theme.button_theme.label_theme.alignment = .Center;
    theme.slider_theme.foreground.alignment = .Center;
    return theme;
}

ui_init :: () {
    getrect_theme = default_grayscale_theme();
}

ui_per_frame_update :: (window: s64, width: int, height: int, current_time: float64) {
}

getrect_handle_event :: (event: $T) {
}

get_rect :: (x: float64, y: float64, w: float64, h: float64) -> Rect {
    return Rect.{x, y, w, h};
}

button :: (r: Rect, label: string) -> bool {
    return false;
}

slider :: (r: Rect, value: *float, min: float64, max: float64, step: float64, theme: *Slider_Theme, prefix: string, suffix: string) -> bool {
    return false;
}

dropdown :: (r: Rect, items: $T, value: *s32) -> Dropdown_State {
    return Dropdown_State.{false};
}

draw_popups :: () {
}

set_default_theme :: (theme: Overall_Theme) {
    getrect_theme = theme;
}

