//
//  SBLArchiveExtractor.h
//  Cyanide
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SBLExtractArchiveToDirectory(NSURL *url, NSString *destination, NSError **error);

NS_ASSUME_NONNULL_END
