#scope_export;

Pool :: struct {
    memblock_size: int;
    bytes_left: int;
    current_block: *void;
    current_pos: int;
}

pool_allocator_proc :: 2;

set_allocators :: (pool: *Pool) {
    if !pool return;
    pool.memblock_size = 65536;
    pool.bytes_left = 0;
}

get :: (pool: *Pool, size: int) -> *void #intrinsic;

reset :: (pool: *Pool) #intrinsic;

release :: (pool: *Pool) #intrinsic;
