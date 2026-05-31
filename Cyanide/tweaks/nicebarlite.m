//
//  nicebarlite.m
//  NiceBar Lite: status-bar text slots.
//

#import "nicebarlite.h"
#import "remote_objc.h"
#import "../TaskRop/RemoteCall.h"

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <math.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <stdio.h>
#import <string.h>
#import <sys/sysctl.h>
#import <time.h>
#import <unistd.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;

typedef struct {
    double x;
    double y;
    double width;
    double height;
} NBLRect;

typedef struct {
    double screenWidth;
    double screenHeight;
    double topAreaHeight;
} NBLLayout;

static const uint64_t kNBLBaseTag = 99540;
static const double kNBLFallbackScreenWidth = 390.0;
static const double kNBLWinH = 18.0;
static const double kNBLFontPt = 11.0;
static const double kNBLTopFontPt = 8.8;
// Was 999999.0/1001.0; keep it below the system status bar so scroll-to-top taps pass through.
static const double kNBLWindowLevel = 999.0;
static const double kNBLSideMargin = 20.0;
static const double kNBLTopSideMargin = 29.0;
static const double kNBLTopY = 0.0;
static const double kNBLBottomY = 38.0;
static const double kNBLTextHPad = 6.0;
static const double kNBLMinWidth = 34.0;
static const double kNBLNetworkWidth = 91.0;
static const double kNBLCornerRadius = 6.0;
static const double kNBLPillFillAlpha = 0.92;
static const double kNBLPillBorderAlpha = 0.42;
static const uint64_t kNBLPillTagBase = 99640;

static uint64_t gNBLWindow = 0;
static uint64_t gNBLPills[NiceBarLiteSlotCount] = {0};
static uint64_t gNBLLabels[NiceBarLiteSlotCount] = {0};
static uint64_t gNBLSetTextSel = 0;
static uint64_t gNBLSetTextColorSel = 0;
static uint64_t gNBLPerformMainSel = 0;
static uint64_t gNBLNSStringClass = 0;
static uint64_t gNBLAllocSel = 0;
static uint64_t gNBLInitUTF8Sel = 0;
static uint64_t gNBLUIApplicationClass = 0;
static uint64_t gNBLUIWindowClass = 0;
static uint64_t gNBLUIViewClass = 0;
static uint64_t gNBLUILabelClass = 0;
static uint64_t gNBLUIVisualEffectViewClass = 0;
static uint64_t gNBLUIBlurEffectClass = 0;
static uint64_t gNBLUIFontClass = 0;
static uint64_t gNBLUIColorClass = 0;
static uint64_t gNBLBlackColor = 0;
static uint64_t gNBLWhiteColor = 0;
static uint64_t gNBLTextColor = 0;
static uint64_t gNBLFillColor = 0;
static uint64_t gNBLBorderColor = 0;
static uint64_t gNBLClearColor = 0;
static uint64_t gNBLFontNormal = 0;
static uint64_t gNBLFontTop = 0;
static uint64_t gNBLApplyTick = 0;
static NSString *gNBLLastText[NiceBarLiteSlotCount] = { nil };
static double gNBLLastX[NiceBarLiteSlotCount] = {0};
static double gNBLLastY[NiceBarLiteSlotCount] = {0};
static double gNBLLastW[NiceBarLiteSlotCount] = {0};
static BOOL gNBLLastHidden[NiceBarLiteSlotCount] = {0};
static BOOL gNBLHasLastLayout[NiceBarLiteSlotCount] = {0};
static BOOL gNBLWindowVisible = NO;
static double gNBLLastWindowW = 0.0;
static double gNBLLastWindowH = 0.0;
static BOOL gNBLHasWindowFrame = NO;
static uint64_t gNBLReadTick = 0;
static double gNBLTickDownKB = 0.0;
static double gNBLTickUpKB = 0.0;
static double gNBLTickNowSeconds = 0.0;

static void *g_iokit = NULL;
static CFMutableDictionaryRef (*pIOServiceMatching)(const char *) = NULL;
static io_service_t (*pIOServiceGetMatchingService)(mach_port_t, CFDictionaryRef) = NULL;
static CFTypeRef (*pIORegistryEntryCreateCFProperty)(io_service_t, CFStringRef, CFAllocatorRef, uint32_t) = NULL;
static kern_return_t (*pIOObjectRelease)(io_object_t) = NULL;

static bool nbl_should_log_tick(void)
{
    return gNBLApplyTick == 1;
}

static bool nbl_ensure_iokit_symbols(void)
{
    if (!g_iokit) {
        g_iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_GLOBAL);
        if (!g_iokit) return false;
        pIOServiceMatching               = dlsym(g_iokit, "IOServiceMatching");
        pIOServiceGetMatchingService     = dlsym(g_iokit, "IOServiceGetMatchingService");
        pIORegistryEntryCreateCFProperty = dlsym(g_iokit, "IORegistryEntryCreateCFProperty");
        pIOObjectRelease                 = dlsym(g_iokit, "IOObjectRelease");
    }
    return pIOServiceMatching && pIOServiceGetMatchingService &&
           pIORegistryEntryCreateCFProperty && pIOObjectRelease;
}

