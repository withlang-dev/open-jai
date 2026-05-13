#scope_export;

Pool :: struct {
    memblock_size: int;
    bytes_left: int;
}

pool_allocator_proc :: 2;

set_allocators :: (pool: *Pool) {
    if !pool return;
    pool.memblock_size = 65536;
    pool.bytes_left = 0;
}

get :: (pool: *Pool, size: int) -> *void {
    if !pool return null;
    if pool.memblock_size == 0 pool.memblock_size = 65536;
    if pool.bytes_left == 0 pool.bytes_left = pool.memblock_size;
    if size > 0 {
        if pool.bytes_left > size pool.bytes_left -= size;
        else pool.bytes_left = 0;
    }
    return cast(*void) 1;
}

reset :: (pool: *Pool) {
    if !pool return;
    if pool.memblock_size == 0 pool.memblock_size = 65536;
    pool.bytes_left = pool.memblock_size;
}

release :: (pool: *Pool) {
    if !pool return;
    if pool.memblock_size == 0 pool.memblock_size = 65536;
    pool.bytes_left = 0;
}
