//
//  livewp.m
//  LiveWP (Live Wallpaper) implementation
//
//  策略：一个 AVPlayer 驱动两个 AVPlayerLayer，
//  分别插到 SBHomeScreenWindow 和 SBCoverSheetWindow 的 layer index 0。
//

#import "livewp.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdio.h>
#import <unistd.h>

// ============================================================================
// MARK: - Global State
// ============================================================================

static uint64_t g_livewp_player = 0;
static uint64_t g_livewp_home_layer = 0;       // 主屏幕的 AVPlayerLayer
static uint64_t g_livewp_lock_layer = 0;       // 锁屏的 AVPlayerLayer
static uint64_t g_livewp_player_item = 0;
static uint64_t g_livewp_looper = 0;
static uint64_t g_livewp_home_window = 0;
static uint64_t g_livewp_lock_window = 0;
static bool g_livewp_configured = false;
static bool g_livewp_paused = false;

typedef struct { double x, y, w, h; } LiveWPRect;

// ============================================================================
// MARK: - Keys
// ============================================================================

NSString * const kLiveWPEnabled = @"LiveWPEnabled";
NSString * const kLiveWPVideoPath = @"LiveWPVideoPath";

// ============================================================================
// MARK: - Forward Declarations
// ============================================================================

static bool livewp_create_player(NSString *videoPath);
static bool livewp_attach_and_play(void);
static void livewp_cleanup(void);

// ============================================================================
// MARK: - Public Interface
// ============================================================================

// 从相对路径拼接为绝对路径（兼容旧版绝对路径）
NSString *livewp_absolute_path(void) {
    NSString *rel = [[NSUserDefaults standardUserDefaults] stringForKey:kLiveWPVideoPath];
    if (!rel || rel.length == 0) return nil;
    if ([rel hasPrefix:@"/"]) return rel;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:rel];
}

bool livewp_apply_in_session(void)
{
    NSString *videoPath = livewp_absolute_path();
    if (!videoPath || videoPath.length == 0) {
        log_user("[LIVEWP] No video path configured.\n");
        return false;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        log_user("[LIVEWP] Video file not found: %s\n", videoPath.UTF8String);
        return false;
    }

    if (g_livewp_configured) {
        livewp_stop_in_session();
        usleep(100000);
    }

    if (!livewp_create_player(videoPath)) return false;
    if (!livewp_attach_and_play()) { livewp_cleanup(); return false; }

    g_livewp_configured = true;
    g_livewp_paused = false;
    log_user("[LIVEWP] OK: playing.\n");
    return true;
}

bool livewp_stop_in_session(void)
{
    if (!g_livewp_configured) return true;

    if (r_is_objc_ptr(g_livewp_player))
        r_msg2_main(g_livewp_player, "pause", 0, 0, 0, 0);

    if (r_is_objc_ptr(g_livewp_home_layer))
        r_msg2_main(g_livewp_home_layer, "removeFromSuperlayer", 0, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_lock_layer))
        r_msg2_main(g_livewp_lock_layer, "removeFromSuperlayer", 0, 0, 0, 0);

    livewp_cleanup();
    g_livewp_configured = false;
    g_livewp_paused = false;
    log_user("[LIVEWP] stopped.\n");
    return true;
}

bool livewp_repair_in_session(void)
{
    if (!g_livewp_configured) return false;
    if (g_livewp_paused) return true;
    return livewp_attach_and_play();
}

bool livewp_pause_in_session(void)
{
    if (!g_livewp_configured) return true;

    if (r_is_objc_ptr(g_livewp_player))
        r_msg2_main(g_livewp_player, "pause", 0, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_home_layer))
        r_msg2_main(g_livewp_home_layer, "setHidden:", 1, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_lock_layer))
        r_msg2_main(g_livewp_lock_layer, "setHidden:", 1, 0, 0, 0);

    if (!g_livewp_paused) {
        log_user("[LIVEWP] paused while screen is asleep.\n");
    }
    g_livewp_paused = true;
    return true;
}

