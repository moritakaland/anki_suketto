local mp = mp;
local io = io;
local string = string;

local path_separator = os.getenv("HOME") ~= nil and '/' or '\\';
local function join_path(p1, p2)
    p1 = string.gsub(p1, "$"..path_separator, "");
    p2 = string.gsub(p2, "$"..path_separator, "");
    return p1..path_separator..p2;
end

-------------------
-- CONFIGURATION --
-------------------
local config = {
    ---------------
    -- Snapshots --
    ---------------
    ["snapshot_width"] = 160,           -- Width of snapshot.  -1 for default (160).
    ["snapshot_height"] = 160,          -- Height of snapshot. -1 for default (160).
    
    -- If true, the snapshot will be taken at the subtitle start time pos.
    -- If false, the snapshot will be taken at whatever time pos you pressed the key on.
    -- Only applies to extracting subtitles.
    ["snapshot_on_subtitle_start"] = false,
    
    -- Take snapshots when exporting audio with the quick export or ab loop export.
    -- The snapshots for these are not placed in the card_media_path but in a seperate one for audio clips.
    -- Check the "File Paths" section below for more info.
    ["snapshot_on_quick_audio_export"] = true,
    ["snapshot_on_ab_loop_export"] = true,
    
    -----------
    -- Audio --
    -----------
    ["audio_bitrate"]   = 96000,        -- Bitrate of extracted audio

    -- These two options add padding to the start or the end of extracted audio.
    -- This padding is only applied when extracting a subtitle, not when only clipping audio.
    ["audio_pad_start"] = 0.60,
    ["audio_pad_end"]   = 0.60,
    ["audio_lookback_length"] = 7,      -- How far back to look back (in seconds) when using the quick export.
    
    ----------------
    -- File Paths --
    ----------------
    -- Where extracted files are dumped (directories must already exist!).

    -- card_export_path:            Where the CSV formatted subtitles are placed (Anki formatted cards).
    --                              This is a single text file.
    ["card_export_path"]            = join_path(mp.get_script_directory(), "exported_cards.txt"),
    
    -- card_export_path_no_sub:     Where the CSV formatted cards are placed without the subtitle text.
    --                              This is useful for when you don't have subtitles for your target language
    --                              but the subtitle timing of English (or other) subtitles still match well.
    ["card_export_path_no_subs"]     = join_path(mp.get_script_directory(), "exported_cards_no_subs.txt"),

    -- card_media_path:             Where the audio and images from exported subtitles are placed.
    --                              Named "collection.media" by default since this is mainly for Anki cards.
    ["card_media_path"]             = join_path(mp.get_script_directory(), "collection.media"),

    -- audio_export_path:           Where audio from ab loop or quick exports are placed.
    ["audio_export_path"]           = join_path(mp.get_script_directory(), "audio_clips"),

    -- audio_export_snapshot_path:  If snapshots for quick exports or ab loops are enabled, they will be
    --                              placed in this directory. These are kept seperate from card exports.
    ["audio_export_snapshot_path"]  = join_path(mp.get_script_directory(), "audio_clip_snapshots"),

};

--------------
-- Keybinds --
--------------
-- These are only the DEFAULTS of the key binds.
-- They can be changed within your own config using the key names.
-- If the value of any of these are set to -1, they are ignored and not registered as key binds.
config.keybinds = {
    ["suketto_export_subtitle"]             = "b", -- Default key to extract a subtitle and it's audio.
    ["suketto_export_subtitle_media_only"]  = "B", -- Extract audio and snapshot with CSV format but without the subtitle text.

    ["suketto_audio_export_selection"]      = "n", -- Export the current AB loop
    ["suketto_quick_export_audio"]          = "N", -- Default key to quick clip audio.
};
 
local function trim_whitespace(str)
    return string.match(str, "^%s*(.-)%s*$");
end

local function sanitize_title(str)
    return string.gsub(trim_whitespace(str:gsub("%b()", ""):gsub("%b[]", "")), "%s+", "_");
