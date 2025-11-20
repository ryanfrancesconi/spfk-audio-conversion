// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import "sndfile.h"
#import "sox.h"
#import "SoxWrapper.h"

@implementation SoxWrapper

char *_sox = "sox";

- (int)createMultiChannelWave:(NSArray *)inputs
                       output:(NSString *)output {
    int count = 2;

    // sox -M chan1.wav chan2.wav chan3.wav chan4.wav chan5.wav multi.wav
    char *argv[2 + inputs.count + 1];

    argv[0] = _sox;
    argv[1] = (char *)"-M";

    // add each input path
    for (id object in inputs) {
        NSString *value = (NSString *)object;

        argv[count++] = (char *)value.UTF8String;
    }

    // then the file to create
    argv[count++] = (char *)output.UTF8String;

    return sox_main(count, argv);
}

- (int)convert:(NSString *)input
        output:(NSString *)output
          bits:(NSString *)bits
    sampleRate:(NSString *)sampleRate
{
    char *argv[7];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)"-b";
    argv[3] = (char *)bits.UTF8String;
    argv[4] = (char *)"-r";
    argv[5] = (char *)sampleRate.UTF8String;
    argv[6] = (char *)output.UTF8String;
    return sox_main(7, argv);
}

- (int)convert:(NSString *)input
        output:(NSString *)output
          bits:(NSString *)bits
{
    char *argv[5];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)"-b";
    argv[3] = (char *)bits.UTF8String;
    argv[4] = (char *)output.UTF8String;
    return sox_main(5, argv);
}

- (int)convert:(NSString *)input
        output:(NSString *)output
    sampleRate:(NSString *)sampleRate
{
    char *argv[5];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)"-r";
    argv[3] = (char *)sampleRate.UTF8String;
    argv[4] = (char *)output.UTF8String;
    return sox_main(5, argv);
}

- (int)convert:(NSString *)input
        output:(NSString *)output
{
    char *argv[3];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)output.UTF8String;
    return sox_main(3, argv);
}

- (int)convert:(NSString *)input
        output:(NSString *)output
       bitRate:(NSString *)bitRate
    sampleRate:(NSString *)sampleRate
{
    char *argv[7];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)"-C";
    argv[3] = (char *)bitRate.UTF8String;
    argv[4] = (char *)"-r";
    argv[5] = (char *)sampleRate.UTF8String;
    argv[6] = (char *)output.UTF8String;
    return sox_main(7, argv);
}

- (int)convert:(NSString *)input
        output:(NSString *)output
       bitRate:(NSString *)bitRate
{
    char *argv[5];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)"-C";
    argv[3] = (char *)bitRate.UTF8String;
    argv[4] = (char *)output.UTF8String;
    return sox_main(5, argv);
}

- (int)remix:(NSString *)input
      output:(NSString *)output
     channel:(NSString *)channel
{
    char *argv[5];

    argv[0] = _sox;
    argv[1] = (char *)input.UTF8String;
    argv[2] = (char *)output.UTF8String;
    argv[3] = (char *)"remix";
    argv[4] = (char *)channel.UTF8String;
    return sox_main(5, argv);
}

