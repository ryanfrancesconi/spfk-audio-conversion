//  SoxWrapper.h
//  Obj C wrapper for libsox based calls
//  Created by Ryan Francesconi on 4/24/19.
//  Copyright © 2019 Audio Design Desk. All rights reserved.

#import <Foundation/Foundation.h>
#import "sox.h"

NS_ASSUME_NONNULL_BEGIN

@interface SoxWrapper : NSObject

+ (void)createMultiChannelWave:(NSArray *)inputs
                        output:(NSString *)output;

+ (void)remix:(NSString *)input
       output:(NSString *)output
      channel:(NSString *)channel;

+ (int)demux:(NSString *)input
       output:(NSString *)output
      channel:(NSString *)channel;

+ (void) trim:(NSString *)input
       output:(NSString *)output
    startTime:(NSString *)startTime
      endTime:(NSString *)endTime;

+ (void)convert:(NSString *)input
         output:(NSString *)output
           bits:(NSString *)bits
     sampleRate:(NSString *)sampleRate;

+ (void)convert:(NSString *)input
         output:(NSString *)output
           bits:(NSString *)bits;

+ (void)convert:(NSString *)input
         output:(NSString *)output
     sampleRate:(NSString *)sampleRate;

+ (void)convert:(NSString *)input
         output:(NSString *)output;

+ (void)convert:(NSString *)input
         output:(NSString *)output
        bitRate:(NSString *)bitRate
     sampleRate:(NSString *)sampleRate;

+ (void)convert:(NSString *)input
         output:(NSString *)output
        bitRate:(NSString *)bitRate;

@end

NS_ASSUME_NONNULL_END
