//
//  nicebarlite.h
//  NiceBar Lite: status-bar text slots.
//

#ifndef nicebarlite_h
#define nicebarlite_h

#import <stdbool.h>
#import <stdint.h>

typedef enum {
    NiceBarLiteSlotTopLeft = 0,
    NiceBarLiteSlotTopRight = 1,
    NiceBarLiteSlotBottomLeft = 2,
    NiceBarLiteSlotBottomRight = 3,
    NiceBarLiteSlotBottomCenter = 4,
    NiceBarLiteSlotCount = 5
} NiceBarLiteSlot;

typedef enum {
    NiceBarLiteContentOff = 0,
    NiceBarLiteContentCustomText = 1,
    NiceBarLiteContentSystem = 2,
    NiceBarLiteContentTimeFormat = 3,
    NiceBarLiteContentWeather = 4
} NiceBarLiteContentKind;

typedef enum {
    NiceBarLiteSystemBatteryTemp = 0,
    NiceBarLiteSystemFreeRAM = 1,
    NiceBarLiteSystemBatteryPercent = 2,
    NiceBarLiteSystemNetworkSpeed = 3,
    NiceBarLiteSystemUptime = 4,
    NiceBarLiteSystemDate = 5,
    NiceBarLiteSystemLunarDate = 6,
    NiceBarLiteSystemTodayTraffic = 7,
    NiceBarLiteSystemCurrentIP = 8,
    NiceBarLiteSystemFreeDisk = 9,
    NiceBarLiteSystemThermalState = 10,
    NiceBarLiteSystemLast = NiceBarLiteSystemThermalState
} NiceBarLiteSystemItem;

typedef struct {
    int kind;
    int systemItem;
    const char *customText;
    const char *timeFormat;
    const char *weatherText;
    const char *systemLanguage;
} NiceBarLiteSlotConfig;

typedef struct {
    NiceBarLiteSlotConfig slots[NiceBarLiteSlotCount];
    bool celsius;
    uint32_t updateMask;
} NiceBarLiteConfig;

bool nicebarlite_apply_in_session(NiceBarLiteConfig config);
bool nicebarlite_stop_in_session(void);
void nicebarlite_forget_remote_state(void);

#endif /* nicebarlite_h */