static double nbl_read_battery_temp_c(void)
{
    static double cachedTempC = -1.0;
    static time_t lastRead = 0;
    time_t now = time(NULL);
    if (lastRead != 0 && now >= lastRead && (now - lastRead) < 60) return cachedTempC;
    lastRead = now;

    if (!nbl_ensure_iokit_symbols()) return cachedTempC;
    io_service_t svc = pIOServiceGetMatchingService(MACH_PORT_NULL,
                                                    pIOServiceMatching("AppleSmartBattery"));
    if (svc == MACH_PORT_NULL) return cachedTempC;

    CFNumberRef prop = (CFNumberRef)pIORegistryEntryCreateCFProperty(svc,
                                                                     CFSTR("Temperature"),
                                                                     kCFAllocatorDefault, 0);
    if (prop) {
        int64_t raw = 0;
        if (CFNumberGetValue(prop, kCFNumberSInt64Type, &raw)) {
            cachedTempC = (double)raw / 100.0;
        }
        CFRelease(prop);
    }
    pIOObjectRelease(svc);
    return cachedTempC;
}

static double nbl_read_free_ram_gb(void)
{
    mach_port_t host = mach_host_self();
    vm_statistics64_data_t stat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&stat, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS) return -1.0;
    uint64_t bytes = (uint64_t)stat.free_count * (uint64_t)vm_kernel_page_size;
    return (double)bytes / (1024.0 * 1024.0 * 1024.0);
}

static int nbl_read_battery_percent(void)
{
    UIDevice *dev = UIDevice.currentDevice;
    dev.batteryMonitoringEnabled = YES;
    float level = dev.batteryLevel;
    if (level < 0.0f) return -1;
    return (int)llroundf(level * 100.0f);
}

static int nbl_read_uptime_minutes(void)
{
    struct timeval boot;
    size_t len = sizeof(boot);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boot, &len, NULL, 0) != 0) return -1;
    time_t now = time(NULL);
    if (now <= boot.tv_sec) return -1;
    return (int)((now - boot.tv_sec) / 60);
}

static bool nbl_read_net_totals(uint64_t *ibytes, uint64_t *obytes)
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

static double nbl_now_seconds(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0.0;
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1000000000.0);
}

static void nbl_prepare_tick_metrics(void)
{
    if (gNBLReadTick == gNBLApplyTick) return;
    gNBLReadTick = gNBLApplyTick;
    gNBLTickDownKB = 0.0;
    gNBLTickUpKB = 0.0;
    gNBLTickNowSeconds = nbl_now_seconds();
    if (gNBLTickNowSeconds <= 0.0) return;

    static bool havePrev = false;
    static uint64_t prevIn = 0;
    static uint64_t prevOut = 0;
    static double prevTime = 0.0;

    uint64_t totalIn = 0;
    uint64_t totalOut = 0;
    if (!nbl_read_net_totals(&totalIn, &totalOut)) return;
    if (havePrev && gNBLTickNowSeconds > prevTime) {
        double dt = gNBLTickNowSeconds - prevTime;
        gNBLTickDownKB = ((double)((totalIn >= prevIn) ? totalIn - prevIn : 0) / dt) / 1024.0;
        gNBLTickUpKB = ((double)((totalOut >= prevOut) ? totalOut - prevOut : 0) / dt) / 1024.0;
    }
    prevIn = totalIn;
    prevOut = totalOut;
    prevTime = gNBLTickNowSeconds;
    havePrev = true;
}

static NSString *nbl_format_speed(double kbValue)
{
    if (!isfinite(kbValue) || kbValue < 0.0) kbValue = 0.0;
    if (kbValue < 999.5) return [NSString stringWithFormat:@"%lldK", (long long)llround(kbValue)];
    double mbValue = kbValue / 1024.0;
    if (mbValue < 10.0) return [NSString stringWithFormat:@"%.1fM", mbValue];
    return [NSString stringWithFormat:@"%.0fM", mbValue];
}

static NSString *nbl_lunar_date_text(void);
static NSString *nbl_lunar_date_text_cn(bool full);

static bool nbl_date_format_uses_chinese_locale(NSString *format)
{
    return [format isEqualToString:@"a h:mm"] ||
           [format rangeOfString:@"月"].location != NSNotFound;
}

static NSString *nbl_chinese_weekday_text(void)
{
    NSInteger weekday = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:[NSDate date]];
    NSArray<NSString *> *weekdays = @[@"", @"星期日", @"星期一", @"星期二", @"星期三", @"星期四", @"星期五", @"星期六"];
    if (weekday < 1 || weekday >= (NSInteger)weekdays.count) return @"星期-";
    return weekdays[(NSUInteger)weekday];
}

