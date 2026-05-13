#import "Basic";

#scope_export;

Thread_Continue_Status :: enum {
    CONTINUE;
    STOP;
}

Thread_Proc :: #type *void;
Thread_Group_Proc :: #type *void;

Thread :: struct {
    index: int;
    started: bool;
    done: bool = true;
}

Thread_Group :: struct {
    threads: [..] Thread;
    completed_work: [..] *void;
    logging: bool = true;
    started: bool;
    shutdown_requested: bool;
}

Mutex :: struct {
    debug_name: int;
    order: int;
    lock_count: int;
    recursion_count: int;
    locked: bool;
}

thread_init :: (thread: *Thread, proc: Thread_Proc) -> bool {
    if !thread return false;

    thread.index = 1;
    thread.started = false;
    thread.done = true;
    return true;
}

thread_start :: (thread: *Thread) -> bool {
    if !thread return false;

    thread.started = true;
    thread.done = true;
    return true;
}

thread_deinit :: (thread: *Thread) {
    if !thread return;

    thread.started = false;
    thread.done = true;
}

thread_destroy :: (thread: *Thread) {
    thread_deinit(thread);
}

thread_is_done :: (thread: *Thread) -> bool {
    return true;
}

init :: (group: *Thread_Group, thread_count: int, proc: Thread_Group_Proc, enable_work_stealing: bool) -> bool {
    if !group return false;

    group.logging = true;
    group.started = false;
    group.shutdown_requested = false;

    i := 0;
    while i < thread_count {
        thread := array_add(*group.threads);
        thread.index = i + 1;
        thread.done = true;
        i += 1;
    }

    return true;
}

start :: (group: *Thread_Group) -> bool {
    if !group return false;
    group.started = true;
    return true;
}

add_work :: (group: *Thread_Group, work: *void, logging_name := "") -> bool {
    if !group return false;
    array_add(*group.completed_work, work);
    return true;
}

get_completed_work :: (group: *Thread_Group) -> [..] *void {
    if !group {
        empty: [..] *void;
        return empty;
    }
    return group.completed_work;
}

shutdown :: (group: *Thread_Group) {
    if !group return;
    group.shutdown_requested = true;
    group.started = false;
}

init :: (mutex: *Mutex, name: string) -> bool {
    return init(mutex, name, 0);
}

init :: (mutex: *Mutex, name: string, order: int) -> bool {
    if !mutex return false;

    mutex.debug_name = name.count;
    mutex.order = order;
    mutex.lock_count = 0;
    mutex.recursion_count = 0;
    mutex.locked = false;
    return true;
}

lock :: (mutex: *Mutex) {
    if !mutex return;

    mutex.locked = true;
    mutex.lock_count += 1;
    mutex.recursion_count += 1;
}

unlock :: (mutex: *Mutex) {
    if !mutex return;

    if mutex.recursion_count > 0 mutex.recursion_count = mutex.recursion_count - 1;
    if mutex.recursion_count == 0 mutex.locked = false;
}
