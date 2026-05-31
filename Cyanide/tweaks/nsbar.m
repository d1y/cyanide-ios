//
//  nsbar.m
//  NSBar: Network Speed Bar
//

#import "nsbar.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ifaddrs.h>
#import <math.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <time.h>

// Constants
// Only test my iPhone 14 in iOS 18.0
static const uint64_t kNSBarOverlayTag = 99422;
static const double kNSBarWinH = 18.0;
static const double kNSBarFontPt = 11.5;
// Was 999999.0/1001.0; keep it below the system status bar so scroll-to-top taps pass through.
static const double kNSBarWinLevel = 999.0;
static const double kNSBarMargin = 20.0;
static const double kNSBarTopY = 0.0;      // 顶部留 1px 间距
static const double kNSBarBottomY = 38.0;  // 更靠下（从 28.0 改为 44.0）
static const double kNSBarTextHPad = 7.0;
static const double kNSBarMinWidth = 54.0;
static const double kNSBarNetworkWidth = 104.0;
static const double kNSBarPillBorderAlpha = 0.42;

// Global state
static uint64_t gNSBarApplyTick = 0;
static uint64_t gNSBarOverlayWindow = 0;
static uint64_t gNSBarOverlayLabel = 0;
static NSBarPosition gNSBarLastPosition = NSBarPositionTopLeft;

// Cached selectors
static uint64_t gNSBarSetTextSel = 0;
static uint64_t gNSBarPerformMainSel = 0;
static uint64_t gNSBarNSStringClass = 0;
static uint64_t gNSBarAllocSel = 0;
static uint64_t gNSBarInitUTF8Sel = 0;
static uint64_t gNSBarUIColorClass = 0;
static uint64_t gNSBarBorderColor = 0;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} NSBarRect;

static bool nsbar_should_log_tick(void)
{
    return gNSBarApplyTick == 1;
}

static bool read_net_totals(uint64_t *ibytes, uint64_t *obytes)
{
    if (!ibytes || !obytes) return false;
    *ibytes = 0;
    *obytes = 0;

    struct ifaddrs *head = NULL;
    if (getifaddrs(&head) != 0) return false;

    for (struct ifaddrs *ifa = head; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || !ifa->ifa_data || !ifa->ifa_name) continue;
        if (ifa->ifa_addr->sa_family != AF_LINK) continue;
        if ((ifa->ifa_flags & IFF_LOOPBACK) != 0) continue;
        if (strncmp(ifa->ifa_name, "lo", 2) == 0) continue;

        const struct if_data *data = (const struct if_data *)ifa->ifa_data;
        *ibytes += (uint64_t)data->ifi_ibytes;
        *obytes += (uint64_t)data->ifi_obytes;
    }

    freeifaddrs(head);
    return true;
}

static double nsbar_now_seconds(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0.0;
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1000000000.0);
}

static void read_net_speed_kbps(double *downKB, double *upKB)
{
    static bool havePrev = false;
    static uint64_t prevIn = 0;
    static uint64_t prevOut = 0;
    static double prevTime = 0.0;

    if (downKB) *downKB = 0.0;
    if (upKB) *upKB = 0.0;

    uint64_t totalIn = 0;
    uint64_t totalOut = 0;
    double now = nsbar_now_seconds();
    if (now <= 0.0 || !read_net_totals(&totalIn, &totalOut)) return;

    if (havePrev && now > prevTime) {
        uint64_t din = (totalIn >= prevIn) ? (totalIn - prevIn) : 0;
        uint64_t dout = (totalOut >= prevOut) ? (totalOut - prevOut) : 0;
        double dt = now - prevTime;
        if (downKB) *downKB = ((double)din / dt) / 1024.0;
        if (upKB) *upKB = ((double)dout / dt) / 1024.0;
    }

    prevIn = totalIn;
    prevOut = totalOut;
    prevTime = now;
    havePrev = true;
}

static NSString *format_net_speed(double kbValue)
{
    if (!isfinite(kbValue) || kbValue < 0.0) kbValue = 0.0;
    if (kbValue < 999.5) return [NSString stringWithFormat:@"%lldK", (long long)llround(kbValue)];
    double mbValue = kbValue / 1024.0;
    if (mbValue < 10.0) return [NSString stringWithFormat:@"%.1fM", mbValue];
    return [NSString stringWithFormat:@"%.0fM", mbValue];
}

static NSString *build_nsbar_text(void)
{
    double downKB = 0.0;
    double upKB = 0.0;
    read_net_speed_kbps(&downKB, &upKB);
    return [NSString stringWithFormat:@"↓%@ ↑%@",
            format_net_speed(downKB), format_net_speed(upKB)];
}

