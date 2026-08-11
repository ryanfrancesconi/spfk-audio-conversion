// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Converts audio files using libsndfile directly.
/// Each instance is independent — safe for concurrent use across threads.
@interface SndFileConverter : NSObject

/// Convert PCM audio (WAV/AIFF/FLAC) to FLAC.
/// @param input Path to the input audio file.
/// @param output Path for the output FLAC file.
/// @param bitDepth Output bit depth (16 or 24). Pass 0 to preserve the source bit depth.
/// @return 0 on success, non-zero on failure.
- (int)convertToFLAC:(NSString *)input
              output:(NSString *)output
            bitDepth:(int)bitDepth;

/// Convert PCM audio (WAV/AIFF/FLAC) to Ogg Vorbis.
/// @param input Path to the input audio file.
/// @param output Path for the output Ogg file.
/// @return 0 on success, non-zero on failure.
- (int)convertToVorbis:(NSString *)input
                output:(NSString *)output;

/// Convert PCM audio (WAV/AIFF/FLAC) to Ogg Opus.
/// Opus encodes only at 8/12/16/24/48 kHz; resample the input before calling.
/// @param input Path to the input audio file.
/// @param output Path for the output Opus file.
/// @return 0 on success, non-zero on failure.
- (int)convertToOpus:(NSString *)input
              output:(NSString *)output;

/// Read audio file info via libsndfile.
/// @param path Path to the audio file.
/// @param sampleRate On return, the file's sample rate.
/// @param channels On return, the number of channels.
/// @param bitDepth On return, the bit depth (8, 16, 24) or 0 if not PCM.
/// @return 0 on success, non-zero on failure.
- (int)fileInfo:(NSString *)path
     sampleRate:(int *)sampleRate
       channels:(int *)channels
       bitDepth:(int *)bitDepth;

@end

NS_ASSUME_NONNULL_END
