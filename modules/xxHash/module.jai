#scope_export;

#import "Basic";

XXH_PRIME32_1 :: cast(u32) 0x9E3779B1;
XXH_PRIME32_2 :: cast(u32) 0x85EBCA77;
XXH_PRIME32_3 :: cast(u32) 0xC2B2AE3D;
XXH_PRIME32_4 :: cast(u32) 0x27D4EB2F;
XXH_PRIME32_5 :: cast(u32) 0x165667B1;

XXH_PRIME64_1 :: cast(u64) 0x9E3779B185EBCA87;
XXH_PRIME64_2 :: cast(u64) 0xC2B2AE3D27D4EB4F;
XXH_PRIME64_3 :: cast(u64) 0x165667B19E3779F9;
XXH_PRIME64_4 :: cast(u64) 0x85EBCA77C2B2AE63;
XXH_PRIME64_5 :: cast(u64) 0x27D4EB2F165667C5;

XXH32_state_t :: struct {
    total_len_32: u32;
    large_len: u32;
    v1: u32;
    v2: u32;
    v3: u32;
    v4: u32;
    mem32: [4] u32;
    memsize: u32;
}

XXH64_state_t :: struct {
    total_len: u64;
    v1: u64;
    v2: u64;
    v3: u64;
    v4: u64;
    mem64: [4] u64;
    memsize: u32;
}

xxh32_rotl :: (x: u32, r: u32) -> u32 {
    return (x << r) | (x >> (32 - r));
}

xxh64_rotl :: (x: u64, r: u64) -> u64 {
    return (x << r) | (x >> (64 - r));
}

xxh32_round :: (acc: u32, input: u32) -> u32 {
    a := acc + input * XXH_PRIME32_2;
    a = xxh32_rotl(a, 13);
    a *= XXH_PRIME32_1;
    return a;
}

xxh64_round :: (acc: u64, input: u64) -> u64 {
    a := acc + input * XXH_PRIME64_2;
    a = xxh64_rotl(a, 31);
    a *= XXH_PRIME64_1;
    return a;
}

xxh64_mergeRound :: (acc: u64, val: u64) -> u64 {
    v := xxh64_round(0, val);
    a := acc ^ v;
    a = a * XXH_PRIME64_1 + XXH_PRIME64_4;
    return a;
}

read_u32_le :: (ptr: *u8) -> u32 {
    return cast(u32) ptr[0]
         | (cast(u32) ptr[1] << 8)
         | (cast(u32) ptr[2] << 16)
         | (cast(u32) ptr[3] << 24);
}

read_u64_le :: (ptr: *u8) -> u64 {
    return cast(u64) ptr[0]
         | (cast(u64) ptr[1] << 8)
         | (cast(u64) ptr[2] << 16)
         | (cast(u64) ptr[3] << 24)
         | (cast(u64) ptr[4] << 32)
         | (cast(u64) ptr[5] << 40)
         | (cast(u64) ptr[6] << 48)
         | (cast(u64) ptr[7] << 56);
}

XXH32_reset :: (state: *XXH32_state_t, seed: u32) {
    state.total_len_32 = 0;
    state.large_len = 0;
    state.v1 = seed + XXH_PRIME32_1 + XXH_PRIME32_2;
    state.v2 = seed + XXH_PRIME32_2;
    state.v3 = seed;
    state.v4 = seed - XXH_PRIME32_1;
    state.memsize = 0;
    for i: 0..3  state.mem32[i] = 0;
}

XXH32_update :: (state: *XXH32_state_t, input_ptr: *u8, len: u32) {
    if len == 0 return;

    state.total_len_32 += len;
    if state.total_len_32 >= 16  state.large_len = 1;

    p := input_ptr;
    remaining := len;

    if state.memsize + remaining < 16 {
        memcpy_bytes(cast(*u8) *state.mem32[0] + cast(int) state.memsize, p, cast(int) remaining);
        state.memsize += remaining;
        return;
    }

    if state.memsize > 0 {
        fill := 16 - state.memsize;
        memcpy_bytes(cast(*u8) *state.mem32[0] + cast(int) state.memsize, p, cast(int) fill);
        mp := cast(*u8) *state.mem32[0];
        state.v1 = xxh32_round(state.v1, read_u32_le(mp));
        state.v2 = xxh32_round(state.v2, read_u32_le(mp + 4));
        state.v3 = xxh32_round(state.v3, read_u32_le(mp + 8));
        state.v4 = xxh32_round(state.v4, read_u32_le(mp + 12));
        p += cast(int) fill;
        remaining -= fill;
        state.memsize = 0;
    }

    while remaining >= 16 {
        state.v1 = xxh32_round(state.v1, read_u32_le(p));
        state.v2 = xxh32_round(state.v2, read_u32_le(p + 4));
        state.v3 = xxh32_round(state.v3, read_u32_le(p + 8));
        state.v4 = xxh32_round(state.v4, read_u32_le(p + 12));
        p += 16;
        remaining -= 16;
    }

    if remaining > 0 {
        memcpy_bytes(cast(*u8) *state.mem32[0], p, cast(int) remaining);
        state.memsize = remaining;
    }
}

