<p align="center">
  <img src="https://raw.githubusercontent.com/zeroxjf/cyanide/main/Cyanide/Assets.xcassets/AppIcon.appiconset/icon-ios-1024x1024.png" alt="Cyanide" width="160">
</p>

<h1 align="center">Cyanide</h1>

**By [@zeroxjf](https://github.com/zeroxjf) and [@d1y](https://x.com/chenhonzhou)** — an iOS tweak runner built on top of the DarkSword kernel r/w primitive.

Cyanide is a fork of [`wh1te4ever/darksword-kexploit-fun`](https://github.com/wh1te4ever/darksword-kexploit-fun)
for iOS kernel research. It wraps the native DarkSword kernel stages in an
Objective-C iOS app, restructures the UI as an Installer/Settings split, and
adds a few reliability fixes for repeated local testing. It does not ship
the browser-delivered WebKit/dyld parts of the original DarkSword chain.

## Fork Notice

This is [`d1y/cyanide-ios`](https://github.com/d1y/cyanide-ios), a fork of
[`zeroxjf/cyanide`](https://github.com/zeroxjf/cyanide).

Differences from upstream:
- All original upstream tweaks included and kept in sync
- Adds **NSBar**, **NiceBar Lite**, **SnowBoard Lite**, **LiveWP**,
  and **App Switcher Grid**
- Removed closed-source/Patreon-gated tweaks (Notification Island,
  IPA Decryptor, Dynamic Stage Lite, FastLockX Lite)
- No Patreon authentication — all tweaks are free and open-source
- Categories aligned with upstream's Sources tab organization

## Install

Open this page on your iPhone/iPad and tap the button below.

<p align="center">
  <a href="https://github.com/d1y/cyanide-ios/releases/latest" target="_blank">
    <img src="https://github.com/CelloSerenity/altdirect/blob/main/assets/png/Download_Blue.png?raw=true" alt="Download .ipa" width="160">
  </a>
</p>

## Feedback

- [Report a bug](https://github.com/d1y/cyanide-ios/issues/new)
- [Request a feature](https://github.com/d1y/cyanide-ios/issues/new)
- [Telegram group](https://t.me/ios_cyanide) for setup help and discussion

## Tweaks

These tweaks have been tested on iOS 18.x and 26.x. Expect version drift in
SpringBoard and related daemons to break things on other releases.

### Status Bar

- **StatBar**: battery temperature and free-RAM overlay anchored to the
  SpringBoard status bar, with optional C/F and network-speed display.
- **NSBar**: compact live download/upload speed overlay for the status bar,
  with selectable corner/center positions. Ported by d1y.
- **NiceBar Lite**: configurable status-bar-adjacent labels for custom text,
  date/time formats, battery, memory, traffic, uptime, IP address, disk,
  thermal state, and other live readouts. Ported by d1y.

### Home Screen

- **SBCustomizer**: dock icon count, home-screen columns/rows, and hidden icon
  labels.
- **Home Layout Extras**: extra padding around the home grid and dock, plus
  per-icon scale for home and dock icons. Stacks on top of SBCustomizer.
- **Gravity Lite**: core port of Julio Verne's classic Gravity tweak. Applies
  UIDynamicAnimator physics to home-screen and dock icons — gravity, collisions,
  bounce, friction, accelerometer steering, shake pulses, and an explosion
  button.
- **Hide Home Bar**: zeros the home indicator asset page to hide the bottom
  bar. Respring to apply; separate Restore action.

### System

- **Powercuff**: CPU/GPU underclocking through simulated `thermalmonitord`
  pressure levels (off, nominal, light, moderate, heavy). Lasts until reboot.
  Port of [`rpetrich/Powercuff`](https://github.com/rpetrich/Powercuff).
- **Watch Pairing Override**: edits the watchOS pairing range stored on the
  iPhone so you can pair a newer Apple Watch or revive an older one.
- **Call Recording Sound**: replaces the CallServices disclosure audio files
  with silent payloads. Separate Silence and Restore actions.
- **Location Simulator**: drives Apple's CoreLocation simulation path from a
  RemoteCall host process and sets a static target coordinate.
- **Disable OTA Updates**: toggles the launchd OTA `disabled.plist` to block or
  unblock update prompts. Persists across reboots.

### SpringBoard

- **Axon Lite**: groups Notification Center requests by app with a SpringBoard
  overlay and dedups duplicates while the RemoteCall session is alive.
- **App Switcher Grid**: grid-style app switcher for this RemoteCall session.
- **QuickLoader**: executes user-selected `.js` files via RemoteCall bridge.
- **Disable App Library**: removes the App Library page past the last home screen.
- **Disable Icon Fly-In**: skips the spring-in animation when icons appear.
- **Zero Wake Animation**: snaps the display on instantly when waking.
- **Zero Backlight Fade**: instant lock/unlock backlight.
- **Double-Tap to Lock**: lock the device with a wallpaper double-tap.
- **Drag Coefficient**: custom SpringBoard animation speed multiplier.

### Theming

- **Cyanide Themer**: per-bundle icon theme engine. Walks SpringBoard's
  SBIconView hierarchy and swaps each icon's image with a PNG matched on bundle
  ID. Ships with iOS 6 Theme.
- **SnowBoard Lite**: imports SnowBoard/IconBundles-style theme folders or
  archives into Cyanide's local theme library, then applies the selected theme.
  Ported by d1y.
- **LiveWP**: plays a selected MP4/MOV/M4V video as wallpaper behind the lock
  screen and home screen. Ported by d1y.

### In Development

> ⚠︎ Unstable or in-development — require Experimental Tweaks to be enabled in Settings.

- **Signal Readouts**: replaces the signal-strength glyphs with live numeric
  readouts — RSRP dBm on cellular, bar count on WiFi.
- **TypeBanner**: shows a pill banner below the Dynamic Island when the active
  Messages conversation shows a typing indicator. Detection fires only while
  Messages.app is running.

## JavaScript Tweaks

Cyanide includes two JavaScript tweak runners contributed by Iggy05:

- **QuickLoader** imports a local `.js` file from Files and exposes declared
  `@param` values as settings rows.
- **RepoTweaks Store** imports HTTPS JSON repositories and downloads selected
  JavaScript tweaks from those sources. Cyanide seeds the zeroxjf source at
  `https://zeroxjf.github.io/cyanide-repotweaks.json` by default.

Only run scripts and repositories you trust; JavaScript tweaks can call Cyanide
RemoteCall helpers and may destabilize SpringBoard if the script is buggy.

## Supported Targets

Tested target range:

- iOS/iPadOS 17.0 through 18.7.1
- iOS/iPadOS 26.0 through 26.0.1
- A19/M5 devices are not supported

The kernel bugs used here, `CVE-2025-43510` and `CVE-2025-43520`, were fixed in
iOS/iPadOS 18.7.2 and 26.1. Later builds are outside this kernel exploit window.

## What This Fork Changes

- Cleans shared exploit state before each attempt.
- Matches the target process with an explicit marker.
- Validates sockets before using the spray path.
- Treats missed races as retryable failures instead of hard failures.
- Tightens the A18/M4 `pe_v2` path with initialized target-file contents,
  stable local remap addresses, bounded page freeing, socket-spray preflight
  checks, and controlled zone-trim retries.

## Kernel Research Features

- Escape the app sandbox.
- Control or crash userspace processes from the app.
- Change UID, GID, and sticky bits on target files.
- Disable ASLR by setting `P_DISABLE_ASLR` in `launchd`'s `proc->p_flag`.

## Credits

- [`opa334`](https://github.com/opa334): original [`darksword-kexploit`](https://github.com/opa334/darksword-kexploit), ChOma, and XPF — the kernel r/w primitive Cyanide is built on.
- [`wh1te4ever`](https://github.com/wh1te4ever): [`kfun` / `darksword-kexploit-fun`](https://github.com/wh1te4ever/darksword-kexploit-fun) — the RemoteCall implementation that lets a sideloaded app apply tweaks inside SpringBoard. Cyanide is a fork of this project.
- [`zeroxjf`](https://github.com/zeroxjf): upstream [`cyanide`](https://github.com/zeroxjf/cyanide) — the main project this fork is based on.
- [`d1y`](https://x.com/chenhonzhou): NSBar, NiceBar Lite, SnowBoard Lite, LiveWP, App Switcher Grid, and this fork's ongoing maintenance.
- [`rooootdev`](https://github.com/rooootdev): working kexploit behavior used to stabilize this fork, and the App Switcher Grid RemoteCall approach.
- [`neonmodder123`](https://github.com/neonmodder123): Web Respring method.
- [`kolbicz`](https://github.com/kolbicz): OTA Disabler, SpringBoard tweaks, and
  the RemoteCall/CLSimulationManager GPS spoofer prototype used as the starting
  point for Location Simulator.
- `ezzuldinSt`: LSpoof app-side `CLLocationManager` spoofing, picker,
  bookmarks, and route-simulation reference used while shaping Location
  Simulator.
- `YangJiiii` (`@duongduong0908`): EnsWilde and Disable Call Recording
  BookRestore reference tools used while shaping Call Recording Sound.
- `@Little_34306`: credited by the original call-recording projects for the
  Disable Call Recording concept.
- [`rpetrich`](https://github.com/rpetrich): Powercuff.
- [Julio Verne](https://github.com/julioverne): the original [Gravity](https://github.com/julioverne/Gravity) tweak that Gravity Lite is a core port of.
- [`tomt000`](https://github.com/tomt000): [Dynamic Stage](https://havoc.app/package/dynamicstage) — the original Stage Manager-for-iPhone tweak.
- [`Iggy05`](https://github.com/Iggy05): QuickLoader and RepoTweaks JavaScript runners, and QuickLoader standalone mode.
- [`C4ndyF1sh` / `jailbreakdotparty`](https://github.com/jailbreakdotparty): original home bar zeroing technique.

### UI inspiration

- The classic [Installer.app](https://github.com/AppTapp/Installer-3) (Ripdev & Nullriver Software, now maintained by AppTapp and the Legacy Jailbreak community) — the iPhoneOS 1 package-manager look that the Cyanide Installer tab is modeled after.
- The [Sileo Project](https://github.com/Sileo/Sileo) (the Sileo Team) — the queue → review → confirm install flow and the bottom queue-popup pattern.

## Build

```sh
./scripts/build.sh
```

The build script uses the `Cyanide` scheme, disables code signing, and writes
an unsigned IPA to:

```text
build/Cyanide.ipa
```

Equivalent manual build:

```sh
xcodebuild \
  -project Cyanide.xcodeproj \
  -scheme Cyanide \
  -sdk iphoneos \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## License

This repository is licensed under **AGPL-3.0**. See `LICENSE`.

All tweaks in this fork are open-source and free to use, modify, and distribute
under the AGPL-3.0 terms. No Patreon, no gated features, no private submodule.
