// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import <Foundation/Foundation.h>
#import "sox.h"

NS_ASSUME_NONNULL_BEGIN

///  Obj C wrapper for libsox based calls. Please note that SoX isn't suitable for concurrency and
///  this API is designed to be used via the SoX object in Swift.
@interface SoxWrapper : NSObject

- (void)createMultiChannelWave:(NSArray *)inputs
                        output:(NSString *)output;

- (void)remix:(NSString *)input
       output:(NSString *)output
      channel:(NSString *)channel;

- (void) trim:(NSString *)input
       output:(NSString *)output
    startTime:(NSString *)startTime
      endTime:(NSString *)endTime;

- (void)convert:(NSString *)input
         output:(NSString *)output
           bits:(NSString *)bits
     sampleRate:(NSString *)sampleRate;

- (void)convert:(NSString *)input
         output:(NSString *)output
           bits:(NSString *)bits;

- (void)convert:(NSString *)input
         output:(NSString *)output
     sampleRate:(NSString *)sampleRate;

- (void)convert:(NSString *)input
         output:(NSString *)output;

- (void)convert:(NSString *)input
         output:(NSString *)output
        bitRate:(NSString *)bitRate
     sampleRate:(NSString *)sampleRate;

- (void)convert:(NSString *)input
         output:(NSString *)output
        bitRate:(NSString *)bitRate;

@end

NS_ASSUME_NONNULL_END