end

local function strip_extension(path)
    local i = path:match(".+()%.%w+$");
    if(i) then
        return path:sub(1, i-1);
    end
    return path;
end

local function format_time(time)
    local timestamp = time or mp.get_property_number("time-pos");
    return string.format("%02d_%02d_%02d_%03d",
        timestamp/3600,
        timestamp/60%60,
        timestamp%60,
        timestamp*1000%1000
    );
end

local function get_title()
    return sanitize_title(strip_extension(mp.get_property("filename/no-ext")));
end

local function get_active_sub()
    local sub_text = mp.get_property("sub-text");
    local sub_start, sub_end = mp.get_property_number("sub-start"), mp.get_property_number("sub-end");

    if(not sub_text or sub_text == "") then
        return false, "No active subtitle.";
    end

    sub_text = trim_whitespace(sub_text);
    sub_text = string.gsub(sub_text, "\n", "");

    if(nil == sub_start or nil == sub_end) then
        return false, "Invalid subtitle timing.";
    end

    if(0 > sub_start or sub_end <= sub_start) then
        return false, "Invalid subtitle timing.";
    end
    
    -- Compensate for mpv subtitle delays
    local sub_delay = mp.get_property_number("sub-delay");
    if(sub_delay) then
        sub_start = sub_start + sub_delay;
        sub_end = sub_end + sub_delay;

        if(sub_start < 0) then
            sub_start = 0;
        end

        if(sub_end < 0) then
            sub_end = 0;
        end
    end

    return sub_text, sub_start, sub_end;
end

local function encode_mp3(path, pos_start, pos_end)
    local result, err = mp.command_native({
        name = "subprocess",
        args = {
            "mpv", mp.get_property("path"),
            "--start="..pos_start,
            "--end="..pos_end,
            "--aid="..mp.get_property("aid"),
            "--vid=no",
            "--loop-file=no",
            "--oac=libmp3lame",
            "--oacopts=b="..config["audio_bitrate"] or "96000",
            "--oset-metadata=title="..get_title(),
            "-o="..path..".mp3"
        },
        capture_stdout = true,
        capture_stderr = true
    });

    if(err) then
        return false, "mp3 encoding failed: "..err;
    end

    return path;
end

local function encode_png(path, pos_start, width, height)
    local result, err = mp.command_native({
        name = "subprocess",
        args = {
            "mpv", mp.get_property("path"),
            "--start="..pos_start,
            "--frames=1",
            "--no-audio",
            "--no-sub",
            "--loop-file=no",
            "--vf-add=scale="..width..":"..height,
            "-o="..path..".png"
        },
        capture_stdout = true,
        capture_stderr = true
    });

    if(err) then
        return false, "png encoding failed: "..err;
    end

    return path;
end

local function export_card(no_subs)
    -- Get active subtitle to extract
    local sub_text, sub_start, sub_end = get_active_sub();
    if(not sub_text) then
        return false, sub_start;
    end
    
    local time_pos = config["snapshot_on_subtitle_start"] and sub_start or mp.get_property_number("time-pos");
    local filename = string.format("%s_%s", get_title(), format_time(time_pos));
    filename:gsub("[/\\|<>?:\"*]", "");
    
    -- Export PNG file
    local success, err = encode_png(
        join_path(config["card_media_path"], filename),
        time_pos,
        config["snapshot_width"] > 0 and config["snapshot_width"] or 160,
        config["snapshot_height"] > 0 and config["snapshot_height"] or 160
    );

    if(not success) then
        return false, err;
    end
    
    -- Export MP3 file
    sub_start = sub_start + config["audio_pad_start"] or 0;
    sub_end = sub_end + config["audio_pad_end"] or 0;
    success, err = encode_mp3(
        join_path(config["card_media_path"], filename),
        sub_start,
        sub_end
    );

    if(not success) then
        return false, err;
    end
    
    -- Export card
    local handle = io.open(no_subs and config["card_export_path_no_subs"] or config["card_export_path"], "a");
    if(handle) then
        if(no_subs) then

            handle:write(string.format("<img src=\'%s\'>;[sound:%s]\n",
                filename..".png",
                filename..".mp3"
            ));

        else

            handle:write(string.format("%s;<img src=\'%s\'>;[sound:%s]\n",
                sub_text,
                filename..".png",
                filename..".mp3"
            ));

        end
        handle:close();
    else
        return false, string.format("Missing path '%s'!", config["card_export_path"] or "exported_cards.txt");
    end
    return true;