static NSString *nbl_date_with_format(NSString *format)
{
    if (format.length == 0) format = @"HH:mm";
    if ([format isEqualToString:@"cyanide:lunar"]) return nbl_lunar_date_text();
    if ([format isEqualToString:@"cyanide:lunar-cn"]) return nbl_lunar_date_text_cn(false);
    if ([format isEqualToString:@"cyanide:lunar-cn-full"]) return nbl_lunar_date_text_cn(true);
    if ([format isEqualToString:@"cyanide:cn-date-weekday"] || [format isEqualToString:@"M月d日 EEE"]) {
        return [NSString stringWithFormat:@"%@ %@", nbl_date_with_format(@"M月d日"), nbl_chinese_weekday_text()];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = nbl_date_format_uses_chinese_locale(format)
        ? [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"]
        : [NSLocale currentLocale];
    formatter.dateFormat = format;
    NSString *text = [formatter stringFromDate:[NSDate date]];
    return text.length ? text : @"--";
}

static NSString *nbl_lunar_date_text(void)
{
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    if (c.month <= 0 || c.day <= 0) return @"Lunar --";
    return [NSString stringWithFormat:@"L%02ld/%02ld", (long)c.month, (long)c.day];
}

static NSString *nbl_lunar_date_text_cn(bool full)
{
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    if (c.month <= 0 || c.day <= 0) return @"农历--";
    NSArray<NSString *> *months = @[
        @"正月", @"二月", @"三月", @"四月", @"五月", @"六月",
        @"七月", @"八月", @"九月", @"十月", @"冬月", @"腊月",
    ];
    NSArray<NSString *> *days = @[
        @"初一", @"初二", @"初三", @"初四", @"初五", @"初六", @"初七", @"初八", @"初九", @"初十",
        @"十一", @"十二", @"十三", @"十四", @"十五", @"十六", @"十七", @"十八", @"十九", @"二十",
        @"廿一", @"廿二", @"廿三", @"廿四", @"廿五", @"廿六", @"廿七", @"廿八", @"廿九", @"三十",
    ];
    NSString *month = (c.month >= 1 && c.month <= (NSInteger)months.count) ? months[(NSUInteger)c.month - 1] : @"";
    NSString *day = (c.day >= 1 && c.day <= (NSInteger)days.count) ? days[(NSUInteger)c.day - 1] : @"";
    if (!month.length || !day.length) return @"农历--";
    return full ? [NSString stringWithFormat:@"农历%@%@", month, day]
                : [NSString stringWithFormat:@"%@%@", month, day];
}

static NSString *nbl_system_text(int item, bool celsius)
{
    switch (item) {
        case NiceBarLiteSystemBatteryTemp: {
            double tempC = nbl_read_battery_temp_c();
            if (tempC <= 0.0) return @"--";
            double v = celsius ? tempC : (tempC * 9.0 / 5.0 + 32.0);
            return [NSString stringWithFormat:@"%.1f%c", v, celsius ? 'C' : 'F'];
        }
        case NiceBarLiteSystemFreeRAM: {
            double ram = nbl_read_free_ram_gb();
            if (ram <= 0.0) return @"--";
            if (ram < 1.0) return [NSString stringWithFormat:@"%.0fMB", ram * 1024.0];
            return [NSString stringWithFormat:@"%.2fGB", ram];
        }
        case NiceBarLiteSystemBatteryPercent: {
            int pct = nbl_read_battery_percent();
            return pct >= 0 ? [NSString stringWithFormat:@"%d%%", pct] : @"--";
        }
        case NiceBarLiteSystemNetworkSpeed: {
            double down = gNBLTickDownKB;
            double up = gNBLTickUpKB;
            return [NSString stringWithFormat:@"↓%@↑%@", nbl_format_speed(down), nbl_format_speed(up)];
        }
        case NiceBarLiteSystemUptime: {
            int minutes = nbl_read_uptime_minutes();
            if (minutes < 0) return @"--";
            int hours = minutes / 60;
            int mins = minutes % 60;
            if (hours >= 24) return [NSString stringWithFormat:@"%dd%dh", hours / 24, hours % 24];
            return [NSString stringWithFormat:@"%dh%02dm", hours, mins];
        }
        case NiceBarLiteSystemDate:
            return nbl_date_with_format(@"M/d");
        case NiceBarLiteSystemLunarDate:
            return nbl_lunar_date_text();
        default:
            return @"--";
    }
}

static NSString *nbl_text_for_slot(NiceBarLiteSlotConfig slot, bool celsius)
{
    switch (slot.kind) {
        case NiceBarLiteContentCustomText:
            return slot.customText && slot.customText[0] ? @(slot.customText) : @"Text";
        case NiceBarLiteContentSystem:
            return nbl_system_text(slot.systemItem, celsius);
        case NiceBarLiteContentTimeFormat:
            return nbl_date_with_format(slot.timeFormat && slot.timeFormat[0] ? @(slot.timeFormat) : @"HH:mm");
        case NiceBarLiteContentWeather:
            return slot.weatherText && slot.weatherText[0] ? @(slot.weatherText) : @"Weather --";
        case NiceBarLiteContentOff:
        default:
            return @"";
    }
}

static bool nbl_valid_screen_length(double v)
{
    return isfinite(v) && v >= 100.0 && v <= 2000.0;
}

static double nbl_fallback_top_area(double screenWidth, double screenHeight)
{
    double shortSide = fmin(screenWidth, screenHeight);
    double longSide = fmax(screenWidth, screenHeight);
    if (!nbl_valid_screen_length(shortSide) || !nbl_valid_screen_length(longSide)) return 20.0;
    if (longSide >= 852.0 && shortSide >= 390.0) return 59.0;
    if (longSide >= 844.0 && shortSide >= 390.0) return 47.0;
    if (longSide >= 812.0 && shortSide >= 375.0) return 44.0;
    return 20.0;
}

static NBLLayout nbl_read_layout(void)
{
    NBLLayout m = { kNBLFallbackScreenWidth, 844.0, 47.0 };
    CGRect b = UIScreen.mainScreen.bounds;
    if (nbl_valid_screen_length(b.size.width)) m.screenWidth = b.size.width;
    if (nbl_valid_screen_length(b.size.height)) m.screenHeight = b.size.height;
    m.topAreaHeight = nbl_fallback_top_area(m.screenWidth, m.screenHeight);
    return m;
}

static double nbl_top_row_y(double topAreaHeight)
{
    (void)topAreaHeight;
    return kNBLTopY;
}

static double nbl_bottom_row_y(double topAreaHeight)
{
    (void)topAreaHeight;
    return kNBLBottomY;
}

static bool nbl_send_double_main(uint64_t obj, const char *selName, double value)
{
    if (!r_is_objc_ptr(obj)) return false;
    r_msg2_main_raw(obj, selName,
                    &value, sizeof(value),
                    NULL, 0, NULL, 0, NULL, 0);
    return true;
}

static bool nbl_send_rect_main(uint64_t obj, const char *selName,
                               double x, double y, double width, double height)
{
    if (!r_is_objc_ptr(obj)) return false;
    NBLRect rect = { x, y, width, height };
    r_msg2_main_raw(obj, selName,
                    &rect, sizeof(rect),
                    NULL, 0, NULL, 0, NULL, 0);
    return true;
}

static void nbl_make_label_click_through(uint64_t label)
{
    if (!r_is_objc_ptr(label)) return;
    r_msg2_main(label, "setUserInteractionEnabled:", 0, 0, 0, 0);
    r_msg2_main(label, "setMultipleTouchEnabled:", 0, 0, 0, 0);
    r_msg2_main(label, "setExclusiveTouch:", 0, 0, 0, 0);
}

static void nbl_make_window_click_through(uint64_t win)
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

static void nbl_purge_legacy_window_labels(void)
{
    if (!r_is_objc_ptr(gNBLWindow)) return;
    uint64_t subviews = r_msg2_main(gNBLWindow, "subviews", 0, 0, 0, 0);
    if (!r_is_objc_ptr(subviews)) return;
    uint64_t count = r_msg2_main(subviews, "count", 0, 0, 0, 0);
    if (count == 0 || count > 128) return;

    for (uint64_t idx = count; idx > 0; idx--) {
        uint64_t child = r_msg2_main(subviews, "objectAtIndex:", idx - 1, 0, 0, 0);
        if (!r_is_objc_ptr(child)) continue;
        uint64_t tag = r_msg2_main(child, "tag", 0, 0, 0, 0);
        if (tag >= kNBLBaseTag && tag < kNBLBaseTag + NiceBarLiteSlotCount) {
            r_msg2_main(child, "setHidden:", 1, 0, 0, 0);
            r_msg2_main(child, "removeFromSuperview", 0, 0, 0, 0);
        }
    }
}

static bool nbl_create_or_fetch_window(void);
static uint64_t nbl_nsstring_utf8_fast(const char *cstr)
{
    if (!cstr) cstr = "";
    uint64_t buf = r_alloc_str(cstr);
    if (!buf) return 0;
    if (!gNBLNSStringClass) gNBLNSStringClass = r_class("NSString");
    if (!gNBLAllocSel) gNBLAllocSel = r_sel("alloc");
    if (!gNBLInitUTF8Sel) gNBLInitUTF8Sel = r_sel("initWithUTF8String:");
    if (!r_is_objc_ptr(gNBLNSStringClass) || !gNBLAllocSel || !gNBLInitUTF8Sel) {
        r_free(buf);
        return 0;
    }
    uint64_t allocated = r_msg(gNBLNSStringClass, gNBLAllocSel, 0, 0, 0, 0);
    uint64_t ns = r_is_objc_ptr(allocated) ? r_msg(allocated, gNBLInitUTF8Sel, buf, 0, 0, 0) : 0;
    r_free(buf);
    return ns;
}

static void nbl_release_remote_obj(uint64_t obj)
{
    if (!r_is_objc_ptr(obj)) return;
    r_dlsym_call(R_TIMEOUT, "CFRelease", obj, 0, 0, 0, 0, 0, 0, 0);
}

static bool nbl_set_text_fast(uint64_t label, uint64_t textObj)
{
    if (!r_is_objc_ptr(label) || !r_is_objc_ptr(textObj)) return false;
    if (!gNBLSetTextSel) gNBLSetTextSel = r_sel("setText:");
    if (!gNBLSetTextSel) return false;
    r_msg2_main(label, "setText:", textObj, 0, 0, 0);
    return true;
}

static uint64_t nbl_status_text_color(void)
{
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNBLUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNBLTextColor)) {
        double white = 1.0;
        double alpha = 0.96;
        gNBLTextColor = r_msg2_main_raw(gNBLUIColorClass, "colorWithWhite:alpha:",
                                        &white, sizeof(white),
                                        &alpha, sizeof(alpha),
                                        NULL, 0, NULL, 0);
    }
    if (r_is_objc_ptr(gNBLTextColor)) return gNBLTextColor;
    if (!r_is_objc_ptr(gNBLWhiteColor)) {
        gNBLWhiteColor = r_msg2_main(gNBLUIColorClass, "whiteColor", 0, 0, 0, 0);
    }
    return gNBLWhiteColor;
}

