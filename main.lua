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
    ["snapshot_width"] = 240,           -- Width of snapshot (in pixels).  -1 for default (240).
    ["snapshot_height"] = 160,          -- Height of snapshot (in pixels). -1 for default (160).
    
    -- If true, snapshot will be taken at the time position you pressed the key on, instead
    -- of the subtitle start time position. Default is false.
    ["snapshot_on_keypress"] = false,

    -- If true, a snapshot will be taken when clipping audio when using the Quick Export.
    -- These snapshots are stored in a seperate directory set by the "snapshot_export_path"
    -- config option. Default is true.
    ["snapshot_on_quick_export"] = true,

    -- If true, a snapshot will be taken when using the A-B loop export.
    -- These snapshots are stored in a seperate directory set by the "snapshot_export_path"
    -- config option. Default is true.
    ["snapshot_on_ab_loop_export"] = true,
    
    -----------
    -- Audio --
    -----------
 
    -- The bitrate of extracted audio. Default is 96000.
    ["audio_bitrate"]   = 96000,

    -- The amount of padding to add to the beginning of exported audio.
    -- This padding is only applied when exporting subtitles, not when clipping audio using
    -- quick export or A-B loop export. Default is 0.60
    ["audio_pad_start"] = 0.60,

    -- The amount of padding to add to the end of exported audio.
    -- This padding is only applied when exporting subtitles, not when clipping audio using
    -- quick export or A-B loop export. Default is 0.60
    ["audio_pad_end"]   = 0.60,

    -- How far to look back (in seconds) when quick exporting audio. Default is 7.
    ["audio_lookback_length"] = 7,
    
    ----------------
    -- File Paths --
    ----------------
    -- Where extracted files are dumped (directories and files must already exist!).

    -- A path to a file that CSV-formatted subtitles are written (for use with Anki).
    -- Default is "exported_cards.txt" within this addons directory.
    ["card_export_path"]                = join_path(mp.get_script_directory(), "exported_cards.txt"),
    
    -- A path to a file that CSV-formatted data is written (for use with Anki).
    -- This is for when you want to extract the span of a subtitle without the subtitle text.
    -- Useful for when the subtitles are not in your target language but other subtitles match
    -- the timing of the audio well enough.
    -- Default is "exported_cards_no_subtitles.txt" within this addons directory.
    ["card_export_path_no_subtitles"]   = join_path(mp.get_script_directory(), "exported_cards_no_subtitles.txt"),

    -- A path to a folder where audio/images are placed for exported cards.
    -- Default is "collection.media" for easy merging with Anki directories.
    ["card_media_path"]                 = join_path(mp.get_script_directory(), "collection.media"),

    -- A path to a folder where audio is placed from the Quick Export or A-B Loop export.
    -- Default is "audio_clips" within this addons directory.
    ["audio_export_path"]               = join_path(mp.get_script_directory(), "audio_clips"),

    -- A path to a folder where snapshots are placed from the Quick Export or A-B loop export.
    -- Default is "snapshots" within this addons directory.
    ["snapshot_export_path"]            = join_path(mp.get_script_directory(), "snapshots"),
};

-----------------------
-- Utility Functions --
-----------------------
local function trim_whitespace(str)
    return string.match(str, "^%s*(.-)%s*$");
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

local function sanitize_title(str)
    return string.gsub(trim_whitespace(str:gsub("%b()", ""):gsub("%b[]", "")), "%s+", "_");
end

local function get_title()
    return sanitize_title(strip_extension(mp.get_property("filename/no-ext")));
end

local function format_filename(format, ...)
    local args = {...};
    local filename = string.format(format, get_title(), unpack(args));
    return string.gsub(filename, "[/\\|<>?:\"*]", "");
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

local function calc_padded_time_pos(time_start, time_end)
    time_start = time_start - config["audio_pad_start"] or 0;
    time_end = time_end + config["audio_pad_end"] or 0;
    return time_start, time_end;
end

