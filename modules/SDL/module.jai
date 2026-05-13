#scope_export;

SDL_INIT_VIDEO :: 0x00000020;

SDL_WINDOWPOS_UNDEFINED :: 0x1FFF0000;
SDL_WINDOW_OPENGL :: 0x00000002;
SDL_WINDOW_RESIZABLE :: 0x00000020;

SDL_GL_CONTEXT_PROFILE_MASK :: 21;
SDL_GL_CONTEXT_PROFILE_CORE :: 1;

SDL_QUIT :: 0x100;
SDL_KEYUP :: 0x301;
SDL_WINDOWEVENT :: 0x200;
SDL_WINDOWEVENT_SIZE_CHANGED :: 0x05;
SDLK_ESCAPE :: 27;

SDL_Keysym :: struct {
    sym: int;
}

SDL_KeyboardEvent :: struct {
    keysym: SDL_Keysym;
}

SDL_WindowEvent :: struct {
    event: int;
    data1: int;
    data2: int;
}

SDL_Event :: struct {
    type: int;
    key: SDL_KeyboardEvent;
    window: SDL_WindowEvent;
}

SDL_WINDOWPOS_CENTERED_DISPLAY :: (display_index: int) -> int {
    return 0x2FFF0000 + display_index;
}

SDL_Init :: (flags: int) -> int {
    return 0;
}

SDL_Quit :: () {
}

SDL_CreateWindow :: (title: string, x: int, y: int, w: int, h: int, flags: int) -> *void {
    return cast(*void) 1;
}

SDL_DestroyWindow :: (window: *void) {
}

SDL_SetWindowTitle :: (window: *void, title: *u8) {
}

SDL_GetError :: () -> string {
    return "";
}

SDL_GL_SetAttribute :: (attribute: int, value: int) -> int {
    return 0;
}

SDL_GL_CreateContext :: (window: *void) -> s64 {
    return 1;
}

SDL_GL_GetProcAddress :: (name: string) -> *void {
    return cast(*void) 1;
}

SDL_GL_SwapWindow :: (window: *void) {
}

SDL_PollEvent :: (event: *SDL_Event) -> bool {
    return false;
}
