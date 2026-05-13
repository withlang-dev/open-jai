#import "Basic";

#scope_export;

Sound_Data_Type :: enum {
    LINEAR_SAMPLE_ARRAY;
    ADPCM_COMPRESSED;
    OGG_COMPRESSED;
}

Sound_Stream_Flags :: enum_flags {
    REPEATING;
}

Sound_Category :: enum {
    SOUND_EFFECT;
    MUSIC;
}

Mixer_Sound_Data :: struct {
    name: string;
    full_path: string;
    buffer: string;
    type: Sound_Data_Type;
    nchannels: u16;
    nsamples_times_nchannels: int;
    wSamplesPerBlock: int;
    nBlockAlign: int;
    samples: *s16;
    sampling_rate: u32;
}

Sound_Stream :: struct {
    sound_data: *Mixer_Sound_Data;
    user_volume_scale: float64 = 1.0;
    desired_rate: float64 = 1.0;
    repeat_end_position: int;
    flags: Sound_Stream_Flags;
    category: Sound_Category;
    marked: bool;
}

Sound_Player :: struct {
    update_history: bool;
    streams: [..] Sound_Stream;
}

init_sound_player :: (player: *Sound_Player, window: s64 = 0, open_audio := true, start_audio_thread := true) -> bool {
    return init(player, window, open_audio, start_audio_thread);
}

init :: (player: *Sound_Player, window: s64, open_audio := true, start_audio_thread := true) -> bool {
    if !player return false;
    return true;
}

make_stream :: (player: *Sound_Player, data: *Mixer_Sound_Data) -> *Sound_Stream {
    if !player return null;

    stream := array_add(*player.streams);
    stream.sound_data = data;
    stream.user_volume_scale = 1.0;
    stream.desired_rate = 1.0;
    stream.repeat_end_position = 0;
    stream.flags = 0;
    stream.category = .SOUND_EFFECT;
    stream.marked = false;
    return stream;
}

play_sound :: (player: *Sound_Player, data: *Mixer_Sound_Data) -> *Sound_Stream {
    return make_stream(player, data);
}

pre_entity_update :: (player: *Sound_Player) {
    if !player return;

    for player.streams {
        it.marked = false;
    }
}

post_entity_update :: (player: *Sound_Player, dt: float) {
    if !player return;
}
