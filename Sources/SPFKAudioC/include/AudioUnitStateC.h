// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

@interface AudioUnitStateC : NSObject

+ (OSStatus)loadFactoryPreset:(AudioUnit)audioUnit
                        named:(NSString *)name;

+ (OSStatus)notifyAudioUnitListener:(AudioUnit)audioUnit;

@end