static uint64_t nsbar_nsstring_utf8_fast(const char *cstr)
{
    if (!cstr) cstr = "n/a";
    uint64_t buf = r_alloc_str(cstr);
    if (!buf) return 0;
    if (!gNSBarNSStringClass) gNSBarNSStringClass = r_class("NSString");
    if (!gNSBarAllocSel) gNSBarAllocSel = r_sel("alloc");
    if (!gNSBarInitUTF8Sel) gNSBarInitUTF8Sel = r_sel("initWithUTF8String:");
    if (!r_is_objc_ptr(gNSBarNSStringClass) || !gNSBarAllocSel || !gNSBarInitUTF8Sel) {
        r_free(buf);
        return 0;
    }
    uint64_t allocated = r_msg(gNSBarNSStringClass, gNSBarAllocSel, 0, 0, 0, 0);
    uint64_t ns = r_is_objc_ptr(allocated) ? r_msg(allocated, gNSBarInitUTF8Sel, buf, 0, 0, 0) : 0;
    r_free(buf);
    return ns;
}

static bool nsbar_set_text_fast(uint64_t label, uint64_t textObj)
{
    if (!r_is_objc_ptr(label) || !r_is_objc_ptr(textObj)) return false;
    if (!gNSBarSetTextSel) gNSBarSetTextSel = r_sel("setText:");
    if (!gNSBarSetTextSel) return false;
    r_msg2_main(label, "setText:", textObj, 0, 0, 0);
    return true;
}

static void nsbar_release_remote_obj(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return;
    r_dlsym_call(R_TIMEOUT, "CFRelease", obj, 0, 0, 0, 0, 0, 0, 0);
}

static bool r_send_double_main(uint64_t obj, const char *selName, double value)
{
    if (!r_is_objc_ptr(obj)) return false;
    r_msg2_main_raw(obj, selName,
                    &value, sizeof(value),
                    NULL, 0,
                    NULL, 0,
                    NULL, 0);
    return true;
}

static bool r_send_rect_main(uint64_t obj, const char *selName,
                             double x, double y, double width, double height)
{
    if (!r_is_objc_ptr(obj)) return false;
    NSBarRect rect = { x, y, width, height };
    r_msg2_main_raw(obj, selName,
                    &rect, sizeof(rect),
                    NULL, 0,
                    NULL, 0,
                    NULL, 0);
    return true;
}

static uint64_t nsbar_pill_border_color(void)
{
    if (!r_is_objc_ptr(gNSBarUIColorClass)) gNSBarUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNSBarUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNSBarBorderColor)) {
        double white = 0.72;
        double alpha = kNSBarPillBorderAlpha;
        gNSBarBorderColor = r_msg2_main_raw(gNSBarUIColorClass, "colorWithWhite:alpha:",
                                            &white, sizeof(white),
                                            &alpha, sizeof(alpha),
                                            NULL, 0,
                                            NULL, 0);
    }
    return gNSBarBorderColor;
}

static void nsbar_make_label_click_through(uint64_t label)
{
    if (!r_is_objc_ptr(label)) return;
    r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
    r_msg2_main(label, "setMultipleTouchEnabled:", 0, 0, 0, 0);
    r_msg2_main(label, "setExclusiveTouch:", 0, 0, 0, 0);
}

static void nsbar_make_window_click_through(uint64_t win)
{
    if (!r_is_objc_ptr(win)) return;
    r_msg2_main(win, "setUserInteractionEnabled:", 0, 0, 0, 0);
    r_msg2_main(win, "setMultipleTouchEnabled:", 0, 0, 0, 0);
    r_msg2_main(win, "setExclusiveTouch:", 0, 0, 0, 0);

    const char *selectors[] = {
        "_setWindowIgnoresHitTest:",
        "setWindowIgnoresHitTest:",
        "_setIgnoresHitTesting:",
        "setIgnoresHitTesting:",
        "setIgnoresHitTest:",
    };
    for (size_t i = 0; i < sizeof(selectors) / sizeof(selectors[0]); i++) {
        if (r_responds_main(win, selectors[i])) {
            r_msg2_main(win, selectors[i], 1, 0, 0, 0);
        }
    }
}

