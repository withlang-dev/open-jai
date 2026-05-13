#scope_export;

GL_VENDOR :: 0x1F00;
GL_RENDERER :: 0x1F01;
GL_VERSION :: 0x1F02;
GL_SHADING_LANGUAGE_VERSION :: 0x8B8C;

GL_COLOR_BUFFER_BIT :: 0x00004000;
GL_TEXTURE_2D :: 0x0DE1;
GL_TEXTURE_MIN_FILTER :: 0x2801;
GL_TEXTURE_MAG_FILTER :: 0x2800;
GL_NEAREST :: 0x2600;

GL_ARRAY_BUFFER :: 0x8892;
GL_STATIC_DRAW :: 0x88E4;
GL_VERTEX_SHADER :: 0x8B31;
GL_FRAGMENT_SHADER :: 0x8B30;
GL_TRIANGLES :: 0x0004;
GL_FLOAT :: 0x1406;
GL_FALSE :: 0;
GL_TRUE :: 1;

gl: s64 = 0;
last_clear_mask: int;
last_viewport_width: int;
last_viewport_height: int;
last_clear_r: float64;
last_clear_g: float64;
last_clear_b: float64;
last_clear_a: float64;
next_gl_handle: int = 1;

gl_load :: (gl_context: *s64, get_proc_address: Any) -> bool {
    gl_context.* = 1;
    return true;
}

glGetString :: (name: int) -> string {
    if name == GL_VENDOR return "OpenJai";
    if name == GL_VERSION return "OpenJai GL 1.0";
    if name == GL_RENDERER return "OpenJai Software GL";
    if name == GL_SHADING_LANGUAGE_VERSION return "OpenJai GLSL";
    return "";
}

glTexParameteri :: (target: int, pname: int, param: int) {
}

glViewport :: (x: int, y: int, width: int, height: int) {
    last_viewport_width = width;
    last_viewport_height = height;
}

glClearColor :: (r: float64, g: float64, b: float64, a: float64) {
    last_clear_r = r;
    last_clear_g = g;
    last_clear_b = b;
    last_clear_a = a;
}

glClear :: (mask: int) {
    last_clear_mask = mask;
}

glGenBuffers :: (count: int, buffers: *u32) {
    if count > 0 && buffers {
        buffers.* = xx next_gl_handle;
        next_gl_handle += count;
    }
}

glBindBuffer :: (target: int, buffer: int) {
}

glBufferData :: (target: int, size: int, data: Any, usage: int) {
}

glCreateShader :: (kind: int) -> int {
    result := next_gl_handle;
    next_gl_handle += 1;
    return result;
}

_glShaderSource :: (shader: int, source: string) {
}

glCompileShader :: (shader: int) {
}

glCreateProgram :: () -> int {
    result := next_gl_handle;
    next_gl_handle += 1;
    return result;
}

glAttachShader :: (program: int, shader: int) {
}

glLinkProgram :: (program: int) {
}

glGetUniformLocation :: (program: int, name: string) -> int {
    return 0;
}

glGetAttribLocation :: (program: int, name: string) -> int {
    return 0;
}

glUseProgram :: (program: int) {
}

glDrawArrays :: (mode: int, first: int, count: int) {
}
