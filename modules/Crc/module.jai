#scope_export;

#import "Basic";

CRC64_ECMA_POLY :: 0x42F0E1EBA9EA3693;

crc64 :: (value: string) -> u64 {
    crc: u64 = 0;
    for i: 0..value.count-1 {
        crc = crc ^ (cast(u64) value[i] << 56);
        for bit: 0..7 {
            if (crc & 0x8000000000000000) != 0 {
                crc = (crc << 1) ^ CRC64_ECMA_POLY;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}
