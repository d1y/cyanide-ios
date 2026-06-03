//
//  PackageCatalog.m
//  Cyanide
//

#import "PackageCatalog.h"
#import "../SettingsViewController.h"

@implementation PackageCatalog

// Mirrors of the private SettingsSection enum values in SettingsViewController.m
// (kept in sync — must match the underlying section indices used for the
// detail-mode SettingsViewController push).
static const NSInteger kSecSBC          = 4;
static const NSInteger kSecStatBar      = 5;
static const NSInteger kSecNSBar        = 6;
static const NSInteger kSecNiceBarLite  = 7;
static const NSInteger kSecRSSI         = 8;
static const NSInteger kSecPowercuff    = 11;
static const NSInteger kSecLayoutExtras = 13;
static const NSInteger kSecNanoRegistry = 14;
static const NSInteger kSecThemer       = 15;
static const NSInteger kSecSnowBoardLite = 16;
static const NSInteger kSecLiveWP       = 17;
static const NSInteger kSecGravityLite  = 18;
static const NSInteger kSecDragCoefficient = 19;

+ (NSArray<Package *> *)allPackages
{
    NSArray<Package *> *full = [self allPackagesIncludingExperimental];
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled];
    if (experimentalOn) return full;

    NSMutableArray<Package *> *out = [NSMutableArray arrayWithCapacity:full.count];
    for (Package *p in full) {
        if (p.experimental) continue;
        [out addObject:p];
    }
    return out;
}