static uint64_t nsbar_overlay_font(void)
{
    uint64_t UIFont = r_class("UIFont");
    if (!r_is_objc_ptr(UIFont)) return 0;

    double size = kNSBarFontPt;
    double weight = 0.0;
    uint64_t font = r_msg2_main_raw(UIFont, "monospacedDigitSystemFontOfSize:weight:",
                                    &size, sizeof(size),
                                    &weight, sizeof(weight),
                                    NULL, 0,
                                    NULL, 0);
    if (r_is_objc_ptr(font)) return font;

    return r_msg2_main_raw(UIFont, "systemFontOfSize:",
                           &size, sizeof(size),
                           NULL, 0,
                           NULL, 0,
                           NULL, 0);
}

static void nsbar_apply_overlay_style(uint64_t label)
{
    if (!r_is_objc_ptr(label)) return;
    nsbar_make_label_click_through(label);

    uint64_t font = nsbar_overlay_font();
    if (r_is_objc_ptr(font)) {
        r_msg2_main(label, "setFont:", font, 0, 0, 0);
    }
    r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", 0, 0, 0, 0);
    r_msg2_main(label, "setLineBreakMode:", 2, 0, 0, 0); // NSLineBreakByClipping

    uint64_t layer = r_msg2_main(label, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = kNSBarWinH / 2.0;
        double borderWidth = 0.5;
        r_send_double_main(layer, "setCornerRadius:", radius);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
        r_send_double_main(layer, "setBorderWidth:", borderWidth);
        uint64_t borderColor = nsbar_pill_border_color();
        if (r_is_objc_ptr(borderColor)) {
            uint64_t cgColor = r_msg2_main(borderColor, "CGColor", 0, 0, 0, 0);
            if (cgColor) r_msg2_main(layer, "setBorderColor:", cgColor, 0, 0, 0);
        }
    }
}

static double nsbar_measure_text_width(NSString *text)
{
    if (text.length == 0) return kNSBarMinWidth;
    UIFont *font = nil;
    if (@available(iOS 9.0, *)) {
        font = [UIFont monospacedDigitSystemFontOfSize:kNSBarFontPt weight:UIFontWeightRegular];
    }
    if (!font) font = [UIFont systemFontOfSize:kNSBarFontPt];
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    return ceil([text sizeWithAttributes:attrs].width);
}

static double nsbar_width_for_text(NSString *text, NSBarPosition position)
{
    CGRect bounds = UIScreen.mainScreen.bounds;
    double screenWidth = bounds.size.width;
    if (!isfinite(screenWidth) || screenWidth < 100.0) screenWidth = 390.0;
    double maxWidth = (position == NSBarPositionCenter)
        ? screenWidth * 0.40
        : (screenWidth * 0.5) - kNSBarMargin - 4.0;
    if (maxWidth < kNSBarMinWidth) maxWidth = kNSBarMinWidth;

    double width = kNSBarNetworkWidth;
    if (width < kNSBarMinWidth) width = kNSBarMinWidth;
    if (width > maxWidth) width = maxWidth;
    return width;
}

static void nsbar_calculate_position(NSBarPosition position, double *outX, double *outY, double width)
{
    CGRect bounds = UIScreen.mainScreen.bounds;
    double screenWidth = bounds.size.width;
    
    double x = 0.0;
    double y = 0.0;
    
    switch (position) {
        case NSBarPositionTopLeft:
            x = kNSBarMargin;
            y = kNSBarTopY;
            break;
        case NSBarPositionBottomLeft:
            x = kNSBarMargin;
            y = kNSBarBottomY;
            break;
        case NSBarPositionTopRight:
            x = screenWidth - width - kNSBarMargin;
            y = kNSBarTopY;
            break;
        case NSBarPositionBottomRight:
            x = screenWidth - width - kNSBarMargin;
            y = kNSBarBottomY;
            break;
        case NSBarPositionCenter:
            // With StatBar same position
            x = (screenWidth - width) / 2.0;
            y = kNSBarBottomY;
            printf("[NSBAR] Center position: screenWidth=%.1f width=%.1f x=%.1f y=%.1f\n",
                   screenWidth, width, x, y);
            break;
        default:
            printf("[NSBAR] Unknown position: %d, using top left\n", position);
            x = kNSBarMargin;
            y = kNSBarTopY;
            break;
    }
    
    *outX = x;
    *outY = y;
}

