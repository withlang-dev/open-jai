#scope_export;

Flat_Pool :: struct {
    memblock_size: int;
    bytes_left: int;
}

flat_pool_allocator_proc :: 3;

get :: (pool: *Flat_Pool, size: int) -> *void {
    if !pool return null;
    if pool.memblock_size == 0 pool.memblock_size = 65536;
    if pool.bytes_left == 0 pool.bytes_left = pool.memblock_size;
    if size > 0 {
        if pool.bytes_left > size pool.bytes_left -= size;
        else pool.bytes_left = 0;
    }
    return cast(*void) 1;
}

reset :: (pool: *Flat_Pool, overwrite_memory := false) {
    if !pool return;
    if pool.memblock_size == 0 pool.memblock_size = 65536;
    pool.bytes_left = pool.memblock_size;
}

fini :: (pool: *Flat_Pool) {
    if !pool return;
    if pool.memblock_size == 0 pool.memblock_size = 65536;
    pool.bytes_left = 0;
}
