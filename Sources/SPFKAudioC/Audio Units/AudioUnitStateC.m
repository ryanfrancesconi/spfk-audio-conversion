// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import <CoreAudio/AudioHardware.h>
#import "AudioUnitStateC.h"

@implementation AudioUnitStateC

+ (void)loadFactoryPreset:(AudioUnit)audioUnit
                    named:(NSString *)name
{
    OSStatus result;

    // Retrieve the list of factory presets
    CFArrayRef array;
    UInt32 dataSize = sizeof(CFArrayRef);

    result = AudioUnitGetProperty(audioUnit,
                                  kAudioUnitProperty_FactoryPresets,
                                  kAudioUnitScope_Global,
                                  0,
                                  &array,
                                  &dataSize);

    if (result != noErr) {
        // TODO: return error
        return;
    }

    int index = 0;
    long count = CFArrayGetCount(array);

    // find the index of the preset
    for (int i = 0; i < count - 1; i++) {
        AUPreset *preset = (AUPreset *)CFArrayGetValueAtIndex(array, i);

        if (preset->presetName == (__bridge CFStringRef _Nullable)(name)) {
            index = i;
            break;
        }
    }

    if (index < count) {
        AUPreset *preset = (AUPreset *)CFArrayGetValueAtIndex(array, index);

        result = AudioUnitSetProperty(audioUnit,
                                      kAudioUnitProperty_PresentPreset,
                                      kAudioUnitScope_Global,
                                      0,
                                      preset,
                                      sizeof(AUPreset));

        if (result == noErr) {
            AudioUnitParameter aup;
            aup.mAudioUnit = audioUnit;
            aup.mParameterID = kAUParameterListener_AnyParameter;
            aup.mScope = kAudioUnitScope_Global;
            aup.mElement = 0;
            AUParameterListenerNotify(NULL, NULL, &aup);
        }
    }

    CFRelease(array);
}

/// Must notify the host that a parameter has been changed, blast out all parameters with this function
/// useful in the case of preset loading
+ (void)notifyAudioUnitListener:(AudioUnit)audioUnit
{
    //  Get number of parameters in this unit (size in bytes really):
    UInt32 parameterListSize = 0;

    AudioUnitGetPropertyInfo(audioUnit,
                             kAudioUnitProperty_ParameterList,
                             kAudioUnitScope_Global,
                             0,
                             &parameterListSize,
                             NULL);

    //  Get ids for the parameters:
    AudioUnitParameterID *parameterIDs = malloc(parameterListSize);
    AudioUnitGetProperty(audioUnit,
                         kAudioUnitProperty_ParameterList,
                         kAudioUnitScope_Global,
                         0,
                         parameterIDs,
                         &parameterListSize);

    AudioUnitParameterInfo parameterInfo_t;
    UInt32 parameterInfoSize = sizeof(AudioUnitParameterInfo);
    UInt32 parametersCount = parameterListSize / sizeof(AudioUnitParameterID);

    for (UInt32 pIndex = 0; pIndex < parametersCount; pIndex++) {
        AudioUnitGetProperty(audioUnit,
                             kAudioUnitProperty_ParameterInfo,
                             kAudioUnitScope_Global,
                             parameterIDs[pIndex],
                             &parameterInfo_t,
                             &parameterInfoSize);

        AudioUnitEvent ev;
        ev.mEventType = kAudioUnitEvent_ParameterValueChange;
        ev.mArgument.mParameter.mAudioUnit = audioUnit;
        ev.mArgument.mParameter.mParameterID = parameterIDs[pIndex];
        ev.mArgument.mParameter.mScope = kAudioUnitScope_Global;
        ev.mArgument.mParameter.mElement = 0;

        // Notify any listeners (i.e. the plugin's editor) that the parameter has been changed.
        AUEventListenerNotify(NULL, NULL, &ev);
    }
}

@end
