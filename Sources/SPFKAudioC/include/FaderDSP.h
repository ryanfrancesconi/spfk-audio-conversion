// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

#ifndef FaderDSP_h
#define FaderDSP_h

#import <AudioToolbox/AUParameters.h>
#import <Foundation/Foundation.h>

// visible to swift

static const NSString *kAudioUnitFaderSubTypeString = @"fder";

typedef NS_ENUM(AUParameterAddress, FaderParameter) {
    FaderParameterLeftGain,
    FaderParameterRightGain,
    FaderParameterFlipStereo,
    FaderParameterMixToMono
};

#endif // !FaderDSP_h
