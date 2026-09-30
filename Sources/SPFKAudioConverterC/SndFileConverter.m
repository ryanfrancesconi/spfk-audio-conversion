// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

#import "SndFileConverter.h"
#import <sndfile/sndfile.h>

#define BUFFER_FRAMES 8192

/// Closes both files and folds in what the loop could not see: a read that stopped on an error
/// rather than at the end, a write the encoder reported as complete although the file write under
/// it failed, and an encoder that could not flush its last block on close.
static int finishConversion(SNDFILE *inFile, SNDFILE *outFile, int result) {
    if (sf_error(inFile) != SF_ERR_NO_ERROR || sf_error(outFile) != SF_ERR_NO_ERROR) {
        result = -1;
    }

    if (sf_close(outFile) != 0) {
        result = -1;
    }

    sf_close(inFile);

    return result;
}

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

    // Integer sources are copied as int, which is exact. libsndfile does not scale float samples
    // into the int range on an int read, so a float source read that way arrives as silence; it
    // is copied as float instead, clipped to full scale by the encoder.
    int sourceSubformat = inputInfo.format & SF_FORMAT_SUBMASK;
    BOOL isFloatSource = sourceSubformat == SF_FORMAT_FLOAT || sourceSubformat == SF_FORMAT_DOUBLE;

    sf_count_t readCount;
    int result = 0;

    if (isFloatSource) {
        sf_command(outFile, SFC_SET_CLIPPING, NULL, SF_TRUE);

        float *buffer = (float *)malloc(BUFFER_FRAMES * inputInfo.channels * sizeof(float));
        if (buffer == NULL) {
            sf_close(outFile);
            sf_close(inFile);
            return -1;
        }

        while ((readCount = sf_readf_float(inFile, buffer, BUFFER_FRAMES)) > 0) {
            if (sf_writef_float(outFile, buffer, readCount) != readCount) {
                result = -1;
                break;
            }
        }

        free(buffer);

    } else {
        int *buffer = (int *)malloc(BUFFER_FRAMES * inputInfo.channels * sizeof(int));
        if (buffer == NULL) {
            sf_close(outFile);
            sf_close(inFile);
            return -1;
        }

        while ((readCount = sf_readf_int(inFile, buffer, BUFFER_FRAMES)) > 0) {
            if (sf_writef_int(outFile, buffer, readCount) != readCount) {
                result = -1;
                break;
            }
        }

        free(buffer);
    }

    return finishConversion(inFile, outFile, result);
}

- (int)convertToVorbis:(NSString *)input
                output:(NSString *)output
               bitRate:(int)bitRate
{
    return [self convertToOgg:input output:output subformat:SF_FORMAT_VORBIS bitRate:bitRate];
}

- (int)convertToOpus:(NSString *)input
              output:(NSString *)output
             bitRate:(int)bitRate
{
    return [self convertToOgg:input output:output subformat:SF_FORMAT_OPUS bitRate:bitRate];
}

/// libsndfile's Vorbis quality (0...1) for a stereo bit rate. The encoder takes a quality rather
/// than a rate, so this interpolates between rates measured from a 48 kHz stereo encode; 83 kbps
/// is the lowest it produces.
static double vorbisQuality(int bitRate) {
    static const double kbps[] = {83, 124, 183, 299, 499};
    static const double quality[] = {0, 0.25, 0.5, 0.75, 1};
    double target = bitRate / 1000.0;

    if (target <= kbps[0]) return quality[0];

    for (int i = 1; i < 5; i++) {
        if (target <= kbps[i]) {
            double t = (target - kbps[i - 1]) / (kbps[i] - kbps[i - 1]);
            return quality[i - 1] + t * (quality[i] - quality[i - 1]);
        }
    }

    return quality[4];
}

/// libsndfile's Opus compression level (0...1) for a stereo bit rate. The level runs linearly from
/// 256 kbps down to 6 kbps per channel.
static double opusCompressionLevel(int bitRate) {
    double perChannel = bitRate / 2.0;
    double level = (256000.0 - perChannel) / (256000.0 - 6000.0);

    return level < 0 ? 0 : level > 1 ? 1 : level;
}

/// Shared Ogg encode path. `subformat` selects the codec carried in the container.
- (int)convertToOgg:(NSString *)input
             output:(NSString *)output
          subformat:(int)subformat
            bitRate:(int)bitRate
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
    outputInfo.format = SF_FORMAT_OGG | subformat;

    SNDFILE *outFile = sf_open(output.UTF8String, SFM_WRITE, &outputInfo);
    if (outFile == NULL) {
        sf_close(inFile);
        return -1;
    }

    // Before the first write, which is when the encoder is configured.
    if (bitRate > 0) {
        BOOL applied;

        if (subformat == SF_FORMAT_VORBIS) {
            double quality = vorbisQuality(bitRate);
            applied = sf_command(outFile, SFC_SET_VBR_ENCODING_QUALITY, &quality, sizeof(quality)) == SF_TRUE;
        } else {
            double level = opusCompressionLevel(bitRate);
            applied = sf_command(outFile, SFC_SET_COMPRESSION_LEVEL, &level, sizeof(level)) == SF_TRUE;
        }

        if (!applied) {
            sf_close(outFile);
            sf_close(inFile);
            return -1;
        }
    }

    // Use float buffers for lossy encoding
    float *buffer = (float *)malloc(BUFFER_FRAMES * inputInfo.channels * sizeof(float));
    if (buffer == NULL) {
        sf_close(outFile);
        sf_close(inFile);
        return -1;
    }

    sf_count_t readCount;
    int result = 0;

    while ((readCount = sf_readf_float(inFile, buffer, BUFFER_FRAMES)) > 0) {
        if (sf_writef_float(outFile, buffer, readCount) != readCount) {
            result = -1;
            break;
        }
    }

    free(buffer);

    return finishConversion(inFile, outFile, result);
}

- (int)fileInfo:(NSString *)path
     sampleRate:(int *)sampleRate
       channels:(int *)channels
       bitDepth:(int *)bitDepth
{
    SF_INFO info;
    memset(&info, 0, sizeof(info));

    SNDFILE *file = sf_open(path.UTF8String, SFM_READ, &info);
    if (file == NULL) {
        return -1;
    }

    *sampleRate = info.samplerate;
    *channels = info.channels;

    int sub = info.format & SF_FORMAT_SUBMASK;
    if (sub == SF_FORMAT_PCM_S8) {
        *bitDepth = 8;
    } else if (sub == SF_FORMAT_PCM_16) {
        *bitDepth = 16;
    } else if (sub == SF_FORMAT_PCM_24) {
        *bitDepth = 24;
    } else if (sub == SF_FORMAT_PCM_32) {
        *bitDepth = 32;
    } else {
        *bitDepth = 0;
    }

    sf_close(file);
    return 0;
}

@end
