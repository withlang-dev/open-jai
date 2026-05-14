#scope_export;

#import "Basic";

BASE64_ALPHABET     :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
BASE64URL_ALPHABET  :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

base64_encode :: (input: string) -> string {
    return base64_encode_with_alphabet(input, BASE64_ALPHABET, true);
}

base64url_encode :: (input: string) -> string {
    return base64_encode_with_alphabet(input, BASE64URL_ALPHABET, false);
}

base64_decode :: (text: string) -> string, bool {
    return base64_decode_with_alphabet(text, BASE64_ALPHABET);
}

base64url_decode :: (text: string) -> string, bool {
    return base64_decode_with_alphabet(text, BASE64URL_ALPHABET);
}

base64_encode_with_alphabet :: (input: string, alphabet: string, padding: bool) -> string {
    out: [..] u8;

    i := 0;
    while i < input.count {
        b0 := cast(u32) input[i];
        has1 := i + 1 < input.count;
        has2 := i + 2 < input.count;
        b1 := ifx has1 then cast(u32) input[i + 1] else 0;
        b2 := ifx has2 then cast(u32) input[i + 2] else 0;

        value := (b0 << 16) | (b1 << 8) | b2;
        array_add(*out, alphabet[(value >> 18) & 0x3f]);
        array_add(*out, alphabet[(value >> 12) & 0x3f]);

        if has1 {
            array_add(*out, alphabet[(value >> 6) & 0x3f]);
        } else if padding {
            array_add(*out, #char "=");
        }

        if has2 {
            array_add(*out, alphabet[value & 0x3f]);
        } else if padding {
            array_add(*out, #char "=");
        }

        i += 3;
    }

    return to_string(out.data, out.count);
}

base64_decode_with_alphabet :: (text: string, alphabet: string) -> string, bool {
    padded_count := text.count;
    remainder := padded_count % 4;
    if remainder == 1 return "", false;
    if remainder != 0 padded_count += 4 - remainder;

    out: [..] u8;
    i := 0;
    while i < padded_count {
        c0 := ifx i + 0 < text.count then text[i + 0] else #char "=";
        c1 := ifx i + 1 < text.count then text[i + 1] else #char "=";
        c2 := ifx i + 2 < text.count then text[i + 2] else #char "=";
        c3 := ifx i + 3 < text.count then text[i + 3] else #char "=";

        if c0 == #char "=" || c1 == #char "=" return "", false;
        pad2 := c2 == #char "=";
        pad3 := c3 == #char "=";

        v0, ok0 := base64_index_of(c0, alphabet);
        v1, ok1 := base64_index_of(c1, alphabet);
        v2: int;
        ok2: bool;
        if pad2 {
            v2 = 0;
            ok2 = true;
        } else {
            v2, ok2 = base64_index_of(c2, alphabet);
        }
        v3: int;
        ok3: bool;
        if pad3 {
            v3 = 0;
            ok3 = true;
        } else {
            v3, ok3 = base64_index_of(c3, alphabet);
        }
        if !ok0 || !ok1 || !ok2 || !ok3 return "", false;
        if pad2 && !pad3 return "", false;

        value := (cast(u32) v0 << 18) | (cast(u32) v1 << 12) | (cast(u32) v2 << 6) | cast(u32) v3;
        array_add(*out, cast(u8) ((value >> 16) & 0xff));
        if !pad2 array_add(*out, cast(u8) ((value >> 8) & 0xff));
        if !pad3 array_add(*out, cast(u8) (value & 0xff));

        i += 4;
    }

    return to_string(out.data, out.count), true;
}

base64_index_of :: (c: u8, alphabet: string) -> int, bool {
    for ch: alphabet {
        if ch == c return it_index, true;
    }
    return 0, false;
}