static bool nsbar_apply_overlay_layout(uint64_t win, uint64_t label, NSBarPosition position, NSString *text)
{
    if (!r_is_objc_ptr(win)) return false;

    double width = nsbar_width_for_text(text, position);
    double x = 0.0;
    double y = 0.0;
    
    nsbar_calculate_position(position, &x, &y, width);

    if (nsbar_should_log_tick()) {
        printf("[NSBAR] overlay: layout position=%d frame={%.1f,%.1f,%.1f,%.1f}\n",
               position, x, y, width, kNSBarWinH);
    }

    bool ok = true;
    ok &= r_send_rect_main(win, "setFrame:", x, y, width, kNSBarWinH);
    ok &= r_send_double_main(win, "setWindowLevel:", kNSBarWinLevel);
    r_msg2_main(win, "setUserInteractionEnabled:", 0, 0, 0, 0);

    if (r_is_objc_ptr(label)) {
        ok &= r_send_rect_main(label, "setFrame:", 0.0, 0.0, width, kNSBarWinH);
    }
    
    return ok;
}

static bool nsbar_install_overlay(NSString *text, NSBarPosition position)
{
    if (nsbar_should_log_tick())
        printf("[NSBAR] overlay: entry (dedicated UIWindow)\n");

    const char *utf8 = text.UTF8String;
    if (!utf8) utf8 = "n/a";
    uint64_t textObj = nsbar_nsstring_utf8_fast(utf8);
    if (!r_is_objc_ptr(textObj)) { 
        printf("[NSBAR] overlay: NSString alloc failed\n"); 
        return false; 
    }

    // Fast path: update existing overlay
    if (r_is_objc_ptr(gNSBarOverlayWindow) && r_is_objc_ptr(gNSBarOverlayLabel)) {
        if (nsbar_should_log_tick())
            printf("[NSBAR] fast path: current position=%d last position=%d\n", position, gNSBarLastPosition);
        bool ok = nsbar_set_text_fast(gNSBarOverlayLabel, textObj);
        nsbar_release_remote_obj(textObj);
        if (ok) {
            nsbar_apply_overlay_layout(gNSBarOverlayWindow, gNSBarOverlayLabel, position, text);
            gNSBarLastPosition = position;
            if (nsbar_should_log_tick())
                printf("[NSBAR] overlay: fast cached text updated\n");
            return true;
        }
        gNSBarOverlayWindow = 0;
        gNSBarOverlayLabel = 0;
        return false;
    }

    // Create new overlay
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) {
        nsbar_release_remote_obj(textObj);
        printf("[NSBAR] overlay: UIApplication missing\n");
        return false;
    }

    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) {
        nsbar_release_remote_obj(textObj);
        printf("[NSBAR] overlay: sharedApplication nil\n");
        return false;
    }

    uint64_t assocKey = r_sel("darkswordNSBarOverlayWindow");
    if (!assocKey) {
        nsbar_release_remote_obj(textObj);
        printf("[NSBAR] overlay: assoc key failed\n");
        return false;
    }

    // Check for cached window
    uint64_t cachedWin = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                      app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(cachedWin)) {
        uint64_t cachedLabel = r_msg2_main(cachedWin, "viewWithTag:", kNSBarOverlayTag, 0, 0, 0);
        if (nsbar_should_log_tick())
            printf("[NSBAR] overlay: cached window=0x%llx label=0x%llx\n", cachedWin, cachedLabel);
        if (r_is_objc_ptr(cachedLabel)) {
            gNSBarOverlayWindow = cachedWin;
            gNSBarOverlayLabel = cachedLabel;
            gNSBarLastPosition = position;
            nsbar_set_text_fast(cachedLabel, textObj);
            nsbar_make_window_click_through(cachedWin);
            nsbar_apply_overlay_style(cachedLabel);
            nsbar_apply_overlay_layout(cachedWin, cachedLabel, position, text);
            r_msg2_main(cachedWin, "setHidden:", 0, 0, 0, 0);
            nsbar_release_remote_obj(textObj);
            if (nsbar_should_log_tick())
                printf("[NSBAR] overlay: cached text updated\n");
            return true;
        }
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, 0, 1, 0, 0, 0, 0);
        gNSBarOverlayWindow = 0;
        gNSBarOverlayLabel = 0;
    }

    // Get window scene
    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
        if (count > 0 && count < 64) keyWin = r_msg2_main(windows, "objectAtIndex:", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWin)) { 
        printf("[NSBAR] overlay: keyWindow nil\n"); 
        return false; 
    }

    uint64_t scene = r_msg2_main(keyWin, "windowScene", 0, 0, 0, 0);
    if (!r_is_objc_ptr(scene)) { 
        printf("[NSBAR] overlay: windowScene nil\n"); 
        return false; 
    }

    // Create window
    uint64_t UIWindow = r_class("UIWindow");
    if (!r_is_objc_ptr(UIWindow)) { 
        printf("[NSBAR] overlay: UIWindow missing\n"); 
        return false; 
    }

    uint64_t winAlloc = r_msg2_main(UIWindow, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(winAlloc)) { 
        printf("[NSBAR] overlay: UIWindow alloc failed\n"); 
        return false; 
    }

    uint64_t win = r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0, 0, 0);
    if (!r_is_objc_ptr(win)) { 
        printf("[NSBAR] overlay: initWithWindowScene failed\n"); 
        return false; 
    }
    if (nsbar_should_log_tick())
        printf("[NSBAR] overlay: window=0x%llx\n", win);

    uint64_t UIColor = r_class("UIColor");
    if (r_is_objc_ptr(UIColor)) {
        uint64_t clear = r_msg2_main(UIColor, "clearColor", 0, 0, 0, 0);
        if (r_is_objc_ptr(clear)) r_msg2_main(win, "setBackgroundColor:", clear, 0, 0, 0);
    }

    // Create label
    uint64_t UILabel = r_class("UILabel");
    if (!r_is_objc_ptr(UILabel)) { 
        printf("[NSBAR] overlay: UILabel missing\n"); 
        return false; 
    }

    uint64_t labelAlloc = r_msg2_main(UILabel, "alloc", 0, 0, 0, 0);
    if (!r_is_objc_ptr(labelAlloc)) { 
        printf("[NSBAR] overlay: UILabel alloc failed\n"); 
        return false; 
    }

    uint64_t label = r_msg2_main(labelAlloc, "init", 0, 0, 0, 0);
    if (!r_is_objc_ptr(label)) { 
        printf("[NSBAR] overlay: UILabel init failed\n"); 
        return false; 
    }
    if (nsbar_should_log_tick())
        printf("[NSBAR] overlay: label=0x%llx\n", label);

    r_msg2_main(label, "setText:", textObj, 0, 0, 0);
    r_msg2_main(label, "setTag:", kNSBarOverlayTag, 0, 0, 0);
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    r_msg2_main(label, "setNumberOfLines:", 1, 0, 0, 0);
    r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", 0, 0, 0, 0);
    r_msg2_main(label, "setLineBreakMode:", 2, 0, 0, 0);

    if (r_is_objc_ptr(UIColor)) {
        uint64_t black = r_msg2_main(UIColor, "blackColor", 0, 0, 0, 0);
        uint64_t white = r_msg2_main(UIColor, "whiteColor", 0, 0, 0, 0);
        if (r_is_objc_ptr(black)) r_msg2_main(label, "setBackgroundColor:", black, 0, 0, 0);
        if (r_is_objc_ptr(white)) r_msg2_main(label, "setTextColor:", white, 0, 0, 0);
    }

    nsbar_apply_overlay_style(label);
    nsbar_make_window_click_through(win);
    nsbar_apply_overlay_layout(win, label, position, text);
    r_msg2_main(win, "addSubview:", label, 0, 0, 0);
    r_msg2_main(win, "setHidden:", 0, 0, 0, 0);
    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, win, 1, 0, 0, 0, 0);
    
    gNSBarOverlayWindow = win;
    gNSBarOverlayLabel = label;
    gNSBarLastPosition = position;
    nsbar_release_remote_obj(textObj);

    if (nsbar_should_log_tick())
        printf("[NSBAR] overlay: installed dedicated window\n");
    return true;
}