static uint64_t nbl_pill_fill_color(void)
{
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNBLUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNBLFillColor)) {
        double white = 0.0;
        double alpha = kNBLPillFillAlpha;
        gNBLFillColor = r_msg2_main_raw(gNBLUIColorClass, "colorWithWhite:alpha:",
                                        &white, sizeof(white),
                                        &alpha, sizeof(alpha),
                                        NULL, 0, NULL, 0);
    }
    if (r_is_objc_ptr(gNBLFillColor)) return gNBLFillColor;
    if (!r_is_objc_ptr(gNBLBlackColor)) {
        gNBLBlackColor = r_msg2_main(gNBLUIColorClass, "blackColor", 0, 0, 0, 0);
    }
    return gNBLBlackColor;
}

static uint64_t nbl_pill_border_color(void)
{
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (!r_is_objc_ptr(gNBLUIColorClass)) return 0;
    if (!r_is_objc_ptr(gNBLBorderColor)) {
        double white = 0.72;
        double alpha = kNBLPillBorderAlpha;
        gNBLBorderColor = r_msg2_main_raw(gNBLUIColorClass, "colorWithWhite:alpha:",
                                          &white, sizeof(white),
                                          &alpha, sizeof(alpha),
                                          NULL, 0, NULL, 0);
    }
    return gNBLBorderColor;
}

