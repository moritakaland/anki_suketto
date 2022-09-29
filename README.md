This script is targetted towards language learning.

By using the default export key (b), the current subtitle will be extracted to a CSV formatted file (default: exportedcards.txt) to be imported into Anki. Along with that, an image and audio spanning the length of the subtitle will be dumped into collection.media.

## Features
* Exporting of subtitles, images and audio to a Anki-supported formats (default key: b).
* Exporting images and audio spanning the length of a subtitle. This is useful for when you don't have subtitles for your target language, but have other language subtitles that match the timing well enough. CSV data will be exported to a seperate text file. (default key: Shift+b)
* Exporting audio and images spanning the built in A-B Loop feature of MPV. Images can be disabled in configuration. (default key: n)
* Quickly export the last *x* seconds (default: 7) of audio along with an image. Images can be disabled in configuration. (default key: Shift+n)

## Configuration
To configure the behaviour, look at the config table within main.lua.
