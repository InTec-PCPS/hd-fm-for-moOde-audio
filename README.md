Personal project only!

# HD-Radio and FM Radio for moOde audio

A Frankenstein's monster to add over-the-air US FM and multicast FM (HD) stations to moOde audio's Radio list using an RTL-SDR dongle.

- For HD-Radio, it uses nrsc5 by theori-io (https://github.com/theori-io/nrsc5) to decode signals from an RTL-SDR dongle attached to the Raspberry Pi. Artist/Title are scraped from the nrsc5 stderr and sent to Icecast as metadata.
- For standard FM radio, no decoder is needed, but RDS info is picked up using redsea by windytan (https://github.com/windytan/redsea).
- The signals are encoded by ffmpeg/libmp3lame and sent to Icecast.
- Icecast sets up a local stream that is interpreted by moOdeaudio as a webradio station.

Adding stations to moOdeaudio uses a URI that tunes the frequency and multicast channel:
- http://127.0.0.1:8080/tune?freq=93.3&prog=0 (for HD. prog 0 is HD-1)
- http://127.0.0.1:8081/fmtune?freq=102.3 (for FM.)

Note to self: remember to enable and start services...and to set icecast passwords where needed. Python needs flask. Icecast needs to be installed. nrsc5 and redsea need to be compiled.

nrsc5 build deps: git build-essential cmake autoconf libtool libao-dev libfftw3-dev librtlsdr-dev
redsea build deps: git build-essential meson libsndfile1-dev libliquid-dev
redsea runtime deps: libiconv libsndfile liquid-dsp nlohmann-json
