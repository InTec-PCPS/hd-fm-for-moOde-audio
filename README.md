Personal project only!

Anyone who stumbles upon this is welcome to take it, use it, make it better. There's plenty of room for that. For example, I started with HD and added FM later. I'm sure they could be combined.

Added vibe-coded install script that handles everything but setting passwords for icecast (see notes).

![Project Logo](images/radio-hd.jpg "moOdeHD")

# HD-Radio and FM Radio for moOde audio

A Frankenstein's monster to add over-the-air US FM and multicast FM (HD) stations to moOde audio's Radio list using an RTL-SDR dongle.

Works with moOde 10. Note that there's no way to scan stations and auto-add them to the moOde radio library.

![Sequence](images/sequence.png "audio and metadata sequence")

## How it works ##

- Stations are added to moOde audio like any other streaming radio station. Stream URLs are formatted like this (for HD, prog 0 is HD-1):
  - <pre>http://127.0.0.1:8080/tune?freq=93.3&prog=0</pre>
  - <pre>http://127.0.0.1:8081/fmtune?freq=102.3</pre>
- Clicking a station starts a sequence of events that tunes the RTL-SDR dongle, captures its audio and metadata, and eventually passes it back to moOde audio as a local stream.
  - For HD-Radio, it uses **nrsc5** by theori-io (https://github.com/theori-io/nrsc5) to decode signals from an RTL-SDR dongle attached to the Raspberry Pi. Artist/Title are scraped from the nrsc5 stderr and sent to Icecast2 as metadata.
  - For standard FM radio, it uses **rtl-sdr** tools with RDS info picked up by **redsea** by windytan (https://github.com/windytan/redsea).
  - The audio is re-encoded by **ffmpeg/libmp3lame** and sent along with any station/artist/song info to Icecast2.
  - **Icecast2** sets up a local stream that is interpreted by moOde audio as a webradio station.

## Notes to Self for moOde major releases

- Remember to enable services in /etc/systemd/system: <pre>sudo systemctl enable ###.service</pre>
- Runtime and build dependencies: git build-essential cmake autoconf libtool libao-dev libfftw3-dev librtlsdr-dev meson libsndfile1-dev libliquid-dev python3-flask icecast2.
- Remember to set icecast passwords in /etc/icecast2/icecast.xml, /usr/local/bin/fm-run, and hd-run. Doesn't matter what they are as long as they match.
- Icecast doesn't need configuration during install. The xml file here is all that's needed.
- nrsc5 and redsea must be compiled and installed. Binaries aren't included here.
- Add user to plugdev and audio groups <pre>sudo usermod -aG plugdev [username] && sudo usermod -aG audio [username]</pre>
- Most files have both their location and their permissions included inside the file istelf (for bad memory reasons).

