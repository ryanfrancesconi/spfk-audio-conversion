
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BpmEstimation : NSObject

// mini bpm
+ (double)processMbpm:(const float *)data
      numberOfSamples:(int)numberOfSamples
           sampleRate:(double)sampleRate;

// bpm-tools
+ (double)processXwax:(const float *)data
      numberOfSamples:(int)numberOfSamples
           sampleRate:(double)sampleRate;
@end

NS_ASSUME_NONNULL_END
