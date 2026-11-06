# SPFKAudioConversion

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-audio-conversion)](https://github.com/ryanfrancesconi/spfk-audio-conversion/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-audio-conversion%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-audio-conversion)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-audio-conversion%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-audio-conversion)

Audio file conversion and edit rendering for macOS.

## Features

- Convert to PCM (WAV, AIFF, CAF), AAC, MP3, FLAC, Ogg Vorbis or Opus, one file at a time or as a
  concurrent batch (`AudioFormatConverter`, `BatchAudioFormatConverter`)
- Copy tags, BEXT, iXML, artwork, markers and Finder tags to the output
- Render a pending `AudioEditDescription` (`AudioEditRenderer`)
- Split a file into its detected segments (`SegmentDivider`)
- Build reversed copies (`ReversedAudioBuilder`)
- Decode Matroska audio to PCM (`MatroskaAudioDecoder`)
- MP3 is encoded with LAME, and FLAC, Vorbis and Opus through libsndfile

## Notes

- Converting with no markers to copy does not remove markers already in the output. Call
  `AudioFormatConverter.removeMarkers(from:outputType:)` when the output should have none.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