static double nbl_font_size_for_slot(NiceBarLiteSlot slot)
{
    return (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
        ? kNBLTopFontPt
        : kNBLFontPt;
}

static double nbl_side_margin_for_slot(NiceBarLiteSlot slot)
{
    return (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
        ? kNBLTopSideMargin
        : kNBLSideMargin;
}

static void nbl_apply_label_style(uint64_t label, NiceBarLiteSlot slot)
{
    if (!r_is_objc_ptr(label)) return;
    nbl_make_label_click_through(label);

    if (!r_is_objc_ptr(gNBLUIFontClass)) gNBLUIFontClass = r_class("UIFont");
    if (r_is_objc_ptr(gNBLUIFontClass)) {
        uint64_t *fontCache = (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
            ? &gNBLFontTop
            : &gNBLFontNormal;
        double size = nbl_font_size_for_slot(slot);
        double weight = 0.0;
        if (!r_is_objc_ptr(*fontCache)) {
            *fontCache = r_msg2_main_raw(gNBLUIFontClass, "monospacedDigitSystemFontOfSize:weight:",
                                         &size, sizeof(size),
                                         &weight, sizeof(weight),
                                         NULL, 0, NULL, 0);
            if (!r_is_objc_ptr(*fontCache)) {
                *fontCache = r_msg2_main_raw(gNBLUIFontClass, "systemFontOfSize:",
                                             &size, sizeof(size),
                                             NULL, 0, NULL, 0, NULL, 0);
            }
        }
        if (r_is_objc_ptr(*fontCache)) r_msg2_main(label, "setFont:", *fontCache, 0, 0, 0);
    }

    uint64_t color = nbl_status_text_color();
    if (r_is_objc_ptr(color)) r_msg2_main(label, "setTextColor:", color, 0, 0, 0);
    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (r_is_objc_ptr(gNBLUIColorClass) && !r_is_objc_ptr(gNBLClearColor)) {
        gNBLClearColor = r_msg2_main(gNBLUIColorClass, "clearColor", 0, 0, 0, 0);
    }
    if (r_is_objc_ptr(gNBLClearColor)) r_msg2_main(label, "setBackgroundColor:", gNBLClearColor, 0, 0, 0);
    r_msg2_main(label, "setOpaque:", 0, 0, 0, 0);
    if (r_responds_main(label, "setClearsContextBeforeDrawing:")) {
        r_msg2_main(label, "setClearsContextBeforeDrawing:", 1, 0, 0, 0);
    }
    r_msg2_main(label, "setClipsToBounds:", 1, 0, 0, 0);
    r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", 1, 0, 0, 0);
    r_msg2_main(label, "setLineBreakMode:", 2, 0, 0, 0); // NSLineBreakByClipping
}

static void nbl_apply_pill_style(uint64_t pill)
{
    if (!r_is_objc_ptr(pill)) return;
    nbl_make_label_click_through(pill);

    uint64_t fill = nbl_pill_fill_color();
    if (r_is_objc_ptr(fill)) r_msg2_main(pill, "setBackgroundColor:", fill, 0, 0, 0);
    r_msg2_main(pill, "setOpaque:", 0, 0, 0, 0);
    r_msg2_main(pill, "setClipsToBounds:", 1, 0, 0, 0);

    uint64_t layer = r_msg2_main(pill, "layer", 0, 0, 0, 0);
    if (r_is_objc_ptr(layer)) {
        double radius = kNBLCornerRadius;
        double borderWidth = 0.5;
        nbl_send_double_main(layer, "setCornerRadius:", radius);
        r_msg2_main(layer, "setMasksToBounds:", 1, 0, 0, 0);
        nbl_send_double_main(layer, "setBorderWidth:", borderWidth);
        uint64_t borderColor = nbl_pill_border_color();
        if (r_is_objc_ptr(borderColor)) {
            uint64_t cgColor = r_msg2_main(borderColor, "CGColor", 0, 0, 0, 0);
            if (cgColor) r_msg2_main(layer, "setBorderColor:", cgColor, 0, 0, 0);
        }
    }
}

static void nbl_refresh_text_colors(void)
{
    uint64_t color = nbl_status_text_color();
    if (!r_is_objc_ptr(color)) return;
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        if (r_is_objc_ptr(gNBLLabels[i])) {
            r_msg2_main(gNBLLabels[i], "setTextColor:", color, 0, 0, 0);
        }
    }
}

static uint64_t nbl_ensure_pill(NiceBarLiteSlot slot)
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return 0;
    if (r_is_objc_ptr(gNBLPills[slot])) return gNBLPills[slot];
    if (!nbl_create_or_fetch_window()) return 0;

    uint64_t existing = r_msg2_main(gNBLWindow, "viewWithTag:", kNBLPillTagBase + slot, 0, 0, 0);
    if (r_is_objc_ptr(existing)) {
        gNBLPills[slot] = existing;
        nbl_apply_pill_style(existing);
        return existing;
    }

    if (!r_is_objc_ptr(gNBLUIViewClass)) gNBLUIViewClass = r_class("UIView");
    uint64_t alloc = r_is_objc_ptr(gNBLUIViewClass)
        ? r_msg2_main(gNBLUIViewClass, "alloc", 0, 0, 0, 0)
        : 0;
    uint64_t pill = r_is_objc_ptr(alloc) ? r_msg2_main(alloc, "init", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(pill)) return 0;

    r_msg2_main(pill, "setTag:", kNBLPillTagBase + slot, 0, 0, 0);
    r_msg2_main(pill, "setHidden:", 1, 0, 0, 0);
    nbl_apply_pill_style(pill);
    r_msg2_main(gNBLWindow, "addSubview:", pill, 0, 0, 0);
    gNBLPills[slot] = pill;
    return pill;
}

static double nbl_measure_text_width(NSString *text, NiceBarLiteSlot slot)
{
    if (text.length == 0) return 0.0;
    UIFont *font = nil;
    double size = nbl_font_size_for_slot(slot);
    if (@available(iOS 9.0, *)) {
        font = [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightRegular];
    }
    if (!font) font = [UIFont systemFontOfSize:size];
    NSDictionary *attrs = @{ NSFontAttributeName: font };
    return ceil([text sizeWithAttributes:attrs].width);
}

static BOOL nbl_slot_is_network_speed(NiceBarLiteSlotConfig slot)
{
    return slot.kind == NiceBarLiteContentSystem &&
           slot.systemItem == NiceBarLiteSystemNetworkSpeed;
}

static double nbl_width_for_text(NSString *text,
                                 NiceBarLiteSlot slot,
                                 NiceBarLiteSlotConfig config,
                                 NBLLayout layout)
{
    if (text.length == 0) return 1.0;
    double maxWidth = slot == NiceBarLiteSlotBottomCenter
        ? (layout.screenWidth * 0.34)
        : (layout.screenWidth * 0.5) - nbl_side_margin_for_slot(slot) - 4.0;
    if (maxWidth < kNBLMinWidth) maxWidth = kNBLMinWidth;
    double width = nbl_slot_is_network_speed(config)
        ? kNBLNetworkWidth
        : nbl_measure_text_width(text, slot) + (kNBLTextHPad * 2.0);
    if (width < kNBLMinWidth) width = kNBLMinWidth;
    if (width > maxWidth) width = maxWidth;
    return width;
}

static NBLRect nbl_rect_for_slot(NiceBarLiteSlot slot,
                                 NiceBarLiteSlotConfig config,
                                 NSString *text,
                                 NBLLayout layout)
{
    double width = nbl_width_for_text(text, slot, config, layout);
    double x = 0.0;
    double sideMargin = nbl_side_margin_for_slot(slot);
    double y = (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotTopRight)
        ? nbl_top_row_y(layout.topAreaHeight)
        : nbl_bottom_row_y(layout.topAreaHeight);

    if (slot == NiceBarLiteSlotBottomCenter) {
        x = (layout.screenWidth - width) * 0.5;
    } else if (slot == NiceBarLiteSlotTopLeft || slot == NiceBarLiteSlotBottomLeft) {
        x = sideMargin;
    } else {
        x = layout.screenWidth - width - sideMargin;
    }
    return (NBLRect){ floor(x), floor(y), width, kNBLWinH };
}

static bool nbl_layout_slot(uint64_t label,
                            NiceBarLiteSlot slot,
                            NiceBarLiteSlotConfig config,
                            NSString *text,
                            NBLLayout layout)
{
    if (!r_is_objc_ptr(label)) return false;
    NBLRect rect = nbl_rect_for_slot(slot, config, text, layout);
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    return nbl_send_rect_main(label, "setFrame:", rect.x, rect.y, rect.width, rect.height);
}

static bool nbl_create_or_fetch_window(void)
{
    if (r_is_objc_ptr(gNBLWindow)) return true;

    if (!r_is_objc_ptr(gNBLUIApplicationClass)) gNBLUIApplicationClass = r_class("UIApplication");
    if (!r_is_objc_ptr(gNBLUIApplicationClass)) return false;
    uint64_t app = r_msg2_main(gNBLUIApplicationClass, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t assocKey = r_sel("cyanideNiceBarLiteWindow");
    if (!assocKey) return false;
    uint64_t cached = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                   app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(cached)) {
        gNBLWindow = cached;
        nbl_make_window_click_through(gNBLWindow);
        nbl_purge_legacy_window_labels();
        return true;
    }

    uint64_t keyWin = r_msg2_main(app, "keyWindow", 0, 0, 0, 0);
    if (!r_is_objc_ptr(keyWin)) {
        uint64_t windows = r_msg2_main(app, "windows", 0, 0, 0, 0);
        uint64_t count = r_is_objc_ptr(windows) ? r_msg2_main(windows, "count", 0, 0, 0, 0) : 0;
        if (count > 0 && count < 64) keyWin = r_msg2_main(windows, "objectAtIndex:", 0, 0, 0, 0);
    }
    if (!r_is_objc_ptr(keyWin)) return false;
    uint64_t scene = r_msg2_main(keyWin, "windowScene", 0, 0, 0, 0);
    if (!r_is_objc_ptr(scene)) return false;

    if (!r_is_objc_ptr(gNBLUIWindowClass)) gNBLUIWindowClass = r_class("UIWindow");
    if (!r_is_objc_ptr(gNBLUIWindowClass)) return false;
    uint64_t winAlloc = r_msg2_main(gNBLUIWindowClass, "alloc", 0, 0, 0, 0);
    uint64_t win = r_is_objc_ptr(winAlloc) ? r_msg2_main(winAlloc, "initWithWindowScene:", scene, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(win)) return false;

    if (!r_is_objc_ptr(gNBLUIColorClass)) gNBLUIColorClass = r_class("UIColor");
    if (r_is_objc_ptr(gNBLUIColorClass)) {
        if (!r_is_objc_ptr(gNBLClearColor)) {
            gNBLClearColor = r_msg2_main(gNBLUIColorClass, "clearColor", 0, 0, 0, 0);
        }
        if (r_is_objc_ptr(gNBLClearColor)) r_msg2_main(win, "setBackgroundColor:", gNBLClearColor, 0, 0, 0);
    }
    nbl_send_double_main(win, "setWindowLevel:", kNBLWindowLevel);
    nbl_make_window_click_through(win);

    r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, win, 1, 0, 0, 0, 0);
    gNBLWindow = win;
    nbl_purge_legacy_window_labels();
    return true;
}

