# SPFKAudioConversion

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
| **Input** | All `AudioFileType` cases (WAV, AIFF, CAF, M4A, MP3, MP4, FLAC, OGG, etc.) |
| **Output** | WAV, AIFF, CAF, M4A, MP3, FLAC, OGG Opus |

## Usage

### Single File Conversion

```swift
import SPFKAudioConversion

// Basic conversion (options inferred from output extension)
let converter = AudioFormatConverter(inputURL: inputURL, outputURL: outputURL)
try await converter.start()

// With explicit options
var options = AudioFormatConverterOptions()
options.format = .wav
options.sampleRate = 44100
options.bitsPerChannel = 16
options.channels = 2

let converter = AudioFormatConverter(inputURL: inputURL, outputURL: outputURL, options: options)
try await converter.start()
```

### Conversion Options

```swift
// PCM options with bit depth rule
let options = try AudioFormatConverterOptions(
    pcmFormat: .wav,
    sampleRate: 48000,
    bitsPerChannel: 24,
    channels: 2,
    bitDepthRule: .lessThanOrEqual // won't upsample beyond source bit depth
)

// Compressed output with bit rate
var options = AudioFormatConverterOptions(format: .m4a)
options.bitRate = 256_000 // bits per second (clamped to 64k-320k)
```

### Batch Conversion

```swift
let sources = inputURLs.map { url in
    AudioFormatConverterSource(
        input: url,
        output: outputDir.appending(component: "\(url.stem).m4a"),
        options: AudioFormatConverterOptions(format: .m4a)
    )
}

let batch = await BatchAudioFormatConverter(inputs: sources)
await batch.update(delegate: self) // optional progress reporting
let results = try await batch.start()

for result in results {
    switch result {
    case .success(let source):
        print("Converted: \(source.output.lastPathComponent)")
    case .failed(let source, let error):
        print("Failed: \(source.input.lastPathComponent) - \(error)")
    }
}
```

### Convenience Functions

```swift
// Quick WAV conversion
try await AudioFormatConverter.convertToWave(
    inputURL: inputURL,
    outputURL: outputURL,
    sampleRate: 44100,
    bitDepth: 16
)

// Format detection
let isPCM = AudioFormatConverter.isPCM(url: fileURL)
let isCompressed = AudioFormatConverter.isCompressed(url: fileURL)
```

## Metadata Copying

Metadata is automatically copied from source to output after conversion, controlled by `MetadataCopyScheme` (default: `.copyAll`):

| Scheme | Tags | BEXT/iXML | XMP | Markers | Artwork |
|--------|:----:|:---------:|:---:|:-------:|:-------:|
| `.copyAll` | yes | yes | yes | yes | yes |
| `.copyTextAndMarkers` | yes | yes | yes | yes | -- |
| `.copyText` | yes | yes | yes | -- | -- |
| `.copyMarkers` | -- | -- | -- | yes | -- |
| `.ignore` | -- | -- | -- | -- | -- |

```swift
let source = AudioFormatConverterSource(
    input: inputURL,
    output: outputURL,
    options: options,
    metadataCopyScheme: .copyText // default is .copyAll
)
```

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

SPFKAudioConverterC (ObjC target)
  |-- LameConverter      LAME encoder + mpg123 decoder
  |-- SndFileConverter   libsndfile for FLAC/OGG + file info queries

BatchAudioFormatConverter
  |-- Structured concurrency with batchMap
  |-- Sliding window of 8 concurrent conversions
  |-- Per-file progress via BatchAudioFormatConverterDelegate
```

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Foundation extensions and utilities |
| [spfk-audio-base](https://github.com/ryanfrancesconi/spfk-audio-base) | Audio type definitions (`AudioFileType`, `AudioDefaults`) |
| [spfk-metadata](https://github.com/ryanfrancesconi/spfk-metadata) | Audio file metadata parsing |
| [spfk-metadata-xmp](https://github.com/ryanfrancesconi/spfk-metadata-xmp) | XMP metadata reading/writing |
| [spfk-lame](https://github.com/ryanfrancesconi/spfk-lame) | LAME + mpg123 xcframeworks for MP3 encoding/decoding |
| [spfk-utils](https://github.com/ryanfrancesconi/spfk-utils) | General utilities (`Entropy`, `Serializable`) |
| [sndfile-binary-xcframework](https://github.com/sbooth/sndfile-binary-xcframework) | libsndfile for FLAC/OGG encoding |
| [ogg-binary-xcframework](https://github.com/sbooth/ogg-binary-xcframework) | Ogg container library |
| [flac-binary-xcframework](https://github.com/sbooth/flac-binary-xcframework) | FLAC codec |
| [vorbis-binary-xcframework](https://github.com/sbooth/vorbis-binary-xcframework) | Vorbis codec |
| [opus-binary-xcframework](https://github.com/sbooth/opus-binary-xcframework) | Opus codec |

## Requirements

- **Platforms:** macOS 13+
- **Swift:** 6.2+

## About

Spongefork (SPFK) is the personal software projects of [Ryan Francesconi](https://github.com/ryanfrancesconi). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2016 to 2025 he was the lead macOS developer at [Audio Design Desk](https://add.app).

