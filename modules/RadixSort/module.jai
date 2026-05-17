#scope_export;

#import "Basic";

MAX_RADIX_COUNT :: 65536;

RadixSort :: struct {
    ranks: [MAX_RADIX_COUNT] u32;
    count: u32;
}

sort :: (r: *RadixSort, data: *u32, count: u32) {
    r.count = count;
    for i: 0..cast(int)count-1 {
        r.ranks[i] = cast(u32) i;
    }
    for i: 1..cast(int)count-1 {
        key := r.ranks[i];
        key_val := data[key];
        j := i - 1;
        while j >= 0 && data[r.ranks[j]] > key_val {
            r.ranks[j + 1] = r.ranks[j];
            j -= 1;
        }
        r.ranks[j + 1] = key;
    }
}

rank :: (r: *RadixSort, index: u32) -> u32 {
    return r.ranks[index];
}

free_resources :: (r: *RadixSort) {
}
