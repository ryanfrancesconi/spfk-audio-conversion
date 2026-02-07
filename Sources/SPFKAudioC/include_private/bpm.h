
#include <stdlib.h>

#ifndef BPM_H
#define BPM_H

#define LOWER 84.0
#define UPPER 146.0

#ifdef __cplusplus
extern "C" {
#endif

double scan_for_bpm(
    const float  *data,
    size_t       len,
    double       sample_rate,
    unsigned int steps,
    unsigned int samples
    );

#ifdef __cplusplus
}
#endif

#endif
