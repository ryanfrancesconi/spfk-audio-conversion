// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

#import "LameConverter.h"
#import <sndfile/sndfile.h>
#import <lame/lame.h>

#define BUFFER_FRAMES 8192

// MP3 buffer needs to be large enough: worst case is 1.25 * num_samples + 7200
#define MP3_BUFFER_SIZE (int)(1.25 * BUFFER_FRAMES + 7200)

@implementation LameConverter

- (int)convertToMP3:(NSString *)input
             output:(NSString *)output
            bitRate:(int)bitRate
            quality:(int)quality
{
    // Open input with libsndfile
    SF_INFO inputInfo;
    memset(&inputInfo, 0, sizeof(inputInfo));

    SNDFILE *inFile = sf_open(input.UTF8String, SFM_READ, &inputInfo);
    if (inFile == NULL) {
        return -1;
    }

    int channels = inputInfo.channels;

    if (channels > 2) {
        sf_close(inFile);
        return -1;
    }

    // Initialize LAME encoder
    lame_global_flags *lame = lame_init();
    if (lame == NULL) {
        sf_close(inFile);
        return -1;
    }

    lame_set_num_channels(lame, channels);
    lame_set_in_samplerate(lame, inputInfo.samplerate);
    lame_set_mode(lame, channels == 1 ? MONO : JOINT_STEREO);

    if (bitRate > 0) {
        lame_set_brate(lame, bitRate);
        lame_set_VBR(lame, vbr_off);
    } else {
        // VBR mode — quality 4 is default VBR size
        lame_set_VBR(lame, vbr_mtrh);
        lame_set_VBR_quality(lame, 4.0f);
    }

    lame_set_quality(lame, quality);

    if (lame_init_params(lame) < 0) {
        lame_close(lame);
        sf_close(inFile);
        return -1;
    }

    // Open output MP3 file
    FILE *mp3File = fopen(output.UTF8String, "wb");
    if (mp3File == NULL) {
        lame_close(lame);
        sf_close(inFile);
        return -1;
    }

    // Allocate buffers
    int totalSamples = BUFFER_FRAMES * channels;
    float *pcmBuffer = (float *)malloc(totalSamples * sizeof(float));
    unsigned char *mp3Buffer = (unsigned char *)malloc(MP3_BUFFER_SIZE);

    if (pcmBuffer == NULL || mp3Buffer == NULL) {
        free(pcmBuffer);
        free(mp3Buffer);
        fclose(mp3File);
        lame_close(lame);
        sf_close(inFile);
        return -1;
    }

    int result = 0;
    sf_count_t readCount;

    while ((readCount = sf_readf_float(inFile, pcmBuffer, BUFFER_FRAMES)) > 0) {
        int mp3Bytes;

        if (channels == 1) {
            mp3Bytes = lame_encode_buffer_ieee_float(
                lame,
                pcmBuffer,    // left channel
                NULL,         // right channel (NULL for mono)
                (int)readCount,
                mp3Buffer,
                MP3_BUFFER_SIZE
            );
        } else {
            mp3Bytes = lame_encode_buffer_interleaved_ieee_float(
                lame,
                pcmBuffer,
                (int)readCount,
                mp3Buffer,
                MP3_BUFFER_SIZE
            );
        }

        if (mp3Bytes < 0) {
            result = -1;
            break;
        }

        if (mp3Bytes > 0) {
            fwrite(mp3Buffer, 1, mp3Bytes, mp3File);
        }
    }

    // Flush remaining MP3 data
    if (result == 0) {
        int flushBytes = lame_encode_flush(lame, mp3Buffer, MP3_BUFFER_SIZE);
        if (flushBytes > 0) {
            fwrite(mp3Buffer, 1, flushBytes, mp3File);
        }

        // Write VBR/Xing header for accurate seeking
        lame_mp3_tags_fid(lame, mp3File);
    }

    free(pcmBuffer);
    free(mp3Buffer);
    fclose(mp3File);
    lame_close(lame);
    sf_close(inFile);

    return result;
}

@end
