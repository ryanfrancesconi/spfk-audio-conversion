# SPFKAudioConversion

Audio file format conversion library supporting PCM and compressed formats via CoreAudio, AVFoundation, and SoX.

## Features

- Convert between PCM formats (WAV, AIFF, CAF) with sample rate, bit depth, and channel count options
- Encode to compressed formats (M4A/AAC, MP3)
- Decode compressed formats to PCM
- Transcode between compressed formats via intermediate PCM
- Batch conversion with configurable concurrency and progress reporting
- Automatic >=2GB file promotion to CAF (64-bit container)
- Bit depth rule enforcement to prevent unnecessary upsampling

## Supported Formats

| Direction | Formats |
|-----------|---------|
| **Input** | All `AudioFileType` cases (WAV, AIFF, CAF, M4A, MP3, MP4, FLAC, OGG, etc.) |
| **Output** | WAV, AIFF, CAF, M4A, MP3 |

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

## Architecture

```
AudioFormatConverter.start()
  |-- PCM output        --> convertToPCM()        [CoreAudio ExtAudioFile]
  |-- MP3 output        --> convertToMP3()         [SoX]
  |-- PCM in, M4A out   --> AssetWriter            [AVFoundation]
  |-- Compressed in/out --> convertCompressed()     [intermediate PCM + AssetWriter]

BatchAudioFormatConverter
  |-- Structured concurrency with TaskGroup
  |-- Sliding window of 8 concurrent conversions
  |-- Per-file progress via BatchAudioFormatConverterDelegate
```

## Dependencies

- **SPFKBase** - Foundation extensions and utilities
- **SPFKAudioBase** - Audio type definitions (`AudioFileType`, `AudioDefaults`)
- **SPFKMetadata** - Audio file metadata parsing
- **SPFKSoX** - SoX wrapper for MP3 encoding
- **SPFKUtils** - General utilities (`Entropy`, `Serializable`)

## Requirements

- macOS 12+
- Swift 6.2+
