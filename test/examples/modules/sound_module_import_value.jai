#import "Basic";
#import "Sound_Player";
#import "Wav_File";

#run {
    player: Sound_Player;
    data: Mixer_Sound_Data;
    data.sampling_rate = 44100;

    stream := make_stream(*player, *data);
    stream.flags |= .REPEATING;
    stream.category = .MUSIC;

    format, samples, ok, extra := get_wav_header("abcd");

    print("sound:% % % % % % % %\n",
        player.streams.count,
        stream != null,
        stream.flags == .REPEATING,
        stream.category == .MUSIC,
        ok,
        format.wFormatTag,
        samples.count,
        extra.wSamplesAccordingToFactChunk);
}

main :: () {}
