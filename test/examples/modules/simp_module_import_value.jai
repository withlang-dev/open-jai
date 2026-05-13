#import "Basic";
#import "Simp";

#run {
    texture: Texture;
    loaded := texture_load_from_file(*texture, "ship.png");
    font := get_font_at_size("fonts/", "test.ttf", 24);

    set_render_target(42);
    set_shader_for_color(false);
    set_shader_for_images(*texture);
    clear_render_target(0.25, 0.5, 0.75, 1.0);
    swap_buffers(42);

    print("simp:% % % % % % % % % %\n",
        loaded,
        texture.id,
        texture.width,
        texture.height,
        font != null,
        font.pixel_height,
        state.target,
        state.color_shader_enabled,
        state.image_shader_texture_id,
        state.frame_count);
}

main :: () {}
