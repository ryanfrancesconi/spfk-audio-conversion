// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio
// Heavily based on the AudioKit version. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

#pragma once

#import <AudioToolbox/AudioToolbox.h>
#include <stdarg.h>

CF_EXTERN_C_BEGIN

/* visible to swift */

/// Pointer to an instance of a DSPBase subclass
typedef struct DSPBase *DSPRef;

DSPRef createDSP(OSType code);

AUParameterAddress getParameterAddressDSP(const char *name);

AUInternalRenderBlock internalRenderBlockDSP(DSPRef pDSP);

size_t inputBusCountDSP(DSPRef pDSP);

bool canProcessInPlaceDSP(DSPRef pDSP);

void setBufferDSP(DSPRef pDSP, AudioBufferList *buffer, size_t busIndex);

void allocateRenderResourcesDSP(DSPRef pDSP, uint32_t channelCount, double sampleRate);
void deallocateRenderResourcesDSP(DSPRef pDSP);

void resetDSP(DSPRef pDSP);

void setParameterValueDSP(DSPRef pDSP, AUParameterAddress address, AUValue value);
AUValue getParameterValueDSP(DSPRef pDSP, AUParameterAddress address);

void setBypassDSP(DSPRef pDSP, bool bypassed);
bool getBypassDSP(DSPRef pDSP);

void initializeConstantDSP(DSPRef pDSP, AUValue value);

void setWavetableDSP(DSPRef pDSP, const float *table, size_t length, int index);

void deleteDSP(DSPRef pDSP);

CF_EXTERN_C_END

#ifdef __cplusplus

// invisible to swift

#include "DSPBase.hpp"

#endif // __cplusplus
