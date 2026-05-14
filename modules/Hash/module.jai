#scope_export;

#import "Basic";

sdbm_hash :: (data: *u8, count: int) -> u32 {
    hash: u32 = 0;
    for i: 0..count-1 {
        c := cast(u32) data[i];
        hash = c + (hash << 6) + (hash << 16) - hash;
    }
    return hash;
}

fnv1a_hash :: (data: *u8, count: int) -> u32 {
    hash: u32 = 2166136261;
    for i: 0..count-1 {
        hash = hash ^ cast(u32) data[i];
        hash *= 16777619;
    }
    return hash;
}

get_hash :: (value: string) -> u32 {
    return fnv1a_hash(value.data, value.count);
}
