// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Converts PCM audio to MP3 using LAME.
/// Each instance is independent — safe for concurrent use across threads.
@interface LameConverter : NSObject

/// Convert PCM audio (WAV/AIFF) to MP3.
/// @param input Path to the input audio file (read via libsndfile).
/// @param output Path for the output MP3 file.
/// @param bitRate Target bitrate in kbps (e.g. 128, 256). Pass 0 for LAME VBR default.
/// @param quality LAME algorithm quality: 0 = best/slowest, 9 = worst/fastest. 2 is recommended.
/// @return 0 on success, non-zero on failure.
- (int)convertToMP3:(NSString *)input
             output:(NSString *)output
            bitRate:(int)bitRate
            quality:(int)quality;

@end

NS_ASSUME_NONNULL_END