static uint64_t nbl_ensure_label(NiceBarLiteSlot slot)
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return 0;
    if (r_is_objc_ptr(gNBLLabels[slot])) return gNBLLabels[slot];
    uint64_t pill = nbl_ensure_pill(slot);
    if (!r_is_objc_ptr(pill)) return 0;

    uint64_t existing = r_msg2_main(pill, "viewWithTag:", kNBLBaseTag + slot, 0, 0, 0);
    if (!r_is_objc_ptr(existing) && r_is_objc_ptr(gNBLWindow)) {
        existing = r_msg2_main(gNBLWindow, "viewWithTag:", kNBLBaseTag + slot, 0, 0, 0);
        if (r_is_objc_ptr(existing)) {
            r_msg2_main(existing, "removeFromSuperview", 0, 0, 0, 0);
            uint64_t content = r_msg2_main(pill, "contentView", 0, 0, 0, 0);
            uint64_t parent = r_is_objc_ptr(content) ? content : pill;
            r_msg2_main(parent, "addSubview:", existing, 0, 0, 0);
        }
    }
    if (r_is_objc_ptr(existing)) {
        gNBLLabels[slot] = existing;
        gNBLHasLastLayout[slot] = NO;
        gNBLLastText[slot] = nil;
        nbl_apply_label_style(existing, slot);
        return existing;
    }

    if (!r_is_objc_ptr(gNBLUILabelClass)) gNBLUILabelClass = r_class("UILabel");
    if (!r_is_objc_ptr(gNBLUILabelClass)) return 0;
    uint64_t labelAlloc = r_msg2_main(gNBLUILabelClass, "alloc", 0, 0, 0, 0);
    uint64_t label = r_is_objc_ptr(labelAlloc) ? r_msg2_main(labelAlloc, "init", 0, 0, 0, 0) : 0;
    if (!r_is_objc_ptr(label)) return 0;

    r_msg2_main(label, "setTag:", kNBLBaseTag + slot, 0, 0, 0);
    r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
    r_msg2_main(label, "setNumberOfLines:", 1, 0, 0, 0);
    r_msg2_main(label, "setHidden:", 1, 0, 0, 0);
    nbl_apply_label_style(label, slot);
    uint64_t content = r_msg2_main(pill, "contentView", 0, 0, 0, 0);
    uint64_t parent = r_is_objc_ptr(content) ? content : pill;
    r_msg2_main(parent, "addSubview:", label, 0, 0, 0);

    gNBLLabels[slot] = label;
    gNBLHasLastLayout[slot] = NO;
    gNBLLastText[slot] = nil;
    return label;
}

