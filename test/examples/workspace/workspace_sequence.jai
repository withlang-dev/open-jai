#import "Basic";
#import "Compiler";

current_workspace :: () -> Workspace {
    return get_current_workspace();
}

create_workspace :: () -> Workspace {
    return compiler_create_workspace();
}

w2 :: #run current_workspace();
w3 :: #run create_workspace();
w4 :: #run create_workspace();
w5 :: #run create_workspace();

main :: () {
    print("% % % %\n", w2, w3, w4, w5);
}