bool livewp_resume_in_session(void)
{
    if (!g_livewp_configured) return false;

    bool wasPaused = g_livewp_paused;
    g_livewp_paused = false;
    if (r_is_objc_ptr(g_livewp_home_layer))
        r_msg2_main(g_livewp_home_layer, "setHidden:", 0, 0, 0, 0);
    if (r_is_objc_ptr(g_livewp_lock_layer))
        r_msg2_main(g_livewp_lock_layer, "setHidden:", 0, 0, 0, 0);

    bool ok = livewp_attach_and_play();
    if (wasPaused) {
        log_user("[LIVEWP] resumed after screen wake result=%d.\n", ok);
    }
    return ok;
}

// 热替换视频：复用旧 player 实例，只替换 playerItem 和 looper
// 所有 AVFoundation 对象都在 SpringBoard 进程里通过 RemoteCall 创建
bool livewp_swap_video_in_session(NSString *videoPath)
{
    if (!g_livewp_configured || !r_is_objc_ptr(g_livewp_player)) {
        log_user("[LIVEWP] swap: not configured\n");
        return false;
    }

    uint64_t pathStr = r_nsstr_retained(videoPath.UTF8String);
    if (!r_is_objc_ptr(pathStr)) return false;
    uint64_t url = r_msg2_main(r_class("NSURL"), "fileURLWithPath:", pathStr, 0, 0, 0);
    r_msg2(pathStr, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(url)) return false;

    // 在 SpringBoard 进程里创建新 AVPlayerItem
    uint64_t newItem = r_msg2_main(r_class("AVPlayerItem"), "playerItemWithURL:", url, 0, 0, 0);
    if (!r_is_objc_ptr(newItem)) {
        log_user("[LIVEWP] swap: failed to create playerItem\n");
        return false;
    }

    // replaceCurrentItemWithPlayerItem: — layer 保持不变，只是换了视频源
    r_msg2_main(g_livewp_player, "replaceCurrentItemWithPlayerItem:", newItem, 0, 0, 0);

    // 重建 looper（旧 looper 持有的是旧 item，需要换成新的）
    uint64_t looperCls = r_class("AVPlayerLooper");
    if (r_is_objc_ptr(looperCls)) {
        g_livewp_looper = r_msg2_main(looperCls, "playerLooperWithPlayer:templateItem:",
                                       g_livewp_player, newItem, 0, 0);
    }
    g_livewp_player_item = newItem;

    r_msg2_main(g_livewp_player, "play", 0, 0, 0, 0);
    log_user("[LIVEWP] video swapped OK\n");
    return true;
}

void livewp_forget_remote_state(void)
{
    g_livewp_player = 0;
    g_livewp_home_layer = 0;
    g_livewp_lock_layer = 0;
    g_livewp_player_item = 0;
    g_livewp_looper = 0;
    g_livewp_home_window = 0;
    g_livewp_lock_window = 0;
    g_livewp_configured = false;
    g_livewp_paused = false;
}

// ============================================================================
// MARK: - Private Helpers
// ============================================================================