---------------
-- Exporting --
---------------
local function export_card(no_subs)
    local sub_text, sub_start, sub_end = get_active_sub();
    if(not sub_text) then
        return false, sub_start;
    end
    
    local time_pos = sub_start;
    if(config["snapshot_on_keypress"]) then
        time_pos = mp.get_property_number("time-pos");
    end
    
    local filename = format_filename("%s_%s", time_pos);
    local success, err = encode_png(
        join_path(config["card_media_path"], filename),
        time_pos,
        config["snapshot_width"] > 0 and config["snapshot_width"] or 240,
        config["snapshot_height"] > 0 and config["snapshot_height"] or 160
    );

    if(not success) then
        return false, err;
    end
    
    sub_start, sub_end = calc_padded_time_pos(sub_start, sub_end);
    success, err = encode_mp3(
        join_path(config["card_media_path"], filename),
        sub_start,
        sub_end
    );

    if(not success) then
        return false, err;
    end
    
    local export_path = config["card_export_path"];
    if(no_subs) then
        export_path = config["card_export_path_no_subtitles"];
    end

    local handle = io.open(export_path, "a");
    if(not handle) then
        return false, string.format("Missing path '%s'!", config["card_export_path"] or "exported_cards.txt");
    end

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

    return true;
end

local function quick_export()
    local time_pos = mp.get_property_number("time-pos");
    local lookback_pos = time_pos - config["audio_lookback_length"];
    if(lookback_pos < 0) then
        lookback_pos = 0;
    end

    local filename = format_filename("%s_%s_%s", format_time(lookback_pos), format_time(time_pos));
    local success, err = encode_mp3(
        join_path(config["audio_export_path"], filename),
        lookback_pos,
        time_pos
    );

    if(not success) then
        return false, err;
    end
    
    -- Take a snapshot if it's enabled
    if(config["snapshot_on_quick_export"]) then
        success, err = encode_png(
            join_path(config["snapshot_export_path"], filename),
            config["snapshot_on_keypress"] and time_pos or lookback_pos,
            config["snapshot_width"] > 0 and config["snapshot_width"] or 240,
            config["snapshot_height"] > 0 and config["snapshot_height"] or 160
        );

        if(not success) then
            return false, err;
        end
    end

    return true;
end

local function ab_loop_export()
    local a_point = mp.get_property("ab-loop-a");
    if("no" == a_point) then
        return false, "No A-B loop selected";
    end
    
    local b_point = mp.get_property("ab-loop-b");
    if("no" == b_point) then
        return false, "No B point selected";
    end

    if(b_point <= a_point) then
        return false, "Invalid A-B loop timing. B must come after A.";
    end

    if(b_point-a_point < 1) then
        return false, "A-B loop must be 1 second or longer.";
    end

    local filename = format_filename("%s_%s_%s", format_time(a_point), format_time(b_point));
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
            join_path(config["snapshot_export_path"], filename),
            config["snapshot_on_keypress"] and mp.get_property_number("time-pos") or  a_point,
            config["snapshot_width"] > 0 and config["snapshot_width"] or 240,
            config["snapshot_height"] > 0 and config["snapshot_height"] or 160
        );

        if(not success) then
            return false, err;
        end
    end

    return true;
end

--------------
-- BINDINGS --
--------------
-- These the default key binds. Don't change them here, use your mpv config instead.
-- If the value of any of these are set to -1, they are ignored and not registered as key binds.
local keybinds = {
    ["suketto_export_subtitle"]             = "b", -- Default key to extract a subtitle and its audio.
    ["suketto_export_subtitle_media_only"]  = "B", -- Extract audio and snapshot with CSV format but without the subtitle text.

    ["suketto_audio_export_selection"]      = "n", -- Export the current AB loop
    ["suketto_quick_export_audio"]          = "N", -- Default key to quick clip audio.
};

local keybind_funcs = {
    ["suketto_export_subtitle"] = function()
        local success, err = export_card();
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
            return;
        end
        mp.commandv("show-text", "Card Exported", 1000);
    end,

    ["suketto_export_subtitle_media_only"] = function()
        local success, err = export_card(true);
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
            return;
        end
        mp.commandv("show-text", "Card Exported (media only)", 1000);
    end,

    ["suketto_audio_export_selection"] = function()
        local success, err = ab_loop_export();
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
            return;
        end
        mp.commandv("show-text", "AB loop audio exported", 1000);
    end,

    ["suketto_quick_export_audio"] = function()
        local success, err = quick_export();
        if(not success) then
            mp.commandv("show-text", err, 1000);
            print(err);
            return;
        end
        mp.commandv("show-text", "Audio Exported (quick)", 1000);
    end,
};

for k,v in pairs(keybinds) do
    if(-1 ~= v) then
        mp.add_key_binding(v, k, keybind_funcs[k]);
    end
end
