//  AudioUnitStateC.h
//  Created by Ryan Francesconi on 3/5/18.
//  Copyright © 2018 Audio Design Desk. All rights reserved.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioUnitStateC : NSObject

+ (void)loadFactoryPreset:(AudioUnit)audioUnit
        named:(NSString *)name;

+ (void)notifyAudioUnitListener:(AudioUnit)audioUnit;

@end