static uint64_t livewp_make_layer(uint64_t player)
{
    uint64_t layer = r_msg2_main(r_class("AVPlayerLayer"), "playerLayerWithPlayer:", player, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return 0;
    uint64_t gravity = r_nsstr_retained("AVLayerVideoGravityResizeAspectFill");
    if (r_is_objc_ptr(gravity)) {
        r_msg2_main(layer, "setVideoGravity:", gravity, 0, 0, 0);
        r_msg2(gravity, "release", 0, 0, 0, 0);
    }
    return layer;
}

static bool livewp_create_player(NSString *videoPath)
{
    uint64_t avf = r_alloc_str("/System/Library/Frameworks/AVFoundation.framework/AVFoundation");
    if (avf) { r_dlsym_call(R_TIMEOUT, "dlopen", avf, 2, 0, 0, 0, 0, 0, 0); r_free(avf); }

    uint64_t pathStr = r_nsstr_retained(videoPath.UTF8String);
    if (!r_is_objc_ptr(pathStr)) return false;
    uint64_t url = r_msg2_main(r_class("NSURL"), "fileURLWithPath:", pathStr, 0, 0, 0);
    r_msg2(pathStr, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(url)) return false;

    uint64_t playerItem = r_msg2_main(r_class("AVPlayerItem"), "playerItemWithURL:", url, 0, 0, 0);
    if (!r_is_objc_ptr(playerItem)) return false;

    uint64_t playerClass = r_class("AVQueuePlayer");
    if (!r_is_objc_ptr(playerClass)) playerClass = r_class("AVPlayer");
    if (!r_is_objc_ptr(playerClass)) return false;

    uint64_t player = r_msg2_main(playerClass, "playerWithPlayerItem:", playerItem, 0, 0, 0);
    if (!r_is_objc_ptr(player)) return false;

    double zero = 0.0;
    r_msg2_main_raw(player, "setVolume:", &zero, sizeof(zero), NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main(player, "setPreventsDisplaySleepDuringVideoPlayback:", 0, 0, 0, 0);

    uint64_t looperCls = r_class("AVPlayerLooper");
    uint64_t looper = r_is_objc_ptr(looperCls)
        ? r_msg2_main(looperCls, "playerLooperWithPlayer:templateItem:", player, playerItem, 0, 0)
        : 0;

    // 两个 layer：一个给主屏幕，一个给锁屏
    uint64_t homeLayer = livewp_make_layer(player);
    uint64_t lockLayer = livewp_make_layer(player);
    if (!r_is_objc_ptr(homeLayer) || !r_is_objc_ptr(lockLayer)) return false;

    uint64_t session = r_msg2_main(r_class("AVAudioSession"), "sharedInstance", 0, 0, 0, 0);
    if (r_is_objc_ptr(session)) {
        uint64_t cat = r_nsstr_retained("AVAudioSessionCategoryAmbient");
        if (r_is_objc_ptr(cat)) {
            r_dlsym_call(R_TIMEOUT, "objc_msgSend", session, r_sel("setCategory:withOptions:error:"),
                         cat, (uint64_t)1, (uint64_t)0, 0, 0, 0);
            r_msg2(cat, "release", 0, 0, 0, 0);
        }
    }

    g_livewp_player = player;
    g_livewp_player_item = playerItem;
    g_livewp_home_layer = homeLayer;
    g_livewp_lock_layer = lockLayer;
    g_livewp_looper = looper;
    g_livewp_paused = false;
    log_user("[LIVEWP] player OK (2 layers)\n");
    return true;
}

// 辅助：把 layer 插到指定 window 的 index 0，返回是否已附着成功。
static bool livewp_ensure_layer_in_window(uint64_t layer, uint64_t window, bool *movedOut)
{
    if (movedOut) *movedOut = false;
    if (!r_is_objc_ptr(layer) || !r_is_objc_ptr(window)) return false;

    uint64_t winLayer = r_msg2_main(window, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(winLayer)) return false;

    LiveWPRect bounds = {0};
    r_msg2_main_struct_ret(window, "bounds", &bounds, sizeof(bounds),
                           NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    r_msg2_main_raw(layer, "setFrame:",
                    &bounds, sizeof(bounds), NULL, 0, NULL, 0, NULL, 0);

    uint64_t curSuper = r_msg2_main(layer, "superlayer", 0, 0, 0, 0);
    if (curSuper != winLayer) {
        if (r_is_objc_ptr(curSuper))
            r_msg2_main(layer, "removeFromSuperlayer", 0, 0, 0, 0);
        r_msg2_main(winLayer, "insertSublayer:atIndex:", layer, 0, 0, 0);
        if (movedOut) *movedOut = true;
    }
    return true;
}

static bool livewp_attach_and_play(void)
{
    if (g_livewp_paused) {
        if (r_is_objc_ptr(g_livewp_player))
            r_msg2_main(g_livewp_player, "pause", 0, 0, 0, 0);
        return true;
    }

    bool homeMoved = false;
    bool lockMoved = false;
    bool homeOK = livewp_ensure_layer_in_window(g_livewp_home_layer,
                                                g_livewp_home_window,
                                                &homeMoved);
    bool lockOK = livewp_ensure_layer_in_window(g_livewp_lock_layer,
                                                g_livewp_lock_window,
                                                &lockMoved);
    if (homeOK || lockOK) {
        r_msg2_main(g_livewp_player, "play", 0, 0, 0, 0);
        if (homeMoved || lockMoved) {
            log_user("[LIVEWP] repair: reused cached windows homeMoved=%d lockMoved=%d\n",
                     homeMoved, lockMoved);
        }
        return true;
    }

    uint64_t app = r_msg2_main(r_class("UIApplication"), "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    // 遍历所有 window，找 SBHomeScreenWindow 和 SBCoverSheetWindow
    uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
    uint64_t wCount = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
    uint64_t homeWin = 0;
    uint64_t lockWin = 0;
    uint64_t homeScreenViewCls = r_class("SBHomeScreenView");
    uint64_t coverSheetCls = r_class("SBCoverSheetWindow");

    for (uint64_t i = 0; i < wCount && i < 32; i++) {
        uint64_t w = r_msg2_main(windows, "objectAtIndex:", i, 0, 0, 0);
        if (!r_is_objc_ptr(w)) continue;

        // 检查是不是 SBCoverSheetWindow
        if (r_is_objc_ptr(coverSheetCls) &&
            r_msg2_main(w, "isKindOfClass:", coverSheetCls, 0, 0, 0)) {
            lockWin = w;
            if (homeWin) break;
            continue;
        }

        // 检查子视图有没有 SBHomeScreenView
        if (!homeWin && r_is_objc_ptr(homeScreenViewCls)) {
            uint64_t subs = r_msg2_main(w, "subviews", 0, 0, 0, 0);
            uint64_t sCount = r_is_objc_ptr(subs) ? r_msg2_main(subs, "count", 0, 0, 0, 0) : 0;
            for (uint64_t j = 0; j < sCount && j < 4; j++) {
                uint64_t sv = r_msg2_main(subs, "objectAtIndex:", j, 0, 0, 0);
                if (r_is_objc_ptr(sv) &&
                    r_msg2_main(sv, "isKindOfClass:", homeScreenViewCls, 0, 0, 0)) {
                    homeWin = w;
                    if (lockWin) break;
                    break;
                }
            }
        }
    }

    // 把各自的 layer 插到各自的 window
    if (r_is_objc_ptr(homeWin)) {
        homeOK = livewp_ensure_layer_in_window(g_livewp_home_layer, homeWin, &homeMoved);
        if (homeOK) g_livewp_home_window = homeWin;
    }
    if (r_is_objc_ptr(lockWin)) {
        lockOK = livewp_ensure_layer_in_window(g_livewp_lock_layer, lockWin, &lockMoved);
        if (lockOK) g_livewp_lock_window = lockWin;
    }

    r_msg2_main(g_livewp_player, "play", 0, 0, 0, 0);

    log_user("[LIVEWP] D: home=0x%llx(%d) lock=0x%llx(%d) wCount=%llu\n",
             homeWin, homeMoved, lockWin, lockMoved, wCount);
    return homeOK || lockOK;
}

static void livewp_cleanup(void)
{
    g_livewp_player = 0;
    g_livewp_player_item = 0;
    g_livewp_home_layer = 0;
    g_livewp_lock_layer = 0;
    g_livewp_looper = 0;
    g_livewp_home_window = 0;
    g_livewp_lock_window = 0;
    g_livewp_paused = false;
}