+ (NSArray<Package *> *)allPackagesIncludingExperimental
{
    static NSArray<Package *> *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *version = @"1.0";

        Package *statBar = [[Package alloc] initWithIdentifier:@"com.darksword.statbar"
                                           name:@"StatBar"
                               shortDescription:@"Battery temperature + free RAM overlay"
                                longDescription:@"Installs an overlay window in SpringBoard that shows live battery temperature and free RAM next to the system status bar. Refresh timing is adjustable so you can trade live updates for battery life.\n\nConfigure units, visible metrics, and refresh speed in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Status Bar"
                                     symbolName:@"thermometer.medium"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsStatBarEnabled
                                          isNew:NO];
        statBar.settingsSection = kSecStatBar;

        Package *nsBar = [[Package alloc] initWithIdentifier:@"com.darksword.nsbar"
                                           name:@"NSBar"
                               shortDescription:@"Network speed overlay in status bar area"
                                longDescription:@"Displays real-time network speed (download/upload) in a compact overlay window positioned in the status bar area. Choose from 4 positions: top-left, bottom-left, top-right, or bottom-right.\n\nRefreshes about once per second while the RemoteCall session is alive. Configure position in the Settings tab."
                                        version:version
                                         author:@"d1y"
                                       category:@"Other Tweaks"
                                     symbolName:@"network"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNSBarEnabled
                                          isNew:YES];
        nsBar.settingsSection = kSecNSBar;

        Package *niceBarLite = [[Package alloc] initWithIdentifier:@"com.darksword.nicebarlite"
                                           name:@"NiceBar Lite"
                               shortDescription:@"NiceBar-style four-corner status labels"
                                longDescription:@"A lightweight NiceBar port for Cyanide. It places plain text labels in the four status-bar corner slots: top-left, top-right, bottom-left, and bottom-right.\n\nEach slot can show custom text, device stats such as battery temperature, free RAM, battery percent, network speed, uptime, date or lunar date, a custom time format, or user-provided weather text. Labels do not draw a black pill background; they use status-bar-style text coloring and refresh about once per second while the RemoteCall session is alive."
                                        version:version
                                         author:@"d1y"
                                       category:@"Other Tweaks"
                                     symbolName:@"textformat.size"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsNiceBarLiteEnabled
                                          isNew:YES];
        niceBarLite.settingsSection = kSecNiceBarLite;

        Package *signal = [[Package alloc] initWithIdentifier:@"com.darksword.rssidisplay"
                                           name:@"Signal Readouts"
                               shortDescription:@"RSRP dBm on cellular, bar count on WiFi"
                                longDescription:@"Replaces the signal-strength glyphs in the status bar with live numeric readouts: RSRP in dBm for cellular, and the active bar count for WiFi. Updates roughly once per second.\n\nToggle WiFi-only or cellular-only in the Settings tab.\n\nIn development: the live RemoteCall refresh interferes with other SpringBoard tweaks and the readouts may not even render reliably. Only available while Experimental Tweaks is enabled in Settings."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"antenna.radiowaves.left.and.right"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsRSSIDisplayEnabled
                                          isNew:NO];
        signal.settingsSection = kSecRSSI;
        signal.experimental = YES;
        signal.unstableWarning = @"⚠️ Experimental: in-development and may not work at all. The live status-bar refresh interferes with other SpringBoard tweaks and can drop readouts entirely. Turning this on adds risk with no guaranteed feature in return.";

        Package *sbc = [[Package alloc] initWithIdentifier:@"com.darksword.sbcustomizer"
                                           name:@"SBCustomizer"
                               shortDescription:@"Custom dock count and home screen grid"
                                longDescription:@"Customizes the dock icon count and the home screen icon grid (columns and rows). Optionally hides icon labels.\n\nAdjust the per-axis counts and the label-hide switch in the Settings tab."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Home Screen Layout"
                                     symbolName:@"square.grid.3x3.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSBCEnabled
                                          isNew:NO];
        sbc.settingsSection = kSecSBC;

        Package *powercuff = [[Package alloc] initWithIdentifier:@"com.darksword.powercuff"
                                           name:@"Powercuff"
                               shortDescription:@"Underclock the CPU/GPU thermal pressure"
                                longDescription:@"Drives thermalmonitord with synthetic thermal pressure to underclock the CPU and GPU. Useful for cooling-sensitive workloads or extending runtime under load. Effects persist until reboot.\n\nNominal is the daily-use default. Light, Moderate, and Heavy intentionally underclock the CPU more, so lag and slower app launches mean it is working as intended. Those levels can be too slow for comfortable day-to-day use, especially on older devices.\n\nPick a level in the Settings tab."
                                        version:version
                                         author:@"rpetrich"
                                       category:@"Performance"
                                     symbolName:@"bolt.slash.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsPowercuffEnabled
                                          isNew:NO];
        powercuff.settingsSection = kSecPowercuff;

        Package *axon = [[Package alloc] initWithIdentifier:@"com.darksword.axonlite"
                                           name:@"Axon Lite"
                               shortDescription:@"Group Notification Center requests by app"
                                longDescription:@"Groups visible Notification Center requests by app in a SpringBoard overlay and filters duplicates while Cyanide keeps the RemoteCall session alive.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"bell.badge.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAxonLiteEnabled
                                          isNew:YES];
        axon.unstableWarning = @"⚠️ Experimental: work-in-progress. Expect SpringBoard crashes, dropped notifications, layout glitches, and breakage between Cyanide builds. Don't rely on it for anything important.";

        Package *typeBanner = [[Package alloc] initWithIdentifier:@"com.darksword.typebanner"
                                           name:@"TypeBanner"
                               shortDescription:@"iMessage typing banner under the Dynamic Island"
                                longDescription:@"Port of TypeMillennium. Shows a pill banner just below the Dynamic Island whenever the active Messages conversation list shows a typing indicator.\n\nv1 limitation: detection runs against the Messages app's own view hierarchy via RemoteCall, so it only fires while Messages.app is running. The original tweak's system-wide imagent hook requires code injection, which is not available in this sandboxed environment without a code-signing bypass.\n\nNo extra configuration."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Experimental"
                                     symbolName:@"ellipsis.bubble.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsTypeBannerEnabled
                                          isNew:YES];
        typeBanner.experimental = YES;
        typeBanner.unstableWarning = @"⚠️ Experimental: extremely unstable and risky. Polls MobileSMS over RemoteCall every ~1.5s, opens SpringBoard sessions on state change, and is known to crash SpringBoard. Detection only fires while Messages.app is running. Battery cost is non-trivial.";

        Package *themer = [[Package alloc] initWithIdentifier:@"com.darksword.themer"
                                           name:@"Cyanide Themer"
                               shortDescription:@"Per-bundle icon theme engine"
                                longDescription:@"Replaces stock app icons by walking SpringBoard's SBIconView hierarchy and swapping each icon's image with a PNG matched on the app's bundle identifier.\n\nPick a theme in Settings > Cyanide Themer. Cyanide ships with iOS 6 Theme, using icons from zagnut531/iOS-6-Icons: https://github.com/zagnut531/iOS-6-Icons. You can also import a custom folder of <bundleID>.png files or a binary plist mapping bundle IDs to PNG data.\n\nApplied at Run; not persisted across respring. The current build also seeds SpringBoard's icon cache and rounds imported PNGs before upload so icons survive common home-screen relayouts more cleanly."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"paintpalette.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsThemerEnabled
                                          isNew:YES];
        themer.experimental = NO;
        themer.settingsSection = kSecThemer;
        themer.unstableWarning = @"⚠️ Beta: icon theming works but RemoteCall-backed changes may need re-applying after a respring or SpringBoard restart. Pick a theme in Settings > Cyanide Themer before running.";

        Package *snowboardLite = [[Package alloc] initWithIdentifier:@"com.darksword.snowboardlite"
                                           name:@"SnowBoard Lite"
                               shortDescription:@"Local SnowBoard-style icon theme library"
                                longDescription:@"Imports icon themes into a local library and lets you switch the active theme from a native iOS-style settings page.\n\nThis is separate from Cyanide Themer. Current scope is intentionally lightweight: bundled iOS 6 Theme, local folder/.zip/.deb imports, and direct archive URL imports recursively scan IconBundles directories and convert PNG assets into Cyanide's existing icon replacement pipeline. Full SnowBoard parity, masks, overlays, UIImages, badges, docks, and folders are out of scope for the first milestone."
                                        version:version
                                         author:@"d1y"
                                       category:@"Other Tweaks"
                                     symbolName:@"square.stack.3d.up.fill"
                                          kind:PackageInstallKindToggle
                                     enabledKey:kSettingsSnowBoardLiteEnabled
                                          isNew:YES];
        snowboardLite.settingsSection = kSecSnowBoardLite;
        snowboardLite.unstableWarning = @"⚠️ Preview: import and select a SnowBoard Lite theme before queuing or applying.";

        Package *liveWP = [[Package alloc] initWithIdentifier:@"com.darksword.livewp"
                                           name:@"LiveWP"
                               shortDescription:@"Video wallpaper for lock screen and home screen"
                                longDescription:@"Plays a user-selected video file as a dynamic wallpaper behind the lock screen and home screen. Uses AVPlayer in a low-level UIWindow (windowLevel -1) to display the video continuously.\n\nSupports MP4, MOV, and M4V formats. Select a video file in Settings > LiveWP, then enable the toggle and hit Apply Tweaks. The video loops automatically and persists until you disable the tweak or respring.\n\nApplied at Run; not persisted across respring. Large video files (>100MB) may impact performance."
                                        version:version
                                         author:@"d1y"
                                       category:@"Other Tweaks"
                                     symbolName:@"play.rectangle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLiveWPEnabled
                                          isNew:YES];
        liveWP.settingsSection = kSecLiveWP;

        Package *gravityLite = [[Package alloc] initWithIdentifier:@"com.darksword.gravitylite"
                                           name:@"Gravity Lite"
                               shortDescription:@"Tilt-driven icon physics"
                                longDescription:@"RemoteCall-only port of Julio Verne's classic Gravity tweak. It captures the visible SpringBoard icon views, replaces them with physics snapshots, and applies UIDynamicAnimator gravity, collision, bounce, friction, resistance, optional dock physics, tilt steering, restore, and an explosion pulse.\n\nThis is not a full Substrate-style port. Activator/Home-button hooks, drag gestures, and preference-daemon notifications are intentionally left out. Use Settings to tune the core physics and Restore Icon Layout to reset."
                                        version:version
                                         author:@"Julio Verne / zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"arrow.down.circle.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsGravityLiteEnabled
                                          isNew:YES];
        gravityLite.settingsSection = kSecGravityLite;
        gravityLite.unstableWarning = @"⚠️ Beta: RemoteCall-only physics can be reset by SpringBoard relayouts such as page swipes, folder transitions, or resprings. Use Restore Icon Layout if icons stay displaced.";
        gravityLite.knownIssues = @[
            @"To start cleanly, enable Keep Alive, apply Gravity Lite, then leave Cyanide so SpringBoard remains visible.",
            @"Page swipes, folder opens, rotation, or SpringBoard relayouts may stop the effect. Run Gravity Lite again.",
        ];

        Package *layoutExtras = [[Package alloc] initWithIdentifier:@"com.darksword.layoutextras"
                                           name:@"Home Layout Extras"
                               shortDescription:@"Extra home/dock padding and per-icon scaling"
                                longDescription:@"Adds extra padding around the home grid and the dock, and scales icons up or down. Stacks on top of SBCustomizer.\n\nDial in left/right/top/bottom padding for the home screen, horizontal padding for the dock, and home/dock icon scale in the Settings tab. Defaults match stock (zero padding, 100% scale).\n\nApplied at Run; not persisted across respring.\n\niOS 18: mutates the SBIconController layout configuration directly (upstream kolbicz path).\niOS 26: walks the live SBIconListView/SBIconView hierarchy and adjusts frames + iconImageInfo per icon (the iOS 26 layout class is read-only). One-shot at Run on iOS 26 — rotation/page swipe may force iOS 26's auto-layout to re-fit, so re-Run if that happens."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"Home Screen Layout"
                                     symbolName:@"square.dashed.inset.filled"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsLayoutExtrasEnabled
                                          isNew:YES];
        layoutExtras.settingsSection = kSecLayoutExtras;
        NSInteger iosMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        if (iosMajor >= 26) {
            layoutExtras.knownIssues = @[
                @"iOS 26: layout may reset after rotation or page swipe. Re-run to reapply.",
            ];
        }

        Package *nanoRegistry = [[Package alloc] initWithIdentifier:@"com.darksword.nanoregistry"
                                           name:@"Watch Pairing Override"
                               shortDescription:@"Pair a newer watch or revive an older one"
                                longDescription:@"Changes the watchOS pairing range saved on this iPhone.\n\nMost people should use watchOS Range 99/23/10/6 in Settings, then apply the override. These are pairing protocol generations, not Apple Watch model numbers. 99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. 10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\nApple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\nRespring or reboot after installing or removing the override before trying to pair."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Beta"
                                     symbolName:@"applewatch.radiowaves.left.and.right"
                                           kind:PackageInstallKindNanoRegistry
                                     enabledKey:nil
                                          isNew:YES];
        nanoRegistry.settingsSection = kSecNanoRegistry;

        list = @[
            statBar,
            nsBar,
            niceBarLite,
            sbc,
            layoutExtras,
            powercuff,

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-app-library"
                                           name:@"Disable App Library"
                               shortDescription:@"Remove the App Library page"
                                longDescription:@"Removes the App Library page that sits past your last home-screen page. Swiping past the last page becomes a no-op."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableAppLibrary
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-icon-flyin"
                                           name:@"Disable Icon Fly-In"
                               shortDescription:@"Skip the icon spring animation"
                                longDescription:@"Skips the spring animation that plays when home screen icons appear after unlock or app switch. Icons just appear in their final position."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"sparkles"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableIconFlyIn
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-wake-animation"
                                           name:@"Zero Wake Animation"
                               shortDescription:@"Snap on instantly when waking"
                                longDescription:@"Removes the fade-in animation when waking the display. The screen pops on at full brightness immediately."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"moon.zzz.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroWakeAnimation
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.zero-backlight-fade"
                                           name:@"Zero Backlight Fade"
                               shortDescription:@"Instant lock/unlock backlight"
                                longDescription:@"Cuts the backlight fade duration to zero so the display switches on or off instantly on lock and unlock."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"sun.max.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSZeroBacklightFade
                                          isNew:NO],

            [[Package alloc] initWithIdentifier:@"com.darksword.double-tap-to-lock"
                                           name:@"Double-Tap to Lock"
                               shortDescription:@"Lock with a wallpaper double-tap"
                                longDescription:@"Double-tap an empty area of the wallpaper to lock the device. No more reaching for the side button."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard Tweaks"
                                     symbolName:@"hand.tap.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDoubleTapToLock
                                          isNew:NO],

            ({
                Package *drag = [[Package alloc] initWithIdentifier:@"com.darksword.drag-coefficient"
                                                               name:@"Drag Coefficient"
                                                   shortDescription:@"Custom SpringBoard animation speed multiplier"
                                                    longDescription:@"Overrides _UIAnimationDragCoefficient in SpringBoard to make UIKit animations faster or slower.\n\nSet the coefficient in Settings > Drag Coefficient. 50% = 0.5x coefficient (about 2x faster), 25% = 0.25x coefficient (about 4x faster), 100% = stock.\n\nImported from kolbicz/DarkSword-Tweaks."
                                                            version:version
                                                             author:@"kolbicz"
                                                           category:@"SpringBoard Tweaks"
                                                         symbolName:@"dial.medium.fill"
                                                               kind:PackageInstallKindToggle
                                                         enabledKey:kSettingsDSDragCoefficientEnabled
                                                              isNew:YES];
                drag.settingsSection = kSecDragCoefficient;
                drag;
            }),

            [[Package alloc] initWithIdentifier:@"com.darksword.ota-block"
                                           name:@"OTA Updates"
                               shortDescription:@"Enable or disable over-the-air system updates"
                                longDescription:@"Disables or enables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots.\n\nNo Run/Apply step required for this package. Use Disable to block OTA updates, or Enable to restore them."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"System Updates"
                                     symbolName:@"icloud.slash.fill"
                                           kind:PackageInstallKindOTA
                                     enabledKey:nil
                                          isNew:NO],

            // Beta last so the warning sits at the bottom of the Installer.
            signal,
            axon,
            nanoRegistry,
            typeBanner,
            themer,
            snowboardLite,
            liveWP,
            gravityLite,
        ];
    });
    return list;
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSArray<NSString *> *preferred = @[
        @"Experimental",
        @"Beta",
        @"Status Bar",
        @"Home Screen Layout",
        @"Performance",
        @"System Updates",
        @"System",
        @"SpringBoard Tweaks",
        @"Other Tweaks",
    ];
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    for (Package *p in [self allPackages]) {
        if (![all containsObject:p.category]) [all addObject:p.category];
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (NSString *cat in preferred) {
        if ([all containsObject:cat]) [order addObject:cat];
    }
    for (NSString *cat in all) {
        if (![order containsObject:cat]) [order addObject:cat];
    }
    return order;
}

+ (NSDictionary<NSString *, NSArray<Package *> *> *)packagesByCategory
{
    NSMutableDictionary<NSString *, NSMutableArray<Package *> *> *buckets = [NSMutableDictionary dictionary];
    for (Package *p in [self allPackages]) {
        NSMutableArray<Package *> *bucket = buckets[p.category];
        if (!bucket) {
            bucket = [NSMutableArray array];
            buckets[p.category] = bucket;
        }
        [bucket addObject:p];
    }
    return buckets;
}

@end
