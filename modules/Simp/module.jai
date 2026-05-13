#import "Basic";
#import "Input";
#import "Math";

#scope_export;

Texture :: struct {
    id: int;
    width: int;
    height: int;
}

Dynamic_Font :: struct {
    id: int;
    pixel_height: int;
    path: string;
    filename: string;
}

Render_State :: struct {
    target: Window_Type;
    clear_r: float64;
    clear_g: float64;
    clear_b: float64;
    clear_a: float64;
    color_shader_enabled: bool;
    image_shader_texture_id: int;
    frame_count: int;
    primitive_count: int;
}

gl: s64 = 0;
state: Render_State;
next_texture_id: int = 1;
next_font_id: int = 1;
default_font: Dynamic_Font;

gl_load :: (gl_context: *s64, get_proc_address: Any) -> bool {
    gl_context.* = 1;
    return true;
}

set_render_target :: (window: Window_Type) {
    state.target = window;
}

update_window :: (window: Window_Type) {
    state.target = window;
}

set_shader_for_color :: (enabled := true) {
    state.color_shader_enabled = enabled;
}

set_shader_for_images :: (texture: *Texture) {
    if texture {
        state.image_shader_texture_id = texture.id;
    } else {
        state.image_shader_texture_id = 0;
    }
}

clear_render_target :: (r: float64, g: float64, b: float64, a: float64) {
    state.clear_r = r;
    state.clear_g = g;
    state.clear_b = b;
    state.clear_a = a;
}

swap_buffers :: (window: Window_Type) {
    state.target = window;
    state.frame_count += 1;
}

immediate_begin :: () {
}

immediate_flush :: () {
}

immediate_quad :: (x0: float64, y0: float64, x1: float64, y1: float64, color: Vector4) {
    state.primitive_count += 1;
}

immediate_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    state.primitive_count += 1;
}

immediate_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, uv0 := Vector2.{0, 0}, uv1 := Vector2.{1, 0}, uv2 := Vector2.{1, 1}, uv3 := Vector2.{0, 1}) {
    state.primitive_count += 1;
}

immediate_triangle :: (p0: Vector3, p1: Vector3, p2: Vector3, c0: Vector4, c1: Vector4, c2: Vector4) {
    state.primitive_count += 1;
}

texture_load_from_file :: (texture: *Texture, filename: string) -> bool {
    if !texture return false;

    texture.id = next_texture_id;
    texture.width = 32;
    texture.height = 32;
    next_texture_id += 1;
    return true;
}

get_font_at_size :: (path: string, filename: string, pixel_height: int) -> *Dynamic_Font {
    default_font.id = next_font_id;
    default_font.pixel_height = pixel_height;
    default_font.path = path;
    default_font.filename = filename;
    next_font_id += 1;
    return *default_font;
}

load_font :: (path: string, filename: string, pixel_height: int) -> *Dynamic_Font {
    return get_font_at_size(path, filename, pixel_height);
}

draw_text :: (font: *Dynamic_Font, text: string, x: float64, y: float64, color: Vector4) {
    if font state.primitive_count += 1;
}

DrawTexturePro :: (texture: Texture, source: Any, dest: Any, origin: Any, rotation: float64, tint: Vector4) {
    if texture.id != 0 state.primitive_count += 1;
}
