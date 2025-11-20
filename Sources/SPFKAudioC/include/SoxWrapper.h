// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

///  Obj C wrapper for libsox based calls. Note that SoX isn't suitable for concurrency and
///  this API is designed to be used via the SoX object in Swift.
@interface SoxWrapper : NSObject

- (int)createMultiChannelWave:(NSArray *)inputs
                       output:(NSString *)output;

- (int)remix:(NSString *)input
      output:(NSString *)output
     channel:(NSString *)channel;

- (int)  trim:(NSString *)input
       output:(NSString *)output
    startTime:(NSString *)startTime
      endTime:(NSString *)endTime;

- (int)convert:(NSString *)input
        output:(NSString *)output
          bits:(NSString *)bits
    sampleRate:(NSString *)sampleRate;

- (int)convert:(NSString *)input
        output:(NSString *)output
          bits:(NSString *)bits;

- (int)convert:(NSString *)input
        output:(NSString *)output
    sampleRate:(NSString *)sampleRate;

- (int)convert:(NSString *)input
        output:(NSString *)output;

- (int)convert:(NSString *)input
        output:(NSString *)output
       bitRate:(NSString *)bitRate
    sampleRate:(NSString *)sampleRate;

- (int)convert:(NSString *)input
        output:(NSString *)output
       bitRate:(NSString *)bitRate;

@end

NS_ASSUME_NONNULL_END