bool nicebarlite_apply_in_session(NiceBarLiteConfig config)
{
    gNBLApplyTick++;
    nbl_prepare_tick_metrics();
    uint32_t updateMask = config.updateMask;
    BOOL updateAll = (updateMask == 0);

    NSString *texts[NiceBarLiteSlotCount] = { nil };
    BOOL hidden[NiceBarLiteSlotCount] = { NO };
    BOOL hasVisibleSlot = NO;
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        if (!updateAll && ((updateMask & (1u << i)) == 0)) continue;
        texts[i] = nbl_text_for_slot(config.slots[i], config.celsius);
        hidden[i] = texts[i].length == 0;
        if (!hidden[i]) hasVisibleSlot = YES;
    }

    if (updateAll && !hasVisibleSlot) {
        if (r_is_objc_ptr(gNBLWindow) && gNBLWindowVisible) {
            r_msg2_main(gNBLWindow, "setHidden:", 1, 0, 0, 0);
            gNBLWindowVisible = NO;
        }
        for (int i = 0; i < NiceBarLiteSlotCount; i++) {
            uint64_t view = r_is_objc_ptr(gNBLPills[i]) ? gNBLPills[i] : gNBLLabels[i];
            if (r_is_objc_ptr(view) && (!gNBLHasLastLayout[i] || !gNBLLastHidden[i])) {
                r_msg2_main(view, "setHidden:", 1, 0, 0, 0);
                gNBLLastHidden[i] = YES;
                gNBLHasLastLayout[i] = YES;
            }
        }
        return true;
    }

    if (!updateAll && !r_is_objc_ptr(gNBLWindow)) return false;
    if (!nbl_create_or_fetch_window()) {
        printf("[NICEBARLITE] failed to create overlay window\n");
        return false;
    }

    NBLLayout layout = nbl_read_layout();
    double windowH = layout.topAreaHeight + 24.0;
    if (!gNBLHasWindowFrame ||
        fabs(gNBLLastWindowW - layout.screenWidth) > 0.5 ||
        fabs(gNBLLastWindowH - windowH) > 0.5) {
        nbl_send_rect_main(gNBLWindow, "setFrame:", 0.0, 0.0, layout.screenWidth, windowH);
        nbl_send_double_main(gNBLWindow, "setWindowLevel:", kNBLWindowLevel);
        gNBLLastWindowW = layout.screenWidth;
        gNBLLastWindowH = windowH;
        gNBLHasWindowFrame = YES;
    }
    if (!gNBLWindowVisible) {
        nbl_refresh_text_colors();
    }

    bool ok = true;
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        if (!updateAll && ((updateMask & (1u << i)) == 0)) continue;
        NSString *text = texts[i];
        uint64_t label = gNBLLabels[i];
        if (hidden[i]) {
            uint64_t view = r_is_objc_ptr(gNBLPills[i]) ? gNBLPills[i] : label;
            if (r_is_objc_ptr(view) && (!gNBLHasLastLayout[i] || !gNBLLastHidden[i])) {
                r_msg2_main(view, "setHidden:", 1, 0, 0, 0);
                gNBLLastHidden[i] = YES;
                gNBLHasLastLayout[i] = YES;
            }
            continue;
        }

        label = nbl_ensure_label((NiceBarLiteSlot)i);
        if (!r_is_objc_ptr(label)) {
            ok = false;
            continue;
        }
        uint64_t pill = gNBLPills[i];
        if (!r_is_objc_ptr(pill)) pill = label;

        BOOL networkSpeed = nbl_slot_is_network_speed(config.slots[i]);
        r_msg2_main(label, "setAdjustsFontSizeToFitWidth:", networkSpeed ? 0 : 1, 0, 0, 0);
        NBLRect rect = nbl_rect_for_slot((NiceBarLiteSlot)i, config.slots[i], text, layout);
        BOOL textChanged = !gNBLLastText[i] || ![gNBLLastText[i] isEqualToString:text];
        BOOL layoutChanged = !gNBLHasLastLayout[i] ||
                             fabs(gNBLLastX[i] - rect.x) > 0.5 ||
                             fabs(gNBLLastY[i] - rect.y) > 0.5 ||
                             fabs(gNBLLastW[i] - rect.width) > 0.5;
        BOOL hiddenChanged = !gNBLHasLastLayout[i] || gNBLLastHidden[i] != hidden[i];

        if (textChanged) {
            uint64_t textObj = nbl_nsstring_utf8_fast(text.UTF8String);
            if (!r_is_objc_ptr(textObj)) {
                ok = false;
            } else {
                ok &= nbl_set_text_fast(label, textObj);
                nbl_release_remote_obj(textObj);
                gNBLLastText[i] = [text copy];
            }
        }
        if (layoutChanged) {
            r_msg2_main(label, "setTextAlignment:", 1, 0, 0, 0);
            ok &= nbl_send_rect_main(pill, "setFrame:", rect.x, rect.y, rect.width, rect.height);
            ok &= nbl_send_rect_main(label, "setFrame:", 0.0, 0.0, rect.width, rect.height);
            gNBLLastX[i] = rect.x;
            gNBLLastY[i] = rect.y;
            gNBLLastW[i] = rect.width;
        }
        if (hiddenChanged) {
            r_msg2_main(pill, "setHidden:", hidden[i] ? 1 : 0, 0, 0, 0);
            r_msg2_main(label, "setHidden:", hidden[i] ? 1 : 0, 0, 0, 0);
            gNBLLastHidden[i] = hidden[i];
        }
        gNBLHasLastLayout[i] = YES;
    }

    if (!gNBLWindowVisible) {
        r_msg2_main(gNBLWindow, "setHidden:", 0, 0, 0, 0);
        gNBLWindowVisible = YES;
    }

    if (nbl_should_log_tick()) {
        printf("[NICEBARLITE] applied overlay screen=%.1fx%.1f top=%.1f ok=%d\n",
               layout.screenWidth, layout.screenHeight, layout.topAreaHeight, ok);
    }
    return ok;
}

