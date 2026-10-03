// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Decodes a file through libsndfile as interleaved 32-bit float.
///
/// Holds a read position, so one caller may drive an instance at a time.
@interface SndFileReader : NSObject

/// Returns nil when libsndfile cannot open the file; `error` then carries its reason.
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) double sampleRate;
@property (nonatomic, readonly) int channelCount;

/// Frames in the file as libsndfile reports them.
@property (nonatomic, readonly) int64_t frameCount;

/// Reads up to `frames` interleaved frames into `buffer`. Returns the frames read, 0 at the end,
/// or -1 on a decode error.
- (int64_t)readFloat:(float *)buffer frames:(int64_t)frames;

/// Moves the read position to `frame`. Returns NO when libsndfile refuses.
- (BOOL)seekToFrame:(int64_t)frame;

@end

NS_ASSUME_NONNULL_END
