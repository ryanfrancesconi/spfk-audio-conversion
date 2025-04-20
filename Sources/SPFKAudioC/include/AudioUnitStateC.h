// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface AudioUnitStateC : NSObject

+ (void)loadFactoryPreset:(AudioUnit)audioUnit
        named:(NSString *)name;

+ (void)notifyAudioUnitListener:(AudioUnit)audioUnit;

@end