XXH32_digest :: (state: *XXH32_state_t) -> u32 {
    h32: u32;
    if state.large_len != 0 {
        h32 = xxh32_rotl(state.v1, 1) + xxh32_rotl(state.v2, 7) + xxh32_rotl(state.v3, 12) + xxh32_rotl(state.v4, 18);
    } else {
        h32 = state.v3 + XXH_PRIME32_5;
    }

    h32 += state.total_len_32;

    p := cast(*u8) *state.mem32[0];
    remaining := state.memsize;

    while remaining >= 4 {
        h32 += read_u32_le(p) * XXH_PRIME32_3;
        h32 = xxh32_rotl(h32, 17) * XXH_PRIME32_4;
        p += 4;
        remaining -= 4;
    }

    while remaining > 0 {
        h32 += cast(u32) p[0] * XXH_PRIME32_5;
        h32 = xxh32_rotl(h32, 11) * XXH_PRIME32_1;
        p += 1;
        remaining -= 1;
    }

    h32 ^= h32 >> 15;
    h32 *= XXH_PRIME32_2;
    h32 ^= h32 >> 13;
    h32 *= XXH_PRIME32_3;
    h32 ^= h32 >> 16;

    return h32;
}

XXH64_reset :: (state: *XXH64_state_t, seed: u64) {
    state.total_len = 0;
    state.v1 = seed + XXH_PRIME64_1 + XXH_PRIME64_2;
    state.v2 = seed + XXH_PRIME64_2;
    state.v3 = seed;
    state.v4 = seed - XXH_PRIME64_1;
    state.memsize = 0;
    for i: 0..3  state.mem64[i] = 0;
}

XXH64_update :: (state: *XXH64_state_t, input_ptr: *u8, len: u32) {
    if len == 0 return;

    state.total_len += cast(u64) len;

    p := input_ptr;
    remaining := cast(u32) len;

    if state.memsize + remaining < 32 {
        memcpy_bytes(cast(*u8) *state.mem64[0] + cast(int) state.memsize, p, cast(int) remaining);
        state.memsize += remaining;
        return;
    }

    if state.memsize > 0 {
        fill := 32 - state.memsize;
        memcpy_bytes(cast(*u8) *state.mem64[0] + cast(int) state.memsize, p, cast(int) fill);
        mp := cast(*u8) *state.mem64[0];
        state.v1 = xxh64_round(state.v1, read_u64_le(mp));
        state.v2 = xxh64_round(state.v2, read_u64_le(mp + 8));
        state.v3 = xxh64_round(state.v3, read_u64_le(mp + 16));
        state.v4 = xxh64_round(state.v4, read_u64_le(mp + 24));
        p += cast(int) fill;
        remaining -= fill;
        state.memsize = 0;
    }

    while remaining >= 32 {
        state.v1 = xxh64_round(state.v1, read_u64_le(p));
        state.v2 = xxh64_round(state.v2, read_u64_le(p + 8));
        state.v3 = xxh64_round(state.v3, read_u64_le(p + 16));
        state.v4 = xxh64_round(state.v4, read_u64_le(p + 24));
        p += 32;
        remaining -= 32;
    }

    if remaining > 0 {
        memcpy_bytes(cast(*u8) *state.mem64[0], p, cast(int) remaining);
        state.memsize = remaining;
    }
}

XXH64_digest :: (state: *XXH64_state_t) -> u64 {
    h64: u64;
    if state.total_len >= 32 {
        h64 = xxh64_rotl(state.v1, 1) + xxh64_rotl(state.v2, 7) + xxh64_rotl(state.v3, 12) + xxh64_rotl(state.v4, 18);
        h64 = xxh64_mergeRound(h64, state.v1);
        h64 = xxh64_mergeRound(h64, state.v2);
        h64 = xxh64_mergeRound(h64, state.v3);
        h64 = xxh64_mergeRound(h64, state.v4);
    } else {
        h64 = state.v3 + XXH_PRIME64_5;
    }

    h64 += state.total_len;

    p := cast(*u8) *state.mem64[0];
    remaining := state.memsize;

    while remaining >= 8 {
        k1 := xxh64_round(0, read_u64_le(p));
        h64 ^= k1;
        h64 = xxh64_rotl(h64, 27) * XXH_PRIME64_1 + XXH_PRIME64_4;
        p += 8;
        remaining -= 8;
    }

    while remaining >= 4 {
        h64 ^= cast(u64) read_u32_le(p) * XXH_PRIME64_1;
        h64 = xxh64_rotl(h64, 23) * XXH_PRIME64_2 + XXH_PRIME64_3;
        p += 4;
        remaining -= 4;
    }

    while remaining > 0 {
        h64 ^= cast(u64) p[0] * XXH_PRIME64_5;
        h64 = xxh64_rotl(h64, 11) * XXH_PRIME64_1;
        p += 1;
        remaining -= 1;
    }

    h64 ^= h64 >> 33;
    h64 *= XXH_PRIME64_2;
    h64 ^= h64 >> 29;
    h64 *= XXH_PRIME64_3;
    h64 ^= h64 >> 32;

    return h64;
}

memcpy_bytes :: (dst: *u8, src: *u8, count: int) {
    for i: 0..count-1 {
        dst[i] = src[i];
    }
}
