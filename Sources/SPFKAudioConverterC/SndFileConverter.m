// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

#import "SndFileConverter.h"
#import <sndfile/sndfile.h>

#define BUFFER_FRAMES 8192

@implementation SndFileConverter

- (int)convertToFLAC:(NSString *)input
              output:(NSString *)output
            bitDepth:(int)bitDepth
{
    SF_INFO inputInfo;
    memset(&inputInfo, 0, sizeof(inputInfo));

    SNDFILE *inFile = sf_open(input.UTF8String, SFM_READ, &inputInfo);
    if (inFile == NULL) {
        return -1;
    }

    // Determine output subformat from requested bit depth
    int subformat;
    if (bitDepth == 16) {
        subformat = SF_FORMAT_PCM_16;
    } else if (bitDepth == 24) {
        subformat = SF_FORMAT_PCM_24;
    } else if (bitDepth == 8) {
        subformat = SF_FORMAT_PCM_S8;
    } else {
        // Preserve source bit depth
        subformat = inputInfo.format & SF_FORMAT_SUBMASK;
        // FLAC only supports PCM subformats — default to 24 if source is float/other
        if (subformat != SF_FORMAT_PCM_S8 &&
            subformat != SF_FORMAT_PCM_16 &&
            subformat != SF_FORMAT_PCM_24) {
            subformat = SF_FORMAT_PCM_24;
        }
    }

    SF_INFO outputInfo;
    memset(&outputInfo, 0, sizeof(outputInfo));
    outputInfo.samplerate = inputInfo.samplerate;
    outputInfo.channels = inputInfo.channels;
    outputInfo.format = SF_FORMAT_FLAC | subformat;

    SNDFILE *outFile = sf_open(output.UTF8String, SFM_WRITE, &outputInfo);
    if (outFile == NULL) {
        sf_close(inFile);
        return -1;
    }

    // Copy audio data in chunks using integer format for lossless precision
    int *buffer = (int *)malloc(BUFFER_FRAMES * inputInfo.channels * sizeof(int));
    if (buffer == NULL) {
        sf_close(outFile);
        sf_close(inFile);
        return -1;
    }

    sf_count_t readCount;
    while ((readCount = sf_readf_int(inFile, buffer, BUFFER_FRAMES)) > 0) {
        sf_writef_int(outFile, buffer, readCount);
    }

    free(buffer);
    sf_close(outFile);
    sf_close(inFile);

    return 0;
}

- (int)convertToOGG:(NSString *)input
             output:(NSString *)output
{
    SF_INFO inputInfo;
    memset(&inputInfo, 0, sizeof(inputInfo));

    SNDFILE *inFile = sf_open(input.UTF8String, SFM_READ, &inputInfo);
    if (inFile == NULL) {
        return -1;
    }

    SF_INFO outputInfo;
    memset(&outputInfo, 0, sizeof(outputInfo));
    outputInfo.samplerate = inputInfo.samplerate;
    outputInfo.channels = inputInfo.channels;
    outputInfo.format = SF_FORMAT_OGG | SF_FORMAT_OPUS;

    SNDFILE *outFile = sf_open(output.UTF8String, SFM_WRITE, &outputInfo);
    if (outFile == NULL) {
        sf_close(inFile);
        return -1;
    }

    // Use float buffers for lossy encoding
    float *buffer = (float *)malloc(BUFFER_FRAMES * inputInfo.channels * sizeof(float));
    if (buffer == NULL) {
        sf_close(outFile);
        sf_close(inFile);
        return -1;
    }

    sf_count_t readCount;
    while ((readCount = sf_readf_float(inFile, buffer, BUFFER_FRAMES)) > 0) {
        sf_writef_float(outFile, buffer, readCount);
    }

    free(buffer);
    sf_close(outFile);
    sf_close(inFile);

    return 0;
}

@end