end

local function quick_extract_audio()
    local time_pos = mp.get_property_number("time-pos");
    local lookback_pos = time_pos - config["audio_lookback_length"];
    if(lookback_pos < 0) then
        lookback_pos = 0;
    end

    local filename = string.format("%s_%s_%s", get_title(), format_time(lookback_pos), format_time(time_pos));
    local success, err = encode_mp3(
        join_path(config["audio_export_path"], filename),
        lookback_pos,
        time_pos
    );

    if(not success) then
        return false, err;
    end
    
    -- Take a snapshot if it's enabled
    if(config["snapshot_on_quick_audio_export"]) then
        success, err = encode_png(
            join_path(config["audio_export_snapshot_path"], filename),
            lookback_pos,
            config["snapshot_width"] > 0 and config["snapshot_width"] or 160,
            config["snapshot_height"] > 0 and config["snapshot_height"] or 160
        );

        if(not success) then
            return false, err;
        end
    end

    return true;
end

-- TODO: snapshot timing on keypress for ab loops
local function audio_export_ab_loop()
    local a_point = mp.get_property("ab-loop-a");
    if("no" == a_point) then
        return false, "No A-B loop selected";
    end
    
    local b_point = mp.get_property("ab-loop-b");
    if("no" == b_point) then
        return false, "No B point selected";
    end

    a_point, b_point = mp.get_property_number("ab-loop-a"), mp.get_property_number("ab-loop-b");
    if(b_point <= a_point) then
        -- mpv is actually smart about this. I am too lazy to be smart.
        return false, "Invalid A-B loop timing. B must come after A.";
    end

    if(b_point-a_point < 1) then
        return false, "A-B loop must be 1 second or longer.";
    end

    local filename = string.format("%s_%s_%s", get_title(), format_time(a_point), format_time(b_point));
    local success, err = encode_mp3(
        join_path(config["audio_export_path"], filename),
        a_point,
        b_point
    );

    if(not success) then
        return false, err;
    end

    -- Take a snapshot if it's enabled
    if(config["snapshot_on_ab_loop_export"]) then
        success, err = encode_png(
            join_path(config["audio_export_snapshot_path"], filename),
            a_point,
            config["snapshot_width"] > 0 and config["snapshot_width"] or 160,
            config["snapshot_height"] > 0 and config["snapshot_height"] or 160
        );

        if(not success) then
            return false, err;
        end
    end

    return true;
end

---------------
-- BINDINGS --
---------------
local keybind_funcs = {
    ["suketto_export_subtitle"] = function()
        local success, err = export_card();
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
        else
            mp.commandv("show-text", "Card Exported", 1000);
        end
    end,

    ["suketto_export_subtitle_media_only"] = function()
        local success, err = export_card(true);
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
        else
            mp.commandv("show-text", "Card Exported (media only)", 1000);
        end
    end,

    ["suketto_audio_export_selection"] = function()
        local success, err = audio_export_ab_loop();
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
        else
            mp.commandv("show-text", "AB loop audio exported", 1000);
        end
    end,

    ["suketto_quick_export_audio"] = function()
        local success, err = quick_extract_audio();
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
        else
            mp.commandv("show-text", "Audio Exported (quick)", 1000);
        end
    end,
};

for k,v in pairs(config["keybinds"]) do
    if(-1 ~= v) then
        mp.add_key_binding(v, k, keybind_funcs[k]);
    end
end
