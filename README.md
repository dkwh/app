# RPi-Diskalvier-network-player
(inspired by Florian Bador)
This player allows for a Raspberry Pi to host a Midi player/recorder server. This plays using the serial MIDI port used for various instruments and DOES NOT CONTAIN A SYNTHYSIZER! It was designed to update a player piano from Yamaha that still took floppy disks for playback. You can route it to a local synth like timidity if you need support for a synth.
It has a web interface and REST support for future Alexa and Google home integration.
![](./static/screenshot.png)

Very much a WIP

Currently the player works for selecting songs, playing them, scraping the tempo and other information from midi files, playing back a midi file from a given time (seek, not supported by standard libraries and deceivingly difficult to implement due to tempo changes and timings)
, downloading the songs, and changing the tempo.

Need to fix:
keys stuck down when pausing (sometimes), recording functionality, proper button updates on the web interface, better process management (sometimes a process gets stuck due to the API), tons of little bugs.

Need to add: Database support (to reduce memory overhead and launch time), Playlist support, input/output device selection, auto launch on startup, Google Assistant support (using IFTTT), instrument changer, secure connection (SSL), automated setup (GUI for config file).

If you want to try it out you can run the setu
