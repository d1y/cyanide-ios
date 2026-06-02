//
//  map_app.h
//  Cyanide
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Maps SnowBoard/IconBundles file names, common aliases, and Android package
// names to iOS bundle identifiers. Returns nil when the name cannot resolve.
NSString *_Nullable CNDMappedIOSBundleIDForIconName(NSString *name,
                                                    BOOL *_Nullable usedAlias);

NS_ASSUME_NONNULL_END
