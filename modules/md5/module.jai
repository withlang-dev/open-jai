#scope_export;

#import "Basic";

md5 :: (input: string) -> string {
    S :: u32.[
        7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
        5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
        4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
        6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
    ];

    K :: u32.[
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    ];

    a0: u32 = 0x67452301;
    b0: u32 = 0xefcdab89;
    c0: u32 = 0x98badcfe;
    d0: u32 = 0x10325476;

    orig_len_bits: u64 = cast(u64) input.count * 8;

    pad_len := 64 - ((input.count + 9) % 64);
    if pad_len == 64  pad_len = 0;
    total := input.count + 1 + pad_len + 8;

    buf: [256] u8;
    for i: 0..input.count-1  buf[i] = input.data[i];
    buf[input.count] = 0x80;
    for i: 0..pad_len-1  buf[input.count + 1 + i] = 0;
    for i: 0..7  buf[total - 8 + i] = cast(u8) ((orig_len_bits >> cast(u64) (i * 8)) & 0xFF);

    offset := 0;
    while offset < total {
        M: [16] u32;
        for j: 0..15 {
            idx := offset + j * 4;
            M[j] = cast(u32) buf[idx]
                 | (cast(u32) buf[idx+1] << 8)
                 | (cast(u32) buf[idx+2] << 16)
                 | (cast(u32) buf[idx+3] << 24);
        }

        A := a0;
        B := b0;
        C := c0;
        D := d0;

        for i: 0..63 {
            F: u32;
            g: int;
            if i < 16 {
                F = (B & C) | ((~B) & D);
                g = i;
            } else if i < 32 {
                F = (D & B) | ((~D) & C);
                g = (5 * i + 1) % 16;
            } else if i < 48 {
                F = B ^ C ^ D;
                g = (3 * i + 5) % 16;
            } else {
                F = C ^ (B | (~D));
                g = (7 * i) % 16;
            }
            F = F + A + K[i] + M[g];
            A = D;
            D = C;
            C = B;
            B = B + left_rotate32(F, S[i]);
        }

        a0 += A;
        b0 += B;
        c0 += C;
        d0 += D;
        offset += 64;
    }

    digest: [16] u8;
    for i: 0..3 {
        digest[i]      = cast(u8) ((a0 >> cast(u32) (i*8)) & 0xFF);
        digest[4 + i]  = cast(u8) ((b0 >> cast(u32) (i*8)) & 0xFF);
        digest[8 + i]  = cast(u8) ((c0 >> cast(u32) (i*8)) & 0xFF);
        digest[12 + i] = cast(u8) ((d0 >> cast(u32) (i*8)) & 0xFF);
    }

    hex_chars :: "0123456789abcdef";
    result: [32] u8;
    for i: 0..15 {
        result[i*2]     = hex_chars[cast(int) (digest[i] >> 4)];
        result[i*2 + 1] = hex_chars[cast(int) (digest[i] & 0x0F)];
    }

    out: string;
    out.data = result.data;
    out.count = 32;
    return out;
}

left_rotate32 :: (x: u32, c: u32) -> u32 {
    return (x << c) | (x >> (32 - c));
}