bool nicebarlite_stop_in_session(void)
{
    uint64_t UIApplication = r_class("UIApplication");
    if (!r_is_objc_ptr(UIApplication)) return false;
    uint64_t app = r_msg2_main(UIApplication, "sharedApplication", 0, 0, 0, 0);
    if (!r_is_objc_ptr(app)) return false;

    uint64_t assocKey = r_sel("cyanideNiceBarLiteWindow");
    if (!assocKey) return false;
    uint64_t win = r_dlsym_call(R_TIMEOUT, "objc_getAssociatedObject",
                                app, assocKey, 0, 0, 0, 0, 0, 0);
    if (r_is_objc_ptr(win)) {
        r_msg2_main(win, "setHidden:", 1, 0, 0, 0);
        r_dlsym_call(R_TIMEOUT, "objc_setAssociatedObject", app, assocKey, 0, 1, 0, 0, 0, 0);
    }
    nicebarlite_forget_remote_state();
    printf("[NICEBARLITE] stopped\n");
    return true;
}

void nicebarlite_forget_remote_state(void)
{
    gNBLWindow = 0;
    for (int i = 0; i < NiceBarLiteSlotCount; i++) {
        gNBLPills[i] = 0;
        gNBLLabels[i] = 0;
        gNBLLastText[i] = nil;
        gNBLLastX[i] = 0.0;
        gNBLLastY[i] = 0.0;
        gNBLLastW[i] = 0.0;
        gNBLLastHidden[i] = NO;
        gNBLHasLastLayout[i] = NO;
    }
    gNBLWindowVisible = NO;
    gNBLLastWindowW = 0.0;
    gNBLLastWindowH = 0.0;
    gNBLHasWindowFrame = NO;
    gNBLSetTextSel = 0;
    gNBLSetTextColorSel = 0;
    gNBLPerformMainSel = 0;
    gNBLNSStringClass = 0;
    gNBLAllocSel = 0;
    gNBLInitUTF8Sel = 0;
    gNBLUIApplicationClass = 0;
    gNBLUIWindowClass = 0;
    gNBLUIViewClass = 0;
    gNBLUILabelClass = 0;
    gNBLUIVisualEffectViewClass = 0;
    gNBLUIBlurEffectClass = 0;
    gNBLUIFontClass = 0;
    gNBLUIColorClass = 0;
    gNBLBlackColor = 0;
    gNBLWhiteColor = 0;
    gNBLTextColor = 0;
    gNBLFillColor = 0;
    gNBLBorderColor = 0;
    gNBLClearColor = 0;
    gNBLFontNormal = 0;
    gNBLFontTop = 0;
}
