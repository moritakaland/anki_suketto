This script is targetted towards language learning.

By using the default export key (b), the current subtitle (along with an audio clip and snapshot) will be extracted to a CSV formatted file (default: exported_cards.txt) to be imported into Anki.

## Features
* Exporting of subtitles, images and audio to a Anki-supported formats (default key: b).
* Exporting images and audio spanning the length of a subtitle. Useful for when the subtitles are not in your target language but the other subtitles match the timing of the audio well enough. CSV data will be exported to a seperate text file. (default key: Shift+b)
* Exporting audio and images spanning the built in A-B Loop feature of MPV. Images can be disabled in configuration. (default key: n)
* Quickly export the last *n* seconds (default: 7) of audio along with an image. Images can be disabled in configuration. (default key: Shift+n)

## Configuration
To configure the behaviour, see the config options within main.lua.
