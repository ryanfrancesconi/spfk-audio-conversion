// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

#import "SndFileReader.h"
#import <sndfile/sndfile.h>

@implementation SndFileReader {
    SNDFILE *_file;
}

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    SF_INFO info;
    memset(&info, 0, sizeof(info));

    _file = sf_open(path.fileSystemRepresentation, SFM_READ, &info);

    if (_file == NULL) {
        if (error != NULL) {
            NSString *reason = [NSString stringWithUTF8String:sf_strerror(NULL)] ?: @"unknown error";
            *error = [NSError errorWithDomain:@"SndFileReader"
                                         code:sf_error(NULL)
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"libsndfile could not open %@: %@",
                                                      path.lastPathComponent, reason] }];
        }
        return nil;
    }

    _sampleRate = info.samplerate;
    _channelCount = info.channels;
    _frameCount = info.frames;

    return self;
}

- (void)dealloc {
    if (_file != NULL) {
        sf_close(_file);
    }
}

- (int64_t)readFloat:(float *)buffer frames:(int64_t)frames {
    sf_count_t read = sf_readf_float(_file, buffer, frames);

    if (read == 0 && sf_error(_file) != SF_ERR_NO_ERROR) {
        return -1;
    }

    return read;
}

- (BOOL)seekToFrame:(int64_t)frame {
    return sf_seek(_file, frame, SEEK_SET) == frame;
}

@end
