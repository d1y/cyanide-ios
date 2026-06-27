//
//  PackageCatalog.m
//  Cyanide
//

#import "PackageCatalog.h"
#import "../SettingsViewController.h"
#import "../tweaks/RepoTweaks.h"

@interface Package ()
@property (nonatomic, readwrite, copy) NSString *symbolName;
@property (nonatomic, readwrite, copy) NSString *author;
@end

@implementation PackageCatalog

static NSString *catalog_string_or_empty(id value)
{
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSArray<NSString *> *catalog_repotweaks_urls(NSUserDefaults *d)
{
    id raw = [d objectForKey:@"RepoTweaksURLs"];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    for (id value in (NSArray *)raw) {
        if ([value isKindOfClass:NSString.class]) [urls addObject:value];
    }
    return urls;
}

static NSDictionary *catalog_repotweaks_caches(NSUserDefaults *d)
{
    id raw = [d objectForKey:@"RepoTweaksCaches"];
    return [raw isKindOfClass:NSDictionary.class] ? (NSDictionary *)raw : @{};
}

static BOOL catalog_repo_script_requires_native_bridge(NSString *rawScript)
{
    if (![rawScript isKindOfClass:NSString.class] || rawScript.length == 0) return NO;
    return [rawScript containsString:@"nativeCallBuff"] ||
           [rawScript containsString:@"runOnMainEvaluate"] ||
           [rawScript containsString:@"Native.callSymbol"];
}

+ (NSArray<Package *> *)repoPackages
{
    repotweaks_seed_default_repos();

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *caches = catalog_repotweaks_caches(d);
    NSMutableArray<Package *> *packages = [NSMutableArray array];

    for (NSString *url in catalog_repotweaks_urls(d)) {
        id repoRaw = caches[url];
        if (![repoRaw isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *repo = (NSDictionary *)repoRaw;
        NSString *repoName = catalog_string_or_empty(repo[@"repoName"]);
        NSString *author = catalog_string_or_empty(repo[@"author"]);
        id tweaksRaw = repo[@"tweaks"];
        if (![tweaksRaw isKindOfClass:NSArray.class]) continue;

        for (id tweakRaw in (NSArray *)tweaksRaw) {
            if (![tweakRaw isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *tweak = (NSDictionary *)tweakRaw;
            NSString *tweakID = catalog_string_or_empty(tweak[@"id"]);
            NSString *name = catalog_string_or_empty(tweak[@"name"]);
            NSString *scriptURL = catalog_string_or_empty(tweak[@"scriptURL"]);
            if (tweakID.length == 0 || name.length == 0 || scriptURL.length == 0) continue;

            NSString *identifier = [NSString stringWithFormat:@"repo.%@", repotweaks_storage_key(url, tweakID)];
            Package *pkg = [[Package alloc] initRepoTweakWithIdentifier:identifier
                                                                   name:name
                                                       shortDescription:catalog_string_or_empty(tweak[@"description"])
                                                                version:catalog_string_or_empty(tweak[@"version"])
                                                                 author:author
                                                               repoName:repoName
                                                                repoURL:url
                                                            repoTweakID:tweakID
                                                           repoScriptURL:scriptURL];
            NSString *symbol = catalog_string_or_empty(tweak[@"symbol"]);
            if (symbol.length > 0) pkg.symbolName = symbol;
            NSString *tweakAuthor = catalog_string_or_empty(tweak[@"author"]);
            if (tweakAuthor.length > 0) pkg.author = tweakAuthor;
            NSString *rawScript = [d stringForKey:repotweaks_script_defaults_key(url, tweakID)];
            NSString *unsupportedReason = repotweaks_unsupported_reason(tweak);
            if (unsupportedReason.length > 0) {
                pkg.installDisabledReason = unsupportedReason;
                pkg.unstableWarning = unsupportedReason;
            } else if (rawScript.length == 0) {
                pkg.installDisabledReason = @"Refresh this source from the Sources tab before installing.";
            } else if (pkg.repoTweakUsesQuickLoader && catalog_repo_script_requires_native_bridge(rawScript)) {
                pkg.installDisabledReason = @"This repo tweak needs a dedicated Cyanide native backend before it can install.";
            }
            [packages addObject:pkg];
        }
    }

    return [packages sortedArrayUsingComparator:^NSComparisonResult(Package *a, Package *b) {
        return [a.name caseInsensitiveCompare:b.name];
    }];
}

// Mirrors of the private SettingsSection enum values in SettingsViewController.m
// (kept in sync — must match the underlying section indices used for the
// detail-mode SettingsViewController push).
static const NSInteger kSecSBC              = 4;
static const NSInteger kSecStatBar          = 5;
static const NSInteger kSecNSBar            = 6;
static const NSInteger kSecNiceBarLite      = 7;
static const NSInteger kSecRSSI             = 8;
static const NSInteger kSecTypeBanner       = 10;
static const NSInteger kSecPowercuff        = 11;
static const NSInteger kSecLocationSim      = 19;
static const NSInteger kSecDragCoefficient  = 20;
static const NSInteger kSecLayoutExtras     = 13;
static const NSInteger kSecNanoRegistry     = 14;
static const NSInteger kSecSnowBoardLite    = 16;
static const NSInteger kSecLiveWP           = 17;
static const NSInteger kSecGravityLite      = 18;
static const NSInteger kSecAppSwitcherGrid  = 21;
static const NSInteger kSecThemer           = 15;
static const NSInteger kSecQuickLoader      = 22;
static const NSInteger kSecRepoTweaks       = 23;

+ (NSArray<Package *> *)allPackages
{
    NSArray<Package *> *full = [self allPackagesIncludingExperimental];
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled];

    NSMutableArray<Package *> *out = [NSMutableArray arrayWithCapacity:full.count];
    for (Package *p in full) {
        if (p.creatorOnly) continue;
        if (p.experimental && !experimentalOn) continue;
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
                                       category:@"Status Bar"
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
                                       category:@"Status Bar"
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
                                       category:@"In Development"
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
                                       category:@"Home Screen"
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
                                       category:@"System"
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
                                       category:@"SpringBoard"
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
                                       category:@"In Development"
                                     symbolName:@"ellipsis.bubble.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsTypeBannerEnabled
                                          isNew:YES];
        typeBanner.experimental = YES;
        typeBanner.unstableWarning = @"⚠️ Experimental: extremely unstable and risky. Polls MobileSMS over RemoteCall every ~1.5s, opens SpringBoard sessions on state change, and is known to crash SpringBoard. Detection only fires while Messages.app is running. Battery cost is non-trivial.";

        Package *appSwitcherGrid = [[Package alloc] initWithIdentifier:@"com.darksword.appswitchergrid"
                                           name:@"App Switcher Grid"
                               shortDescription:@"Grid-style app switcher for this session"
                                longDescription:@"Applies a runtime-only SpringBoard method patch that makes the App Switcher report the grid/deck style used by SBDeckSwitcherModifier.\n\nThis does not write system files and does not persist across SpringBoard restarts. A respring restores the stock app switcher. The implementation is based on the RemoteCall approach used by rooootdev/lara."
                                        version:version
                                         author:@"rooootdev"
                                       category:@"SpringBoard"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsAppSwitcherGridEnabled
                                          isNew:YES];
        appSwitcherGrid.settingsSection = kSecAppSwitcherGrid;
        appSwitcherGrid.experimental = YES;
        appSwitcherGrid.unstableWarning = @"⚠️ Experimental: patches SpringBoard runtime methods in memory. It should be session-only and respring restores stock, but unsupported builds may glitch the app switcher or crash SpringBoard.";

        Package *themer = [[Package alloc] initWithIdentifier:@"com.darksword.themer"
                                           name:@"Cyanide Themer"
                               shortDescription:@"Per-bundle icon theme engine"
                                longDescription:@"Replaces stock app icons by walking SpringBoard's SBIconView hierarchy and swapping each icon's image with a PNG matched on the app's bundle identifier.\n\nPick a theme in Settings > Cyanide Themer. Cyanide ships with iOS 6 Theme, using icons from zagnut531/iOS-6-Icons: https://github.com/zagnut531/iOS-6-Icons. You can also import a custom folder of <bundleID>.png files or a binary plist mapping bundle IDs to PNG data.\n\nApplied at Run; not persisted across respring. The current build also seeds SpringBoard's icon cache and rounds imported PNGs before upload so icons survive common home-screen relayouts more cleanly."
                                        version:version
                                         author:@"zeroxjf"
                                       category:@"Theming"
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
                                       category:@"Theming"
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
                                       category:@"Theming"
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
                                       category:@"Home Screen"
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
                                       category:@"Home Screen"
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
                                       category:@"System"
                                     symbolName:@"applewatch.radiowaves.left.and.right"
                                           kind:PackageInstallKindNanoRegistry
                                     enabledKey:nil
                                          isNew:YES];
        nanoRegistry.settingsSection = kSecNanoRegistry;
        nanoRegistry.unstableWarning = @"Warning: modifies a local NanoRegistry MobileAsset. Cyanide saves a .cyanide.bak backup beside the original, but system-file edits can fail or require a respring/reboot. Apply or remove this override at your own risk.";

        Package *callRecordingSound = [[Package alloc] initWithIdentifier:@"com.darksword.callrecording-sound"
                                           name:@"Call Recording Sound"
                               shortDescription:@"Silence disclosure start/stop sounds"
                                longDescription:@"Replaces the CallServices StartDisclosureWithTone and StopDisclosure audio files with Cyanide's bundled silent payloads.\n\nCredits: YangJiiii (@duongduong0908) for the EnsWilde and Disable Call Recording BookRestore reference tools. @Little_34306 is credited by the original projects for the Disable Call Recording concept. Cyanide port, KRW-backed implementation, and generated replacement silent audio assets by zeroxjf.\n\nSystem-file warning: this modifies files under /var/mobile/Library/CallServices/Greetings/default. Cyanide backs up the first originals into its app container, but system file replacement can fail, partially apply, or require a respring/reboot to settle.\n\nLegal note: call-recording disclosure sounds may exist to satisfy consent, notification, or privacy-law requirements in some places. You are responsible for understanding and following the laws that apply to you.\n\nThis port does not use the old Books/BookRestore/sparserestore path. Cyanide runs KRW, unlocks local /private/var write access, then writes directly to the CallServices files.\n\nUse Restore Original Sounds to write Cyanide's backups back when present. You apply or restore this tweak at your own risk."
                                        version:version
                                         author:@"YangJiiii (@duongduong0908) / zeroxjf"
                                       category:@"System"
                                     symbolName:@"speaker.slash.fill"
                                           kind:PackageInstallKindCallRecordingSound
                                     enabledKey:nil
                                          isNew:NO];
        callRecordingSound.experimental = NO;
        callRecordingSound.unstableWarning = @"Beta: persistent CallServices system-file replacement. Disclosure sounds may be legally required where you live; you are responsible for your use and apply this at your own risk. Use Restore Original Sounds before removing Cyanide if you want Cyanide's backups written back.";

        Package *hideHomeBar = [[Package alloc] initWithIdentifier:@"com.darksword.hide-home-bar"
                                           name:@"Hide Home Bar"
                               shortDescription:@"Hide the bottom home indicator"
                                longDescription:@"Zeros the first page of /System/Library/PrivateFrameworks/MaterialKit.framework/Assets.car using Cyanide's stable file-page zero path, which hides the bottom home indicator after SpringBoard reloads assets.\n\nRun Hide Home Bar by itself, then respring so SpringBoard refreshes the asset cache. To bring the home indicator back, choose Restore Home Bar and respring again. Other live SpringBoard tweaks, such as App Switcher Grid, should be applied in a separate run after the respring.\n\nCredits: C4ndyF1sh/ZeroCalories for the Home Bar target and jailbreakdotparty/dirtyZero for the original page-zeroing idea. Cyanide port by zeroxjf."
                                        version:version
                                         author:@"C4ndyF1sh / jailbreakdotparty / zeroxjf"
                                       category:@"Home Screen"
                                     symbolName:@"line.3.horizontal"
                                           kind:PackageInstallKindHideHomeBar
                                     enabledKey:nil
                                          isNew:NO];
        hideHomeBar.unstableWarning = @"Beta: system asset page zeroing. Run by itself, then respring after hiding. To restore the home indicator, choose Restore Home Bar and respring.";

        Package *otaBlock = [[Package alloc] initWithIdentifier:@"com.darksword.ota-block"
                                           name:@"OTA Updates"
                               shortDescription:@"Enable or disable over-the-air system updates"
                                longDescription:@"Disables or enables the launchd jobs responsible for over-the-air system updates by editing disabled.plist. State persists across reboots.\n\nSystem-file warning: this edits /private/var/db/com.apple.xpc.launchd/disabled.plist. Incorrect or partial writes can affect launchd job state across boot. You disable or re-enable OTA updates at your own risk.\n\nNo Run/Apply step required for this package. Use Disable to block OTA updates, or Enable to restore them."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"System"
                                     symbolName:@"icloud.slash.fill"
                                          kind:PackageInstallKindOTA
                                    enabledKey:nil
                                         isNew:NO];
        otaBlock.unstableWarning = @"Warning: persistent system-file edit. This package modifies launchd disabled.plist to change OTA job state across reboot. Disable or re-enable OTA updates at your own risk.";

        Package *disableAppLibrary = [[Package alloc] initWithIdentifier:@"com.darksword.disable-app-library"
                                           name:@"Disable App Library"
                               shortDescription:@"Remove the App Library page"
                                longDescription:@"Removes the App Library page that sits past your last home-screen page. Swiping past the last page becomes a no-op."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
                                     symbolName:@"square.grid.2x2.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDisableAppLibrary
                                          isNew:NO];

        Package *quickLoader = [[Package alloc] initWithIdentifier:@"com.darksword.quickloader"
                                           name:@"QuickLoader"
                               shortDescription:@"Executes custom .js code"
                                longDescription:@"Select a local JavaScript file from Files, configure any declared parameters, and run it through Cyanide's SpringBoard RemoteCall bridge.\n\nOnly run scripts you trust. JavaScript tweaks can send private SpringBoard messages and destabilize the device if the script is buggy."
                                        version:@"1.0"
                                         author:@"Iggy05"
                                       category:@"SpringBoard"
                                     symbolName:@"bolt.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsQuickLoaderEnabled
                                          isNew:NO];
        quickLoader.settingsSection = kSecQuickLoader;
        quickLoader.unstableWarning = @"Runs user-selected JavaScript with access to Cyanide's RemoteCall helpers. Only use scripts you trust; bad scripts can crash SpringBoard.";

        Package *locationSim = [[Package alloc] initWithIdentifier:@"com.darksword.locationsim"
                                           name:@"Location Simulator"
                               shortDescription:@"CoreLocation static point simulation"
                                longDescription:@"Spoofs the device's GPS location via Apple's CLSimulationManager. Requires Apple Maps installed and set up — Maps is the RemoteCall host process that drives the simulation.\n\nThis is a manual tool, not an installable package. Open Controls, choose a target, then use Simulate Current Target or Restore Real Location. Each run opens the activity log and marks completion when the request returns. Reset may take a few minutes and may require a reboot plus extra wait time.\n\nSettings exposes the current target plus altitude and accuracy. v1 is static-point only; route playback and alternate daemon hosts are next.\n\nNot all apps respect the simulated location. Apps that use their own location validation or additional signals may ignore it.\n\nCredits: kolbicz provided the GPS spoofer RemoteCall/CLSimulationManager prototype this is based on. ezzuldinSt's LSpoof provided the app-side CLLocationManager spoofing, picker, bookmarks, and route-simulation reference.\n\nSystem-behavior warning: simulated locations can affect more than maps. Features tied to location, including time zone, date/time behavior, weather, automation, reminders, and service checks, may behave unexpectedly. Only use this if you know what you're doing.\n\nLegal and service-use note: simulated locations may violate app terms, platform rules, game rules, ride-share or delivery policies, or local law depending on how they are used. Use only where you have permission. You are responsible for your use and apply or restore this tweak at your own risk."
                                        version:version
                                         author:@"zeroxjf, kolbicz, ezzuldinSt"
                                       category:@"System"
                                     symbolName:@"location.fill"
                                           kind:PackageInstallKindDirectTool
                                     enabledKey:nil
                                          isNew:NO];
        locationSim.settingsSection = kSecLocationSim;
        locationSim.experimental = NO;
        locationSim.unstableWarning = @"Beta: requires Apple Maps installed and set up. Changes CoreLocation's active simulation state — may affect time zone, date/time, and other location-tied behavior. Some apps and services prohibit or detect simulated locations. Only use this if you know what you're doing.";

        list = @[
            statBar,
            nsBar,
            niceBarLite,
            sbc,
            layoutExtras,
            gravityLite,
            powercuff,

            disableAppLibrary,

            [[Package alloc] initWithIdentifier:@"com.darksword.disable-icon-flyin"
                                           name:@"Disable Icon Fly-In"
                               shortDescription:@"Skip the icon spring animation"
                                longDescription:@"Skips the spring animation that plays when home screen icons appear after unlock or app switch. Icons just appear in their final position."
                                        version:version
                                         author:@"kolbicz"
                                       category:@"SpringBoard"
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
                                       category:@"SpringBoard"
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
                                       category:@"SpringBoard"
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
                                       category:@"SpringBoard"
                                     symbolName:@"hand.tap.fill"
                                           kind:PackageInstallKindToggle
                                     enabledKey:kSettingsDSDoubleTapToLock
                                          isNew:NO],

            ({
                Package *drag = [[Package alloc] initWithIdentifier:@"com.darksword.drag-coefficient"
                                                               name:@"Drag Coefficient"
                                                   shortDescription:@"Custom SpringBoard animation speed multiplier"
                                                    longDescription:@"Overrides _UIAnimationDragCoefficient in SpringBoard to make all UIKit spring animations faster or slower.\n\nSet the coefficient in the Drag Coefficient settings panel. 50% = 0.50× (2× faster), 25% = 0.25× (4× faster), 100% = stock.\n\nImported from kolbicz/DarkSword-Tweaks."
                                                            version:version
                                                             author:@"kolbicz"
                                                           category:@"SpringBoard"
                                                         symbolName:@"dial.medium.fill"
                                                               kind:PackageInstallKindToggle
                                                         enabledKey:kSettingsDSDragCoefficientEnabled
                                                              isNew:NO];
                drag.settingsSection = kSecDragCoefficient;
                drag;
            }),

            otaBlock,

            // Higher-risk/manual packages last so their warnings sit below core tweaks.
            signal,
            axon,
            nanoRegistry,
            callRecordingSound,
            hideHomeBar,
            typeBanner,
            locationSim,
            snowboardLite,
            liveWP,
            appSwitcherGrid,
            quickLoader,
        ];
    });
    NSArray<Package *> *repoPackages = [self repoPackages];
    if (repoPackages.count == 0) return list;

    // Dedup: skip repo packages whose name matches a native package
    // This avoids duplicates like "Hide Home Bar" appearing in both
    // "Home Screen" (native) and "JavaScript Tweaks" (remote repo).
    NSMutableSet<NSString *> *nativeNames = [NSMutableSet set];
    for (Package *p in list) {
        if (p.name.length > 0) [nativeNames addObject:p.name];
    }
    NSMutableArray<Package *> *uniqueRepo = [NSMutableArray array];
    for (Package *p in repoPackages) {
        if (p.name.length > 0 && [nativeNames containsObject:p.name]) continue;
        [uniqueRepo addObject:p];
    }
    if (uniqueRepo.count == 0) return list;
    return [list arrayByAddingObjectsFromArray:uniqueRepo];
}

+ (NSArray<NSString *> *)categoriesInOrder
{
    NSArray<NSString *> *preferred = @[
        @"In Development",
        @"Experimental",
        @"Status Bar",
        @"Home Screen",
        @"Theming",
        @"SpringBoard",
        @"System",
        @"JavaScript Tweaks",
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
