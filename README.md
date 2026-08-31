# SPFKAudioConversion

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-audio-conversion)](https://github.com/ryanfrancesconi/spfk-audio-conversion/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-audio-conversion%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-audio-conversion)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-audio-conversion%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-audio-conversion)

Audio file format conversion library supporting PCM and compressed formats via CoreAudio, AVFoundation, LAME, and libsndfile.

## Features

- Convert between PCM formats (WAV, AIFF, CAF) with sample rate, bit depth, and channel count options
- Encode to compressed formats (M4A/AAC, MP3, FLAC, OGG Opus)
- Decode compressed formats to PCM
- Transcode between compressed formats via intermediate PCM
- Batch conversion with configurable concurrency and progress reporting
- Automatic >=2GB file promotion to CAF (64-bit container)
- Bit depth rule enforcement to prevent unnecessary upsampling

## Supported Formats

| Direction | Formats |
|-----------|---------|
| **Input** | Anything AVFoundation or libsndfile opens (WAV, AIFF, CAF, M4A, MP3, MP4, FLAC, OGG, etc.), plus Matroska via `MatroskaAudioDecoder` |
| **Output** | WAV, AIFF, CAF, M4A, MP3, FLAC, OGG Opus |

Matroska is not an `AVAudioFile` format — `.mka`/`.mkv`/`.webm` are absent from
`AVURLAsset.audiovisualTypes()` and `AVAudioFile(forReading:)` throws `'fmt?'` on them. They are
readable here only through the decoder below, and are not writable at all.

## Key types

| Type | Description |
|------|-------------|
| **`AudioFormatConverter`** | One conversion, dispatching to the right encoder for the output format |
| **`AudioFormatConverterSource`** | The input file, output file and options for one operation |
| **`AudioFormatConverterAdjustment`** | A change the converter had to make to the requested options, so the caller can report it |
| **`BatchAudioFormatConverter`** | The above under structured concurrency, with a sliding window of 8 and per-file progress through its delegate |
| **`BatchAudioFormatConverterResult`** | What one file in a batch produced |
| **`AudioEditRenderer`** | Applies a pending edit — trim, reverse, fade — and writes the result |
| **`SegmentDivider`** / **`SegmentDividerOptions`** | Splitting a file into its detected segments |
| **`BatchSegmentRenderer`** | That split across many files at once |
| **`MetadataPaster`** | Pastes a filtered subset of metadata from one file to another |
| **`MatroskaAudioDecoder`** | Demuxed Matroska blocks as PCM, seekable by frame |
| **`AVAssetReaderPCMSource`** | The same shape over an AVFoundation asset |

`AudioEditRenderer` loads the whole source file into memory as a PCM buffer, applies the edit and
writes the output, copying text metadata and markers across afterward. PCM formats and AAC are
written directly through `AVAudioFile`; MP3, FLAC and OGG go through an intermediate WAV and the
converter. **The whole file is in memory** — fine for sample libraries and short clips, and not for
very long recordings.

`MetadataPaster`'s operations are all best-effort: a failure in one section does not stop the rest.

## Metadata Copying

Metadata is automatically copied from source to output after conversion, controlled by `MetadataCopyScheme` (default: `.copyAll`):

| Scheme | Tags | BEXT/iXML | XMP | Markers | Artwork |
|--------|:----:|:---------:|:---:|:-------:|:-------:|
| `.copyAll` | yes | yes | yes | yes | yes |
| `.copyTextAndMarkers` | yes | yes | yes | yes | -- |
| `.copyText` | yes | yes | yes | -- | -- |
| `.copyMarkers` | -- | -- | -- | yes | -- |
| `.ignore` | -- | -- | -- | -- | -- |

**Marker format mapping** — markers are written in the native chapter/cue format of the output:

| Output format | Marker format |
|---------------|---------------|
| WAV, AIFF | RIFF cue points (AudioToolbox) |
| MP3 | ID3v2 CHAP frames |
| FLAC, OGG, Opus | Vorbis comment chapters |
| M4A, MP4, M4B | Nero `chpl` chapters |

BEXT and iXML are WAV-to-WAV only. XMP copy is best-effort (silently skipped if not present).

## Architecture

```
AudioFormatConverter.start()
  |-- PCM output        --> convertToPCM()         [CoreAudio ExtAudioFile]
  |-- MP3 output        --> convertToMP3()         [LAME via LameConverter]
  |-- FLAC output       --> convertToFLAC()        [libsndfile via SndFileConverter]
  |-- OGG Opus output   --> convertToOGG()         [libsndfile via SndFileConverter]
  |-- PCM in, M4A out   --> AssetWriter            [AVFoundation]
  |-- Compressed in/out --> convertCompressed()     [intermediate PCM + target encoder]

```

`LameConverter` and `SndFileConverter` are the two encoders in the ObjC target, wrapping LAME +
mpg123 and libsndfile respectively.

`BatchAudioFormatConverter` runs the above under structured concurrency, with a sliding window of
8 concurrent conversions and per-file progress through `BatchAudioFormatConverterDelegate`.

### Matroska

`MatroskaAudioDecoder` turns demuxed blocks into PCM and seeks by frame.
`MatroskaPCMBlockReader` handles uncompressed tracks, widening to float with no converter in the
path — the data is already PCM, so putting `AVAudioConverter` in front of it would only add a
place to go wrong.

`MatroskaAudioDecoder+WaveformPCMSource` is the conformance that lets a waveform parse a container
AVFoundation cannot open.

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Foundation extensions and utilities |
| [spfk-audio-base](https://github.com/ryanfrancesconi/spfk-audio-base) | Audio type definitions (`AudioFileType`, `AudioDefaults`) |
| [spfk-metadata](https://github.com/ryanfrancesconi/spfk-metadata) | Audio file metadata parsing |
| [spfk-matroska](https://github.com/ryanfrancesconi/spfk-matroska) | Matroska demuxing, for the decoder above |
| [spfk-lame](https://github.com/ryanfrancesconi/spfk-lame) | LAME + mpg123 xcframeworks for MP3 encoding/decoding |
| [spfk-utils](https://github.com/ryanfrancesconi/spfk-utils) | General utilities (`Entropy`, `Serializable`) |
| [spfk-waveform](https://github.com/ryanfrancesconi/spfk-waveform) | Waveform scanning, for the intermediate PCM path |
| [spfk-video](https://github.com/ryanfrancesconi/spfk-video) | Video track reading and frame extraction |
| [sndfile-binary-xcframework](https://github.com/sbooth/sndfile-binary-xcframework) | libsndfile for FLAC/OGG encoding |
| [ogg-binary-xcframework](https://github.com/sbooth/ogg-binary-xcframework) | Ogg container library |
| [flac-binary-xcframework](https://github.com/sbooth/flac-binary-xcframework) | FLAC codec |
| [vorbis-binary-xcframework](https://github.com/sbooth/vorbis-binary-xcframework) | Vorbis codec |
| [opus-binary-xcframework](https://github.com/sbooth/opus-binary-xcframework) | Opus codec |

## Requirements

- **Platforms:** macOS 13+
- **Swift:** 6.2+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