- (int)remix2:(NSString *)input
       output:(NSString *)output
      channel:(NSString *)channel {
    /* All libSoX applications must start by initialising the SoX library */
    if (sox_init() != SOX_SUCCESS) {
        // error
        return;
    }

    sox_format_t *soxInput, *soxOutput = NULL;
    sox_effects_chain_t *chain;
    sox_effect_t *e;
    sox_signalinfo_t interm_signal;
    char *args[10];

    soxInput = sox_open_read(input.UTF8String, NULL, NULL, NULL);
    interm_signal = soxInput->signal; /* NB: deep copy */

    sox_encodinginfo_t out_encoding = soxInput->encoding;

    sox_signalinfo_t out_signal = {
        interm_signal.rate,
        1, // mono
        0,
        0,
        NULL
    };

    soxOutput = sox_open_write(
        output.UTF8String,
        &out_signal,
        &out_encoding,
        NULL,
        NULL,
        NULL
        );

    chain = sox_create_effects_chain(&soxInput->encoding, &soxInput->encoding);

    /* The first effect in the effect chain must be something that can source
     * samples; in this case, we use the built-in handler that inputs
     * data from an audio file */
    e = sox_create_effect(sox_find_effect("input"));
    args[0] = (char *)soxInput;
    sox_effect_options(e, 1, args);
    sox_add_effect(chain, e, &interm_signal, &soxInput->signal);
    free(e);

    e = sox_create_effect(sox_find_effect("remix"));
    args[0] = (char *)channel.UTF8String;
    sox_effect_options(e, 1, args);
    sox_add_effect(chain, e, &interm_signal, &out_signal);
    free(e);

    e = sox_create_effect(sox_find_effect("channels"));
    sox_effect_options(e, 0, NULL);
    sox_add_effect(chain, e, &interm_signal, &out_signal);
    free(e);

    /* The last effect in the effect chain must be something that only consumes
     * samples; in this case, we use the built-in handler that outputs
     * data to an audio file */
    e = sox_create_effect(sox_find_effect("output"));
    args[0] = (char *)soxOutput;
    sox_effect_options(e, 1, args);
    sox_add_effect(chain, e, &interm_signal, &out_signal);
    free(e);

    sox_flow_effects(chain, NULL, NULL);
    sox_delete_effects_chain(chain);
    sox_close(soxOutput);
    sox_close(soxInput);
    sox_quit();
}

- (int)  trim:(NSString *)input
       output:(NSString *)output
    startTime:(NSString *)startTime
      endTime:(NSString *)endTime {
    /* All libSoX applications must start by initialising the SoX library */
    if (sox_init() != SOX_SUCCESS) {
        sox_error(1);
        return;
    }

    sox_format_t *soxInput, *soxOutput = NULL;
    sox_effects_chain_t *chain;
    sox_effect_t *e;

    char *args[10];

    soxInput = sox_open_read(input.UTF8String, NULL, NULL, NULL);

    if (soxInput == NULL) {
        sox_quit();
        return;
    }

    sox_signalinfo_t interm_signal = soxInput->signal; /* NB: deep copy */
    sox_encodinginfo_t out_encoding = soxInput->encoding;
    sox_signalinfo_t out_signal = soxInput->signal;

    soxOutput = sox_open_write(output.UTF8String,
                               &out_signal,
                               &out_encoding, NULL, NULL, NULL);

    chain = sox_create_effects_chain(&soxInput->encoding, &soxInput->encoding);

    /* The first effect in the effect chain must be something that can source
     * samples; in this case, we use the built-in handler that inputs
     * data from an audio file */
    e = sox_create_effect(sox_find_effect("input"));
    args[0] = (char *)soxInput;
    sox_effect_options(e, 1, args);
    sox_add_effect(chain, e, &interm_signal, &soxInput->signal);
    free(e);

    e = sox_create_effect(sox_find_effect("trim"));

    int argc = 1;
    args[0] = (char *)startTime.UTF8String;

    if (![endTime isEqualToString:@"0"]) {
        args[1] = (char *)endTime.UTF8String;
        argc = 2;
    }

    sox_effect_options(e, argc, args);
    sox_add_effect(chain, e, &interm_signal, &out_signal);
    free(e);

    // add very fast fade to eliminate clicks
    // TODO: allow for trim fade time to be passed in
    args[0] = "h";
    args[1] = "0.01";
    args[2] = "0";
    args[3] = "0.01";
    e = sox_create_effect(sox_find_effect("fade"));
    sox_effect_options(e, 4, args);
    sox_add_effect(chain, e, &interm_signal, &out_signal);
    free(e);

    /* The last effect in the effect chain must be something that only consumes
     * samples; in this case, we use the built-in handler that outputs
     * data to an audio file */
    e = sox_create_effect(sox_find_effect("output"));
    args[0] = (char *)soxOutput;
    sox_effect_options(e, 1, args);
    sox_add_effect(chain, e, &interm_signal, &out_signal);
    free(e);

    sox_flow_effects(chain, NULL, NULL);
    sox_delete_effects_chain(chain);
    sox_close(soxOutput);
    sox_close(soxInput);

    sox_quit();
}

@end