bool nsbar_apply_in_session(NSBarPosition position)
{
    gNSBarApplyTick++;
    NSString *text = build_nsbar_text();
    if (nsbar_should_log_tick()) {
        printf("[NSBAR] === entry === text='%s' position=%d tick=%llu\n",
               text.UTF8String, position, gNSBarApplyTick);
    }

    return nsbar_install_overlay(text, position);
}

bool nsbar_stop_in_session(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;

    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t assocKey = r_sel("darkswordNSBarOverlayWindow");
    if (!assocKey) return false;

    uint64_t win = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(win)) {
        r_msg2_main(win, "setHidden:", 1, 0, 0, 0);
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, 0, 1, 0, 0, 0, 0);
    }

    gNSBarOverlayWindow = 0;
    gNSBarOverlayLabel = 0;
    printf("[NSBAR] overlay: stopped\n");
    return true;
}

void nsbar_forget_remote_state(void)
{
    gNSBarOverlayWindow = 0;
    gNSBarOverlayLabel = 0;
    gNSBarSetTextSel = 0;
    gNSBarPerformMainSel = 0;
    gNSBarNSStringClass = 0;
    gNSBarAllocSel = 0;
    gNSBarInitUTF8Sel = 0;
    gNSBarUIColorClass = 0;
    gNSBarBorderColor = 0;
    printf("[NSBAR] forgot remote overlay state\n");
}
