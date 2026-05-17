#scope_export;

Flat_Pool :: struct {
    memblock_size: int;
    bytes_left: int;
    current_block: *void;
    current_pos: int;
    alignment: int = 8;
}

flat_pool_allocator_proc :: 3;

get :: (pool: *Flat_Pool, size: int) -> *void #intrinsic;

reset :: (pool: *Flat_Pool, overwrite_memory := false) #intrinsic;

fini :: (pool: *Flat_Pool) #intrinsic;
