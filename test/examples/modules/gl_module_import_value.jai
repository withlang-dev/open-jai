#import "Basic";
#import "GL";

#run {
    loaded := gl_load(*gl, null);
    vendor := glGetString(GL_VENDOR);
    version := glGetString(GL_VERSION);

    buffer: u32;
    glGenBuffers(1, *buffer);
    shader := glCreateShader(GL_VERTEX_SHADER);
    program := glCreateProgram();
    glAttachShader(program, shader);
    glLinkProgram(program);
    glViewport(0, 0, 640, 480);
    glClearColor(0.1, 0.2, 0.3, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);

    print("gl:% % % % % % % % %\n",
        loaded,
        gl,
        vendor,
        version,
        buffer,
        shader,
        program,
        last_viewport_width,
        last_clear_mask == GL_COLOR_BUFFER_BIT);
}

main :: () {}
