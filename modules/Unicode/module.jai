#scope_export;

#import "Basic";

Unicode_Result :: enum {
    CONVERSION_OK;
    SOURCE_EXHAUSTED;
    SOURCE_ILLEGAL;
}

character_utf32_to_utf8 :: (codepoint: u32, out: *string) -> Unicode_Result {
    if codepoint <= 0x7f {
        out.data[0] = cast(u8) codepoint;
        out.count = 1;
        return .CONVERSION_OK;
    }
    if codepoint <= 0x7ff {
        out.data[0] = cast(u8) (0xc0 | (codepoint >> 6));
        out.data[1] = cast(u8) (0x80 | (codepoint & 0x3f));
        out.count = 2;
        return .CONVERSION_OK;
    }
    if codepoint >= 0xd800 && codepoint <= 0xdfff return .SOURCE_ILLEGAL;
    if codepoint <= 0xffff {
        out.data[0] = cast(u8) (0xe0 | (codepoint >> 12));
        out.data[1] = cast(u8) (0x80 | ((codepoint >> 6) & 0x3f));
        out.data[2] = cast(u8) (0x80 | (codepoint & 0x3f));
        out.count = 3;
        return .CONVERSION_OK;
    }
    if codepoint <= 0x10ffff {
        out.data[0] = cast(u8) (0xf0 | (codepoint >> 18));
        out.data[1] = cast(u8) (0x80 | ((codepoint >> 12) & 0x3f));
        out.data[2] = cast(u8) (0x80 | ((codepoint >> 6) & 0x3f));
        out.data[3] = cast(u8) (0x80 | (codepoint & 0x3f));
        out.count = 4;
        return .CONVERSION_OK;
    }
    return .SOURCE_ILLEGAL;
}

utf8_next_character :: (text: *string) -> u32, Unicode_Result {
    code, bytes, result := character_utf8_to_utf32(text.data, text.count);
    if result != .CONVERSION_OK return 0, result;
    text.data += bytes;
    text.count -= bytes;
    return code, result;
}

character_utf8_to_utf32 :: (data: *u8, count: int) -> u32, int, Unicode_Result {
    if count <= 0 return 0, 0, .SOURCE_EXHAUSTED;

    b0 := cast(u32) data[0];
    if b0 < 0x80 return b0, 1, .CONVERSION_OK;

    if (b0 & 0xe0) == 0xc0 {
        if count < 2 return 0, 0, .SOURCE_EXHAUSTED;
        b1 := cast(u32) data[1];
        if (b1 & 0xc0) != 0x80 return 0, 0, .SOURCE_ILLEGAL;
        code := ((b0 & 0x1f) << 6) | (b1 & 0x3f);
        if code < 0x80 return 0, 0, .SOURCE_ILLEGAL;
        return code, 2, .CONVERSION_OK;
    }

    if (b0 & 0xf0) == 0xe0 {
        if count < 3 return 0, 0, .SOURCE_EXHAUSTED;
        b1 := cast(u32) data[1];
        b2 := cast(u32) data[2];
        if (b1 & 0xc0) != 0x80 || (b2 & 0xc0) != 0x80 return 0, 0, .SOURCE_ILLEGAL;
        code := ((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f);
        if code < 0x800 return 0, 0, .SOURCE_ILLEGAL;
        if code >= 0xd800 && code <= 0xdfff return 0, 0, .SOURCE_ILLEGAL;
        return code, 3, .CONVERSION_OK;
    }

    if (b0 & 0xf8) == 0xf0 {
        if count < 4 return 0, 0, .SOURCE_EXHAUSTED;
        b1 := cast(u32) data[1];
        b2 := cast(u32) data[2];
        b3 := cast(u32) data[3];
        if (b1 & 0xc0) != 0x80 || (b2 & 0xc0) != 0x80 || (b3 & 0xc0) != 0x80 return 0, 0, .SOURCE_ILLEGAL;
        code := ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
        if code < 0x10000 || code > 0x10ffff return 0, 0, .SOURCE_ILLEGAL;
        return code, 4, .CONVERSION_OK;
    }

    return 0, 0, .SOURCE_ILLEGAL;
}
