# SPFKAudioConversion

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-audio-conversion)](https://github.com/ryanfrancesconi/spfk-audio-conversion/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-audio-conversion%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-audio-conversion)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-audio-conversion%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-audio-conversion)

The capability that writes audio files: converting between formats, and rendering the edits a user
has queued on a file. ShadowTag's conversion, edit, split and reverse features run through it. It is
macOS only.

Conversion goes from anything AVFoundation, libsndfile or the Matroska demuxer can read, to PCM
(WAV, AIFF, CAF), AAC, MP3, FLAC, Ogg Vorbis or Opus, singly or as a concurrent batch. Metadata
travels with the audio: tags, BEXT and iXML, artwork, and markers rewritten in the output's own
marker format. Rendering applies a pending edit described in spfk-audio-base (trim, channels,
reverse, time and pitch, normalize, fade) and writes the result. The package also splits a file into
its detected segments, builds reversed copies for reversed playback, and decodes containers
AVFoundation cannot open into PCM for anything that needs samples from them.

MP3 is encoded with LAME from spfk-lame, and FLAC and Ogg through libsndfile. Demuxing belongs to
spfk-matroska, time and pitch DSP to spfk-tempo, tag reading and writing to spfk-metadata, and
caching reversed copies to spfk-waveform.

## Markers

Converting with no markers to copy does not remove the ones already in the output, and a trim can
carry the source's markers across at their old times. A render that should keep none has to call
`AudioFormatConverter.removeMarkers(from:outputType:)`.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
