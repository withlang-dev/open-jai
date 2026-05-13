#scope_export;

WAVE_FORMAT_PCM :: 1;
WAVE_FORMAT_DVI_ADPCM :: 17;

Wav_Format :: struct {
    wFormatTag: int;
    nChannels: int;
    nBlockAlign: int;
    nSamplesPerSec: int;
}

Wav_Extra :: struct {
    wSamplesPerBlock: int;
    wSamplesAccordingToFactChunk: int;
}

Wav_File :: struct {
    format: Wav_Format;
    samples: string;
    extra: Wav_Extra;
    success: bool;
}

load_wav_file :: (buffer: string) -> Wav_File {
    result: Wav_File;
    result.format, result.samples, result.success, result.extra = get_wav_header(buffer);
    return result;
}

get_wav_header :: (buffer: string) -> Wav_Format, string, bool, Wav_Extra {
    format: Wav_Format;
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 2;
    format.nBlockAlign = 4;
    format.nSamplesPerSec = 44100;

    extra: Wav_Extra;
    extra.wSamplesPerBlock = 0;
    extra.wSamplesAccordingToFactChunk = buffer.count / 2;

    return format, buffer, true, extra;
}
