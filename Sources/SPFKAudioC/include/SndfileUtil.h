// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/SPFKAudio

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

///  Obj C wrapper for libsox based calls. Please note that SoX isn't suitable for concurrency and
///  this API is designed to be used via the SoX object in Swift.
@interface SndfileUtil : NSObject

- (int)demux:(NSString *)input
      output:(NSString *)output
     channel:(NSString *)channel;


@end

NS_ASSUME_NONNULL_END
