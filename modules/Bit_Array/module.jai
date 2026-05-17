#scope_export;

#import "Basic";

Bit_Array :: struct {
    words: [..] u64;
    count: int;
}

init_bit_array :: (bits: *Bit_Array, bit_count: int) {
    bits.count = bit_count;
    array_reset(*bits.words);

    word_count := (bit_count + 63) / 64;
    for i: 0..word_count-1 {
        array_add(*bits.words, cast(u64) 0);
    }
}

set_bit :: (bits: *Bit_Array, index: int) {
    if !bit_index_in_range(bits, index) return;
    word_index := index / 64;
    bit_index := index % 64;
    bits.words[word_index] |= cast(u64) 1 << bit_index;
}

clear_bit :: (bits: *Bit_Array, index: int) {
    if !bit_index_in_range(bits, index) return;
    word_index := index / 64;
    bit_index := index % 64;
    bits.words[word_index] &= ~(cast(u64) 1 << bit_index);
}

toggle_bit :: (bits: *Bit_Array, index: int) {
    if !bit_index_in_range(bits, index) return;
    word_index := index / 64;
    bit_index := index % 64;
    bits.words[word_index] ^= cast(u64) 1 << bit_index;
}

set_bit_to :: (bits: *Bit_Array, index: int, value: bool) {
    if value {
        set_bit(bits, index);
    } else {
        clear_bit(bits, index);
    }
}

get_bit :: (bits: *Bit_Array, index: int) -> bool {
    if !bit_index_in_range(bits, index) return false;
    word_index := index / 64;
    bit_index := index % 64;
    return (bits.words[word_index] & (cast(u64) 1 << bit_index)) != 0;
}

deinit :: (bits: *Bit_Array) {
    array_free(bits.words);
    bits.count = 0;
}

bit_index_in_range :: (bits: *Bit_Array, index: int) -> bool {
    if !bits return false;
    return index >= 0 && index < bits.count;
}
