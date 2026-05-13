#import "Basic";
#import "Thread";

thread_entry :: (thread: *Thread) -> s64 {
    return thread.index;
}

group_entry :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    return .CONTINUE;
}

#run {
    thread: Thread;
    thread_ok := thread_init(*thread, thread_entry);
    started := thread_start(*thread);
    done := thread_is_done(*thread);
    thread_deinit(*thread);

    group: Thread_Group;
    group_ok := init(*group, 3, group_entry, true);
    start(*group);
    add_work(*group, cast(*void) 10);
    add_work(*group, cast(*void) 20);
    completed := get_completed_work(*group);
    shutdown(*group);

    mutex: Mutex;
    mutex_ok := init(*mutex, "Critical", 7);
    lock(*mutex);
    locked := mutex.locked;
    lock_count := mutex.lock_count;
    unlock(*mutex);

    print(
        "thread:% % % % % % % % % % % %\n",
        thread_ok,
        started,
        done,
        thread.done,
        group_ok,
        group.threads.count,
        completed.count,
        group.shutdown_requested,
        mutex_ok,
        mutex.order,
        locked,
        lock_count
    );
}

main :: () {}
