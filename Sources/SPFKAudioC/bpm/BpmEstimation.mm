
#import "bpm.h"
#import "BpmEstimation.h"
#import "MiniBpm.h"

@implementation BpmEstimation

+ (double)processMbpm:(const float *)data
      numberOfSamples:(int)numberOfSamples
           sampleRate:(double)sampleRate {
    //
    breakfastquay::MiniBPM mbpm((float)sampleRate);

    mbpm.setBPMRange(30, 400);
    mbpm.process(data, numberOfSamples);

    return mbpm.estimateTempo();
}

+ (double)processXwax:(const float *)data
      numberOfSamples:(int)numberOfSamples
           sampleRate:(double)sampleRate {
    return scan_for_bpm(data, (size_t)numberOfSamples, sampleRate, 1024, 1024);
}

@end
