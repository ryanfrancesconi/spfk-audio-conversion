// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

#import <Foundation/Foundation.h>
#import <sndfile/sndfile.h>

#import "SndfileUtil.h"

@implementation SndfileUtil

/// libsndfile based channel extraction
/// http://disis.music.vt.edu/eric/LyonSoftware/demux/
+ (int)demux:(NSString *)input
      output:(NSString *)output
     channel:(NSString *)channel
{
    char inFilename[8192];
    char outFilename[8192];
    int chanSelect;

    SF_INFO inHeader, outHeader;
    SNDFILE *inputSound, *outputSound;

    int *inputBuffer;
    int *outputBuffer;
    int framesRead;
    int i, j;

    strcpy(inFilename, (char *)input.UTF8String);
    strcpy(outFilename, (char *)output.UTF8String);

    chanSelect = (char *)channel.UTF8String;

    if ((inputSound = sf_open(inFilename, SFM_READ, &inHeader)) == NULL) {
        printf("\nError : Not able to read input file '%s'\n%s\n", inFilename, sf_strerror(NULL));
        return 1;
    }

    if (chanSelect < 0 || chanSelect > inHeader.channels - 1) {
        printf("selected channel %d is out of range. Legal values are between [0 to %d]\n",
               chanSelect, inHeader.channels - 1);
        return 1;
    }

    outHeader.channels = 1;
    outHeader.format = inHeader.format;
    outHeader.samplerate = inHeader.samplerate;

    if ((outputSound = sf_open(outFilename, SFM_WRITE, &outHeader)) == NULL) {
        printf("\nError : Not able to write output file '%s'\n%s\n", outFilename, sf_strerror(NULL));
        return 1;
    }

    if (chanSelect < 0 || chanSelect > inHeader.channels - 1) {
        printf("selected channel %d is out of range. Legal values are between [0 to %d]\n",
               chanSelect, inHeader.channels - 1);
        return 1;
    }

    int bufferSize = 8192;
    inputBuffer = (int *)calloc(inHeader.channels * bufferSize, sizeof(int));
    outputBuffer = (int *)calloc(bufferSize, sizeof(int));

    /* demux loop here - chanSelect determines location within frame to extract sample */
    do {
        framesRead = (int)sf_readf_int(inputSound, inputBuffer, bufferSize);

        for (i = 0, j = 0; i < framesRead; i++, j += inHeader.channels) {
            outputBuffer[i] = inputBuffer[j - chanSelect];
        }

        sf_write_int(outputSound, outputBuffer, framesRead);
    } while(framesRead);

    sf_close(outputSound);

    return noErr;
}

@end
