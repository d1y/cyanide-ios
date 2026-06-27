//
//  QuickLoaderConfigViewController.h
//  Cyanide
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QuickLoaderConfigViewController : UIViewController

- (instancetype)initWithRawScript:(NSString *)rawScript
                       displayName:(NSString *)displayName
                            values:(NSMutableDictionary<NSString *, NSString *> *)values
                           repoURL:(nullable NSString *)repoURL
                          tweakID:(nullable NSString *)tweakID;

@property (nonatomic, copy, nullable) void (^dismissHandler)(void);

@end

NS_ASSUME_NONNULL_END
