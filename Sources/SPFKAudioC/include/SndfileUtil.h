// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SndfileUtil : NSObject

+ (int)demux:(NSString *)input
      output:(NSString *)output
     channel:(NSString *)channel;

@end

NS_ASSUME_NONNULL_END
