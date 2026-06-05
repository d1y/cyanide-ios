//
//  SettingsViewController.m
//  Cyanide
//

#import "SettingsViewController.h"
#import "kexploit/kexploit_opa334.h"
#import "tweaks/sbcustomizer.h"
#import "tweaks/powercuff.h"
#import "tweaks/statbar.h"
#import <objc/runtime.h>
#import "tweaks/nsbar.h"
#import "tweaks/nicebarlite.h"
#import "tweaks/rssidisplay.h"
#import "tweaks/axonlite.h"
#import "tweaks/typebanner.h"
#import "tweaks/darksword_tweaks.h"
#import "tweaks/darksword_drag.h"
#import "tweaks/darksword_ota.h"
#import "tweaks/darksword_layout.h"
#import "tweaks/nano_registry.h"
#import "tweaks/killallapps.h"
#import "tweaks/themer.h"
#import "tweaks/snowboardlite.h"
#import "tweaks/livewp.h"
#import "tweaks/gravitylite.h"
#import "tweaks/appswitchergrid.h"

#import <objc/runtime.h>
#import <CoreMotion/CoreMotion.h>
#import <dlfcn.h>
#import "DSKeepAlive.h"
#import "TaskRop/RemoteCall.h"
#import "kexploit/kutils.h"
#import "kexploit/persistence.h"
#import "installer/InstallProgressViewController.h"
#import "installer/Package.h"
#import "installer/PackageCatalog.h"
#import "installer/PackageQueue.h"
#import "docs/DocsViewController.h"
#import "UpdateChecker.h"
#import "SBLArchiveExtractor.h"
#import <WebKit/WebKit.h>
#import <MessageUI/MessageUI.h>
#import <CoreLocation/CoreLocation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>
#import <math.h>
#import <sys/utsname.h>
#import <time.h>
#import <unistd.h>
#import <stdlib.h>

typedef void (^CyanideNiceBarWeatherCompletion)(BOOL ok, NSString *text, NSNumber *temp, NSNumber *code, BOOL fetched);

@interface _CyanideNiceBarWeatherRefresher : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSMutableArray<CyanideNiceBarWeatherCompletion> *pendingCompletions;
@property (nonatomic, assign) BOOL locationRequestInFlight;
@property (nonatomic, assign) BOOL weatherFetchInFlight;
@property (nonatomic, assign) BOOL requestUsesCelsius;
- (void)refreshWeatherForce:(BOOL)force completion:(CyanideNiceBarWeatherCompletion)completion;
@end

typedef NS_ENUM(NSInteger, NiceBarTrafficHistoryRange) {
    NiceBarTrafficHistoryRangeWeek = 0,
    NiceBarTrafficHistoryRangeMonth = 1,
    NiceBarTrafficHistoryRangeYear = 2,
};

@interface NiceBarTrafficChartItem : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) uint64_t bytes;
@end

@implementation NiceBarTrafficChartItem
@end

@interface NiceBarTrafficChartView : UIView
@property (nonatomic, copy) NSArray<NiceBarTrafficChartItem *> *items;
@end

@implementation NiceBarTrafficChartView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)setItems:(NSArray<NiceBarTrafficChartItem *> *)items
{
    _items = [items copy];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGRect bounds = UIEdgeInsetsInsetRect(self.bounds, UIEdgeInsetsMake(10.0, 8.0, 20.0, 8.0));
    if (bounds.size.width <= 1.0 || bounds.size.height <= 1.0) return;

    UIColor *axisColor = [UIColor.separatorColor colorWithAlphaComponent:0.55];
    [axisColor setStroke];
    UIBezierPath *baseline = [UIBezierPath bezierPath];
    [baseline moveToPoint:CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds))];
    [baseline addLineToPoint:CGPointMake(CGRectGetMaxX(bounds), CGRectGetMaxY(bounds))];
    baseline.lineWidth = 1.0 / UIScreen.mainScreen.scale;
    [baseline stroke];

    NSUInteger count = self.items.count;
    if (count == 0) {
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        };
        NSString *text = @"No data";
        CGSize size = [text sizeWithAttributes:attrs];
        [text drawAtPoint:CGPointMake(CGRectGetMidX(bounds) - size.width / 2.0,
                                      CGRectGetMidY(bounds) - size.height / 2.0)
           withAttributes:attrs];
        return;
    }

    uint64_t maxBytes = 0;
    for (NiceBarTrafficChartItem *item in self.items) {
        if (item.bytes > maxBytes) maxBytes = item.bytes;
    }
    if (maxBytes == 0) maxBytes = 1;

    CGFloat slot = bounds.size.width / (CGFloat)count;
    CGFloat barWidth = MAX(3.0, MIN(18.0, slot * 0.56));
    UIColor *barColor = UIColor.systemBlueColor;
    UIColor *mutedBarColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.24];
    UIColor *labelColor = UIColor.secondaryLabelColor;
    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:9.0 weight:UIFontWeightRegular],
        NSForegroundColorAttributeName: labelColor,
    };

    for (NSUInteger i = 0; i < count; i++) {
        NiceBarTrafficChartItem *item = self.items[i];
        CGFloat fraction = (CGFloat)((double)item.bytes / (double)maxBytes);
        CGFloat height = item.bytes == 0 ? 2.0 : MAX(4.0, bounds.size.height * fraction);
        CGFloat x = CGRectGetMinX(bounds) + slot * (CGFloat)i + (slot - barWidth) / 2.0;
        CGFloat y = CGRectGetMaxY(bounds) - height;
        CGRect barRect = CGRectMake(x, y, barWidth, height);
        UIBezierPath *bar = [UIBezierPath bezierPathWithRoundedRect:barRect
                                                       cornerRadius:MIN(barWidth / 2.0, 4.0)];
        [(item.bytes == 0 ? mutedBarColor : barColor) setFill];
        [bar fill];

        BOOL shouldDrawLabel = count <= 12 || i == 0 || i == count - 1 || ((i + 1) % 5 == 0);
        if (shouldDrawLabel && item.label.length > 0) {
            CGSize labelSize = [item.label sizeWithAttributes:labelAttrs];
            CGFloat labelX = x + barWidth / 2.0 - labelSize.width / 2.0;
            CGFloat labelY = CGRectGetMaxY(bounds) + 5.0;
            [item.label drawAtPoint:CGPointMake(labelX, labelY) withAttributes:labelAttrs];
        }
    }
}

@end

@interface NiceBarTrafficSummaryCell : UITableViewCell
@property (nonatomic, strong) UISegmentedControl *rangeControl;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UILabel *averageLabel;
@property (nonatomic, strong) UILabel *peakLabel;
@property (nonatomic, strong) NiceBarTrafficChartView *chartView;
@property (nonatomic, copy) void (^rangeChanged)(NSInteger selectedIndex);
- (void)configureTitle:(NSString *)title
                 total:(NSString *)total
               average:(NSString *)average
                  peak:(NSString *)peak
                 range:(NiceBarTrafficHistoryRange)range
                 items:(NSArray<NiceBarTrafficChartItem *> *)items;
@end

@implementation NiceBarTrafficSummaryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        _rangeControl = [[UISegmentedControl alloc] initWithItems:@[@"Week", @"Month", @"Year"]];
        [_rangeControl addTarget:self action:@selector(rangeControlChanged:) forControlEvents:UIControlEventValueChanged];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        _titleLabel.textColor = UIColor.secondaryLabelColor;

        _totalLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _totalLabel.font = [UIFont systemFontOfSize:30.0 weight:UIFontWeightBold];
        _totalLabel.adjustsFontSizeToFitWidth = YES;
        _totalLabel.minimumScaleFactor = 0.65;
        _totalLabel.textColor = UIColor.labelColor;

        _averageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _averageLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        _averageLabel.textColor = UIColor.secondaryLabelColor;

        _peakLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _peakLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        _peakLabel.textColor = UIColor.secondaryLabelColor;

        _chartView = [[NiceBarTrafficChartView alloc] initWithFrame:CGRectZero];

        for (UIView *view in @[_rangeControl, _titleLabel, _totalLabel, _averageLabel, _peakLabel, _chartView]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:view];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_rangeControl.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14.0],
            [_rangeControl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_rangeControl.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_rangeControl.bottomAnchor constant:16.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [_totalLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4.0],
            [_totalLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_totalLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [_averageLabel.topAnchor constraintEqualToAnchor:_totalLabel.bottomAnchor constant:8.0],
            [_averageLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_averageLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [_peakLabel.topAnchor constraintEqualToAnchor:_averageLabel.bottomAnchor constant:3.0],
            [_peakLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_peakLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],

            [_chartView.topAnchor constraintEqualToAnchor:_peakLabel.bottomAnchor constant:14.0],
            [_chartView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10.0],
            [_chartView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
            [_chartView.heightAnchor constraintEqualToConstant:128.0],
            [_chartView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14.0],
        ]];
    }
    return self;
}

- (void)rangeControlChanged:(UISegmentedControl *)sender
{
    if (self.rangeChanged) self.rangeChanged(sender.selectedSegmentIndex);
}

- (void)configureTitle:(NSString *)title
                 total:(NSString *)total
               average:(NSString *)average
                  peak:(NSString *)peak
                 range:(NiceBarTrafficHistoryRange)range
                 items:(NSArray<NiceBarTrafficChartItem *> *)items
{
    self.rangeControl.selectedSegmentIndex = range;
    self.titleLabel.text = title;
    self.totalLabel.text = total;
    self.averageLabel.text = average;
    self.peakLabel.text = peak;
    self.chartView.items = items;
}

@end

@interface NiceBarTrafficDetailCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIProgressView *progressView;
- (void)configureTitle:(NSString *)title value:(NSString *)value bytes:(uint64_t)bytes peak:(uint64_t)peak;
@end

@implementation NiceBarTrafficDetailCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
        _titleLabel.textColor = UIColor.labelColor;

        _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
        _valueLabel.textColor = UIColor.secondaryLabelColor;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.75;

        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.progressTintColor = UIColor.systemBlueColor;
        _progressView.trackTintColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.14];

        for (UIView *view in @[_titleLabel, _valueLabel, _progressView]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [self.contentView addSubview:view];
        }

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11.0],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],

            [_valueLabel.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:12.0],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_valueLabel.widthAnchor constraintGreaterThanOrEqualToConstant:76.0],

            [_progressView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8.0],
            [_progressView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_progressView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_progressView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)configureTitle:(NSString *)title value:(NSString *)value bytes:(uint64_t)bytes peak:(uint64_t)peak
{
    self.titleLabel.text = title ?: @"";
    self.valueLabel.text = value ?: @"";
    float progress = peak > 0 ? (float)MIN(1.0, (double)bytes / (double)peak) : 0.0f;
    [self.progressView setProgress:progress animated:NO];
    self.progressView.hidden = bytes == 0;
}

@end

@interface NiceBarTrafficHistoryViewController : UITableViewController
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *history;
@property (nonatomic, copy) NSArray<NSString *> *dateKeys;
@property (nonatomic, assign) NiceBarTrafficHistoryRange selectedRange;
@property (nonatomic, copy) NSArray<NiceBarTrafficChartItem *> *chartItems;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *detailRows;
@property (nonatomic, assign) uint64_t rangeTotalBytes;
@property (nonatomic, assign) uint64_t rangePeakBytes;
@property (nonatomic, copy) NSString *rangeTitle;
@property (nonatomic, copy) NSString *averageTitle;
@end

@implementation NiceBarTrafficHistoryViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"Traffic History";
        self.selectedRange = NiceBarTrafficHistoryRangeWeek;
        [self reloadTrafficHistory];
    }
    return self;
}

- (NSDateFormatter *)trafficDateFormatter
{
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyyMMdd";
    });
    return formatter;
}

- (NSDateFormatter *)trafficDisplayDateFormatter
{
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = NSLocale.currentLocale;
        formatter.dateFormat = @"yyyy-MM-dd";
    });
    return formatter;
}

- (uint64_t)bytesForKey:(NSString *)key
{
    NSString *raw = self.history[key] ?: @"0";
    return (uint64_t)strtoull(raw.UTF8String ?: "0", NULL, 10);
}

- (NSDate *)dateForKey:(NSString *)key
{
    if (key.length != 8) return nil;
    return [[self trafficDateFormatter] dateFromString:key];
}

- (NSString *)keyForDate:(NSDate *)date
{
    if (!date) return nil;
    return [[self trafficDateFormatter] stringFromDate:date];
}

- (NiceBarTrafficChartItem *)chartItemWithLabel:(NSString *)label bytes:(uint64_t)bytes
{
    NiceBarTrafficChartItem *item = [[NiceBarTrafficChartItem alloc] init];
    item.label = label ?: @"";
    item.bytes = bytes;
    return item;
}

- (NSString *)titleForSelectedRange
{
    switch (self.selectedRange) {
        case NiceBarTrafficHistoryRangeWeek: return @"This Week";
        case NiceBarTrafficHistoryRangeMonth: return @"This Month";
        case NiceBarTrafficHistoryRangeYear: return @"This Year";
    }
    return @"Traffic";
}

- (NSDate *)startOfUnit:(NSCalendarUnit)unit date:(NSDate *)date interval:(NSTimeInterval *)interval
{
    NSDate *start = nil;
    NSTimeInterval localInterval = 0;
    [NSCalendar.currentCalendar rangeOfUnit:unit startDate:&start interval:&localInterval forDate:date ?: NSDate.date];
    if (interval) *interval = localInterval;
    return start ?: date ?: NSDate.date;
}

- (void)rebuildDerivedTrafficData
{
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *now = NSDate.date;
    NSMutableArray<NiceBarTrafficChartItem *> *chartItems = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    uint64_t total = 0;
    uint64_t peak = 0;

    if (self.selectedRange == NiceBarTrafficHistoryRangeWeek) {
        NSDate *weekStart = [self startOfUnit:NSCalendarUnitWeekOfYear date:now interval:nil];
        NSDateFormatter *weekdayFormatter = [[NSDateFormatter alloc] init];
        weekdayFormatter.locale = NSLocale.currentLocale;
        weekdayFormatter.dateFormat = @"EEE";

        for (NSInteger i = 0; i < 7; i++) {
            NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:i toDate:weekStart options:0];
            NSString *key = [self keyForDate:date];
            uint64_t bytes = [self bytesForKey:key];
            total += bytes;
            if (bytes > peak) peak = bytes;
            [chartItems addObject:[self chartItemWithLabel:[weekdayFormatter stringFromDate:date] bytes:bytes]];
            if (bytes > 0) {
                [rows addObject:@{
                    @"title": [[self trafficDisplayDateFormatter] stringFromDate:date],
                    @"detail": nicebarlite_format_traffic_bytes(bytes),
                    @"bytes": @(bytes),
                }];
            }
        }
        self.averageTitle = @"Daily avg";
    } else if (self.selectedRange == NiceBarTrafficHistoryRangeMonth) {
        NSTimeInterval monthInterval = 0;
        NSDate *monthStart = [self startOfUnit:NSCalendarUnitMonth date:now interval:&monthInterval];
        NSUInteger days = (NSUInteger)MAX(1, (NSInteger)lrint(monthInterval / 86400.0));

        for (NSUInteger i = 0; i < days; i++) {
            NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:(NSInteger)i toDate:monthStart options:0];
            NSString *key = [self keyForDate:date];
            uint64_t bytes = [self bytesForKey:key];
            total += bytes;
            if (bytes > peak) peak = bytes;
            NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)];
            [chartItems addObject:[self chartItemWithLabel:label bytes:bytes]];
            if (bytes > 0) {
                [rows addObject:@{
                    @"title": [[self trafficDisplayDateFormatter] stringFromDate:date],
                    @"detail": nicebarlite_format_traffic_bytes(bytes),
                    @"bytes": @(bytes),
                }];
            }
        }
        self.averageTitle = @"Daily avg";
    } else {
        NSDate *yearStart = [self startOfUnit:NSCalendarUnitYear date:now interval:nil];

        NSDateFormatter *monthTitleFormatter = [[NSDateFormatter alloc] init];
        monthTitleFormatter.locale = NSLocale.currentLocale;
        monthTitleFormatter.dateFormat = @"yyyy-MM";
        for (NSInteger month = 1; month <= 12; month++) {
            NSDate *monthStart = [calendar dateByAddingUnit:NSCalendarUnitMonth value:month - 1 toDate:yearStart options:0];
            NSTimeInterval monthInterval = 0;
            [calendar rangeOfUnit:NSCalendarUnitMonth startDate:NULL interval:&monthInterval forDate:monthStart];
            NSUInteger days = (NSUInteger)MAX(1, (NSInteger)lrint(monthInterval / 86400.0));
            uint64_t monthBytes = 0;
            for (NSUInteger day = 0; day < days; day++) {
                NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:(NSInteger)day toDate:monthStart options:0];
                monthBytes += [self bytesForKey:[self keyForDate:date]];
            }
            total += monthBytes;
            if (monthBytes > peak) peak = monthBytes;
            [chartItems addObject:[self chartItemWithLabel:[NSString stringWithFormat:@"%ld", (long)month] bytes:monthBytes]];
            if (monthBytes > 0) {
                [rows addObject:@{
                    @"title": [monthTitleFormatter stringFromDate:monthStart],
                    @"detail": nicebarlite_format_traffic_bytes(monthBytes),
                    @"bytes": @(monthBytes),
                }];
            }
        }
        self.averageTitle = @"Monthly avg";
    }

    [rows sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> *a, NSDictionary<NSString *, id> *b) {
        return [b[@"title"] compare:a[@"title"]];
    }];

    self.chartItems = chartItems;
    self.detailRows = rows;
    self.rangeTotalBytes = total;
    self.rangePeakBytes = peak;
    self.rangeTitle = [self titleForSelectedRange];
}

- (void)reloadTrafficHistory
{
    NSDictionary<NSString *, NSString *> *history = nicebarlite_traffic_history_snapshot() ?: @{};
    self.history = history;
    self.dateKeys = [[history allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];
    }];
    [self rebuildDerivedTrafficData];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    [self.tableView registerClass:NiceBarTrafficSummaryCell.class forCellReuseIdentifier:@"traffic-summary"];
    [self.tableView registerClass:NiceBarTrafficDetailCell.class forCellReuseIdentifier:@"traffic-detail"];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(refreshTapped)];
}

- (void)refreshTapped
{
    [self reloadTrafficHistory];
    [self.tableView reloadData];
}

- (void)rangeChanged:(NSInteger)selectedIndex
{
    self.selectedRange = (NiceBarTrafficHistoryRange)MAX(0, MIN(2, selectedIndex));
    [self rebuildDerivedTrafficData];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 0) return 1;
    return MAX((NSInteger)self.detailRows.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    if (section == 1) {
        return self.selectedRange == NiceBarTrafficHistoryRangeYear ? @"Monthly Details" : @"Daily Details";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    (void)tableView;
    if (section != 1) return nil;
    return [NSString stringWithFormat:@"Stored at %@", nicebarlite_traffic_store_path()];
}

- (NSString *)summaryAverageText
{
    NSUInteger divisor = 1;
    if (self.selectedRange == NiceBarTrafficHistoryRangeYear) {
        divisor = (NSUInteger)MAX(1, [NSCalendar.currentCalendar component:NSCalendarUnitMonth fromDate:NSDate.date]);
    } else if (self.selectedRange == NiceBarTrafficHistoryRangeMonth) {
        NSDate *start = [self startOfUnit:NSCalendarUnitMonth date:NSDate.date interval:nil];
        NSInteger elapsed = [NSCalendar.currentCalendar components:NSCalendarUnitDay fromDate:start toDate:NSDate.date options:0].day + 1;
        divisor = (NSUInteger)MAX(1, elapsed);
    } else {
        NSDate *start = [self startOfUnit:NSCalendarUnitWeekOfYear date:NSDate.date interval:nil];
        NSInteger elapsed = [NSCalendar.currentCalendar components:NSCalendarUnitDay fromDate:start toDate:NSDate.date options:0].day + 1;
        divisor = (NSUInteger)MAX(1, elapsed);
    }
    uint64_t average = divisor > 0 ? self.rangeTotalBytes / divisor : 0;
    return [NSString stringWithFormat:@"%@ %@", self.averageTitle ?: @"Avg", nicebarlite_format_traffic_bytes(average)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        NiceBarTrafficSummaryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"traffic-summary" forIndexPath:indexPath];
        __weak typeof(self) weakSelf = self;
        cell.rangeChanged = ^(NSInteger selectedIndex) {
            [weakSelf rangeChanged:selectedIndex];
        };
        [cell configureTitle:self.rangeTitle ?: @"Traffic"
                       total:nicebarlite_format_traffic_bytes(self.rangeTotalBytes)
                     average:[self summaryAverageText]
                        peak:[NSString stringWithFormat:@"Peak %@", nicebarlite_format_traffic_bytes(self.rangePeakBytes)]
                       range:self.selectedRange
                       items:self.chartItems ?: @[]];
        return cell;
    }

    if (self.detailRows.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"traffic-empty"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"traffic-empty"];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.text = @"No usage in this range";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        return cell;
    }

    NSDictionary<NSString *, id> *row = self.detailRows[(NSUInteger)indexPath.row];
    NiceBarTrafficDetailCell *cell = [tableView dequeueReusableCellWithIdentifier:@"traffic-detail" forIndexPath:indexPath];
    [cell configureTitle:row[@"title"]
                   value:row[@"detail"]
                   bytes:[row[@"bytes"] unsignedLongLongValue]
                    peak:self.rangePeakBytes];
    return cell;
}

@end

@interface DSRespringOverlayView : UIView
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) BOOL didLoadPayload;
@end

@implementation DSRespringOverlayView

- (NSString *)respringHTML {
    // Verbatim port of Lara's respring.swift payload (by rooootdev,
    // skidded from jailbreak.party; web approach by @neonmodder123).
    return @"<!DOCTYPE html>\n"
           @"<html>\n"
           @"    <body>\n"
           @"        <!--  big credit to @neonmodder123  -->\n"
           @"        <iframe id=\"frame\" srcdoc=\"\" sandbox=\"allow-forms allow-modals allow-orientation-lock allow-pointer-lock allow-popups allow-presentation allow-scripts\"></iframe>\n"
           @"        <script>\n"
           @"            const frame = document.getElementById('frame');\n"
           @"            const script = `\n"
           @"                <html>\n"
           @"                <body>\n"
           @"                    <script>\n"
           @"                        const container = document.createElement('div');\n"
           @"                        container.style.cssText = 'perspective: 1px; perspective-origin: 9999999% 9999999%;';\n"
           @"                        document.body.appendChild(container);\n"
           @"    \n"
           @"                        for (let i = 0; i < 500; i++) {\n"
           @"                            let d = document.createElement('div');\n"
           @"                            d.style.cssText = 'position: absolute; width: 100vw; height: 100vh; backdrop-filter: blur(100px); -webkit-backdrop-filter: blur(100px); transform: translate3d(100000px, 100000px, ' + i + 'px) rotateY(90deg);';\n"
           @"                            container.appendChild(d);\n"
           @"                        }\n"
           @"    \n"
           @"                        setInterval(() => {\n"
           @"                            navigator.share({ title: 'R', text: 'R'.repeat(100000) }).catch(() => {});\n"
           @"                            let x = new Uint8Array(1024 * 1024 * 10);\n"
           @"                            crypto.getRandomValues(x);\n"
           @"                        }, 0);\n"
           @"                    <\\/script>\n"
           @"                </body>\n"
           @"                </html>\n"
           @"            `;\n"
           @"    \n"
           @"            frame.srcdoc = script;\n"
           @"        </script>\n"
           @"    </body>\n"
           @"</html>";
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor blackColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self loadRespringPayload];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.webView.frame = self.bounds;
}

- (void)loadRespringPayload {
    if (self.didLoadPayload) return;
    self.didLoadPayload = YES;
    printf("[RESPRING] loading Lara-style in-app WebKit overlay\n");

    // Mirrors Lara's respringview verbatim: default-init WKWebView, the
    // throwaway WKWebpagePreferences assignment (a no-op in Lara's Swift
    // source — kept for fidelity), then loadHTMLString.
    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [WKWebpagePreferences new].allowsContentJavaScript = YES;
    [self addSubview:webView];
    self.webView = webView;
    [webView loadHTMLString:[self respringHTML] baseURL:nil];
}

@end

NSString * const kSettingsAutoRunKexploit    = @"AutoRunKexploit";
NSString * const kSettingsRunSandboxEscape   = @"RunSandboxEscape";
NSString * const kSettingsRunPatchSandboxExt = @"RunPatchSandboxExt";
NSString * const kSettingsKeepAlive          = @"KeepAlive";

NSString * const kSettingsSBCEnabled    = @"SBCEnabled";
NSString * const kSettingsSBCDockIcons  = @"SBCDockIcons";
NSString * const kSettingsSBCCols       = @"SBCCols";
NSString * const kSettingsSBCRows       = @"SBCRows";
NSString * const kSettingsSBCHideLabels = @"SBCHideLabels";

NSString * const kSettingsPowercuffEnabled = @"PowercuffEnabled";
NSString * const kSettingsPowercuffLevel   = @"PowercuffLevel";
static NSString * const kSettingsPowercuffNominalNoticeShown = @"cyanide.powercuff.nominalDefaultNoticeShown.v1";

NSString * const kSettingsDSDisableAppLibrary = @"DSDisableAppLibrary";
NSString * const kSettingsDSDisableIconFlyIn  = @"DSDisableIconFlyIn";
NSString * const kSettingsDSZeroWakeAnimation = @"DSZeroWakeAnimation";
NSString * const kSettingsDSZeroBacklightFade = @"DSZeroBacklightFade";
NSString * const kSettingsDSDoubleTapToLock   = @"DSDoubleTapToLock";
NSString * const kSettingsDSDragCoefficientEnabled = @"DSDragCoefficientEnabled";
NSString * const kSettingsDSDragCoefficientValue   = @"DSDragCoefficientValue";

NSString * const kSettingsLayoutExtrasEnabled  = @"LayoutExtrasEnabled";
NSString * const kSettingsLayoutHomeExtraLeft   = @"LayoutHomeExtraLeft";
NSString * const kSettingsLayoutHomeExtraRight  = @"LayoutHomeExtraRight";
NSString * const kSettingsLayoutHomeExtraTop    = @"LayoutHomeExtraTop";
NSString * const kSettingsLayoutHomeExtraBottom = @"LayoutHomeExtraBottom";
NSString * const kSettingsLayoutDockExtraHorizontal = @"LayoutDockExtraHorizontal";
NSString * const kSettingsLayoutHomeScalePct    = @"LayoutHomeScalePct";
NSString * const kSettingsLayoutDockScalePct    = @"LayoutDockScalePct";

NSString * const kSettingsStatBarEnabled = @"StatBarEnabled";
NSString * const kSettingsStatBarCelsius = @"StatBarCelsius";
NSString * const kSettingsStatBarShowTemp = @"StatBarShowTemp";
NSString * const kSettingsStatBarShowCPU = @"StatBarShowCPU";
NSString * const kSettingsStatBarShowRAM = @"StatBarShowRAM";
NSString * const kSettingsStatBarShowNet = @"StatBarShowNet";
NSString * const kSettingsStatBarShowLabels = @"StatBarShowLabels";
NSString * const kSettingsStatBarRefreshRateSec = @"StatBarRefreshRateSec";

NSString * const kSettingsNSBarEnabled = @"NSBarEnabled";
NSString * const kSettingsNSBarPosition = @"NSBarPosition";

NSString * const kSettingsNiceBarLiteEnabled = @"NiceBarLiteEnabled";
static NSString * const kSettingsNiceBarLiteCelsius = @"NiceBarLiteCelsius";
static NSString * const kSettingsNiceBarLiteLayoutSideInset = @"NiceBarLiteLayoutSideInset";
static NSString * const kSettingsNiceBarLiteLayoutTopSideInset = @"NiceBarLiteLayoutTopSideInset";
static NSString * const kSettingsNiceBarLiteLayoutBottomSideInset = @"NiceBarLiteLayoutBottomSideInset";
static NSString * const kSettingsNiceBarLiteLayoutTopY = @"NiceBarLiteLayoutTopY";
static NSString * const kSettingsNiceBarLiteLayoutBottomY = @"NiceBarLiteLayoutBottomY";
static NSString * const kSettingsNiceBarLiteLayoutCenterX = @"NiceBarLiteLayoutCenterX";
static NSString * const kSettingsNiceBarLiteSlotKindPrefix = @"NiceBarLiteSlotKind";
static NSString * const kSettingsNiceBarLiteSlotSystemPrefix = @"NiceBarLiteSlotSystem";
static NSString * const kSettingsNiceBarLiteSlotTextPrefix = @"NiceBarLiteSlotText";
static NSString * const kSettingsNiceBarLiteSlotTimePrefix = @"NiceBarLiteSlotTime";
static NSString * const kSettingsNiceBarLiteSlotWeatherPrefix = @"NiceBarLiteSlotWeather";
static NSString * const kSettingsNiceBarLiteSlotWeatherLanguagePrefix = @"NiceBarLiteSlotWeatherLanguage";
static NSString * const kSettingsNiceBarLiteSlotSystemLanguagePrefix = @"NiceBarLiteSlotSystemLanguage";
static NSString * const kSettingsNiceBarLiteWeatherCache = @"NiceBarLiteWeatherCache";
static NSString * const kSettingsNiceBarLiteWeatherTemp = @"NiceBarLiteWeatherTemp";
static NSString * const kSettingsNiceBarLiteWeatherCode = @"NiceBarLiteWeatherCode";
static NSString * const kSettingsNiceBarLiteWeatherUpdatedAt = @"NiceBarLiteWeatherUpdatedAt";
static NSString * const kSettingsNiceBarLiteWeatherLastAttemptAt = @"NiceBarLiteWeatherLastAttemptAt";

NSString * const kSettingsRSSIDisplayEnabled = @"RSSIDisplayEnabled";
NSString * const kSettingsRSSIDisplayWifi    = @"RSSIDisplayWifi";
NSString * const kSettingsRSSIDisplayCell    = @"RSSIDisplayCell";

NSString * const kSettingsAxonLiteEnabled = @"AxonLiteEnabled";

NSString * const kSettingsTypeBannerEnabled = @"TypeBannerEnabled";

NSString * const kSettingsAppSwitcherGridEnabled = @"AppSwitcherGridEnabled";

NSString * const kSettingsGravityLiteEnabled = @"GravityLiteEnabled";
NSString * const kSettingsGravityLiteDockEnabled = @"GravityLiteDockEnabled";
NSString * const kSettingsGravityLiteMagnitudePct = @"GravityLiteMagnitudePct";
NSString * const kSettingsGravityLiteBouncePct = @"GravityLiteBouncePct";
NSString * const kSettingsGravityLiteFrictionPct = @"GravityLiteFrictionPct";
NSString * const kSettingsGravityLiteResistancePct = @"GravityLiteResistancePct";
NSString * const kSettingsGravityLiteAngularResistancePct = @"GravityLiteAngularResistancePct";

NSString * const kSettingsThemerEnabled = @"ThemerEnabled";
NSString * const kSettingsThemerThemeID = @"ThemerThemeID";
NSString * const kSettingsThemerCustomThemePath = @"ThemerCustomThemePath";
NSString * const kSettingsThemerCustomThemeName = @"ThemerCustomThemeName";

NSString * const kSettingsSnowBoardLiteEnabled = @"SnowBoardLiteEnabled";
NSString * const kSettingsSnowBoardLiteSelectedThemeID = @"SnowBoardLiteSelectedThemeID";

NSString * const kSettingsLiveWPEnabled = @"LiveWPEnabled";
NSString * const kSettingsLiveWPVideoPath = @"LiveWPVideoPath";

@interface CyanideLayoutCalibrationPreviewView : UIView
@property (nonatomic, copy) NSString *scope;
@end

@implementation CyanideLayoutCalibrationPreviewView

- (NSInteger)valueForKey:(NSString *)key legacyKey:(NSString *)legacyKey
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id stored = [[d persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] objectForKey:key];
    if (stored) return [d integerForKey:key];
    return legacyKey.length ? [d integerForKey:legacyKey] : [d integerForKey:key];
}

- (void)drawPillInRect:(CGRect)rect text:(NSString *)text active:(BOOL)active
{
    UIColor *fill = active
        ? [UIColor colorWithWhite:1.0 alpha:0.94]
        : [UIColor colorWithWhite:1.0 alpha:0.30];
    UIColor *textColor = active
        ? UIColor.blackColor
        : [UIColor colorWithWhite:1.0 alpha:0.72];
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:CGRectGetHeight(rect) * 0.48];
    [fill setFill];
    [path fill];

    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:8.5 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: textColor,
    };
    CGSize size = [text sizeWithAttributes:attrs];
    CGPoint p = CGPointMake(CGRectGetMidX(rect) - size.width * 0.5,
                            CGRectGetMidY(rect) - size.height * 0.5);
    [text drawAtPoint:p withAttributes:attrs];
}

- (void)drawRect:(CGRect)rect
{
    CGFloat topEdge = [self valueForKey:kSettingsNiceBarLiteLayoutTopSideInset legacyKey:kSettingsNiceBarLiteLayoutSideInset];
    CGFloat bottomEdge = [self valueForKey:kSettingsNiceBarLiteLayoutBottomSideInset legacyKey:kSettingsNiceBarLiteLayoutSideInset];
    CGFloat topY = [[NSUserDefaults standardUserDefaults] integerForKey:kSettingsNiceBarLiteLayoutTopY];
    CGFloat bottomY = [[NSUserDefaults standardUserDefaults] integerForKey:kSettingsNiceBarLiteLayoutBottomY];
    CGFloat centerX = [[NSUserDefaults standardUserDefaults] integerForKey:kSettingsNiceBarLiteLayoutCenterX];

    CGRect bounds = UIEdgeInsetsInsetRect(self.bounds, UIEdgeInsetsMake(2, 4, 2, 4));
    UIBezierPath *screen = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:16.0];
    [[UIColor colorWithRed:0.055 green:0.06 blue:0.075 alpha:1.0] setFill];
    [screen fill];

    CGRect island = CGRectMake(CGRectGetMidX(bounds) - 30.0, CGRectGetMinY(bounds) + 8.0, 60.0, 15.0);
    [[UIColor colorWithWhite:0.0 alpha:0.88] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:island cornerRadius:7.5] fill];

    CGFloat scale = 0.32;
    CGFloat topInset = MAX(8.0, 15.0 + (topEdge * scale));
    CGFloat bottomInset = MAX(8.0, 15.0 + (bottomEdge * scale));
    CGFloat verticalScale = 0.36;
    CGFloat topRowY = CGRectGetMinY(bounds) + 34.0 + (topY * verticalScale);
    CGFloat bottomRowY = CGRectGetMinY(bounds) + 70.0 + (bottomY * verticalScale);
    CGFloat w = 42.0;
    CGFloat h = 15.0;

    [self drawPillInRect:CGRectMake(CGRectGetMinX(bounds) + topInset, topRowY, w, h)
                    text:@"TL"
                  active:YES];
    [self drawPillInRect:CGRectMake(CGRectGetMaxX(bounds) - topInset - w, topRowY, w, h)
                    text:@"TR"
                  active:YES];
    [self drawPillInRect:CGRectMake(CGRectGetMinX(bounds) + bottomInset, bottomRowY, w, h)
                    text:@"BL"
                  active:YES];
    [self drawPillInRect:CGRectMake(CGRectGetMaxX(bounds) - bottomInset - w, bottomRowY, w, h)
                    text:@"BR"
                  active:YES];
    [self drawPillInRect:CGRectMake(CGRectGetMidX(bounds) - 22.0 + (centerX * 0.42), bottomRowY, 44.0, h)
                    text:@"MID"
                  active:YES];
}

@end

// 从相对路径（如 "LiveWP/video.mp4"）拼接为绝对路径
static NSString *settings_livewp_absolute_path(void) {
    NSString *rel = [[NSUserDefaults standardUserDefaults] stringForKey:kSettingsLiveWPVideoPath];
    if (!rel || rel.length == 0) return nil;
    // 兼容旧版绝对路径
    if ([rel hasPrefix:@"/"]) return rel;
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:rel];
}

static NSString *settings_livewp_file_size_text(unsigned long long bytes)
{
    double value = (double)bytes;
    NSArray<NSString *> *units = @[@"B", @"KB", @"MB", @"GB"];
    NSUInteger unit = 0;
    while (value >= 1024.0 && unit + 1 < units.count) {
        value /= 1024.0;
        unit++;
    }
    if (unit == 0) return [NSString stringWithFormat:@"%llu %@", bytes, units[unit]];
    return [NSString stringWithFormat:@"%.1f %@", value, units[unit]];
}

static NSError *settings_sbl_error(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"SnowBoardLite"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"SnowBoard Lite import failed."}];
}

static NSString *settings_sbl_themes_root_for_ui(void)
{
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length == 0) return nil;
    return [[docs stringByAppendingPathComponent:@"SnowBoardLite"] stringByAppendingPathComponent:@"Themes"];
}

static BOOL settings_sbl_remove_theme_dir_if_safe(NSString *path)
{
    NSString *root = [settings_sbl_themes_root_for_ui() stringByStandardizingPath];
    NSString *target = [path stringByStandardizingPath];
    if (root.length == 0 || target.length == 0) return NO;
    NSString *prefix = [root stringByAppendingString:@"/"];
    if (![target hasPrefix:prefix]) return NO;

    BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:target isDirectory:&isDir] || !isDir) return NO;
    NSError *err = nil;
    BOOL ok = [fm removeItemAtPath:target error:&err];
    if (!ok) {
        log_user("[SBL] Failed to remove theme directory: %s\n",
                 err.localizedDescription.UTF8String ?: "unknown error");
    }
    return ok;
}

static NSString *settings_livewp_video_detail(NSString *absPath)
{
    if (absPath.length == 0) return @"Select an MP4, MOV, or M4V file.";
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:absPath error:nil];
    NSString *ext = absPath.pathExtension.uppercaseString.length ? absPath.pathExtension.uppercaseString : @"VIDEO";
    if (!attrs) return ext;
    return [NSString stringWithFormat:@"%@ · %@",
            ext,
            settings_livewp_file_size_text([attrs fileSize])];
}

// Master gate for experimental tweaks. When NO (default), packages that opt
// into the experimental category are hidden from the Installer and the
// Settings bundle list, and any currently-enabled experimental tweak is
// force-disabled when this is flipped off.
NSString * const kSettingsExperimentalTweaksEnabled = @"ExperimentalTweaksEnabled";

// NanoRegistry pairing-compatibility editor. Numbers are the watchOS pairing
// compatibility versions that NRPairingCompatibilityVersionInfo reads from
// /var/mobile/Library/Preferences/com.apple.NanoRegistry.plist via
// CFPreferencesCopyValue("com.apple.NanoRegistry").
NSString * const kSettingsNanoMaxPairing       = @"NanoRegistryMaxPairing";
NSString * const kSettingsNanoMinPairing       = @"NanoRegistryMinPairing";
NSString * const kSettingsNanoMinPairingChipID = @"NanoRegistryMinPairingChipID";
NSString * const kSettingsNanoMinQuickSwitch   = @"NanoRegistryMinQuickSwitch";

static void cyanide_upload_log_if_enabled(void);
static void cyanide_upload_log_milestone(NSString *event);
static void cyanide_start_session_uploads(void);
static void cyanide_stop_session_uploads(void);
static BOOL settings_cleanup_in_progress(void);

extern int  escape_sbx_demo2(void);
extern int  escape_sbx_demo2_in_session(void);
extern int  escape_sbx_demo3(void);

static BOOL g_kexploit_done = NO;
static volatile int g_settings_actions_running = 0;
static volatile int g_settings_respring_cleanup_running = 0;
static volatile int g_settings_actions_rerun_requested = 0;
static volatile int g_springboard_rc_ready = 0;
static volatile int g_springboard_sandbox_escaped = 0;
static volatile int g_statbar_live_running = 0;
static volatile int g_statbar_live_stop_requested = 0;
static volatile int g_nsbar_live_running = 0;
static volatile int g_nsbar_live_stop_requested = 0;
static volatile int g_nicebarlite_live_running = 0;
static volatile int g_nicebarlite_live_stop_requested = 0;
static volatile int64_t g_layout_slider_apply_serial = 0;
static volatile int g_rssi_live_running = 0;
static volatile int g_rssi_live_stop_requested = 0;
static volatile int g_axonlite_live_running = 0;
static volatile int g_axonlite_live_stop_requested = 0;
static volatile int g_typebanner_live_running = 0;
static volatile int g_typebanner_live_stop_requested = 0;
static volatile int g_gravitylite_background_armed = 0;
static volatile int g_gravitylite_start_worker_running = 0;
static volatile int g_gravity_motion_stop_requested = 1;
static volatile uint64_t g_gravity_motion_generation = 0;
static CMMotionManager *g_gravity_motion_manager = nil;
static volatile int g_themer_live_running = 0;
static volatile int g_themer_live_stop_requested = 0;
static volatile int g_livewp_live_running = 0;
static volatile int g_livewp_live_stop_requested = 0;
static volatile int g_themer_repair_running = 0;
static volatile uint64_t g_themer_repair_generation = 0;
static const BOOL kThemerDynamicRepairEnabled = NO;
static volatile int g_app_in_background = 0;
static volatile int g_screen_awake = 1;
static volatile int g_screen_locked = 0;
static volatile int g_screen_lock_state_logged = 0;
static volatile int g_settings_termination_cleanup_started = 0;
static volatile int g_settings_cleanup_running = 0;
static volatile uint64_t g_sbc_live_apply_generation = 0;
static UIBackgroundTaskIdentifier g_statbar_bg_task = (UIBackgroundTaskIdentifier)-1;
static int g_springboard_blanked_notify_token = NOTIFY_TOKEN_INVALID;
static int g_display_status_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_lockstate_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_finished_startup_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_app_state_notify_token = NOTIFY_TOKEN_INVALID;
static int g_springboard_frontmost_notify_token = NOTIFY_TOKEN_INVALID;
static const NSInteger kSBCDefaultDockIcons = 4;
static const NSInteger kSBCDefaultCols = 4;
static const NSInteger kSBCDefaultRows = 6;
static const BOOL kSBCDefaultHideLabels = NO;
// Conservative seed values for the NanoRegistry editor. These represent the
// current "newer watch" baseline without changing the legacy-watch gates.
static const NSInteger kNanoDefaultMaxPairing       = 25;
static const NSInteger kNanoDefaultMinPairing       = 24;
static const NSInteger kNanoDefaultMinPairingChipID = 10;
static const NSInteger kNanoDefaultMinQuickSwitch   = 6;
// Pairing range used to let setup accept newer watchOS pairing generations
// while still accepting generation-23 setup messages from the existing flow.
static const NSInteger kNanoPresetNewerMaxPairing       = 99;
static const NSInteger kNanoPresetNewerMinPairing       = 23;
static const NSInteger kNanoPresetNewerMinPairingChipID = 10;
static const NSInteger kNanoPresetNewerMinQuickSwitch   = 6;
static const NSInteger kNanoUIRowMin = 1;
static const NSInteger kNanoUIRowMax = 999;
static const useconds_t kStatBarLiveIntervalUS = 1000000;
static const NSInteger kStatBarDefaultRefreshRateSec = 1;
static const NSUInteger kStatBarLiveMaxTicks = 43200;
static const useconds_t kNSBarLiveIntervalUS = 500000;
static const useconds_t kNSBarLiveBackgroundIntervalUS = 1000000;
static const useconds_t kNiceBarLiteLiveIntervalUS = 500000;
static const useconds_t kNiceBarLiteLiveBackgroundIntervalUS = 1000000;
static const useconds_t kNiceBarLiteNetworkIntervalUS = 500000;
static const NSUInteger kNiceBarLiteLiveMaxTicks = 43200;
static const NSTimeInterval kNiceBarLiteWeatherRefreshInterval = 900.0;
static const int64_t kLiveBackgroundTaskGraceSeconds = 10;
static const useconds_t kRSSILiveIntervalUS = 250000;
static const useconds_t kRSSILiveBackgroundIntervalUS = 1000000;
static const NSUInteger kRSSILiveMaxTicks = 43200;
static const useconds_t kAxonLiteLiveIntervalUS = 500000;
static const useconds_t kAxonLiteLiveBackgroundIntervalUS = 1500000;
static const NSUInteger kAxonLiteLiveMaxTicks = 43200;
static const int kSettingsSpringBoardRCFirstExceptionTimeoutMS = 3000;
// TypeBanner polls imagent for typing indicators with original-thread-only
// RemoteCall probes and opens SpringBoard only when the banner state changes.
static const useconds_t kTypeBannerLiveIntervalUS = 1000000;
static const useconds_t kTypeBannerLiveBackgroundIntervalUS = 1000000;
static const useconds_t kTypeBannerInitialDaemonSettleUS = 250000;
static const NSUInteger kTypeBannerLiveMaxTicks = 28800;
// Only Clock/Calendar need periodic repair; normal icons persist through the
// model graft and should not be repainted during SpringBoard animations.
static const useconds_t kThemerLiveIntervalUS = 2000000;
static const useconds_t kThemerLiveBackgroundIntervalUS = 10000000;
static const NSUInteger kThemerLiveMaxTicks = 86400;
static const NSUInteger kThemerLegacyLiveMaxTicks = 1;
static const useconds_t kThemerRepairInitialDelayUS = 900000;
static const useconds_t kThemerRepairIntervalUS = 450000;
static const useconds_t kLiveWPLiveIntervalUS = 5000000;
static const useconds_t kLiveWPLiveBackgroundIntervalUS = 15000000;
static const NSUInteger kLiveWPLiveMaxTicks = 43200;
static NSString * const kSettingsRemoteCallStateDidChangeNotification = @"SettingsRemoteCallStateDidChangeNotification";
NSString * const kSettingsActionsDidCompleteNotification = @"SettingsActionsDidCompleteNotification";
NSString * const kSettingsActionsDidCompleteSuccessKey = @"success";
NSString * const kSettingsActionsDidCompleteMessageKey = @"message";
static NSString * const kSettingsCleanupStateDidChangeNotification = @"SettingsCleanupStateDidChangeNotification";

static void settings_notify_cleanup_state_changed(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kSettingsCleanupStateDidChangeNotification
                          object:nil];
    });
}
static NSArray<NSString *> * const kPowercuffLevels = nil;

// Session-scoped record of which tweaks were actually applied since launch.
// Distinct from the persisted NSUserDefaults enable flag — these are wiped on
// app launch and whenever the SpringBoard RemoteCall session is torn down, so
// the UI can show accurate "Installed" state rather than a stale toggle.
static NSMutableSet<NSString *> *g_applied_tweak_keys = nil;

static NSMutableSet<NSString *> *settings_applied_keys_set(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_applied_tweak_keys = [NSMutableSet set];
    });
    return g_applied_tweak_keys;
}

static void settings_mark_tweak_applied(NSString *key, BOOL applied)
{
    if (!key) return;
    NSMutableSet *set = settings_applied_keys_set();
    @synchronized (set) {
        if (applied) [set addObject:key];
        else         [set removeObject:key];
    }
}

BOOL settings_tweak_is_applied(NSString *key)
{
    if (!key) return NO;
    NSMutableSet *set = settings_applied_keys_set();
    @synchronized (set) {
        return [set containsObject:key];
    }
}

static BOOL settings_clear_all_applied_locked(void)
{
    NSMutableSet *set = settings_applied_keys_set();
    BOOL changed = NO;
    @synchronized (set) {
        if (set.count > 0) {
            [set removeAllObjects];
            changed = YES;
        }
    }
    return changed;
}

static NSArray<NSString *> *settings_rc_backed_tweak_keys(void)
{
    static NSArray<NSString *> *keys = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            kSettingsSBCEnabled,
            kSettingsStatBarEnabled,
            kSettingsNSBarEnabled,
            kSettingsNiceBarLiteEnabled,
            kSettingsRSSIDisplayEnabled,
            kSettingsAxonLiteEnabled,
            kSettingsTypeBannerEnabled,
            kSettingsAppSwitcherGridEnabled,
            kSettingsGravityLiteEnabled,
            kSettingsPowercuffEnabled,
            kSettingsDSDisableAppLibrary,
            kSettingsDSDisableIconFlyIn,
            kSettingsDSZeroWakeAnimation,
            kSettingsDSZeroBacklightFade,
            kSettingsDSDoubleTapToLock,
            kSettingsDSDragCoefficientEnabled,
            kSettingsLayoutExtrasEnabled,
            kSettingsThemerEnabled,
            kSettingsSnowBoardLiteEnabled,
            kSettingsLiveWPEnabled,
        ];
    });
    return keys;
}

static void settings_reconcile_applied_from_defaults(void)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in settings_rc_backed_tweak_keys()) {
        if (![d boolForKey:key]) settings_mark_tweak_applied(key, NO);
    }
}

static void settings_notify_package_queue_changed_async(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                            object:[PackageQueue sharedQueue]];
    });
}

static NSObject *settings_rc_lock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSObject *settings_bg_lock(void) {
    static NSObject *lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static uint64_t settings_now_us(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}

static void settings_apply_statbar_once_async(const char *reason);
static void settings_apply_nsbar_once_async(const char *reason);
static void settings_apply_nicebarlite_once_async(const char *reason);
static void settings_apply_rssi_once_async(const char *reason);
static void settings_start_rssi_live_loop(void);
static void settings_start_typebanner_live_loop(void);
static void settings_start_themer_live_loop(void);
static void settings_start_livewp_live_loop(void);
static BOOL settings_livewp_should_play(void);
static void settings_pause_livewp_for_sleep_async(const char *reason);
static void settings_resume_livewp_after_wake_async(const char *reason);
static void settings_schedule_themer_repair_burst(const char *reason);
static void settings_schedule_themer_quiet_repair_burst(const char *reason);
static void settings_notify_remote_call_state_changed(void);
static void settings_request_all_live_loops_stop(const char *reason);
static BOOL settings_nicebar_has_weather_slots(NSUserDefaults *d);
static void settings_nicebar_refresh_weather_if_needed(BOOL force,
                                                       void (^completion)(BOOL ok, NSString *text));
static bool settings_apply_nicebarlite_from_defaults_locked(NSUserDefaults *d);

static BOOL settings_defaults_has_persisted_key(NSUserDefaults *d, NSString *key)
{
    if (key.length == 0) return NO;
    NSDictionary *domain = [d persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    return domain[key] != nil;
}

static BOOL settings_should_log_statbar_tick(NSUInteger tick) {
    // One-shot: log the very first tick so the user can see the loop took
    // off, then go silent forever. The polling continues; we just stop
    // narrating it.
    return tick == 0;
}

static BOOL settings_should_log_nicebar_tick(NSUInteger tick,
                                             uint64_t applyUS,
                                             uint64_t totalUS,
                                             bool ok)
{
    return tick < 4 || !ok || applyUS >= 250000ULL || totalUS >= 400000ULL;
}

static useconds_t settings_live_interval(useconds_t foregroundUS, useconds_t backgroundUS)
{
    return (g_app_in_background != 0) ? backgroundUS : foregroundUS;
}

static useconds_t settings_statbar_refresh_rate_us(void)
{
    NSInteger sec = [[NSUserDefaults standardUserDefaults] integerForKey:kSettingsStatBarRefreshRateSec];
    if (sec <= 0) sec = kStatBarDefaultRefreshRateSec;
    if (sec < 1) sec = 1;
    if (sec > 30) sec = 30;
    return (useconds_t)sec * 1000000;
}

static useconds_t settings_statbar_live_interval_us(void)
{
    return settings_live_interval(kStatBarLiveIntervalUS,
                                  settings_statbar_refresh_rate_us());
}

static const char *settings_live_context(void)
{
    return (g_app_in_background != 0) ? "background" : "foreground";
}

static BOOL settings_app_state_is_foreground(void)
{
    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    return state == UIApplicationStateActive || state == UIApplicationStateInactive;
}

static NSUInteger settings_live_failure_limit(NSUInteger foregroundLimit)
{
    return (g_app_in_background != 0 || g_screen_awake == 0) ? 1 : foregroundLimit;
}

static BOOL settings_rssi_install_allowed(void)
{
    return NO;
}

static BOOL settings_read_screen_awake(void)
{
    BOOL haveState = NO;
    BOOL awake = YES;

    if (g_springboard_blanked_notify_token != NOTIFY_TOKEN_INVALID) {
        uint64_t state = 0;
        if (notify_get_state(g_springboard_blanked_notify_token, &state) == NOTIFY_STATUS_OK) {
            haveState = YES;
            awake = (state == 0);
        }
    }

    if (!haveState && g_display_status_notify_token != NOTIFY_TOKEN_INVALID) {
        uint64_t state = 0;
        if (notify_get_state(g_display_status_notify_token, &state) == NOTIFY_STATUS_OK) {
            awake = (state != 0);
        }
    }

    return awake;
}

static BOOL settings_screen_awake_cached(void)
{
    return g_screen_awake != 0;
}

static BOOL settings_refresh_screen_awake_state(const char *reason)
{
    BOOL awake = settings_read_screen_awake();
    int newValue = awake ? 1 : 0;
    int old = __sync_lock_test_and_set(&g_screen_awake, newValue);
    if (old != newValue) {
        printf("[SETTINGS] screen state=%s%s%s\n",
               awake ? "awake" : "asleep",
               reason ? " via " : "",
               reason ?: "");
    }
    return old == 0 && newValue != 0;
}

static BOOL settings_statbar_screen_awake(void)
{
    (void)settings_refresh_screen_awake_state(NULL);
    return settings_screen_awake_cached();
}

static BOOL settings_read_screen_locked(void)
{
    if (g_springboard_lockstate_notify_token == NOTIFY_TOKEN_INVALID) return NO;

    uint64_t state = 0;
    if (notify_get_state(g_springboard_lockstate_notify_token, &state) != NOTIFY_STATUS_OK) {
        return NO;
    }

    return state != 0;
}

static BOOL settings_screen_locked_cached(void)
{
    return g_screen_locked != 0;
}

static BOOL settings_gravity_motion_can_remote_call(uint64_t generation,
                                                    CMMotionManager *manager)
{
    return manager &&
           manager == g_gravity_motion_manager &&
           generation == g_gravity_motion_generation &&
           g_gravity_motion_stop_requested == 0 &&
           g_springboard_rc_ready != 0 &&
           !settings_screen_locked_cached() &&
           settings_screen_awake_cached() &&
           !settings_cleanup_in_progress();
}

static void settings_start_gravity_motion(double magnitude)
{
    if (g_gravity_motion_manager) {
        [g_gravity_motion_manager stopDeviceMotionUpdates];
        [g_gravity_motion_manager stopAccelerometerUpdates];
        g_gravity_motion_manager = nil;
    }

    CMMotionManager *manager = [[CMMotionManager alloc] init];
    g_gravity_motion_manager = manager;
    uint64_t generation = __sync_add_and_fetch(&g_gravity_motion_generation, 1);
    __sync_lock_test_and_set(&g_gravity_motion_stop_requested, 0);

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;

    if (manager.deviceMotionAvailable) {
        manager.deviceMotionUpdateInterval = 0.05;
        [manager startDeviceMotionUpdatesToQueue:queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
            if (!motion || error || !settings_gravity_motion_can_remote_call(generation, manager)) return;
            double tilt = hypot(motion.gravity.x, motion.gravity.y);
            double angle = (tilt < 0.14) ? M_PI_2 : atan2(-motion.gravity.y, motion.gravity.x);
            double effectiveMagnitude = magnitude * ((tilt < 0.14)
                                                     ? 0.65
                                                     : (0.90 + fmin(tilt, 1.0) * 0.60));
            @synchronized (settings_rc_lock()) {
                if (!settings_gravity_motion_can_remote_call(generation, manager)) return;
                gravitylite_update_gravity_angle_in_session(angle, effectiveMagnitude);
            }
        }];
    } else {
        manager.accelerometerUpdateInterval = 0.05;
        [manager startAccelerometerUpdatesToQueue:queue withHandler:^(CMAccelerometerData *data, NSError *error) {
            if (!data || error || !settings_gravity_motion_can_remote_call(generation, manager)) return;
            double tilt = hypot(data.acceleration.x, data.acceleration.y);
            double angle = (tilt < 0.14) ? M_PI_2 : atan2(-data.acceleration.y, data.acceleration.x);
            double effectiveMagnitude = magnitude * ((tilt < 0.14)
                                                     ? 0.65
                                                     : (0.90 + fmin(tilt, 1.2) * 0.50));
            @synchronized (settings_rc_lock()) {
                if (!settings_gravity_motion_can_remote_call(generation, manager)) return;
                gravitylite_update_gravity_angle_in_session(angle, effectiveMagnitude);
            }
        }];
    }

    printf("[GRAVITY] accelerometer active magnitude=%.2f\n", magnitude);
}

static void settings_stop_gravity_motion(void)
{
    __sync_lock_test_and_set(&g_gravity_motion_stop_requested, 1);
    __sync_add_and_fetch(&g_gravity_motion_generation, 1);
    CMMotionManager *manager = g_gravity_motion_manager;
    if (!manager) return;
    g_gravity_motion_manager = nil;
    [manager stopDeviceMotionUpdates];
    [manager stopAccelerometerUpdates];
    printf("[GRAVITY] accelerometer stopped\n");
}

static BOOL settings_refresh_screen_lock_state(const char *reason)
{
    BOOL locked = settings_read_screen_locked();
    int newValue = locked ? 1 : 0;
    int old = __sync_lock_test_and_set(&g_screen_locked, newValue);
    BOOL firstLog = !__sync_lock_test_and_set(&g_screen_lock_state_logged, 1);
    if (firstLog || old != newValue) {
        printf("[SETTINGS] lock state=%s%s%s\n",
               locked ? "locked" : "unlocked",
               reason ? " via " : "",
               reason ?: "");
    }
    return old != newValue;
}

static BOOL settings_axonlite_can_poll_springboard(void)
{
    // Locked-but-awake is the lockscreen — that's where Axon must run, so the
    // lock state is intentionally not part of this predicate. Only pause while
    // the screen is fully blanked, since SB tears down the cover-sheet VCs and
    // our cached pointers would PAC-fault if we kept calling through them.
    (void)settings_refresh_screen_awake_state(NULL);
    return settings_screen_awake_cached();
}

static const char *settings_axonlite_pause_reason(void)
{
    if (!settings_screen_awake_cached()) return "screen asleep";
    return "screen unavailable";
}

static BOOL settings_typebanner_can_poll_messages(void)
{
    (void)settings_refresh_screen_awake_state(NULL);
    (void)settings_refresh_screen_lock_state(NULL);
    return settings_screen_awake_cached() && !settings_screen_locked_cached();
}

static const char *settings_typebanner_pause_reason(void)
{
    if (!settings_screen_awake_cached()) return "screen asleep";
    if (settings_screen_locked_cached()) return "device locked";
    return "screen unavailable";
}

static void settings_stop_axonlite_then_forget_locked(const char *reason)
{
    if (g_springboard_rc_ready) {
        bool stopped = axonlite_stop_in_session();
        printf("[SETTINGS] Axon Lite stopped before state drop%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", stopped);
    }
    axonlite_forget_remote_state();
}

static void settings_forget_springboard_tweak_state_locked(void)
{
    statbar_forget_remote_state();
    nsbar_forget_remote_state();
    nicebarlite_forget_remote_state();
    rssidisplay_forget_remote_state();
    axonlite_forget_remote_state();
    typebanner_forget_remote_state();
    appswitchergrid_forget_remote_state();
    killallapps_forget_remote_state();
    themer_forget_remote_state();
    livewp_forget_remote_state();
    gravitylite_forget_remote_state();
}

static void settings_stop_springboard_tweaks_locked(const char *reason,
                                                    BOOL springboardWillDie)
{
    if (!g_springboard_rc_ready) {
        settings_forget_springboard_tweak_state_locked();
        return;
    }

    @try {
        bool tbKeepAlive = typebanner_release_mobilesms_keepalive_in_springboard_session();
        bool tbHidden = typebanner_hide_in_springboard_session();
        printf("[SETTINGS] %s TypeBanner cleanup keepAlive=%d hide=%d\n",
               reason ?: "SpringBoard cleanup", tbKeepAlive, tbHidden);
    } @catch (NSException *e) {
        printf("[SETTINGS] %s TypeBanner cleanup exception: %s\n",
               reason ?: "SpringBoard cleanup", e.reason.UTF8String);
    }

    bool axonStopped = springboardWillDie
        ? axonlite_stop_in_session_fast()
        : axonlite_stop_in_session();
    printf("[SETTINGS] %s Axon Lite stop%s result=%d\n",
           reason ?: "SpringBoard cleanup",
           springboardWillDie ? " (fast)" : "",
           axonStopped);

    bool appSwitcherStopped = springboardWillDie
        ? false
        : appswitchergrid_stop_in_session();
    printf("[SETTINGS] %s App Switcher Grid stop%s result=%d\n",
           reason ?: "SpringBoard cleanup",
           springboardWillDie ? " (skipped; SpringBoard dying)" : "",
           appSwitcherStopped);

    bool statStopped = statbar_stop_in_session();
    printf("[SETTINGS] %s StatBar stop result=%d\n",
           reason ?: "SpringBoard cleanup", statStopped);

    bool rssiStopped = rssidisplay_stop_in_session();
    printf("[SETTINGS] %s RSSI stop result=%d\n",
           reason ?: "SpringBoard cleanup", rssiStopped);

    bool themeStopped = themer_stop_in_session();
    printf("[SETTINGS] %s Themer stop result=%d\n",
           reason ?: "SpringBoard cleanup", themeStopped);

    bool livewpStopped = livewp_stop_in_session();
    printf("[SETTINGS] %s LiveWP stop result=%d\n",
           reason ?: "SpringBoard cleanup", livewpStopped);

    settings_stop_gravity_motion();
    bool gravityStopped = gravitylite_stop_in_session();
    printf("[SETTINGS] %s Gravity Lite stop result=%d\n",
           reason ?: "SpringBoard cleanup", gravityStopped);

    bool nsbarStopped = nsbar_stop_in_session();
    printf("[SETTINGS] %s NSBar stop result=%d\n",
           reason ?: "SpringBoard cleanup", nsbarStopped);

    bool nicebarStopped = nicebarlite_stop_in_session();
    printf("[SETTINGS] %s NiceBar Lite stop result=%d\n",
           reason ?: "SpringBoard cleanup", nicebarStopped);

    settings_forget_springboard_tweak_state_locked();
}

static void settings_handle_springboard_restart(void)
{
    // SpringBoard just (re)started. Every pointer we cached from the previous
    // SB incarnation — class addresses, selector slots, retained objects,
    // ivar offsets, the trojan thread, our shmem map — is stale. Calling
    // through any of them under SB-2 hands a wild signed function pointer to
    // BLRAA and PAC-faults us. Drop everything before the next loop tick.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL hadSession = NO;
        @synchronized (settings_rc_lock()) {
            hadSession = (g_springboard_rc_ready != 0);
            // Tell live loops to bail at their next interval check.
            settings_request_all_live_loops_stop("SpringBoard restart");
            g_springboard_rc_ready = 0;
            g_springboard_sandbox_escaped = 0;

            settings_forget_springboard_tweak_state_locked();
            if (hadSession) {
                abandon_remote_call();
            }
        }
        printf("[SETTINGS] SpringBoard restart observed; dropped RemoteCall state (hadSession=%d)\n",
               (int)hadSession);
        if (hadSession) {
            log_user("[APP] SpringBoard restarted; tweak sessions cleared. Hit Run to rebuild.\n");
        }
        settings_notify_remote_call_state_changed();
    });
}

static void settings_install_screen_awake_observers(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int status = notify_register_dispatch("com.apple.springboard.hasBlankedScreen",
                                              &g_springboard_blanked_notify_token,
                                              dispatch_get_main_queue(), ^(int token) {
            (void)token;
            BOOL woke = settings_refresh_screen_awake_state("springboard.hasBlankedScreen");
            log_user("[LIVEWP] Screen notify springboard.hasBlankedScreen awake=%d.\n",
                     settings_screen_awake_cached() ? 1 : 0);
            if (woke) {
                settings_apply_statbar_once_async("screen awake");
                settings_apply_nsbar_once_async("screen awake");
                settings_resume_livewp_after_wake_async("screen awake");
                settings_schedule_themer_quiet_repair_burst("screen awake");
            } else if (!settings_screen_awake_cached()) {
                settings_pause_livewp_for_sleep_async("screen asleep");
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_blanked_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.iokit.hid.displayStatus",
                                          &g_display_status_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            BOOL woke = settings_refresh_screen_awake_state("iokit.displayStatus");
            log_user("[LIVEWP] Screen notify iokit.displayStatus awake=%d.\n",
                     settings_screen_awake_cached() ? 1 : 0);
            if (woke) {
                settings_apply_statbar_once_async("screen awake");
                settings_apply_nsbar_once_async("screen awake");
                settings_resume_livewp_after_wake_async("display awake");
                settings_schedule_themer_quiet_repair_burst("display awake");
            } else if (!settings_screen_awake_cached()) {
                settings_pause_livewp_for_sleep_async("display asleep");
            }
        });
        if (status != NOTIFY_STATUS_OK) {
            g_display_status_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.springboard.lockstate",
                                          &g_springboard_lockstate_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            (void)settings_refresh_screen_lock_state("springboard.lockstate");
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_lockstate_notify_token = NOTIFY_TOKEN_INVALID;
        }

        // Darwin notify fires when SpringBoard finishes its boot/respawn.
        // Either we just launched and SB is fine (cleanup is a no-op against
        // already-zero state) or SB crashed under us and we MUST drop every
        // cached pointer before the live loops fire again into SB-2.
        status = notify_register_dispatch("com.apple.springboard.finishedstartup",
                                          &g_springboard_finished_startup_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            (void)token;
            settings_handle_springboard_restart();
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_finished_startup_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.springboard.applicationStateChanged",
                                          &g_springboard_app_state_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            (void)notify_get_state(token, &state);
            printf("[SETTINGS] springboard application state notify state=%llu\n",
                   (unsigned long long)state);
            settings_schedule_themer_repair_burst("springboard app state changed");
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_app_state_notify_token = NOTIFY_TOKEN_INVALID;
        }

        status = notify_register_dispatch("com.apple.springboard.frontmostApplicationChanged",
                                          &g_springboard_frontmost_notify_token,
                                          dispatch_get_main_queue(), ^(int token) {
            uint64_t state = 0;
            (void)notify_get_state(token, &state);
            printf("[SETTINGS] springboard frontmost app notify state=%llu\n",
                   (unsigned long long)state);
            settings_schedule_themer_repair_burst("springboard frontmost changed");
        });
        if (status != NOTIFY_STATUS_OK) {
            g_springboard_frontmost_notify_token = NOTIFY_TOKEN_INVALID;
        }

        // If the live loop tripped its 3-failure exit during a background
        // window, the screen-wake darwin notifications won't fire (the screen
        // never blanked) and the loop stays dead. Re-arm on app foreground.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            (void)settings_refresh_screen_awake_state("app became active");
            settings_apply_statbar_once_async("app became active");
            settings_apply_nsbar_once_async("app became active");
            settings_schedule_themer_quiet_repair_burst("app became active");
        }];

        (void)settings_refresh_screen_awake_state("startup");
        (void)settings_refresh_screen_lock_state("startup");
    });
}

static void settings_end_statbar_background_task_async(const char *reason)
{
    void (^endTask)(void) = ^{
        @synchronized (settings_bg_lock()) {
            if (g_statbar_bg_task == UIBackgroundTaskInvalid) return;
            UIBackgroundTaskIdentifier task = g_statbar_bg_task;
            g_statbar_bg_task = UIBackgroundTaskInvalid;
            [[UIApplication sharedApplication] endBackgroundTask:task];
            printf("[SETTINGS] StatBar background task ended%s%s\n",
                   reason ? ": " : "", reason ?: "");
        }
    };

    if ([NSThread isMainThread]) {
        endTask();
    } else {
        dispatch_async(dispatch_get_main_queue(), endTask);
    }
}

// Bridge the foreground -> background transition with a short explicit
// UIBackgroundTask. DSKeepAlive's audio background mode carries the ongoing
// live feed; holding a UIBackgroundTask indefinitely trips UIKit's 30s watchdog
// warning and can get the app terminated.
static void settings_begin_statbar_background_task_async(const char *reason)
{
    void (^beginTask)(void) = ^{
        @synchronized (settings_bg_lock()) {
            if (g_statbar_bg_task != UIBackgroundTaskInvalid) return;
            UIApplication *app = [UIApplication sharedApplication];
            __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
            task = [app beginBackgroundTaskWithName:@"cyanide.statbar.live"
                                  expirationHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    @synchronized (settings_bg_lock()) {
                        if (g_statbar_bg_task != task) return;
                        g_statbar_bg_task = UIBackgroundTaskInvalid;
                        [[UIApplication sharedApplication] endBackgroundTask:task];
                        printf("[SETTINGS] StatBar background task expired by iOS; live loop may pause\n");
                    }
                });
            }];
            if (task == UIBackgroundTaskInvalid) {
                printf("[SETTINGS] StatBar background task could not be acquired%s%s\n",
                       reason ? ": " : "", reason ?: "");
                return;
            }
            g_statbar_bg_task = task;
            printf("[SETTINGS] StatBar background task acquired id=%lu%s%s\n",
                   (unsigned long)task,
                   reason ? ": " : "", reason ?: "");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         kLiveBackgroundTaskGraceSeconds * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                @synchronized (settings_bg_lock()) {
                    if (g_statbar_bg_task != task) return;
                    g_statbar_bg_task = UIBackgroundTaskInvalid;
                    [[UIApplication sharedApplication] endBackgroundTask:task];
                    printf("[SETTINGS] StatBar background task ended: transition grace elapsed; keepAlive=%d\n",
                           ds_keepalive_is_running());
                }
            });
        }
    };

    if ([NSThread isMainThread]) {
        beginTask();
    } else {
        dispatch_sync(dispatch_get_main_queue(), beginTask);
    }
}

static void settings_notify_remote_call_state_changed(void)
{
    BOOL ready = (g_springboard_rc_ready != 0);
    BOOL cleared = NO;
    if (!ready) {
        cleared = settings_clear_all_applied_locked();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsRemoteCallStateDidChangeNotification
                                                            object:nil];
        if (cleared) {
            [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                object:[PackageQueue sharedQueue]];
            [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsActionsDidCompleteNotification
                                                                object:nil];
        }
    });
}

static BOOL settings_cleanup_in_progress(void)
{
    return g_settings_cleanup_running != 0 ||
           g_settings_respring_cleanup_running != 0;
}

static void settings_request_all_live_loops_stop(const char *reason)
{
    g_statbar_live_stop_requested = 1;
    g_nsbar_live_stop_requested = 1;
    g_nicebarlite_live_stop_requested = 1;
    g_rssi_live_stop_requested = 1;
    g_axonlite_live_stop_requested = 1;
    g_typebanner_live_stop_requested = 1;
    __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
    settings_stop_gravity_motion();
    g_themer_live_stop_requested = 1;
    g_livewp_live_stop_requested = 1;
    if (reason) {
        printf("[SETTINGS] requested all live RemoteCall loops stop: %s\n", reason);
    }
}

static BOOL settings_has_active_termination_live_tweak(void)
{
    if (g_statbar_live_running || g_nsbar_live_running || g_nicebarlite_live_running || g_rssi_live_running ||
        g_axonlite_live_running || g_typebanner_live_running ||
        g_livewp_live_running) {
        return YES;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return ([d boolForKey:kSettingsStatBarEnabled] &&
            settings_tweak_is_applied(kSettingsStatBarEnabled)) ||
           ([d boolForKey:kSettingsRSSIDisplayEnabled] &&
            settings_tweak_is_applied(kSettingsRSSIDisplayEnabled)) ||
           ([d boolForKey:kSettingsAxonLiteEnabled] &&
            settings_tweak_is_applied(kSettingsAxonLiteEnabled)) ||
           ([d boolForKey:kSettingsTypeBannerEnabled] &&
            settings_tweak_is_applied(kSettingsTypeBannerEnabled)) ||
           ([d boolForKey:kSettingsGravityLiteEnabled] &&
            settings_tweak_is_applied(kSettingsGravityLiteEnabled)) ||
           ([d boolForKey:kSettingsNiceBarLiteEnabled] &&
            settings_tweak_is_applied(kSettingsNiceBarLiteEnabled)) ||
           ([d boolForKey:kSettingsLiveWPEnabled] &&
            settings_tweak_is_applied(kSettingsLiveWPEnabled));
}

static BOOL settings_has_persistent_springboard_remote_call_user(void)
{
    if (settings_has_active_termination_live_tweak() ||
        g_themer_live_running || g_themer_repair_running) {
        return YES;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return ([d boolForKey:kSettingsThemerEnabled] &&
            settings_tweak_is_applied(kSettingsThemerEnabled)) ||
           ([d boolForKey:kSettingsAppSwitcherGridEnabled] &&
            settings_tweak_is_applied(kSettingsAppSwitcherGridEnabled)) ||
           ([d boolForKey:kSettingsSnowBoardLiteEnabled] &&
            settings_tweak_is_applied(kSettingsSnowBoardLiteEnabled));
}

static void settings_wait_live_loops_stopped_for_switch(const char *reason)
{
    uint64_t startUS = settings_now_us();
    BOOL logged = NO;
    while (g_statbar_live_running || g_nsbar_live_running || g_nicebarlite_live_running || g_rssi_live_running ||
           g_axonlite_live_running || g_typebanner_live_running ||
           g_themer_live_running || g_themer_repair_running ||
           g_livewp_live_running) {
        uint64_t nowUS = settings_now_us();
        uint64_t elapsedUS = (startUS != 0 && nowUS >= startUS) ? nowUS - startUS : 0;
        if (!logged) {
            printf("[SETTINGS] waiting for live RemoteCall loops to stop%s%s\n",
                   reason ? ": " : "", reason ?: "");
            logged = YES;
        }
        if (elapsedUS >= 2000000ULL) {
            printf("[SETTINGS] live loop stop wait timed out%s%s stat=%d nsbar=%d nicebar=%d rssi=%d axon=%d type=%d themer=%d livewp=%d\n",
                   reason ? ": " : "", reason ?: "",
                   g_statbar_live_running, g_nsbar_live_running, g_nicebarlite_live_running, g_rssi_live_running,
                   g_axonlite_live_running, g_typebanner_live_running,
                   g_themer_live_running || g_themer_repair_running,
                   g_livewp_live_running);
            break;
        }
        usleep(50000);
    }
    if (logged && !g_statbar_live_running && !g_nsbar_live_running && !g_rssi_live_running &&
        !g_axonlite_live_running && !g_typebanner_live_running &&
        !g_themer_live_running && !g_themer_repair_running &&
        !g_livewp_live_running) {
        printf("[SETTINGS] live RemoteCall loops stopped%s%s\n",
               reason ? ": " : "", reason ?: "");
    }
}

static void settings_wait_live_loops_stopped_for_termination(const char *reason)
{
    uint64_t startUS = settings_now_us();
    const uint64_t timeoutUS = 800000ULL;
    while (g_statbar_live_running || g_nsbar_live_running || g_nicebarlite_live_running || g_rssi_live_running ||
           g_axonlite_live_running || g_typebanner_live_running ||
           g_themer_live_running || g_themer_repair_running ||
           g_livewp_live_running) {
        uint64_t nowUS = settings_now_us();
        uint64_t elapsedUS = (startUS != 0 && nowUS >= startUS) ? nowUS - startUS : 0;
        if (elapsedUS >= timeoutUS) {
            printf("[SETTINGS] termination live-loop wait timed out%s%s stat=%d nsbar=%d nicebar=%d rssi=%d axon=%d type=%d themer=%d livewp=%d\n",
                   reason ? ": " : "", reason ?: "",
                   g_statbar_live_running, g_nsbar_live_running, g_nicebarlite_live_running, g_rssi_live_running,
                   g_axonlite_live_running, g_typebanner_live_running,
                   g_themer_live_running || g_themer_repair_running,
                   g_livewp_live_running);
            break;
        }
        usleep(50000);
    }
}

static void settings_live_loop_sleep_interruptible(uint64_t targetUS,
                                                  useconds_t fallbackUS,
                                                  volatile int *stopFlag)
{
    uint64_t sleptFallbackUS = 0;
    while (!settings_cleanup_in_progress() && (!stopFlag || *stopFlag == 0)) {
        uint64_t nowUS = settings_now_us();
        uint64_t remainingUS = 0;
        if (targetUS != 0 && nowUS != 0 && nowUS < targetUS) {
            remainingUS = targetUS - nowUS;
        } else if (targetUS == 0 && sleptFallbackUS < fallbackUS) {
            remainingUS = (uint64_t)fallbackUS - sleptFallbackUS;
        } else {
            break;
        }

        useconds_t chunkUS = (useconds_t)(remainingUS < 100000ULL ? remainingUS : 100000ULL);
        if (chunkUS == 0) break;
        usleep(chunkUS);
        if (targetUS == 0) sleptFallbackUS += chunkUS;
    }
}

static UIViewController *settings_top_view_controller(UIViewController *vc)
{
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) {
        return settings_top_view_controller(((UINavigationController *)vc).visibleViewController);
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        return settings_top_view_controller(((UITabBarController *)vc).selectedViewController);
    }
    return vc;
}

static UIViewController *settings_active_presenter(UIViewController *fallback)
{
    if (fallback.view.window) return settings_top_view_controller(fallback);

    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive &&
            ws.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow) {
                candidate = window;
                break;
            }
            if (!candidate && !window.hidden && window.rootViewController) {
                candidate = window;
            }
        }
        if (candidate) break;
    }

    return settings_top_view_controller(candidate.rootViewController ?: fallback);
}

static UIWindow *settings_active_window(UIViewController *fallback)
{
    if (fallback.view.window) return fallback.view.window;

    UIWindow *candidate = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive &&
            ws.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow) return window;
            if (!candidate && !window.hidden && window.rootViewController) {
                candidate = window;
            }
        }
    }
    return candidate;
}

static void settings_present_controller(UIViewController *controller, UIViewController *fallback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = settings_active_presenter(fallback);
        if (!presenter) {
            printf("[SETTINGS] presentation skipped: no attached presenter\n");
            return;
        }
        [presenter presentViewController:controller animated:YES completion:nil];
    });
}

static void settings_show_respring_overlay(UIViewController *fallback)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = settings_active_window(fallback);
        if (!window) {
            printf("[RESPRING] overlay skipped: no active window\n");
            return;
        }
        DSRespringOverlayView *overlay = [[DSRespringOverlayView alloc] initWithFrame:window.bounds];
        [window addSubview:overlay];
        [overlay loadRespringPayload];
    });
}

static NSArray<NSString *> *powercuff_levels(void) {
    return @[ @"off", @"nominal", @"light", @"moderate", @"heavy" ];
}

static NSArray<NSString *> *nsbar_positions(void) {
    return @[ @"Top Left", @"Bottom Left", @"Top Right", @"Bottom Right", @"Center" ];
}

static NSComparisonResult settings_compare_system_version(NSString *target)
{
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"0";
    return [version compare:target options:NSNumericSearch];
}

BOOL settings_device_supported(void)
{
    BOOL ios17to18 =
        settings_compare_system_version(@"17.0") != NSOrderedAscending &&
        settings_compare_system_version(@"18.7.1") != NSOrderedDescending;

    BOOL ios26 =
        settings_compare_system_version(@"26.0") != NSOrderedAscending &&
        settings_compare_system_version(@"26.0.1") != NSOrderedDescending;

    return ios17to18 || ios26;
}

static NSString *settings_unsupported_message(void)
{
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"unknown";
    return [NSString stringWithFormat:@"Not supported on iOS %@. Supported: iOS/iPadOS 17.0-18.7.1 or 26.0-26.0.1.", version];
}

static void settings_progress(NSUInteger *step, NSUInteger total, const char *message)
{
    if (!step || !message) return;
    (*step)++;
    log_user("[RUN %lu/%lu] %s\n",
             (unsigned long)*step,
             (unsigned long)total,
             message);
}

static NSString *settings_bundle_string(NSString *key, NSString *fallback)
{
    id value = [NSBundle mainBundle].infoDictionary[key];
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
        return value;
    }
    return fallback;
}

static NSString *settings_app_version_string(void)
{
    return settings_bundle_string(@"CFBundleShortVersionString", @"unknown");
}

static NSString *settings_app_build_string(void)
{
    return settings_bundle_string(@"CFBundleVersion", @"unknown");
}

static void settings_log_run_context(void)
{
    struct utsname u = {0};
    const char *machine = "unknown";
    if (uname(&u) == 0 && u.machine[0]) machine = u.machine;

    NSString *appVersion = settings_app_version_string();
    NSString *appBuild = settings_app_build_string();
    NSString *version = UIDevice.currentDevice.systemVersion ?: @"unknown";
    const char *krwState = g_kexploit_done
        ? "cached app KRW present; validating before use"
        : "no live app KRW; recovery or fresh chain will be attempted";

    log_user("[BOOT] Cyanide app=%s build=%s pid=%d running on %s, iOS/iPadOS %s.\n",
             appVersion.UTF8String, appBuild.UTF8String, getpid(), machine, version.UTF8String);
    log_user("[BOOT] Initializing settings, device support, action planner, and KRW gate.\n");
    log_user("[BOOT] KRW state: %s.\n", krwState);
}

static BOOL settings_ensure_kexploit(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] unsupported device: %s\n", settings_unsupported_message().UTF8String);
        return NO;
    }

    if (g_kexploit_done) {
        if (kexploit_krw_ready()) {
            log_user("[KRW] Reusing the live app KRW session; no exploit rerun needed.\n");
            return YES;
        }
        printf("[SETTINGS] cached KRW is stale; clearing RemoteCall state and recovering\n");
        log_user("[KRW] Cached app KRW failed validation; clearing RemoteCall state and trying recovery.\n");
        g_kexploit_done = NO;
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
    }

    printf("[SETTINGS] kexploit setup: recovery first, fresh cleanup if needed\n");
    log_user("[KRW] Setup: trying parked launchd sockets before any fresh socket spray.\n");
    int res = kexploit_opa334();
    if (res != 0) {
        printf("[SETTINGS] kexploit_opa334 failed: %d\n", res);
        return NO;
    }
    g_kexploit_done = YES;
    settings_notify_remote_call_state_changed();
    return YES;
}

static BOOL settings_nano_load_override_enabled(void)
{
    if (!settings_device_supported()) return NO;
    return krw_persistence_launchd_holds_krw() || krw_persistence_has_saved_recovery();
}

static BOOL settings_ensure_kexploit_recovery_only(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] unsupported device: %s\n", settings_unsupported_message().UTF8String);
        return NO;
    }

    if (g_kexploit_done) {
        if (kexploit_krw_ready() && krw_persistence_launchd_holds_krw()) {
            log_user("[KRW] Reusing parked/recovered KRW for NanoRegistry load.\n");
            return YES;
        }
        log_user("[KRW] NanoRegistry load requires parked KRW recovery; live state is not eligible.\n");
        return NO;
    }

    if (!krw_persistence_has_saved_recovery()) {
        log_user("[KRW] NanoRegistry load disabled: no parked KRW recovery state is saved.\n");
        return NO;
    }

    log_user("[KRW] NanoRegistry load: attempting parked recovery only; fresh spray is disabled for this button.\n");
    if (!krw_persistence_recover()) {
        log_user("[KRW] NanoRegistry load failed: parked KRW recovery was not available.\n");
        return NO;
    }

    g_kexploit_done = YES;
    settings_notify_remote_call_state_changed();
    return YES;
}

static BOOL settings_ensure_springboard_remote_call_locked(void)
{
    if (g_springboard_rc_ready) {
        printf("[SETTINGS] reusing SpringBoard RemoteCall session\n");
        return YES;
    }

    printf("[SETTINGS] initializing SpringBoard RemoteCall session\n");
    if (init_remote_call_with_first_exception_timeout("SpringBoard",
                                                      false,
                                                      kSettingsSpringBoardRCFirstExceptionTimeoutMS) != 0) {
        printf("[SETTINGS] init_remote_call(SpringBoard) failed\n");
        return NO;
    }

    g_springboard_rc_ready = 1;
    g_springboard_sandbox_escaped = 0;
    printf("[SETTINGS] SpringBoard RemoteCall session ready\n");
    settings_notify_remote_call_state_changed();
    return YES;
}

static void settings_destroy_springboard_remote_call_locked_internal(const char *reason, BOOL notifyState)
{
    if (!g_springboard_rc_ready) return;

    printf("[SETTINGS] destroying SpringBoard RemoteCall session%s%s\n",
           reason ? ": " : "", reason ?: "");
    destroy_remote_call();
    g_springboard_rc_ready = 0;
    g_springboard_sandbox_escaped = 0;
    if (notifyState) settings_notify_remote_call_state_changed();
}

static void settings_destroy_springboard_remote_call_locked(const char *reason)
{
    settings_destroy_springboard_remote_call_locked_internal(reason, YES);
}

static void settings_prepare_for_respring_sync(void)
{
    log_user("[RESPRING] Stopping live sessions before respring.\n");
    printf("[SETTINGS] preparing for respring cleanup rcReady=%d\n", g_springboard_rc_ready);
    settings_request_all_live_loops_stop("pre-respring cleanup");
    settings_end_statbar_background_task_async("pre-respring cleanup");
    settings_wait_live_loops_stopped_for_switch("pre-respring cleanup");

    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            // SB is about to be killed by the respring, so cleanup uses the
            // fast variant for tweaks where full remote restoration is wasted.
            settings_stop_springboard_tweaks_locked("pre-respring cleanup", YES);
            settings_destroy_springboard_remote_call_locked("pre-respring cleanup");
        }
    }

    if (g_kexploit_done) {
        bool parked = kexploit_terminal_cleanup();
        printf("[SETTINGS] pre-respring terminal KRW cleanup parked=%d\n", parked);
        g_kexploit_done = NO;
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
        kutils_reset_self_cache();
        settings_notify_remote_call_state_changed();
    }

    log_user("[RESPRING] Cleanup complete. Opening respring flow.\n");
    usleep(300000);
}

static void settings_terminal_kexploit_cleanup_sync_internal(const char *reason)
{
    log_user("[CLEANUP] Stopping live sessions and cleaning local KRW state.\n");
    printf("[SETTINGS] terminal KRW cleanup requested%s%s done=%d rcReady=%d\n",
           reason ? ": " : "", reason ?: "",
           g_kexploit_done, g_springboard_rc_ready);
    settings_request_all_live_loops_stop("terminal KRW cleanup");
    settings_end_statbar_background_task_async("terminal KRW cleanup");
    settings_wait_live_loops_stopped_for_switch("terminal KRW cleanup");

    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            settings_stop_springboard_tweaks_locked("terminal cleanup", NO);
            settings_destroy_springboard_remote_call_locked(reason ?: "terminal KRW cleanup");
        } else {
            settings_forget_springboard_tweak_state_locked();
        }
    }

    if (!g_kexploit_done) {
        printf("[SETTINGS] terminal KRW cleanup skipped: no local KRW session\n");
        log_user("[CLEANUP] No local KRW session is active.\n");
        return;
    }

    bool parked = kexploit_terminal_cleanup();
    printf("[SETTINGS] terminal KRW cleanup result parked=%d\n", parked);
    log_user("%s Clean Up finished. Next Run will try persisted KRW recovery first.\n",
             parked ? "[OK]" : "[WARN]");
    g_kexploit_done = NO;
    g_springboard_rc_ready = 0;
    g_springboard_sandbox_escaped = 0;
    kutils_reset_self_cache();
    settings_notify_remote_call_state_changed();
}

static void settings_terminal_kexploit_cleanup_sync(const char *reason)
{
    settings_terminal_kexploit_cleanup_sync_internal(reason);
}

static BOOL settings_acquire_actions_lock_wait(const char *owner, uint64_t timeoutUS)
{
    uint64_t startUS = settings_now_us();
    BOOL loggedWait = NO;

    while (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
        if (!loggedWait) {
            printf("[SETTINGS] %s waiting for active action before cleanup\n",
                   owner ?: "cleanup");
            log_user("[CLEANUP] Current operation is active; cleanup is queued.\n");
            loggedWait = YES;
        }

        if (timeoutUS != 0) {
            uint64_t nowUS = settings_now_us();
            if (startUS != 0 && nowUS >= startUS && nowUS - startUS >= timeoutUS) {
                printf("[SETTINGS] %s timed out waiting for action lock\n",
                       owner ?: "cleanup");
                log_user("[CLEANUP] Timed out waiting for the current operation to finish.\n");
                return NO;
            }
        }

        usleep(100000);
    }

    if (loggedWait) {
        uint64_t nowUS = settings_now_us();
        uint64_t waitedUS = (startUS != 0 && nowUS >= startUS) ? nowUS - startUS : 0;
        printf("[SETTINGS] %s acquired action lock after %lluus\n",
               owner ?: "cleanup", waitedUS);
    }
    return YES;
}

static void settings_queue_terminal_kexploit_cleanup(const char *reason)
{
    if (__sync_lock_test_and_set(&g_settings_cleanup_running, 1)) {
        printf("[SETTINGS] terminal cleanup already queued/running%s%s\n",
               reason ? ": " : "", reason ?: "");
        log_user("[CLEANUP] Clean Up is already queued.\n");
        return;
    }
    settings_notify_cleanup_state_changed();

    settings_request_all_live_loops_stop("queued terminal cleanup");
    settings_end_statbar_background_task_async("queued terminal cleanup");

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL locked = settings_acquire_actions_lock_wait("terminal cleanup", 0);
        @try {
            settings_terminal_kexploit_cleanup_sync_internal(reason ?: "manual action");
        } @finally {
            if (locked) __sync_lock_release(&g_settings_actions_running);
            __sync_lock_release(&g_settings_cleanup_running);
            settings_notify_cleanup_state_changed();
        }
    });
}

void settings_best_effort_termination_cleanup(const char *reason)
{
    if (__sync_lock_test_and_set(&g_settings_termination_cleanup_started, 1)) {
        printf("[SETTINGS] termination cleanup already attempted%s%s\n",
               reason ? ": " : "", reason ?: "");
        return;
    }

    const char *why = reason ?: "app termination";
    log_user("[CLEANUP] App termination requested (%s); attempting last-chance cleanup.\n", why);
    printf("[SETTINGS] best-effort termination cleanup requested: %s\n", why);

    if (!settings_has_active_termination_live_tweak()) {
        printf("[SETTINGS] termination cleanup skipped: no live tweaks active\n");
        log_user("[CLEANUP] No live tweaks are active; skipping termination cleanup.\n");
        return;
    }

    settings_request_all_live_loops_stop("termination cleanup");
    settings_end_statbar_background_task_async("termination cleanup");
    settings_wait_live_loops_stopped_for_termination(why);
    settings_forget_springboard_tweak_state_locked();
    if (g_springboard_rc_ready) {
        abandon_remote_call();
        g_springboard_rc_ready = 0;
        g_springboard_sandbox_escaped = 0;
    }
    log_user("[CLEANUP] App termination: live loops stopped and SpringBoard RemoteCall was abandoned.\n");
    printf("[SETTINGS] termination cleanup abandoned SpringBoard RemoteCall: %s\n", why);
}

void settings_destroy_springboard_remote_call_sync(void)
{
    settings_request_all_live_loops_stop("remote call sync cleanup");
    settings_end_statbar_background_task_async("remote call sync cleanup");
    settings_wait_live_loops_stopped_for_switch("remote call sync cleanup");
    @synchronized (settings_rc_lock()) {
        if (g_springboard_rc_ready) {
            settings_stop_springboard_tweaks_locked("remote call sync cleanup", NO);
        }
        settings_destroy_springboard_remote_call_locked("manual/sync cleanup");
    }
}

void settings_destroy_springboard_remote_call(void)
{
    settings_request_all_live_loops_stop("remote call cleanup");
    settings_end_statbar_background_task_async("remote call cleanup");
    log_user("[SESSION] Disconnecting from SpringBoard.\n");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        settings_wait_live_loops_stopped_for_switch("remote call cleanup");
        @synchronized (settings_rc_lock()) {
            BOOL hadSession = g_springboard_rc_ready != 0;
            if (g_springboard_rc_ready) {
                settings_stop_springboard_tweaks_locked("remote call cleanup", NO);
            }
            settings_destroy_springboard_remote_call_locked("manual cleanup");
            log_user(hadSession ? "[OK] SpringBoard session disconnected.\n" :
                                  "[SESSION] No active SpringBoard session.\n");
        }
    });
}

static bool settings_apply_sbc_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsSBCEnabled]) return false;

    return sbcustomizer_apply_in_session((int)[d integerForKey:kSettingsSBCDockIcons],
                                         (int)[d integerForKey:kSettingsSBCCols],
                                         (int)[d integerForKey:kSettingsSBCRows],
                                         [d boolForKey:kSettingsSBCHideLabels]);
}

static NSString *settings_nicebar_slot_name(NSInteger slot)
{
    switch (slot) {
        case NiceBarLiteSlotTopLeft: return @"Top left";
        case NiceBarLiteSlotTopRight: return @"Top right";
        case NiceBarLiteSlotBottomLeft: return @"Bottom left";
        case NiceBarLiteSlotBottomCenter: return @"Center";
        case NiceBarLiteSlotBottomRight: return @"Bottom right";
        default: return @"Slot";
    }
}

static NSString *settings_nicebar_key(NSString *prefix, NSInteger slot)
{
    return [NSString stringWithFormat:@"%@%ld", prefix, (long)slot];
}

static NSString *settings_nicebar_kind_name(NSInteger kind)
{
    switch (kind) {
        case NiceBarLiteContentOff: return @"Off";
        case NiceBarLiteContentCustomText: return @"Text";
        case NiceBarLiteContentSystem: return @"System";
        case NiceBarLiteContentTimeFormat: return @"Date / Time";
        case NiceBarLiteContentWeather: return @"Weather";
        default: return @"Off";
    }
}

static NSString *settings_nicebar_system_name(NSInteger item)
{
    switch (item) {
        case NiceBarLiteSystemBatteryTemp: return @"Battery temp";
        case NiceBarLiteSystemFreeRAM: return @"Free RAM";
        case NiceBarLiteSystemBatteryPercent: return @"Battery %";
        case NiceBarLiteSystemNetworkSpeed: return @"Network speed";
        case NiceBarLiteSystemUptime: return @"Uptime";
        case NiceBarLiteSystemDate: return @"Date";
        case NiceBarLiteSystemLunarDate: return @"Lunar date";
        case NiceBarLiteSystemTodayTraffic: return @"Today traffic";
        case NiceBarLiteSystemCurrentIP: return @"Current IP";
        case NiceBarLiteSystemFreeDisk: return @"Free disk";
        case NiceBarLiteSystemThermalState: return @"Thermal state";
        default: return @"Battery temp";
    }
}

static NSString *settings_nicebar_system_description(NSInteger item)
{
    switch (item) {
        case NiceBarLiteSystemBatteryTemp: return @"Battery sensor temperature. Falls back through SpringBoard when local IOKit is unavailable.";
        case NiceBarLiteSystemFreeRAM: return @"Currently free memory, refreshed by the NiceBar live loop.";
        case NiceBarLiteSystemBatteryPercent: return @"Current battery percentage from UIDevice.";
        case NiceBarLiteSystemNetworkSpeed: return @"Live download and upload speed.";
        case NiceBarLiteSystemUptime: return @"Time since the device last booted.";
        case NiceBarLiteSystemTodayTraffic: return @"Traffic counted since NiceBar started tracking today.";
        case NiceBarLiteSystemCurrentIP: return @"Current Wi-Fi IPv4 address, falling back to another active interface.";
        case NiceBarLiteSystemFreeDisk: return @"Available storage reported for important system usage.";
        case NiceBarLiteSystemThermalState: return @"Device heat level shown with emoji; can display English or Chinese.";
        default: return @"System status item.";
    }
}

static NSString *settings_nicebar_system_language_name(NSString *language)
{
    return [language isEqualToString:@"zh"] ? @"中文" : @"English";
}

static NSString *settings_nicebar_time_format_name(NSString *format)
{
    if ([format isEqualToString:@"HH:mm"]) return @"24h time";
    if ([format isEqualToString:@"h:mm a"]) return @"12h time";
    if ([format isEqualToString:@"HH:mm:ss"]) return @"Time + seconds";
    if ([format isEqualToString:@"EEE HH:mm"]) return @"Weekday + time";
    if ([format isEqualToString:@"a h:mm"]) return @"中文上下午";
    if ([format isEqualToString:@"M/d"]) return @"Short date";
    if ([format isEqualToString:@"MM/dd"]) return @"Date";
    if ([format isEqualToString:@"M/d EEE"]) return @"Date + weekday";
    if ([format isEqualToString:@"MM-dd HH:mm"]) return @"Date + time";
    if ([format isEqualToString:@"M月d日"]) return @"中文日期";
    if ([format isEqualToString:@"cyanide:cn-date-weekday"]) return @"中文日期+星期";
    if ([format isEqualToString:@"M月d日 EEE"]) return @"中文日期+星期";
    if ([format isEqualToString:@"cyanide:lunar"]) return @"Lunar date";
    if ([format isEqualToString:@"cyanide:lunar-cn"]) return @"农历";
    if ([format isEqualToString:@"cyanide:lunar-cn-full"]) return @"农历完整";
    return format.length ? format : @"HH:mm";
}

static NSString *settings_nicebar_lunar_cn_preview(BOOL full)
{
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
    NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    if (c.month <= 0 || c.day <= 0) return @"农历--";
    NSArray<NSString *> *months = @[@"正月", @"二月", @"三月", @"四月", @"五月", @"六月",
                                    @"七月", @"八月", @"九月", @"十月", @"冬月", @"腊月"];
    NSArray<NSString *> *days = @[@"初一", @"初二", @"初三", @"初四", @"初五", @"初六", @"初七", @"初八", @"初九", @"初十",
                                  @"十一", @"十二", @"十三", @"十四", @"十五", @"十六", @"十七", @"十八", @"十九", @"二十",
                                  @"廿一", @"廿二", @"廿三", @"廿四", @"廿五", @"廿六", @"廿七", @"廿八", @"廿九", @"三十"];
    NSString *month = (c.month >= 1 && c.month <= (NSInteger)months.count) ? months[(NSUInteger)c.month - 1] : @"";
    NSString *day = (c.day >= 1 && c.day <= (NSInteger)days.count) ? days[(NSUInteger)c.day - 1] : @"";
    if (!month.length || !day.length) return @"农历--";
    return full ? [NSString stringWithFormat:@"农历%@%@", month, day]
                : [NSString stringWithFormat:@"%@%@", month, day];
}

static BOOL settings_nicebar_time_format_uses_chinese_locale(NSString *format)
{
    return [format isEqualToString:@"a h:mm"] ||
           [format rangeOfString:@"月"].location != NSNotFound;
}

static NSString *settings_nicebar_chinese_weekday_preview(void)
{
    NSInteger weekday = [[NSCalendar currentCalendar] component:NSCalendarUnitWeekday fromDate:[NSDate date]];
    NSArray<NSString *> *weekdays = @[@"", @"星期日", @"星期一", @"星期二", @"星期三", @"星期四", @"星期五", @"星期六"];
    if (weekday < 1 || weekday >= (NSInteger)weekdays.count) return @"星期-";
    return weekdays[(NSUInteger)weekday];
}

static NSString *settings_nicebar_preview_for_time_format(NSString *format)
{
    if ([format isEqualToString:@"cyanide:lunar"]) {
        NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierChinese];
        NSDateComponents *c = [cal components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
        if (c.month > 0 && c.day > 0) {
            return [NSString stringWithFormat:@"L%02ld/%02ld", (long)c.month, (long)c.day];
        }
        return @"Lunar --";
    }
    if ([format isEqualToString:@"cyanide:lunar-cn"]) return settings_nicebar_lunar_cn_preview(NO);
    if ([format isEqualToString:@"cyanide:lunar-cn-full"]) return settings_nicebar_lunar_cn_preview(YES);
    if ([format isEqualToString:@"cyanide:cn-date-weekday"] || [format isEqualToString:@"M月d日 EEE"]) {
        return [NSString stringWithFormat:@"%@ %@",
                settings_nicebar_preview_for_time_format(@"M月d日"),
                settings_nicebar_chinese_weekday_preview()];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = settings_nicebar_time_format_uses_chinese_locale(format)
        ? [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"]
        : [NSLocale currentLocale];
    formatter.dateFormat = format.length ? format : @"HH:mm";
    NSString *text = [formatter stringFromDate:[NSDate date]];
    return text.length ? text : @"--";
}

static NSArray<NSDictionary<NSString *, NSString *> *> *settings_nicebar_time_presets(void)
{
    return @[
        @{ @"section": @"Time", @"title": @"24h time",       @"format": @"HH:mm" },
        @{ @"section": @"Time", @"title": @"12h time",       @"format": @"h:mm a" },
        @{ @"section": @"Time", @"title": @"Time + seconds", @"format": @"HH:mm:ss" },
        @{ @"section": @"Time", @"title": @"Weekday + time", @"format": @"EEE HH:mm" },
        @{ @"section": @"日期", @"title": @"Short date",     @"format": @"M/d" },
        @{ @"section": @"日期", @"title": @"Date",           @"format": @"MM/dd" },
        @{ @"section": @"日期", @"title": @"Date + weekday", @"format": @"M/d EEE" },
        @{ @"section": @"日期", @"title": @"Date + time",    @"format": @"MM-dd HH:mm" },
        @{ @"section": @"中文", @"title": @"中文时间",        @"format": @"a h:mm" },
        @{ @"section": @"中文", @"title": @"中文日期",        @"format": @"M月d日" },
        @{ @"section": @"中文", @"title": @"中文日期+星期",    @"format": @"cyanide:cn-date-weekday" },
        @{ @"section": @"农历", @"title": @"Lunar date",     @"format": @"cyanide:lunar" },
        @{ @"section": @"农历", @"title": @"农历",           @"format": @"cyanide:lunar-cn" },
        @{ @"section": @"农历", @"title": @"农历完整",        @"format": @"cyanide:lunar-cn-full" },
    ];
}

static _CyanideNiceBarWeatherRefresher *settings_nicebar_weather_refresher(void)
{
    static _CyanideNiceBarWeatherRefresher *refresher;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        refresher = [[_CyanideNiceBarWeatherRefresher alloc] init];
    });
    return refresher;
}

static BOOL settings_nicebar_has_weather_slots(NSUserDefaults *d)
{
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        if (kind == NiceBarLiteContentWeather) return YES;
    }
    return NO;
}

static NSString *settings_nicebar_weather_summary(NSInteger code, BOOL chinese)
{
    if (chinese) {
        switch (code) {
            case 0: return @"☀️ 晴";
            case 1: return @"🌤️ 晴转多云";
            case 2: return @"⛅️ 局部多云";
            case 3: return @"☁️ 阴";
            case 45:
            case 48: return @"🌫️ 雾";
            case 51:
            case 53:
            case 55: return @"🌦️ 毛毛雨";
            case 56:
            case 57: return @"🌧️ 冻毛毛雨";
            case 61:
            case 63:
            case 65: return @"🌧️ 雨";
            case 66:
            case 67: return @"🌧️ 冻雨";
            case 71:
            case 73:
            case 75:
            case 77: return @"❄️ 雪";
            case 80:
            case 81:
            case 82: return @"🌦️ 阵雨";
            case 85:
            case 86: return @"🌨️ 阵雪";
            case 95: return @"⛈️ 雷暴";
            case 96:
            case 99: return @"⛈️ 雷暴冰雹";
            default: return @"🌡️ 天气";
        }
    }
    switch (code) {
        case 0: return @"☀️ Clear";
        case 1: return @"🌤️ Mostly clear";
        case 2: return @"⛅️ Partly cloudy";
        case 3: return @"☁️ Cloudy";
        case 45:
        case 48: return @"🌫️ Fog";
        case 51:
        case 53:
        case 55: return @"🌦️ Drizzle";
        case 56:
        case 57: return @"🌧️ Freezing drizzle";
        case 61:
        case 63:
        case 65: return @"🌧️ Rain";
        case 66:
        case 67: return @"🌧️ Freezing rain";
        case 71:
        case 73:
        case 75:
        case 77: return @"❄️ Snow";
        case 80:
        case 81:
        case 82: return @"🌦️ Rain showers";
        case 85:
        case 86: return @"🌨️ Snow showers";
        case 95: return @"⛈️ Thunderstorm";
        case 96:
        case 99: return @"⛈️ Storm hail";
        default: return @"🌡️ Weather";
    }
}

static NSString *settings_nicebar_weather_text_for_slot(NSUserDefaults *d, NSInteger slot)
{
    NSNumber *tempNumber = [d objectForKey:kSettingsNiceBarLiteWeatherTemp];
    NSNumber *codeNumber = [d objectForKey:kSettingsNiceBarLiteWeatherCode];
    if (![tempNumber isKindOfClass:NSNumber.class] || ![codeNumber isKindOfClass:NSNumber.class]) {
        return [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?:
               [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, slot)] ?:
               @"Weather --";
    }
    NSString *language = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, slot)] ?: @"en";
    BOOL chinese = [language isEqualToString:@"zh"];
    NSString *summary = settings_nicebar_weather_summary(codeNumber.integerValue, chinese);
    return [NSString stringWithFormat:@"%@ %.0f°", summary, tempNumber.doubleValue];
}

static void settings_nicebar_update_weather_slot_texts(NSUserDefaults *d)
{
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        [d setObject:settings_nicebar_weather_text_for_slot(d, i)
              forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, i)];
    }
}

static void settings_nicebar_store_weather_result(NSUserDefaults *d,
                                                  NSNumber *temp,
                                                  NSNumber *code,
                                                  NSString *fallbackText,
                                                  BOOL fetched)
{
    if ([temp isKindOfClass:NSNumber.class] && [code isKindOfClass:NSNumber.class]) {
        [d setObject:temp forKey:kSettingsNiceBarLiteWeatherTemp];
        [d setObject:code forKey:kSettingsNiceBarLiteWeatherCode];
        NSString *cache = [NSString stringWithFormat:@"%@ %.0f°",
                           settings_nicebar_weather_summary(code.integerValue, NO),
                           temp.doubleValue];
        [d setObject:cache forKey:kSettingsNiceBarLiteWeatherCache];
    } else {
        NSString *resolved = fallbackText.length ? fallbackText : @"Weather --";
        [d setObject:resolved forKey:kSettingsNiceBarLiteWeatherCache];
    }
    [d setObject:[NSDate date] forKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
    if (fetched) {
        [d setObject:[NSDate date] forKey:kSettingsNiceBarLiteWeatherUpdatedAt];
    }
    settings_nicebar_update_weather_slot_texts(d);
    [d synchronize];
}

static void settings_nicebar_schedule_apply_after_weather_update(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if (![d boolForKey:kSettingsNiceBarLiteEnabled] || !g_springboard_rc_ready) return;
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                !g_springboard_rc_ready) return;
            bool ok = settings_apply_nicebarlite_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled, ok);
            printf("[SETTINGS] NiceBar Lite weather refresh apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

static volatile int g_nicebarlite_weather_refresh_requested = 0;

static void settings_nicebar_refresh_weather_if_needed(BOOL force,
                                                       void (^completion)(BOOL ok, NSString *text))
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_nicebar_has_weather_slots(d)) {
        if (force || completion) {
            log_user("[NICEBAR] Weather refresh skipped: no weather slot configured.\n");
        }
        if (completion) completion(NO, [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?: @"");
        return;
    }
    if (!force && completion == nil) {
        NSDate *lastAttempt = [d objectForKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
        if (lastAttempt && [[NSDate date] timeIntervalSinceDate:lastAttempt] < kNiceBarLiteWeatherRefreshInterval) {
            return;
        }
    }
    if (!force && completion == nil &&
        !__sync_bool_compare_and_swap(&g_nicebarlite_weather_refresh_requested, 0, 1)) {
        return;
    }

    if (force || completion) {
        log_user("[NICEBAR] Weather refresh requested force=%d.\n", force ? 1 : 0);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [settings_nicebar_weather_refresher() refreshWeatherForce:force
                                                       completion:^(BOOL ok, NSString *text, NSNumber *temp, NSNumber *code, BOOL fetched) {
            __sync_lock_release(&g_nicebarlite_weather_refresh_requested);
            NSUserDefaults *innerDefaults = [NSUserDefaults standardUserDefaults];
            if (fetched || force) {
                settings_nicebar_store_weather_result(innerDefaults, temp, code, text, ok);
            }
            if (fetched || force || completion) {
                log_user("[NICEBAR] Weather refresh finished ok=%d fetched=%d text=%s temp=%s code=%s\n",
                     ok ? 1 : 0,
                     fetched ? 1 : 0,
                     text.UTF8String ?: "(nil)",
                     temp ? temp.stringValue.UTF8String : "(nil)",
                     code ? code.stringValue.UTF8String : "(nil)");
            }
            if ((fetched || force) &&
                [innerDefaults boolForKey:kSettingsNiceBarLiteEnabled] &&
                g_springboard_rc_ready) {
                settings_nicebar_schedule_apply_after_weather_update();
            }
            if (completion) completion(ok, text);
        }];
    });
}

static NiceBarLiteConfig settings_nicebar_config_from_defaults(NSUserDefaults *d)
{
    NiceBarLiteConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.celsius = [d boolForKey:kSettingsNiceBarLiteCelsius];
    NSInteger legacySideInset = [d integerForKey:kSettingsNiceBarLiteLayoutSideInset];
    BOOL hasTopSide = settings_defaults_has_persisted_key(d, kSettingsNiceBarLiteLayoutTopSideInset);
    BOOL hasBottomSide = settings_defaults_has_persisted_key(d, kSettingsNiceBarLiteLayoutBottomSideInset);
    cfg.topSideInsetOffset = hasTopSide ? [d integerForKey:kSettingsNiceBarLiteLayoutTopSideInset] : legacySideInset;
    cfg.bottomSideInsetOffset = hasBottomSide ? [d integerForKey:kSettingsNiceBarLiteLayoutBottomSideInset] : legacySideInset;
    cfg.topYOffset = [d integerForKey:kSettingsNiceBarLiteLayoutTopY];
    cfg.bottomYOffset = [d integerForKey:kSettingsNiceBarLiteLayoutBottomY];
    cfg.centerXOffset = [d integerForKey:kSettingsNiceBarLiteLayoutCenterX];
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        cfg.slots[i].kind = (int)[d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        cfg.slots[i].systemItem = (int)[d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)];
        NSString *text = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, i)] ?: @"";
        NSString *time = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ?: @"HH:mm";
        NSString *weather = settings_nicebar_weather_text_for_slot(d, i);
        NSString *systemLanguage = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, i)] ?: @"en";
        cfg.slots[i].customText = text.UTF8String;
        cfg.slots[i].timeFormat = time.UTF8String;
        cfg.slots[i].weatherText = weather.UTF8String;
        cfg.slots[i].systemLanguage = systemLanguage.UTF8String;
    }
    return cfg;
}

static void settings_log_nicebar_config(NSUserDefaults *d, const char *prefix)
{
    NSInteger visibleSlots = 0;
    NSInteger netSlots = 0;
    NSInteger secondsSlots = 0;
    NSInteger weatherSlots = 0;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        if (kind == NiceBarLiteContentOff) continue;

        visibleSlots++;
        NSString *detail = settings_nicebar_kind_name(kind);
        if (kind == NiceBarLiteContentSystem) {
            NSInteger item = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)];
            detail = settings_nicebar_system_name(item);
            if (item == NiceBarLiteSystemNetworkSpeed ||
                item == NiceBarLiteSystemTodayTraffic ||
                item == NiceBarLiteSystemCurrentIP) netSlots++;
        } else if (kind == NiceBarLiteContentTimeFormat) {
            NSString *format = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ?: @"HH:mm";
            detail = settings_nicebar_time_format_name(format);
            if ([format rangeOfString:@"ss"].location != NSNotFound) secondsSlots++;
        } else if (kind == NiceBarLiteContentWeather) {
            weatherSlots++;
        }

        [parts addObject:[NSString stringWithFormat:@"%@=%@",
                          settings_nicebar_slot_name(i),
                          detail]];
    }

    NSString *summary = parts.count ? [parts componentsJoinedByString:@", "] : @"all slots off";
    log_user("[NICEBAR] %s visible=%ld net=%ld seconds=%ld weather=%ld celsius=%s | %s\n",
             prefix ?: "config",
             (long)visibleSlots,
             (long)netSlots,
             (long)secondsSlots,
             (long)weatherSlots,
             [d boolForKey:kSettingsNiceBarLiteCelsius] ? "yes" : "no",
             summary.UTF8String);
}

static bool settings_apply_nicebarlite_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsNiceBarLiteEnabled]) return false;
    NiceBarLiteConfig cfg = settings_nicebar_config_from_defaults(d);
    return nicebarlite_apply_in_session(cfg);
}

static bool settings_apply_nicebarlite_mask_from_defaults_locked(NSUserDefaults *d, uint32_t updateMask)
{
    if (![d boolForKey:kSettingsNiceBarLiteEnabled]) return false;
    NiceBarLiteConfig cfg = settings_nicebar_config_from_defaults(d);
    cfg.updateMask = updateMask;
    return nicebarlite_apply_in_session(cfg);
}

static uint32_t settings_nicebar_seconds_mask(NSUserDefaults *d)
{
    uint32_t mask = 0;
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        if (kind != NiceBarLiteContentTimeFormat) continue;
        NSString *format = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ?: @"HH:mm";
        if ([format rangeOfString:@"ss"].location != NSNotFound) mask |= (1u << i);
    }
    return mask;
}

static uint32_t settings_nicebar_clock_mask(NSUserDefaults *d)
{
    uint32_t mask = 0;
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        if (kind == NiceBarLiteContentTimeFormat) {
            mask |= (1u << i);
            continue;
        }
        if (kind != NiceBarLiteContentSystem) continue;
        NSInteger item = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)];
        if (item == NiceBarLiteSystemDate || item == NiceBarLiteSystemLunarDate) {
            mask |= (1u << i);
        }
    }
    return mask;
}

static uint32_t settings_nicebar_network_mask(NSUserDefaults *d)
{
    uint32_t mask = 0;
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
        if (kind != NiceBarLiteContentSystem) continue;
        NSInteger item = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)];
        if (item == NiceBarLiteSystemNetworkSpeed ||
            item == NiceBarLiteSystemTodayTraffic ||
            item == NiceBarLiteSystemCurrentIP) mask |= (1u << i);
    }
    return mask;
}

static uint32_t settings_nicebar_update_mask_for_key(NSString *key)
{
    if (key.length == 0) return 0;
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        if ([key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, i)]) {
            return (1u << i);
        }
    }
    return 0;
}

static BOOL settings_dark_tweaks_any_enabled(NSUserDefaults *d)
{
    return [d boolForKey:kSettingsDSDisableAppLibrary] ||
           [d boolForKey:kSettingsDSDisableIconFlyIn] ||
           [d boolForKey:kSettingsDSZeroWakeAnimation] ||
           [d boolForKey:kSettingsDSZeroBacklightFade] ||
           [d boolForKey:kSettingsDSDoubleTapToLock] ||
           [d boolForKey:kSettingsDSDragCoefficientEnabled];
}

static BOOL settings_enabled_tweak_should_run(NSUserDefaults *d, NSString *key, BOOL pendingOnly)
{
    if (![d boolForKey:key]) return NO;
    return !pendingOnly || !settings_tweak_is_applied(key);
}

static BOOL settings_dark_tweaks_should_run(NSUserDefaults *d, BOOL pendingOnly)
{
    for (NSString *key in @[
        kSettingsDSDisableAppLibrary,
        kSettingsDSDisableIconFlyIn,
        kSettingsDSZeroWakeAnimation,
        kSettingsDSZeroBacklightFade,
        kSettingsDSDoubleTapToLock,
        kSettingsDSDragCoefficientEnabled,
    ]) {
        if (settings_enabled_tweak_should_run(d, key, pendingOnly)) return YES;
    }
    return NO;
}

static bool settings_apply_dark_tweaks_from_defaults_locked(NSUserDefaults *d)
{
    if (!settings_dark_tweaks_any_enabled(d)) return false;

    bool ok = darksword_tweaks_apply_in_session([d boolForKey:kSettingsDSDisableAppLibrary],
                                                [d boolForKey:kSettingsDSDisableIconFlyIn],
                                                [d boolForKey:kSettingsDSZeroWakeAnimation],
                                                [d boolForKey:kSettingsDSZeroBacklightFade],
                                                [d boolForKey:kSettingsDSDoubleTapToLock]);
    if ([d boolForKey:kSettingsDSDragCoefficientEnabled]) {
        NSInteger stored = [d integerForKey:kSettingsDSDragCoefficientValue];
        double coefficient = (stored > 0) ? (double)stored / 100.0 : 0.5;
        ok &= darksword_drag_coefficient_apply(coefficient);
    }
    return ok;
}

static bool settings_apply_layout_extras_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsLayoutExtrasEnabled]) return false;
    double exL  = (double)[d integerForKey:kSettingsLayoutHomeExtraLeft];
    double exR  = (double)[d integerForKey:kSettingsLayoutHomeExtraRight];
    double exT  = (double)[d integerForKey:kSettingsLayoutHomeExtraTop];
    double exB  = (double)[d integerForKey:kSettingsLayoutHomeExtraBottom];
    double dockExH = (double)[d integerForKey:kSettingsLayoutDockExtraHorizontal];
    NSInteger hsPct = [d integerForKey:kSettingsLayoutHomeScalePct];
    NSInteger dkPct = [d integerForKey:kSettingsLayoutDockScalePct];
    double homeScale = (hsPct > 0) ? (double)hsPct / 100.0 : 1.0;
    double dockScale = (dkPct > 0) ? (double)dkPct / 100.0 : 1.0;
    return darksword_layout_apply_in_session(exL, exR, exT, exB, dockExH, homeScale, dockScale);
}

static GravityLiteConfig settings_gravitylite_config_from_defaults(NSUserDefaults *d)
{
    NSInteger magnitudePct = [d integerForKey:kSettingsGravityLiteMagnitudePct];
    NSInteger bouncePct = [d integerForKey:kSettingsGravityLiteBouncePct];
    NSInteger frictionPct = [d integerForKey:kSettingsGravityLiteFrictionPct];
    NSInteger resistancePct = [d integerForKey:kSettingsGravityLiteResistancePct];
    NSInteger angularResistancePct = [d integerForKey:kSettingsGravityLiteAngularResistancePct];
    if (magnitudePct <= 0) magnitudePct = 100;
    if (resistancePct < 0) resistancePct = 0;
    if (angularResistancePct < 0) angularResistancePct = 0;

    GravityLiteConfig config = {
        .includeDock = [d boolForKey:kSettingsGravityLiteDockEnabled],
        .allowsRotation = true,
        .magnitude = (double)magnitudePct / 45.0,
        .bounce = (double)bouncePct / 100.0,
        .friction = (double)frictionPct / 100.0,
        .resistance = (double)resistancePct / 100.0,
        .angularResistance = (double)angularResistancePct / 100.0,
        .explosionForce = 7.0,
    };
    return config;
}

static bool settings_apply_gravitylite_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsGravityLiteEnabled]) return false;
    return gravitylite_apply_in_session(settings_gravitylite_config_from_defaults(d));
}

static void settings_restart_gravity_motion_if_active(const char *reason)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsGravityLiteEnabled]) return;
    if (!settings_tweak_is_applied(kSettingsGravityLiteEnabled)) return;
    if (!g_springboard_rc_ready || settings_cleanup_in_progress()) return;
    if (!settings_screen_awake_cached() || settings_screen_locked_cached()) return;
    if (g_gravity_motion_stop_requested == 0 && g_gravity_motion_manager) return;

    GravityLiteConfig config = settings_gravitylite_config_from_defaults(d);
    settings_start_gravity_motion(config.magnitude);
    printf("[GRAVITY] accelerometer loop restarted%s%s\n",
           reason ? ": " : "", reason ?: "");
}

static bool settings_arm_gravitylite_for_background_start_locked(NSUserDefaults *d,
                                                                 const char *reason)
{
    if (![d boolForKey:kSettingsGravityLiteEnabled]) return false;
    bool stopped = gravitylite_stop_in_session();
    settings_stop_gravity_motion();
    __sync_lock_test_and_set(&g_gravitylite_background_armed, 1);
    settings_mark_tweak_applied(kSettingsGravityLiteEnabled, YES);
    printf("[SETTINGS] Gravity Lite armed for background start%s%s stop=%d\n",
           reason ? ": " : "", reason ?: "", stopped);
    return true;
}

static BOOL settings_gravitylite_start_window_ready(const char *reason)
{
    (void)settings_refresh_screen_awake_state(reason ?: "gravity start");
    (void)settings_refresh_screen_lock_state(reason ?: "gravity start");
    return settings_screen_awake_cached() && !settings_screen_locked_cached();
}

static void settings_apply_armed_gravitylite_once_async(const char *reason)
{
    if (g_gravitylite_start_worker_running != 0) return;
    if (g_gravitylite_background_armed == 0) return;
    if (settings_cleanup_in_progress()) return;
    if (__sync_lock_test_and_set(&g_gravitylite_start_worker_running, 1)) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @try {
            uint64_t waitDeadline = settings_now_us() + 30000000ULL;
            while (!settings_cleanup_in_progress() &&
                   g_gravitylite_background_armed != 0 &&
                   [d boolForKey:kSettingsGravityLiteEnabled] &&
                   g_springboard_rc_ready &&
                   !settings_gravitylite_start_window_ready(reason ?: "gravity start")) {
                if (settings_now_us() >= waitDeadline) return;
                usleep(50000);
            }

            if (settings_cleanup_in_progress()) return;
            if (![d boolForKey:kSettingsGravityLiteEnabled] || !g_springboard_rc_ready) return;
            if (!settings_gravitylite_start_window_ready(reason ?: "gravity start")) return;

            bool ok = false;
            GravityLiteConfig appliedConfig = {0};
            uint64_t applyDeadline = settings_now_us() + 2000000ULL;
            int attempt = 0;
            do {
                usleep(80000);
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        !g_springboard_rc_ready ||
                        ![d boolForKey:kSettingsGravityLiteEnabled] ||
                        !settings_gravitylite_start_window_ready(reason ?: "gravity start")) {
                        return;
                    }
                    if (!__sync_bool_compare_and_swap(&g_gravitylite_background_armed, 1, 0) && attempt == 0) return;
                    appliedConfig = settings_gravitylite_config_from_defaults(d);
                    ok = gravitylite_apply_in_session(appliedConfig);
                    settings_mark_tweak_applied(kSettingsGravityLiteEnabled,
                                                ok && [d boolForKey:kSettingsGravityLiteEnabled]);
                }
                if (ok) break;
                attempt++;
                usleep(120000);
            } while (settings_now_us() < applyDeadline);

            if (ok) {
                settings_start_gravity_motion(appliedConfig.magnitude);
                log_user("[OK] Gravity Lite active.\n");
                cyanide_upload_log_milestone(@"gravity-lite-applied");
            } else {
                log_user("[WARN] Gravity Lite did not start cleanly.\n");
                cyanide_upload_log_milestone(@"gravity-lite-warning");
            }
            printf("[SETTINGS] Gravity Lite start%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
            settings_notify_package_queue_changed_async();
        } @finally {
            __sync_lock_release(&g_gravitylite_start_worker_running);
        }
    });
}

static NSString * const kThemerThemeNone = @"";
static NSString * const kThemerThemeBuiltinIOS6 = @"builtin-ios6";
static NSString * const kThemerThemeCustom = @"custom";

static NSString *settings_themer_builtin_ios6_path(void)
{
    return [[NSBundle mainBundle].bundlePath
        stringByAppendingPathComponent:@"Themes-iOS6.plist"];
}

static NSString *settings_themer_documents_theme_root(void)
{
    NSArray<NSString *> *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count == 0) return nil;
    return [docs.firstObject stringByAppendingPathComponent:@"Themes"];
}

static NSString *settings_themer_imported_theme_dir(void)
{
    NSString *root = settings_themer_documents_theme_root();
    return root ? [root stringByAppendingPathComponent:@"Imported"] : nil;
}

static NSString *settings_themer_imported_plist_path(void)
{
    NSString *root = settings_themer_documents_theme_root();
    return root ? [root stringByAppendingPathComponent:@"Imported.plist"] : nil;
}

static NSString *settings_themer_selected_theme_id(void)
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:kSettingsThemerThemeID] ?: kThemerThemeNone;
}

BOOL settings_themer_has_selected_theme(void)
{
    NSString *theme = settings_themer_selected_theme_id();
    if ([theme isEqualToString:kThemerThemeBuiltinIOS6]) {
        return [[NSFileManager defaultManager] fileExistsAtPath:settings_themer_builtin_ios6_path()];
    }
    if ([theme isEqualToString:kThemerThemeCustom]) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *path = [d stringForKey:kSettingsThemerCustomThemePath];
        BOOL isDir = NO;
        return path.length > 0 &&
               [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    }
    return NO;
}

NSString *settings_themer_selected_theme_display_name(void)
{
    NSString *theme = settings_themer_selected_theme_id();
    if ([theme isEqualToString:kThemerThemeBuiltinIOS6]) return @"iOS 6 Theme";
    if ([theme isEqualToString:kThemerThemeCustom]) {
        NSString *name = [[NSUserDefaults standardUserDefaults]
            stringForKey:kSettingsThemerCustomThemeName];
        return name.length > 0 ? name : @"Imported Theme";
    }
    return @"None";
}

static NSDictionary<NSString *, NSData *> *settings_themer_load_plist_theme(NSString *plistPath)
{
    NSError *err = nil;
    NSData *raw = [NSData dataWithContentsOfFile:plistPath options:0 error:&err];
    if (!raw) {
        printf("[THEMER] resolve: failed to read plist err=%s\n",
               err.localizedDescription.UTF8String ?: "?");
        return nil;
    }
    id parsed = [NSPropertyListSerialization
        propertyListWithData:raw
                     options:NSPropertyListImmutable
                      format:NULL
                       error:&err];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        printf("[THEMER] resolve: plist parse failed err=%s\n",
               err.localizedDescription.UTF8String ?: "?");
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)parsed;
    NSMutableDictionary<NSString *, NSData *> *out = [NSMutableDictionary dictionary];
    for (id key in dict) {
        id value = dict[key];
        if (![key isKindOfClass:NSString.class] ||
            ![value isKindOfClass:NSData.class] ||
            [(NSData *)value length] == 0) {
            continue;
        }
        out[key] = value;
    }
    printf("[THEMER] resolve: loaded plist theme entries=%lu size=%lu path=%s\n",
           (unsigned long)out.count,
           (unsigned long)raw.length,
           plistPath.UTF8String);
    return out;
}

static NSUInteger settings_themer_builtin_ios6_icon_count(void)
{
    static NSUInteger cachedCount = NSUIntegerMax;
    if (cachedCount != NSUIntegerMax) return cachedCount;
    NSDictionary *dict = settings_themer_load_plist_theme(settings_themer_builtin_ios6_path());
    cachedCount = dict.count;
    return cachedCount;
}

// Per-bundle icon swap. A theme must be selected explicitly: either the bundled
// iOS 6 plist, or an imported folder/plist in Documents/Themes/.
static bool settings_apply_themer_from_defaults_locked(NSUserDefaults *d)
{
    if (![d boolForKey:kSettingsThemerEnabled]) {
        printf("[THEMER] resolve: toggle off, skipping\n");
        return false;
    }

    NSString *theme = settings_themer_selected_theme_id();
    if (![theme isEqualToString:kThemerThemeBuiltinIOS6] &&
        ![theme isEqualToString:kThemerThemeCustom]) {
        printf("[THEMER] resolve: no selected theme; install/apply blocked\n");
        log_user("[THEMER] Pick a theme in Settings > Cyanide Themer before running.\n");
        return false;
    }

    if ([theme isEqualToString:kThemerThemeBuiltinIOS6]) {
        NSString *plistPath = settings_themer_builtin_ios6_path();
        if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
            printf("[THEMER] resolve: bundled plist missing at %s\n",
                   plistPath.UTF8String);
            return false;
        }
        NSDictionary *dict = settings_themer_load_plist_theme(plistPath);
        return dict.count > 0 ? themer_apply_data_in_session(dict) : false;
    }

    NSString *path = [d stringForKey:kSettingsThemerCustomThemePath];
    BOOL isDir = NO;
    if (path.length == 0 ||
        ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        printf("[THEMER] resolve: selected custom theme missing path=%s\n",
               path.UTF8String ?: "");
        return false;
    }
    if (isDir) {
        printf("[THEMER] resolve: using imported folder %s\n", path.UTF8String);
        return themer_apply_in_session(path.fileSystemRepresentation);
    }
    NSDictionary *dict = settings_themer_load_plist_theme(path);
    return dict.count > 0 ? themer_apply_data_in_session(dict) : false;
}

static void settings_reset_sbc_defaults(void)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] SBC reset blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:YES forKey:kSettingsSBCEnabled];
    [d setInteger:kSBCDefaultDockIcons forKey:kSettingsSBCDockIcons];
    [d setInteger:kSBCDefaultCols forKey:kSettingsSBCCols];
    [d setInteger:kSBCDefaultRows forKey:kSettingsSBCRows];
    [d setBool:kSBCDefaultHideLabels forKey:kSettingsSBCHideLabels];
    [d synchronize];

    printf("[SETTINGS] SBC reset defaults dock=%ld hs=%ldx%ld hideLabels=%d rcReady=%d\n",
           (long)kSBCDefaultDockIcons,
           (long)kSBCDefaultCols,
           (long)kSBCDefaultRows,
           kSBCDefaultHideLabels,
           g_springboard_rc_ready);

    if (!g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (settings_rc_lock()) {
            if (!g_springboard_rc_ready) return;
            bool ok = settings_apply_sbc_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsSBCEnabled,
                                        ok && [d boolForKey:kSettingsSBCEnabled]);
            printf("[SETTINGS] SBC reset apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

static bool settings_apply_ota_disabled_body(BOOL disable)
{
    if (!settings_ensure_kexploit()) {
        printf("[OTA] kernel primitives were not acquired\n");
        log_user("[OTA] Failed: kernel primitives were not acquired.\n");
        return false;
    }

    bool ok = darksword_ota_set_disabled(disable);

    settings_notify_package_queue_changed_async();
    return ok;
}

BOOL settings_apply_ota_disabled(BOOL disable)
{
    if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
        printf("[SETTINGS] actions already running; ignoring OTA request\n");
        log_user("[OTA] Another action is already running.\n");
        return NO;
    }
    @try {
        return settings_apply_ota_disabled_body(disable);
    } @finally {
        __sync_lock_release(&g_settings_actions_running);
    }
}

static void settings_run_ota_action(BOOL disable)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        log_user("[OTA] %s OTA updates.\n", disable ? "Disabling" : "Enabling");
        bool ok = settings_apply_ota_disabled(disable);
        printf("[SETTINGS] OTA %s result=%d\n", disable ? "disable" : "enable", ok);
        if (ok) {
            log_user("[OK] OTA updates %s. Respring or reboot required for changes to take effect.\n",
                     disable ? "disabled" : "enabled");
        } else {
            log_user("[FAIL] OTA %s failed — see log for [OTA] lines (likely sandbox patch or disabled.plist write).\n",
                     disable ? "disable" : "enable");
        }
    });
}

static void settings_nano_set_defaults_values(NSInteger maxV, NSInteger minV, NSInteger minChipV, NSInteger minQuickV)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:maxV     forKey:kSettingsNanoMaxPairing];
    [d setInteger:minV     forKey:kSettingsNanoMinPairing];
    [d setInteger:minChipV forKey:kSettingsNanoMinPairingChipID];
    [d setInteger:minQuickV forKey:kSettingsNanoMinQuickSwitch];
}

static void settings_nano_load_from_plist_into_defaults(BOOL logResult)
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    nano_registry_values values = {
        .max_pairing         = (int)[d integerForKey:kSettingsNanoMaxPairing],
        .min_pairing         = (int)[d integerForKey:kSettingsNanoMinPairing],
        .min_pairing_chip_id = (int)[d integerForKey:kSettingsNanoMinPairingChipID],
        .min_quick_switch    = (int)[d integerForKey:kSettingsNanoMinQuickSwitch],
    };
    bool present = false;
    bool ok = nano_registry_load(&values, &present);
    if (!ok) {
        if (logResult) log_user("[NANO] Could not read existing override plist (parse failure).\n");
        return;
    }
    [d setInteger:values.max_pairing         forKey:kSettingsNanoMaxPairing];
    [d setInteger:values.min_pairing         forKey:kSettingsNanoMinPairing];
    [d setInteger:values.min_pairing_chip_id forKey:kSettingsNanoMinPairingChipID];
    [d setInteger:values.min_quick_switch    forKey:kSettingsNanoMinQuickSwitch];
    if (logResult) {
        log_user(present
                 ? "[NANO] Loaded existing override: max=%d min=%d minChip=%d minQuick=%d.\n"
                 : "[NANO] No override present on device. Editor populated with current/seed values.\n",
                 values.max_pairing, values.min_pairing,
                 values.min_pairing_chip_id, values.min_quick_switch);
    }
}

// Synchronous entry point used by both the Settings UI buttons and the
// Installer's PackageQueue commit path. Logs progress to the in-app log so
// the InstallProgressViewController shows real lines during the apply.
BOOL settings_apply_nano_registry_now(BOOL apply)
{
    if (!settings_ensure_kexploit()) {
        log_user("[NANO] Failed: kernel primitives were not acquired.\n");
        return NO;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    bool ok;
    nano_registry_values values = {
        .max_pairing         = (int)[d integerForKey:kSettingsNanoMaxPairing],
        .min_pairing         = (int)[d integerForKey:kSettingsNanoMinPairing],
        .min_pairing_chip_id = (int)[d integerForKey:kSettingsNanoMinPairingChipID],
        .min_quick_switch    = (int)[d integerForKey:kSettingsNanoMinQuickSwitch],
    };
    if (apply) {
        log_user("[NANO] Applying pairing override max=%d min=%d minChip=%d minQuick=%d.\n",
                 values.max_pairing, values.min_pairing,
                 values.min_pairing_chip_id, values.min_quick_switch);
        ok = nano_registry_apply(&values);
        if (!ok) {
            log_user("[FAIL] NanoRegistry override write failed — see log for [NANO] lines.\n");
        }
    } else {
        log_user("[NANO] Removing pairing override keys.\n");
        ok = nano_registry_clear();
        if (!ok) {
            log_user("[FAIL] NanoRegistry override clear failed — see log for [NANO] lines.\n");
        }
    }

    // The file write above is necessary but not sufficient — cfprefsd owns
    // the in-memory cache that every CFPreferencesCopyValue call serves
    // from, and it will overwrite our plist with its stale cache the next
    // time any process writes to com.apple.NanoRegistry via the API. Push
    // the same values into cfprefsd's cache so the cache *has* our
    // override and future serializations preserve it.
    if (ok) {
        bool pushed = nano_registry_push_to_cfprefsd(&values, apply ? true : false);
        if (!pushed) {
            log_user("[NANO] cfprefsd push failed; on-disk override may be overwritten by cfprefsd's stale cache.\n");
        }
    }

    return ok ? YES : NO;
}

static void settings_run_nano_apply_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        (void)settings_apply_nano_registry_now(YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

static void settings_run_nano_clear_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        (void)settings_apply_nano_registry_now(NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

static void settings_run_nano_probe_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!settings_ensure_kexploit()) {
            log_user("[NANO-PROBE] Failed: kernel primitives were not acquired.\n");
        } else {
            (void)nano_registry_probe_pairing_assets();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

static void settings_run_nano_steer_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!settings_ensure_kexploit()) {
            log_user("[NANO-STEER] Failed: kernel primitives were not acquired.\n");
        } else {
            (void)nano_registry_steer_new_watch_product_alias();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

static void settings_run_nano_seed_action(void)
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (!settings_ensure_kexploit()) {
            log_user("[NANO-SEED] Failed: kernel primitives were not acquired.\n");
        } else {
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            nano_registry_values values = {
                .max_pairing         = (int)[d integerForKey:kSettingsNanoMaxPairing],
                .min_pairing         = (int)[d integerForKey:kSettingsNanoMinPairing],
                .min_pairing_chip_id = (int)[d integerForKey:kSettingsNanoMinPairingChipID],
                .min_quick_switch    = (int)[d integerForKey:kSettingsNanoMinQuickSwitch],
            };
            bool ok = nano_registry_seed_current_phone_compatibility_index(values.max_pairing);
            if (ok) {
                (void)nano_registry_push_to_cfprefsd(&values, true);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kSettingsActionsDidCompleteNotification
                              object:nil];
        });
    });
}

static void settings_start_statbar_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsStatBarEnabled]) return;

    if (__sync_lock_test_and_set(&g_statbar_live_running, 1)) {
        // Log-once for the process lifetime; further "already running" hits
        // during foreground/background lifecycle churn are pure noise.
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] StatBar live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_statbar_live_running);
        return;
    }

    g_statbar_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] StatBar live loop started interval=%uus background=%uus max=%lu\n",
               kStatBarLiveIntervalUS,
               settings_statbar_refresh_rate_us(),
               (unsigned long)kStatBarLiveMaxTicks);
        cyanide_upload_log_milestone(@"statbar-live-started");

        @try {
            while ([d boolForKey:kSettingsStatBarEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_statbar_live_stop_requested &&
                   tick < kStatBarLiveMaxTicks) {
                useconds_t intervalUS = settings_statbar_live_interval_us();
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] StatBar paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_statbar_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] StatBar resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_statbar_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] StatBar loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                  [d boolForKey:kSettingsStatBarShowTemp],
                                                  [d boolForKey:kSettingsStatBarShowCPU],
                                                  [d boolForKey:kSettingsStatBarShowRAM],
                                                  [d boolForKey:kSettingsStatBarShowNet],
                                                  [d boolForKey:kSettingsStatBarShowLabels]);
                }

                if (tick == 0) {
                    printf("[SETTINGS] StatBar result=%d\n", ok);
                    cyanide_upload_log_milestone(ok ? @"statbar-live-first-ok" : @"statbar-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] StatBar tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsStatBarEnabled] ||
                    g_statbar_live_stop_requested ||
                    tick >= kStatBarLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t elapsedUS = (tickStartUS != 0 && nowUS >= tickStartUS) ? (nowUS - tickStartUS) : 0;
                if (nextTickUS != 0) {
                    intervalUS = settings_statbar_live_interval_us();
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        uint64_t sleepUS = nextTickUS - nowUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] StatBar tick=%lu elapsed=%lluus sleep=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   sleepUS,
                                   settings_live_context());
                        }
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)sleepUS,
                                                               &g_statbar_live_stop_requested);
                    } else {
                        uint64_t overrunUS = nowUS - nextTickUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] StatBar tick=%lu elapsed=%lluus overrun=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   overrunUS,
                                   settings_live_context());
                        }
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_statbar_live_interval_us(),
                                                           &g_statbar_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] StatBar live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsStatBarEnabled],
                   (unsigned long)failures,
                   g_statbar_live_stop_requested);
            if (![d boolForKey:kSettingsStatBarEnabled] || g_statbar_live_stop_requested || failures > 0) {
                settings_end_statbar_background_task_async("live loop exited");
            }
            if (failures > 0)
                cyanide_upload_log_milestone(@"statbar-live-exited-failed");
            __sync_lock_release(&g_statbar_live_running);
        }
    });
}

static void settings_apply_statbar_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsStatBarEnabled] || !g_springboard_rc_ready) return;
    if (g_statbar_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "statbar apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] StatBar lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_statbar_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsStatBarEnabled] ||
                !g_springboard_rc_ready) return;
            ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                          [d boolForKey:kSettingsStatBarShowTemp],
                                          [d boolForKey:kSettingsStatBarShowCPU],
                                          [d boolForKey:kSettingsStatBarShowRAM],
                                          [d boolForKey:kSettingsStatBarShowNet],
                                          [d boolForKey:kSettingsStatBarShowLabels]);
        }
        // Only log lifecycle applies that change result; a clean success on
        // every foreground/background flip is noise.
        static volatile int lastResult = -1;
        int now = ok ? 1 : 0;
        if (now != lastResult) {
            lastResult = now;
            printf("[SETTINGS] StatBar lifecycle apply%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
        }
        settings_start_statbar_live_loop();
    });
}

static void settings_start_nsbar_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNSBarEnabled]) return;

    if (__sync_lock_test_and_set(&g_nsbar_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] NSBar live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_nsbar_live_running);
        return;
    }

    g_nsbar_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] NSBar live loop started interval=%uus background=%uus max=%lu\n",
               kNSBarLiveIntervalUS,
               kNSBarLiveBackgroundIntervalUS,
               (unsigned long)kStatBarLiveMaxTicks);
        cyanide_upload_log_milestone(@"nsbar-live-started");

        @try {
            while ([d boolForKey:kSettingsNSBarEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_nsbar_live_stop_requested &&
                   tick < kStatBarLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kNSBarLiveIntervalUS,
                                                               kNSBarLiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] NSBar paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_nsbar_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] NSBar resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_nsbar_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] NSBar loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    NSBarPosition position = (NSBarPosition)[d integerForKey:kSettingsNSBarPosition];
                    ok = nsbar_apply_in_session(position);
                }

                if (tick == 0) {
                    printf("[SETTINGS] NSBar result=%d\n", ok);
                    cyanide_upload_log_milestone(ok ? @"nsbar-live-first-ok" : @"nsbar-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] NSBar tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsNSBarEnabled] ||
                    g_nsbar_live_stop_requested ||
                    tick >= kStatBarLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t elapsedUS = (tickStartUS != 0 && nowUS >= tickStartUS) ? (nowUS - tickStartUS) : 0;
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kNSBarLiveIntervalUS,
                                                        kNSBarLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        uint64_t sleepUS = nextTickUS - nowUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] NSBar tick=%lu elapsed=%lluus sleep=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   sleepUS,
                                   settings_live_context());
                        }
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)sleepUS,
                                                               &g_nsbar_live_stop_requested);
                    } else {
                        uint64_t overrunUS = nowUS - nextTickUS;
                        if (settings_should_log_statbar_tick(tick - 1)) {
                            printf("[SETTINGS] NSBar tick=%lu elapsed=%lluus overrun=%lluus mode=%s\n",
                                   (unsigned long)(tick - 1),
                                   elapsedUS,
                                   overrunUS,
                                   settings_live_context());
                        }
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kNSBarLiveIntervalUS,
                                                                                  kNSBarLiveBackgroundIntervalUS),
                                                           &g_nsbar_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] NSBar live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsNSBarEnabled],
                   (unsigned long)failures,
                   g_nsbar_live_stop_requested);
            if (![d boolForKey:kSettingsNSBarEnabled] || g_nsbar_live_stop_requested || failures > 0) {
                // NSBar doesn't need background task management like StatBar
            }
            if (failures > 0)
                cyanide_upload_log_milestone(@"nsbar-live-exited-failed");
            __sync_lock_release(&g_nsbar_live_running);
        }
    });
}

static void settings_apply_nsbar_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNSBarEnabled] || !g_springboard_rc_ready) return;
    if (g_nsbar_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "nsbar apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] NSBar lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_nsbar_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                g_settings_termination_cleanup_started ||
                ![d boolForKey:kSettingsNSBarEnabled] ||
                !g_springboard_rc_ready) return;
            NSBarPosition position = (NSBarPosition)[d integerForKey:kSettingsNSBarPosition];
            ok = nsbar_apply_in_session(position);
        }
        static volatile int lastResult = -1;
        int now = ok ? 1 : 0;
        if (now != lastResult) {
            lastResult = now;
            printf("[SETTINGS] NSBar lifecycle apply%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
        }
        settings_start_nsbar_live_loop();
    });
}

static void settings_start_nicebarlite_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNiceBarLiteEnabled]) return;

    if (__sync_lock_test_and_set(&g_nicebarlite_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] NiceBar Lite live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_nicebarlite_live_running);
        return;
    }

    g_nicebarlite_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        time_t lastSecondTick = 0;
        time_t lastMinuteTick = 0;
        uint64_t lastNetworkTickUS = 0;
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] NiceBar Lite live loop started interval=%uus background=%uus max=%lu\n",
               kNiceBarLiteLiveIntervalUS,
               kNiceBarLiteLiveBackgroundIntervalUS,
               (unsigned long)kNiceBarLiteLiveMaxTicks);
        log_user("[NICEBAR] Live loop started fg=%0.1fs bg=%0.1fs max=%lu\n",
                 (double)kNiceBarLiteLiveIntervalUS / 1000000.0,
                 (double)kNiceBarLiteLiveBackgroundIntervalUS / 1000000.0,
                 (unsigned long)kNiceBarLiteLiveMaxTicks);
        settings_log_nicebar_config(d, "live config");

        @try {
            while ([d boolForKey:kSettingsNiceBarLiteEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_nicebarlite_live_stop_requested &&
                   tick < kNiceBarLiteLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kNiceBarLiteLiveIntervalUS,
                                                               kNiceBarLiteLiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] NiceBar Lite paused while screen is asleep\n");
                        log_user("[NICEBAR] Live loop paused: screen asleep.\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_nicebarlite_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] NiceBar Lite resumed after screen wake\n");
                    log_user("[NICEBAR] Live loop resumed after screen wake.\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;
                settings_nicebar_refresh_weather_if_needed(NO, nil);
                uint64_t nowForMaskUS = tickStartUS;
                time_t nowSecond = time(NULL);
                time_t nowMinute = nowSecond / 60;
                uint32_t secondsMask = settings_nicebar_seconds_mask(d);
                uint32_t clockMask = settings_nicebar_clock_mask(d);
                uint32_t networkMask = settings_nicebar_network_mask(d);
                uint32_t updateMask = 0;
                const char *updateReason = "none";
                BOOL clockDue = (clockMask != 0 && nowMinute != lastMinuteTick);

                if (secondsMask != 0 && nowSecond != lastSecondTick) {
                    updateMask = secondsMask | (clockDue ? clockMask : 0);
                    updateReason = clockDue ? "seconds+clock" : "seconds";
                    lastSecondTick = nowSecond;
                    if (clockDue) lastMinuteTick = nowMinute;
                } else if (clockDue) {
                    updateMask = clockMask;
                    updateReason = "clock";
                    lastMinuteTick = nowMinute;
                } else if (networkMask != 0 &&
                           (lastNetworkTickUS == 0 ||
                            (nowForMaskUS >= lastNetworkTickUS &&
                             nowForMaskUS - lastNetworkTickUS >= (uint64_t)kNiceBarLiteNetworkIntervalUS))) {
                    updateMask = networkMask;
                    updateReason = "network";
                    lastNetworkTickUS = nowForMaskUS;
                } else if (secondsMask == 0 && networkMask == 0) {
                    updateMask = 0;
                    updateReason = "full";
                } else {
                    tick++;
                    if (![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                        g_nicebarlite_live_stop_requested ||
                        tick >= kNiceBarLiteLiveMaxTicks) break;

                    uint64_t idleNowUS = settings_now_us();
                    intervalUS = settings_live_interval(kNiceBarLiteLiveIntervalUS,
                                                        kNiceBarLiteLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (idleNowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - idleNowUS),
                                                               &g_nicebarlite_live_stop_requested);
                    } else {
                        nextTickUS = idleNowUS;
                    }
                    continue;
                }

                uint64_t applyStartUS = settings_now_us();
                @synchronized (settings_rc_lock()) {
                    if (g_nicebarlite_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] NiceBar Lite loop has no SpringBoard RemoteCall session\n");
                        log_user("[NICEBAR] Live tick aborted: SpringBoard session is not ready.\n");
                        failures++;
                        break;
                    }
                    ok = (updateMask == 0)
                        ? settings_apply_nicebarlite_from_defaults_locked(d)
                        : settings_apply_nicebarlite_mask_from_defaults_locked(d, updateMask);
                }
                uint64_t applyEndUS = settings_now_us();

                if (tick == 0) {
                    printf("[SETTINGS] NiceBar Lite result=%d\n", ok);
                    log_user("[NICEBAR] First live tick result=%d apply=%llums total=%llums\n",
                             ok ? 1 : 0,
                             (unsigned long long)((applyEndUS >= applyStartUS) ? ((applyEndUS - applyStartUS) / 1000ULL) : 0ULL),
                             (unsigned long long)(((applyEndUS >= tickStartUS) ? (applyEndUS - tickStartUS) : 0ULL) / 1000ULL));
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] NiceBar Lite tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    log_user("[NICEBAR] Live tick failed tick=%lu failures=%lu apply=%llums\n",
                             (unsigned long)tick,
                             (unsigned long)failures,
                             (unsigned long long)((applyEndUS >= applyStartUS) ? ((applyEndUS - applyStartUS) / 1000ULL) : 0ULL));
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                    g_nicebarlite_live_stop_requested ||
                    tick >= kNiceBarLiteLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t totalUS = (nowUS >= tickStartUS) ? (nowUS - tickStartUS) : 0;
                uint64_t applyUS = (applyEndUS >= applyStartUS) ? (applyEndUS - applyStartUS) : 0;
                if (settings_should_log_nicebar_tick(tick - 1, applyUS, totalUS, ok)) {
                    log_user("[NICEBAR] Tick=%lu ok=%d apply=%llums total=%llums interval=%llums rc=%s\n",
                             (unsigned long)(tick - 1),
                             ok ? 1 : 0,
                             (unsigned long long)(applyUS / 1000ULL),
                             (unsigned long long)(totalUS / 1000ULL),
                             (unsigned long long)(intervalUS / 1000ULL),
                             g_springboard_rc_ready ? "ready" : "down");
                    log_user("[NICEBAR] Tick detail reason=%s mask=0x%x seconds=0x%x network=0x%x\n",
                             updateReason,
                             updateMask,
                             secondsMask,
                             networkMask);
                }
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kNiceBarLiteLiveIntervalUS,
                                                        kNiceBarLiteLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_nicebarlite_live_stop_requested);
                    } else {
                        (void)tickStartUS;
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kNiceBarLiteLiveIntervalUS,
                                                                                  kNiceBarLiteLiveBackgroundIntervalUS),
                                                           &g_nicebarlite_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] NiceBar Lite live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsNiceBarLiteEnabled],
                   (unsigned long)failures,
                   g_nicebarlite_live_stop_requested);
            log_user("[NICEBAR] Live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                     (unsigned long)tick,
                     [d boolForKey:kSettingsNiceBarLiteEnabled],
                     (unsigned long)failures,
                     g_nicebarlite_live_stop_requested);
            __sync_lock_release(&g_nicebarlite_live_running);
        }
    });
}

static void settings_apply_nicebarlite_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;
    if (g_settings_termination_cleanup_started) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsNiceBarLiteEnabled] || !g_springboard_rc_ready) return;
    if (g_nicebarlite_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;
        bool ok = false;
        uint64_t beginUS = settings_now_us();
        log_user("[NICEBAR] Lifecycle apply requested%s%s.\n",
                 reason ? ": " : "",
                 reason ?: "");
        settings_log_nicebar_config(d, "lifecycle config");
        settings_nicebar_refresh_weather_if_needed(NO, nil);
        (void)settings_refresh_screen_awake_state(reason ?: "nicebarlite apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] NiceBar Lite lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            log_user("[NICEBAR] Lifecycle apply skipped: screen asleep.\n");
            settings_start_nicebarlite_live_loop();
            return;
        }
        uint64_t applyStartUS = settings_now_us();
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                g_settings_termination_cleanup_started ||
                ![d boolForKey:kSettingsNiceBarLiteEnabled] ||
                !g_springboard_rc_ready) return;
            ok = settings_apply_nicebarlite_from_defaults_locked(d);
        }
        uint64_t endUS = settings_now_us();
        static volatile int lastResult = -1;
        int now = ok ? 1 : 0;
        if (now != lastResult) {
            lastResult = now;
            printf("[SETTINGS] NiceBar Lite lifecycle apply%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
        }
        log_user("[NICEBAR] Lifecycle apply result=%d apply=%llums total=%llums\n",
                 ok ? 1 : 0,
                 (unsigned long long)((endUS >= applyStartUS) ? ((endUS - applyStartUS) / 1000ULL) : 0ULL),
                 (unsigned long long)((endUS >= beginUS) ? ((endUS - beginUS) / 1000ULL) : 0ULL));
        settings_start_nicebarlite_live_loop();
    });
}

static void settings_start_rssi_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_rssi_install_allowed()) return;
    if (![d boolForKey:kSettingsRSSIDisplayEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_rssi_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] RSSI live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_rssi_live_running);
        return;
    }

    g_rssi_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForSleep = NO;

        printf("[SETTINGS] RSSI live loop started interval=%uus background=%uus max=%lu\n",
               kRSSILiveIntervalUS,
               kRSSILiveBackgroundIntervalUS,
               (unsigned long)kRSSILiveMaxTicks);
        cyanide_upload_log_milestone(@"rssi-live-started");

        @try {
            while ([d boolForKey:kSettingsRSSIDisplayEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_rssi_live_stop_requested &&
                   tick < kRSSILiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kRSSILiveIntervalUS,
                                                               kRSSILiveBackgroundIntervalUS);
                if (!settings_statbar_screen_awake()) {
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] RSSI paused while screen is asleep\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_rssi_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] RSSI resumed after screen wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_rssi_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] RSSI loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                      [d boolForKey:kSettingsRSSIDisplayCell]);
                }

                uint64_t tickEndUS = settings_now_us();
                if (tick == 0) {
                    uint64_t elapsedUS = tickEndUS >= tickStartUS ? tickEndUS - tickStartUS : 0;
                    printf("[SETTINGS] RSSI first tick result=%d elapsed=%lluus\n",
                           ok,
                           (unsigned long long)elapsedUS);
                    cyanide_upload_log_milestone(ok ? @"rssi-live-first-ok" : @"rssi-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] RSSI tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(5)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsRSSIDisplayEnabled] ||
                    g_rssi_live_stop_requested ||
                    tick >= kRSSILiveMaxTicks) break;

                uint64_t nowUS = tickEndUS;
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kRSSILiveIntervalUS,
                                                        kRSSILiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_rssi_live_stop_requested);
                    } else {
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kRSSILiveIntervalUS,
                                                                                  kRSSILiveBackgroundIntervalUS),
                                                           &g_rssi_live_stop_requested);
                }
            }
        } @finally {
            printf("[SETTINGS] RSSI live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsRSSIDisplayEnabled],
                   (unsigned long)failures,
                   g_rssi_live_stop_requested);
            if (failures > 0)
                cyanide_upload_log_milestone(@"rssi-live-exited-failed");
            __sync_lock_release(&g_rssi_live_running);
        }
    });
}

static void settings_apply_rssi_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_rssi_install_allowed()) return;
    if (![d boolForKey:kSettingsRSSIDisplayEnabled] || !g_springboard_rc_ready) return;
    if (g_rssi_live_running) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        (void)settings_refresh_screen_awake_state(reason ?: "rssi apply");
        if (!settings_screen_awake_cached()) {
            printf("[SETTINGS] RSSI lifecycle apply%s%s skipped: screen asleep\n",
                   reason ? ": " : "", reason ?: "");
            settings_start_rssi_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsRSSIDisplayEnabled] ||
                !g_springboard_rc_ready) return;
            ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                              [d boolForKey:kSettingsRSSIDisplayCell]);
        }
        printf("[SETTINGS] RSSI lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_rssi_live_loop();
    });
}

static void settings_start_axonlite_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsAxonLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_axonlite_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] Axon Lite live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_axonlite_live_running);
        return;
    }

    g_axonlite_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        uint64_t nextTickUS = settings_now_us();
        BOOL pausedForUnavailableScreen = NO;

        printf("[SETTINGS] Axon Lite live loop started interval=%uus background=%uus max=%lu\n",
               kAxonLiteLiveIntervalUS,
               kAxonLiteLiveBackgroundIntervalUS,
               (unsigned long)kAxonLiteLiveMaxTicks);
        cyanide_upload_log_milestone(@"axon-lite-live-started");

        @try {
            settings_live_loop_sleep_interruptible(0,
                                                   settings_live_interval(kAxonLiteLiveIntervalUS,
                                                                          kAxonLiteLiveBackgroundIntervalUS),
                                                   &g_axonlite_live_stop_requested);
            nextTickUS = settings_now_us();
            while ([d boolForKey:kSettingsAxonLiteEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_axonlite_live_stop_requested &&
                   tick < kAxonLiteLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kAxonLiteLiveIntervalUS,
                                                               kAxonLiteLiveBackgroundIntervalUS);
                // While locked/asleep, CoverSheet churn is exactly where Axon
                // can put sustained pressure on SB. Pause locally without
                // messaging SB so the existing Axon roster/filter state is
                // still there when the screen wakes. The initial cache pass
                // is exempt — interrupting it leaves SB with requests we've
                // already removed but no segmented-control polling to bring
                // them back.
                if (!settings_axonlite_can_poll_springboard() &&
                    axonlite_initial_cache_ready()) {
                    if (!pausedForUnavailableScreen) {
                        pausedForUnavailableScreen = YES;
                        printf("[SETTINGS] Axon Lite paused while %s\n",
                               settings_axonlite_pause_reason());
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_axonlite_live_stop_requested);
                    nextTickUS = settings_now_us();
                    continue;
                }
                if (pausedForUnavailableScreen) {
                    pausedForUnavailableScreen = NO;
                    printf("[SETTINGS] Axon Lite resumed after screen unlock/wake\n");
                }

                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_axonlite_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] Axon Lite loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    if (!settings_axonlite_can_poll_springboard() &&
                        axonlite_initial_cache_ready()) {
                        printf("[SETTINGS] Axon Lite tick skipped inside lock: %s\n",
                               settings_axonlite_pause_reason());
                        nextTickUS = settings_now_us();
                        continue;
                    }
                    ok = axonlite_apply_in_session();
                }

                if (tick == 0) {
                    printf("[SETTINGS] Axon Lite result=%d\n", ok);
                    cyanide_upload_log_milestone(ok ? @"axon-lite-live-first-ok" : @"axon-lite-live-first-failed");
                }
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] Axon Lite tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsAxonLiteEnabled] ||
                    g_axonlite_live_stop_requested ||
                    tick >= kAxonLiteLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                if (nextTickUS != 0) {
                    intervalUS = settings_live_interval(kAxonLiteLiveIntervalUS,
                                                        kAxonLiteLiveBackgroundIntervalUS);
                    nextTickUS += intervalUS;
                    if (nowUS < nextTickUS) {
                        settings_live_loop_sleep_interruptible(nextTickUS,
                                                               (useconds_t)(nextTickUS - nowUS),
                                                               &g_axonlite_live_stop_requested);
                    } else {
                        nextTickUS = nowUS;
                    }
                } else {
                    settings_live_loop_sleep_interruptible(0,
                                                           settings_live_interval(kAxonLiteLiveIntervalUS,
                                                                                  kAxonLiteLiveBackgroundIntervalUS),
                                                           &g_axonlite_live_stop_requested);
                }

                uint64_t elapsedUS = tickStartUS != 0 && nowUS >= tickStartUS ? nowUS - tickStartUS : 0;
                if (tick == 1) {
                    printf("[SETTINGS] Axon Lite tick=0 elapsed=%lluus\n", elapsedUS);
                }
            }
        } @finally {
            printf("[SETTINGS] Axon Lite live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsAxonLiteEnabled],
                   (unsigned long)failures,
                   g_axonlite_live_stop_requested);
            if (failures > 0)
                cyanide_upload_log_milestone(@"axon-lite-live-exited-failed");
            __sync_lock_release(&g_axonlite_live_running);
        }
    });
}

static void settings_start_typebanner_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsTypeBannerEnabled]) return;

    if (__sync_lock_test_and_set(&g_typebanner_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] TypeBanner live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_typebanner_live_running);
        return;
    }

    g_typebanner_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        BOOL deferredLogged = NO;
        BOOL pausedForMessages = NO;
        RemoteCallSession *mobileSession = nil;

        printf("[SETTINGS] TypeBanner live loop started interval=%uus background=%uus max=%lu\n",
               kTypeBannerLiveIntervalUS,
               kTypeBannerLiveBackgroundIntervalUS,
               (unsigned long)kTypeBannerLiveMaxTicks);

        @try {
            while ([d boolForKey:kSettingsTypeBannerEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_typebanner_live_stop_requested &&
                   tick < kTypeBannerLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kTypeBannerLiveIntervalUS,
                                                               kTypeBannerLiveBackgroundIntervalUS);
                uint64_t tickStartUS = settings_now_us();
                bool ok = false;

                if (!g_kexploit_done || g_settings_actions_running) {
                    if (!deferredLogged) {
                        printf("[SETTINGS] TypeBanner tick deferred krw=%d actions=%d\n",
                               g_kexploit_done, g_settings_actions_running);
                        deferredLogged = YES;
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_typebanner_live_stop_requested);
                    continue;
                }
                deferredLogged = NO;

                if (!settings_typebanner_can_poll_messages()) {
                    if (!pausedForMessages) {
                        pausedForMessages = YES;
                        printf("[SETTINGS] TypeBanner paused while %s\n",
                               settings_typebanner_pause_reason());
                    }
                    if (mobileSession) {
                        @synchronized (settings_rc_lock()) {
                            [mobileSession abandonRemoteCall];
                            mobileSession = nil;
                        }
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_typebanner_live_stop_requested);
                    continue;
                }
                if (pausedForMessages) {
                    pausedForMessages = NO;
                    printf("[SETTINGS] TypeBanner resumed after screen unlock/wake\n");
                }

                // TypeBanner now uses imagent original-thread probes for
                // detection. The MobileSMS session pointer is kept only for
                // fallback builds where that path is re-enabled.
                @try {
                    @synchronized (settings_rc_lock()) {
                        if (!g_typebanner_live_stop_requested &&
                            !g_settings_actions_running &&
                            g_kexploit_done &&
                            settings_typebanner_can_poll_messages()) {
                            ok = typebanner_run_once_with_mobile_session_and_current_springboard(&mobileSession,
                                                                                                 g_springboard_rc_ready != 0);
                        } else {
                            ok = true;
                        }
                    }
                } @catch (NSException *e) {
                    printf("[SETTINGS] TypeBanner tick exception: %s\n", e.reason.UTF8String);
                    ok = false;
                }

                if (tick == 0) printf("[SETTINGS] TypeBanner result=%d\n", ok);
                if (ok) {
                    failures = 0;
                } else {
                    failures++;
                    printf("[SETTINGS] TypeBanner tick failed tick=%lu failures=%lu\n",
                           (unsigned long)tick, (unsigned long)failures);
                    if (failures >= settings_live_failure_limit(3)) break;
                }

                tick++;
                if (![d boolForKey:kSettingsTypeBannerEnabled] ||
                    g_typebanner_live_stop_requested ||
                    tick >= kTypeBannerLiveMaxTicks) break;

                uint64_t nowUS = settings_now_us();
                uint64_t elapsedUS = tickStartUS != 0 && nowUS >= tickStartUS ? nowUS - tickStartUS : 0;
                if (elapsedUS < intervalUS) {
                    settings_live_loop_sleep_interruptible(0,
                                                           (useconds_t)(intervalUS - elapsedUS),
                                                           &g_typebanner_live_stop_requested);
                }

                if (tick == 1) {
                    printf("[SETTINGS] TypeBanner tick=0 elapsed=%lluus\n", elapsedUS);
                }
            }
        } @finally {
            if (mobileSession) {
                @synchronized (settings_rc_lock()) {
                    [mobileSession destroyRemoteCall];
                    mobileSession = nil;
                }
            }

            // Best-effort hide the banner before exiting — drops any stale
            // pill that might persist in SpringBoard's window list.
            if (typebanner_has_remote_state() &&
                g_kexploit_done && !g_settings_actions_running && !settings_cleanup_in_progress()) {
                @synchronized (settings_rc_lock()) {
                    RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                                     useMigFilterBypass:NO
                                                                                firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
                    if (springboardSession) {
                        @try {
                            typebanner_release_mobilesms_keepalive_in_springboard_remote_session(springboardSession);
                            typebanner_hide_in_springboard_remote_session(springboardSession);
                        } @catch (NSException *e) {
                            printf("[SETTINGS] TypeBanner final hide exception: %s\n", e.reason.UTF8String);
                        }
                        [springboardSession destroyRemoteCall];
                    }
                }
            } else {
                printf("[SETTINGS] TypeBanner final hide skipped state=%d krw=%d actions=%d cleanup=%d\n",
                       typebanner_has_remote_state(),
                       g_kexploit_done, g_settings_actions_running, settings_cleanup_in_progress());
            }
            typebanner_forget_remote_state();

            printf("[SETTINGS] TypeBanner live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsTypeBannerEnabled],
                   (unsigned long)failures,
                   g_typebanner_live_stop_requested);
            __sync_lock_release(&g_typebanner_live_running);
        }
    });
}

static void settings_start_themer_live_loop(void)
{
    if (!kThemerDynamicRepairEnabled) return;
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;
    if (g_settings_actions_running) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsThemerEnabled] &&
        ![d boolForKey:kSettingsSnowBoardLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_themer_live_running, 1)) {
        static volatile int loggedAlready = 0;
        if (__sync_bool_compare_and_swap(&loggedAlready, 0, 1)) {
            printf("[SETTINGS] Themer dynamic live loop already running\n");
        }
        return;
    }

    if (settings_cleanup_in_progress()) {
        __sync_lock_release(&g_themer_live_running);
        return;
    }

    g_themer_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        NSInteger iosMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        NSUInteger maxTicks = (iosMajor > 0 && iosMajor < 26)
            ? kThemerLegacyLiveMaxTicks
            : kThemerLiveMaxTicks;

        printf("[SETTINGS] Themer dynamic live loop started interval=%uus background=%uus max=%lu iosMajor=%ld\n",
               kThemerLiveIntervalUS,
               kThemerLiveBackgroundIntervalUS,
               (unsigned long)maxTicks,
               (long)iosMajor);

        @try {
            // Start with a sleep so we don't pile a tick on top of the
            // initial Run apply that just completed.
            settings_live_loop_sleep_interruptible(0,
                                                   settings_live_interval(kThemerLiveIntervalUS,
                                                                          kThemerLiveBackgroundIntervalUS),
                                                   &g_themer_live_stop_requested);
            while (([d boolForKey:kSettingsThemerEnabled] ||
                    [d boolForKey:kSettingsSnowBoardLiteEnabled]) &&
                   !settings_cleanup_in_progress() &&
                   !g_themer_live_stop_requested &&
                   tick < maxTicks) {
                useconds_t intervalUS = settings_live_interval(kThemerLiveIntervalUS,
                                                               kThemerLiveBackgroundIntervalUS);
                bool ok = false;

                @synchronized (settings_rc_lock()) {
                    if (g_themer_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        printf("[SETTINGS] Themer dynamic loop has no SpringBoard RemoteCall session\n");
                        failures++;
                        break;
                    }
                    if (!g_kexploit_done || g_settings_actions_running) {
                        // Wait for actions to finish before next tick.
                        ok = true;
                    } else {
                        ok = themer_repaint_dynamic_cached_views_in_session();
                    }
                }

                if (tick == 0) {
                    printf("[SETTINGS] Themer dynamic live first tick result=%d\n", ok);
                }
                failures = ok ? 0 : failures + 1;

                tick++;
                if ((! [d boolForKey:kSettingsThemerEnabled] &&
                     ! [d boolForKey:kSettingsSnowBoardLiteEnabled]) ||
                    g_themer_live_stop_requested ||
                    tick >= maxTicks) break;

                intervalUS = settings_live_interval(kThemerLiveIntervalUS,
                                                    kThemerLiveBackgroundIntervalUS);
                settings_live_loop_sleep_interruptible(0, intervalUS,
                                                       &g_themer_live_stop_requested);
            }
        } @finally {
            printf("[SETTINGS] Themer dynamic live loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsThemerEnabled] || [d boolForKey:kSettingsSnowBoardLiteEnabled],
                   (unsigned long)failures,
                   g_themer_live_stop_requested);
            __sync_lock_release(&g_themer_live_running);
        }
    });
}

static void settings_start_livewp_live_loop(void)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsLiveWPEnabled]) return;
    if (!g_springboard_rc_ready) return;

    if (__sync_lock_test_and_set(&g_livewp_live_running, 1)) {
        return;
    }

    g_livewp_live_stop_requested = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUInteger tick = 0;
        NSUInteger failures = 0;
        BOOL pausedForSleep = NO;
        printf("[SETTINGS] LiveWP live repair loop started interval=%uus background=%uus max=%lu\n",
               kLiveWPLiveIntervalUS,
               kLiveWPLiveBackgroundIntervalUS,
               (unsigned long)kLiveWPLiveMaxTicks);
        @try {
            settings_live_loop_sleep_interruptible(0,
                                                   settings_live_interval(kLiveWPLiveIntervalUS,
                                                                          kLiveWPLiveBackgroundIntervalUS),
                                                   &g_livewp_live_stop_requested);
            while ([d boolForKey:kSettingsLiveWPEnabled] &&
                   !settings_cleanup_in_progress() &&
                   !g_livewp_live_stop_requested &&
                   tick < kLiveWPLiveMaxTicks) {
                useconds_t intervalUS = settings_live_interval(kLiveWPLiveIntervalUS,
                                                               kLiveWPLiveBackgroundIntervalUS);
                if (!settings_livewp_should_play()) {
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready &&
                            [d boolForKey:kSettingsLiveWPEnabled] &&
                            !settings_cleanup_in_progress() &&
                            !g_livewp_live_stop_requested) {
                            (void)livewp_pause_in_session();
                        }
                    }
                    if (!pausedForSleep) {
                        pausedForSleep = YES;
                        printf("[SETTINGS] LiveWP repair loop paused while screen is asleep\n");
                        log_user("[LIVEWP] Repair loop paused: screen asleep.\n");
                    }
                    settings_live_loop_sleep_interruptible(0,
                                                           intervalUS,
                                                           &g_livewp_live_stop_requested);
                    continue;
                }
                if (pausedForSleep) {
                    pausedForSleep = NO;
                    printf("[SETTINGS] LiveWP repair loop resumed after screen wake\n");
                    log_user("[LIVEWP] Repair loop resumed: screen awake.\n");
                }

                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (g_livewp_live_stop_requested) break;
                    if (!g_springboard_rc_ready) {
                        failures++;
                        break;
                    }
                    if (!settings_livewp_should_play()) {
                        ok = livewp_pause_in_session();
                    } else {
                        ok = livewp_resume_in_session();
                    }
                }

                if (tick == 0) {
                    printf("[SETTINGS] LiveWP live first repair tick result=%d\n", ok);
                }
                failures = ok ? 0 : (failures + 1);
                if (ok) {
                    settings_mark_tweak_applied(kSettingsLiveWPEnabled, YES);
                }

                tick++;
                if (![d boolForKey:kSettingsLiveWPEnabled] ||
                    g_livewp_live_stop_requested ||
                    tick >= kLiveWPLiveMaxTicks) break;

                settings_live_loop_sleep_interruptible(0,
                                                       intervalUS,
                                                       &g_livewp_live_stop_requested);
            }
        } @finally {
            printf("[SETTINGS] LiveWP live repair loop exited ticks=%lu enabled=%d failures=%lu stop=%d\n",
                   (unsigned long)tick,
                   [d boolForKey:kSettingsLiveWPEnabled],
                   (unsigned long)failures,
                   g_livewp_live_stop_requested);
            __sync_lock_release(&g_livewp_live_running);
        }
    });
}

static BOOL settings_livewp_should_play(void)
{
    (void)settings_refresh_screen_awake_state(NULL);
    return settings_screen_awake_cached();
}

static void settings_pause_livewp_for_sleep_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsLiveWPEnabled] || !g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                g_settings_termination_cleanup_started ||
                ![d boolForKey:kSettingsLiveWPEnabled] ||
                !g_springboard_rc_ready) return;
            if (settings_livewp_should_play()) return;
            bool ok = livewp_pause_in_session();
            printf("[SETTINGS] LiveWP paused%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
            log_user("[LIVEWP] Screen sleep pause%s%s result=%d.\n",
                     reason ? ": " : "", reason ?: "", ok ? 1 : 0);
        }
    });
}

static void settings_resume_livewp_after_wake_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsLiveWPEnabled] || !g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        bool ok = false;
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                g_settings_termination_cleanup_started ||
                ![d boolForKey:kSettingsLiveWPEnabled] ||
                !g_springboard_rc_ready) return;
            if (!settings_livewp_should_play()) {
                (void)livewp_pause_in_session();
                return;
            }
            ok = livewp_resume_in_session();
            if (ok) settings_mark_tweak_applied(kSettingsLiveWPEnabled, YES);
            printf("[SETTINGS] LiveWP resumed%s%s result=%d\n",
                   reason ? ": " : "", reason ?: "", ok);
            log_user("[LIVEWP] Screen wake resume%s%s result=%d.\n",
                     reason ? ": " : "", reason ?: "", ok ? 1 : 0);
        }
        if (ok) settings_start_livewp_live_loop();
        settings_notify_package_queue_changed_async();
    });
}

static void settings_schedule_themer_repair_burst_internal(const char *reason, BOOL force)
{
    (void)force;
    if (!kThemerDynamicRepairEnabled) return;
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;
    if (g_settings_actions_running) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsThemerEnabled] &&
        ![d boolForKey:kSettingsSnowBoardLiteEnabled]) return;
    if (!g_springboard_rc_ready) return;

    __sync_add_and_fetch(&g_themer_repair_generation, 1);
    if (__sync_lock_test_and_set(&g_themer_repair_running, 1)) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        uint64_t seenGeneration = g_themer_repair_generation;
        NSUInteger tick = 0;
        NSUInteger quietTicks = 0;

        printf("[SETTINGS] Themer dynamic repair burst started%s%s\n",
               reason ? ": " : "", reason ?: "");

        @try {
            while (([d boolForKey:kSettingsThemerEnabled] ||
                    [d boolForKey:kSettingsSnowBoardLiteEnabled]) &&
                   !settings_cleanup_in_progress() &&
                   !g_themer_live_stop_requested &&
                   tick < 1) {
                settings_live_loop_sleep_interruptible(0,
                                                       tick == 0
                                                           ? kThemerRepairInitialDelayUS
                                                           : kThemerRepairIntervalUS,
                                                       &g_themer_live_stop_requested);
                if (g_themer_live_stop_requested) break;

                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (!g_springboard_rc_ready || !g_kexploit_done ||
                        g_settings_actions_running) {
                        ok = true;
                    } else {
                        ok = themer_repaint_dynamic_cached_views_in_session();
                    }
                }

                tick++;
                uint64_t currentGeneration = g_themer_repair_generation;
                if (currentGeneration != seenGeneration) {
                    seenGeneration = currentGeneration;
                    quietTicks = 0;
                } else {
                    quietTicks++;
                    if (quietTicks >= 2) break;
                }

                if (tick == 1) {
                    printf("[SETTINGS] Themer dynamic repair first repaint=%d\n", ok);
                }
            }
        } @finally {
            printf("[SETTINGS] Themer dynamic repair burst exited ticks=%lu\n",
                   (unsigned long)tick);
            __sync_lock_release(&g_themer_repair_running);
        }
    });
}

static void settings_schedule_themer_repair_burst(const char *reason)
{
    settings_schedule_themer_repair_burst_internal(reason, YES);
}

static void settings_schedule_themer_quiet_repair_burst(const char *reason)
{
    settings_schedule_themer_repair_burst_internal(reason, NO);
}

static void settings_apply_axonlite_once_async(const char *reason)
{
    if (!settings_device_supported()) return;
    if (settings_cleanup_in_progress()) return;
    if (g_axonlite_live_running) {
        if (reason) {
            printf("[SETTINGS] Axon Lite lifecycle apply skipped: live loop owns Axon (%s)\n",
                   reason);
        }
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsAxonLiteEnabled] || !g_springboard_rc_ready) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (settings_cleanup_in_progress()) return;
        bool ok = false;
        if (!settings_axonlite_can_poll_springboard()) {
            printf("[SETTINGS] Axon Lite lifecycle apply%s%s skipped: %s\n",
                   reason ? ": " : "", reason ?: "",
                   settings_axonlite_pause_reason());
            settings_start_axonlite_live_loop();
            return;
        }
        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() ||
                ![d boolForKey:kSettingsAxonLiteEnabled] ||
                !g_springboard_rc_ready) return;
            if (!settings_axonlite_can_poll_springboard()) {
                printf("[SETTINGS] Axon Lite lifecycle apply%s%s skipped inside lock: %s\n",
                       reason ? ": " : "", reason ?: "",
                       settings_axonlite_pause_reason());
                settings_start_axonlite_live_loop();
                return;
            }
            ok = axonlite_apply_in_session();
        }
        printf("[SETTINGS] Axon Lite lifecycle apply%s%s result=%d\n",
               reason ? ": " : "", reason ?: "", ok);
        settings_start_axonlite_live_loop();
    });
}

void settings_application_did_enter_background(void)
{
    if (__sync_lock_test_and_set(&g_app_in_background, 1)) return;
    if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d boolForKey:kSettingsKeepAlive]) {
        settings_request_all_live_loops_stop("entered background without keepAlive");
        settings_end_statbar_background_task_async("entered background without keepAlive");
        printf("[SETTINGS] app entered background without keepAlive; live loops stop requested\n");
        return;
    }

    if ([d boolForKey:kSettingsLiveWPEnabled] && g_springboard_rc_ready) {
        settings_pause_livewp_for_sleep_async("entered background");
    }
    BOOL anyLiveLoopNeeded =
        ([d boolForKey:kSettingsAxonLiteEnabled]    && g_springboard_rc_ready) ||
        (settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsStatBarEnabled]     && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsNiceBarLiteEnabled] && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsGravityLiteEnabled] && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsThemerEnabled]      && g_springboard_rc_ready) ||
        ([d boolForKey:kSettingsSnowBoardLiteEnabled] && g_springboard_rc_ready) ||
        [d boolForKey:kSettingsTypeBannerEnabled];
    if (anyLiveLoopNeeded) {
        if ([d boolForKey:kSettingsKeepAlive]) {
            ds_keepalive_apply_enabled(YES);
        }
        settings_begin_statbar_background_task_async("entered background");
        printf("[SETTINGS] background live-loop support keepAlive=%d bgTask=%lu\n",
               ds_keepalive_is_running(),
               (unsigned long)g_statbar_bg_task);
    }

    if ([d boolForKey:kSettingsAxonLiteEnabled] && g_springboard_rc_ready) {
        settings_apply_axonlite_once_async("entered background");
    }
    if ([d boolForKey:kSettingsGravityLiteEnabled] && g_springboard_rc_ready &&
        g_gravitylite_background_armed != 0) {
        settings_apply_armed_gravitylite_once_async("entered background");
    }
    if (settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) {
        settings_apply_rssi_once_async("entered background");
    }
    if (![d boolForKey:kSettingsStatBarEnabled] && ![d boolForKey:kSettingsNSBarEnabled] &&
        ![d boolForKey:kSettingsNiceBarLiteEnabled]) {
        return;
    }
    if (!g_springboard_rc_ready) return;

    printf("[SETTINGS] app entered background with app-side status bar loops\n");
    settings_apply_statbar_once_async("entered background");
    settings_apply_nsbar_once_async("entered background");
    settings_apply_nicebarlite_once_async("entered background");
}

void settings_application_will_enter_foreground(void)
{
    if (!settings_app_state_is_foreground()) return;
    g_app_in_background = 0;
    settings_end_statbar_background_task_async("foreground");
    if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;
    settings_apply_statbar_once_async("will enter foreground");
    settings_apply_nsbar_once_async("will enter foreground");
    settings_apply_nicebarlite_once_async("will enter foreground");
    settings_apply_rssi_once_async("will enter foreground");
    settings_apply_axonlite_once_async("will enter foreground");
    settings_restart_gravity_motion_if_active("will enter foreground");
    settings_resume_livewp_after_wake_async("will enter foreground");
    settings_start_themer_live_loop();
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSettingsTypeBannerEnabled]) {
        settings_start_typebanner_live_loop();
    }
}

void settings_application_did_become_active(void)
{
    if (!settings_app_state_is_foreground()) return;
    g_app_in_background = 0;
    if (settings_cleanup_in_progress() || g_settings_termination_cleanup_started) return;
    settings_apply_statbar_once_async("became active");
    settings_apply_nsbar_once_async("became active");
    settings_apply_nicebarlite_once_async("became active");
    settings_apply_rssi_once_async("became active");
    settings_apply_axonlite_once_async("became active");
    settings_restart_gravity_motion_if_active("became active");
    settings_resume_livewp_after_wake_async("became active");
    settings_start_themer_live_loop();
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kSettingsTypeBannerEnabled]) {
        settings_start_typebanner_live_loop();
    }
}

static BOOL settings_key_is_sbc(NSString *key)
{
    return [key isEqualToString:kSettingsSBCEnabled] ||
           [key isEqualToString:kSettingsSBCDockIcons] ||
           [key isEqualToString:kSettingsSBCCols] ||
           [key isEqualToString:kSettingsSBCRows] ||
           [key isEqualToString:kSettingsSBCHideLabels];
}

static BOOL settings_key_is_statbar(NSString *key)
{
    return [key isEqualToString:kSettingsStatBarEnabled] ||
           [key isEqualToString:kSettingsStatBarCelsius] ||
           [key isEqualToString:kSettingsStatBarShowTemp] ||
           [key isEqualToString:kSettingsStatBarShowCPU] ||
           [key isEqualToString:kSettingsStatBarShowRAM] ||
           [key isEqualToString:kSettingsStatBarShowNet] ||
           [key isEqualToString:kSettingsStatBarShowLabels] ||
           [key isEqualToString:kSettingsStatBarRefreshRateSec];
}

static BOOL settings_key_is_nsbar(NSString *key)
{
    return [key isEqualToString:kSettingsNSBarEnabled] ||
           [key isEqualToString:kSettingsNSBarPosition];
}

static BOOL settings_key_is_nicebarlite(NSString *key)
{
    if ([key isEqualToString:kSettingsNiceBarLiteEnabled] ||
        [key isEqualToString:kSettingsNiceBarLiteCelsius] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutSideInset] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutTopSideInset] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutBottomSideInset] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutTopY] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutBottomY] ||
        [key isEqualToString:kSettingsNiceBarLiteLayoutCenterX]) return YES;
    for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
        if ([key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, i)] ||
            [key isEqualToString:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, i)]) {
            return YES;
        }
    }
    return NO;
}

static BOOL settings_key_is_rssi(NSString *key)
{
    return [key isEqualToString:kSettingsRSSIDisplayEnabled] ||
           [key isEqualToString:kSettingsRSSIDisplayWifi] ||
           [key isEqualToString:kSettingsRSSIDisplayCell];
}

static BOOL settings_key_is_axonlite(NSString *key)
{
    return [key isEqualToString:kSettingsAxonLiteEnabled];
}

static BOOL settings_key_is_typebanner(NSString *key)
{
    return [key isEqualToString:kSettingsTypeBannerEnabled];
}

static BOOL settings_key_is_appswitchergrid(NSString *key)
{
    return [key isEqualToString:kSettingsAppSwitcherGridEnabled];
}

static BOOL settings_key_is_gravitylite(NSString *key)
{
    return [key isEqualToString:kSettingsGravityLiteEnabled] ||
           [key isEqualToString:kSettingsGravityLiteDockEnabled] ||
           [key isEqualToString:kSettingsGravityLiteMagnitudePct] ||
           [key isEqualToString:kSettingsGravityLiteBouncePct] ||
           [key isEqualToString:kSettingsGravityLiteFrictionPct] ||
           [key isEqualToString:kSettingsGravityLiteResistancePct] ||
           [key isEqualToString:kSettingsGravityLiteAngularResistancePct];
}

static BOOL settings_key_is_dark_tweak(NSString *key)
{
    return [key isEqualToString:kSettingsDSDisableAppLibrary] ||
           [key isEqualToString:kSettingsDSDisableIconFlyIn] ||
           [key isEqualToString:kSettingsDSZeroWakeAnimation] ||
           [key isEqualToString:kSettingsDSZeroBacklightFade] ||
           [key isEqualToString:kSettingsDSDoubleTapToLock] ||
           [key isEqualToString:kSettingsDSDragCoefficientEnabled] ||
           [key isEqualToString:kSettingsDSDragCoefficientValue];
}

static BOOL settings_key_affects_package_state(NSString *key)
{
    return [key isEqualToString:kSettingsSBCEnabled] ||
           [key isEqualToString:kSettingsPowercuffEnabled] ||
           [key isEqualToString:kSettingsStatBarEnabled] ||
           [key isEqualToString:kSettingsNSBarEnabled] ||
           [key isEqualToString:kSettingsNiceBarLiteEnabled] ||
           [key isEqualToString:kSettingsRSSIDisplayEnabled] ||
           [key isEqualToString:kSettingsAxonLiteEnabled] ||
           [key isEqualToString:kSettingsTypeBannerEnabled] ||
           [key isEqualToString:kSettingsAppSwitcherGridEnabled] ||
           [key isEqualToString:kSettingsThemerEnabled] ||
           [key isEqualToString:kSettingsSnowBoardLiteEnabled] ||
           [key isEqualToString:kSettingsLiveWPEnabled] ||
           settings_key_is_gravitylite(key) ||
           settings_key_is_dark_tweak(key);
}

static void settings_schedule_live_apply_for_key(NSString *key)
{
    if (settings_cleanup_in_progress()) {
        printf("[SETTINGS] live apply skipped during cleanup for %s\n", key.UTF8String);
        return;
    }

    if (!settings_device_supported()) {
        printf("[SETTINGS] live apply blocked for %s: %s\n",
               key.UTF8String, settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    if (settings_key_is_typebanner(key)) {
        // TypeBanner owns its own daemon + SpringBoard sessions, but its
        // bootstrap is serialized with the shared RemoteCall lock.
        if ([d boolForKey:kSettingsTypeBannerEnabled]) {
            settings_mark_tweak_applied(kSettingsTypeBannerEnabled, YES);
            settings_notify_package_queue_changed_async();
            settings_start_typebanner_live_loop();
        } else {
            g_typebanner_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsTypeBannerEnabled, NO);
            settings_notify_package_queue_changed_async();
            // Best-effort hide if a session is reachable. The live loop will
            // also hide on its own way out, but doing it here gets the pill
            // off the screen faster after the user toggles off.
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (g_kexploit_done) {
                    @synchronized (settings_rc_lock()) {
                        RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                                         useMigFilterBypass:NO
                                                                                    firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
                        if (springboardSession) {
                            @try {
                                typebanner_release_mobilesms_keepalive_in_springboard_remote_session(springboardSession);
                                typebanner_hide_in_springboard_remote_session(springboardSession);
                            } @catch (NSException *e) {
                                printf("[SETTINGS] TypeBanner toggle-off hide exception: %s\n",
                                       e.reason.UTF8String);
                            }
                            [springboardSession destroyRemoteCall];
                        }
                    }
                }
                typebanner_forget_remote_state();
            });
        }
        return;
    }

    if (settings_key_is_appswitchergrid(key)) {
        if ([d boolForKey:kSettingsAppSwitcherGridEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = appswitchergrid_apply_in_session();
                    settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled,
                                                ok && [d boolForKey:kSettingsAppSwitcherGridEnabled]);
                    printf("[SETTINGS] live App Switcher Grid apply result=%d\n", ok);
                }
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsAppSwitcherGridEnabled]) {
            settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) appswitchergrid_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_axonlite(key)) {
        if ([d boolForKey:kSettingsAxonLiteEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (!settings_axonlite_can_poll_springboard()) {
                    printf("[SETTINGS] live Axon Lite apply skipped: %s\n",
                           settings_axonlite_pause_reason());
                    settings_start_axonlite_live_loop();
                    settings_notify_package_queue_changed_async();
                    return;
                }
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    if (!settings_axonlite_can_poll_springboard()) {
                        printf("[SETTINGS] live Axon Lite apply skipped inside lock: %s\n",
                               settings_axonlite_pause_reason());
                        settings_start_axonlite_live_loop();
                        settings_notify_package_queue_changed_async();
                        return;
                    }
                    bool ok = axonlite_apply_in_session();
                    settings_mark_tweak_applied(kSettingsAxonLiteEnabled,
                                                ok && [d boolForKey:kSettingsAxonLiteEnabled]);
                    printf("[SETTINGS] live Axon Lite apply result=%d\n", ok);
                }
                settings_start_axonlite_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsAxonLiteEnabled]) {
            g_axonlite_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsAxonLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) axonlite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_statbar(key)) {
        if ([d boolForKey:kSettingsStatBarEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                       [d boolForKey:kSettingsStatBarShowTemp],
                                                       [d boolForKey:kSettingsStatBarShowCPU],
                                                       [d boolForKey:kSettingsStatBarShowRAM],
                                                       [d boolForKey:kSettingsStatBarShowNet],
                                                       [d boolForKey:kSettingsStatBarShowLabels]);
                    settings_mark_tweak_applied(kSettingsStatBarEnabled,
                                                ok && [d boolForKey:kSettingsStatBarEnabled]);
                    printf("[SETTINGS] live StatBar apply result=%d\n", ok);
                }
                settings_start_statbar_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsStatBarEnabled]) {
            g_statbar_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsStatBarEnabled, NO);
            settings_notify_package_queue_changed_async();
            settings_end_statbar_background_task_async("StatBar disabled");
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) statbar_stop_in_session();
                    }
                });
            }
        }
    }

    if (settings_key_is_nsbar(key)) {
        if (g_settings_termination_cleanup_started) {
            printf("[SETTINGS] live NSBar apply skipped during termination for %s\n", key.UTF8String);
            return;
        }
        if ([d boolForKey:kSettingsNSBarEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        g_settings_termination_cleanup_started ||
                        !g_springboard_rc_ready) return;
                    NSBarPosition position = (NSBarPosition)[d integerForKey:kSettingsNSBarPosition];
                    bool ok = nsbar_apply_in_session(position);
                    settings_mark_tweak_applied(kSettingsNSBarEnabled,
                                                ok && [d boolForKey:kSettingsNSBarEnabled]);
                    printf("[SETTINGS] live NSBar apply result=%d\n", ok);
                }
                settings_start_nsbar_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsNSBarEnabled]) {
            g_nsbar_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsNSBarEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) nsbar_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_rssi(key)) {
        if (!settings_rssi_install_allowed()) {
            if ([d boolForKey:kSettingsRSSIDisplayEnabled]) {
                [d setBool:NO forKey:kSettingsRSSIDisplayEnabled];
                [d synchronize];
            }
            g_rssi_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) rssidisplay_stop_in_session();
                    }
                });
            }
            return;
        }
        if ([d boolForKey:kSettingsRSSIDisplayEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                           [d boolForKey:kSettingsRSSIDisplayCell]);
                    settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled,
                                                ok && [d boolForKey:kSettingsRSSIDisplayEnabled]);
                    printf("[SETTINGS] live RSSI apply result=%d\n", ok);
                }
                settings_start_rssi_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsRSSIDisplayEnabled]) {
            g_rssi_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) rssidisplay_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_nicebarlite(key)) {
        if (g_settings_termination_cleanup_started) {
            printf("[SETTINGS] live NiceBar Lite apply skipped during termination for %s\n", key.UTF8String);
            return;
        }
        BOOL forceWeatherRefresh = [key isEqualToString:kSettingsNiceBarLiteCelsius];
        if (forceWeatherRefresh || [key hasPrefix:kSettingsNiceBarLiteSlotKindPrefix]) {
            settings_nicebar_refresh_weather_if_needed(forceWeatherRefresh, nil);
        }
        if ([d boolForKey:kSettingsNiceBarLiteEnabled] && g_springboard_rc_ready) {
            uint32_t updateMask = settings_nicebar_update_mask_for_key(key);
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                uint64_t beginUS = settings_now_us();
                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() ||
                        g_settings_termination_cleanup_started ||
                        !g_springboard_rc_ready) return;
                    uint64_t applyStartUS = settings_now_us();
                    ok = (updateMask == 0)
                        ? settings_apply_nicebarlite_from_defaults_locked(d)
                        : settings_apply_nicebarlite_mask_from_defaults_locked(d, updateMask);
                    uint64_t endUS = settings_now_us();
                    settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled,
                                                ok && [d boolForKey:kSettingsNiceBarLiteEnabled]);
                    printf("[SETTINGS] live NiceBar Lite apply result=%d mask=0x%x\n", ok, updateMask);
                    log_user("[NICEBAR] Config apply result=%d mask=0x%x apply=%llums total=%llums\n",
                             ok ? 1 : 0,
                             updateMask,
                             (unsigned long long)((endUS >= applyStartUS) ? ((endUS - applyStartUS) / 1000ULL) : 0ULL),
                             (unsigned long long)((endUS >= beginUS) ? ((endUS - beginUS) / 1000ULL) : 0ULL));
                }
                settings_start_nicebarlite_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsNiceBarLiteEnabled]) {
            g_nicebarlite_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) nicebarlite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (settings_key_is_dark_tweak(key)) {
        BOOL isDragValue = [key isEqualToString:kSettingsDSDragCoefficientValue];
        if (!g_springboard_rc_ready) return;
        if (isDragValue) {
            if (![d boolForKey:kSettingsDSDragCoefficientEnabled]) return;
        } else if (![d boolForKey:key]) {
            return;
        }
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @synchronized (settings_rc_lock()) {
                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                bool ok = settings_apply_dark_tweaks_from_defaults_locked(d);
                for (NSString *darkKey in @[
                    kSettingsDSDisableAppLibrary,
                    kSettingsDSDisableIconFlyIn,
                    kSettingsDSZeroWakeAnimation,
                    kSettingsDSZeroBacklightFade,
                    kSettingsDSDoubleTapToLock,
                    kSettingsDSDragCoefficientEnabled,
                ]) {
                    if ([d boolForKey:darkKey]) settings_mark_tweak_applied(darkKey, ok);
                }
                printf("[SETTINGS] live DarkSword tweaks apply result=%d\n", ok);
            }
            settings_notify_package_queue_changed_async();
        });
        return;
    }

    if (settings_key_is_gravitylite(key)) {
        if ([d boolForKey:kSettingsGravityLiteEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                bool ok = false;
                GravityLiteConfig config = {0};
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    ok = settings_app_state_is_foreground()
                        ? settings_arm_gravitylite_for_background_start_locked(d, "live settings")
                        : settings_apply_gravitylite_from_defaults_locked(d);
                    config = settings_gravitylite_config_from_defaults(d);
                    settings_mark_tweak_applied(kSettingsGravityLiteEnabled,
                                                ok && [d boolForKey:kSettingsGravityLiteEnabled]);
                    printf("[SETTINGS] live Gravity Lite apply result=%d\n", ok);
                }
                if (ok && !settings_app_state_is_foreground()) {
                    settings_start_gravity_motion(config.magnitude);
                }
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsGravityLiteEnabled]) {
            __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
            settings_stop_gravity_motion();
            settings_mark_tweak_applied(kSettingsGravityLiteEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) gravitylite_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if ([key isEqualToString:kSettingsLiveWPEnabled]) {
        if ([d boolForKey:kSettingsLiveWPEnabled] && g_springboard_rc_ready) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                bool ok = false;
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    ok = livewp_apply_in_session();
                    settings_mark_tweak_applied(kSettingsLiveWPEnabled, ok);
                    printf("[SETTINGS] live LiveWP apply result=%d\n", ok);
                }
                if (ok) settings_start_livewp_live_loop();
                settings_notify_package_queue_changed_async();
            });
        } else if (![d boolForKey:kSettingsLiveWPEnabled]) {
            g_livewp_live_stop_requested = 1;
            settings_mark_tweak_applied(kSettingsLiveWPEnabled, NO);
            settings_notify_package_queue_changed_async();
            if (g_springboard_rc_ready) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) livewp_stop_in_session();
                    }
                });
            }
        }
        return;
    }

    if (!settings_key_is_sbc(key) || !g_springboard_rc_ready) return;

    uint64_t generation = __sync_add_and_fetch(&g_sbc_live_apply_generation, 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
                   dispatch_get_global_queue(0, 0), ^{
        if (generation != g_sbc_live_apply_generation) return;
        if (settings_cleanup_in_progress()) return;

        @synchronized (settings_rc_lock()) {
            if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
            bool ok = settings_apply_sbc_from_defaults_locked(d);
            settings_mark_tweak_applied(kSettingsSBCEnabled,
                                        ok && [d boolForKey:kSettingsSBCEnabled]);
            printf("[SETTINGS] live SBC apply result=%d\n", ok);
        }
        settings_notify_package_queue_changed_async();
    });
}

void settings_register_defaults(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        kSettingsAutoRunKexploit:    @NO,
        kSettingsRunSandboxEscape:   @YES,
        kSettingsRunPatchSandboxExt: @NO,
        kSettingsKeepAlive:          @YES,

        kSettingsSBCEnabled:    @NO,
        kSettingsSBCDockIcons:  @(kSBCDefaultDockIcons),
        kSettingsSBCCols:       @(kSBCDefaultCols),
        kSettingsSBCRows:       @(kSBCDefaultRows),
        kSettingsSBCHideLabels: @(kSBCDefaultHideLabels),

        kSettingsPowercuffEnabled: @NO,
        kSettingsPowercuffLevel:   @"nominal",

        kSettingsDSDisableAppLibrary: @NO,
        kSettingsDSDisableIconFlyIn:  @NO,
        kSettingsDSZeroWakeAnimation: @NO,
        kSettingsDSZeroBacklightFade: @NO,
        kSettingsDSDoubleTapToLock:   @NO,
        kSettingsDSDragCoefficientEnabled: @NO,
        kSettingsDSDragCoefficientValue:   @50,

        kSettingsLayoutExtrasEnabled:       @NO,
        kSettingsLayoutHomeExtraLeft:       @0,
        kSettingsLayoutHomeExtraRight:      @0,
        kSettingsLayoutHomeExtraTop:        @0,
        kSettingsLayoutHomeExtraBottom:     @0,
        kSettingsLayoutDockExtraHorizontal: @0,
        kSettingsLayoutHomeScalePct:        @100,
        kSettingsLayoutDockScalePct:        @100,

        kSettingsStatBarEnabled: @NO,
        kSettingsStatBarCelsius: @NO,
        kSettingsStatBarShowTemp:   @YES,
        kSettingsStatBarShowCPU:    @YES,
        kSettingsStatBarShowRAM:    @YES,
        kSettingsStatBarShowNet:    @NO,
        kSettingsStatBarShowLabels: @YES,
        kSettingsStatBarRefreshRateSec: @(kStatBarDefaultRefreshRateSec),

        kSettingsNSBarEnabled: @NO,
        kSettingsNSBarPosition: @0,  // 0=TopLeft, 1=BottomLeft, 2=TopRight, 3=BottomRight
        kSettingsNiceBarLiteEnabled: @NO,
        kSettingsNiceBarLiteCelsius: @YES,
        kSettingsNiceBarLiteLayoutSideInset: @0,
        kSettingsNiceBarLiteLayoutTopSideInset: @0,
        kSettingsNiceBarLiteLayoutBottomSideInset: @0,
        kSettingsNiceBarLiteLayoutTopY: @0,
        kSettingsNiceBarLiteLayoutBottomY: @0,
        kSettingsNiceBarLiteLayoutCenterX: @0,
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotTopLeft): @(NiceBarLiteContentTimeFormat),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotTopRight): @(NiceBarLiteContentSystem),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotBottomLeft): @(NiceBarLiteContentSystem),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotBottomCenter): @(NiceBarLiteContentOff),
        settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, NiceBarLiteSlotBottomRight): @(NiceBarLiteContentOff),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotTopLeft): @(NiceBarLiteSystemDate),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotTopRight): @(NiceBarLiteSystemBatteryPercent),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotBottomLeft): @(NiceBarLiteSystemNetworkSpeed),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotBottomCenter): @(NiceBarLiteSystemFreeRAM),
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, NiceBarLiteSlotBottomRight): @(NiceBarLiteSystemFreeRAM),
        settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, NiceBarLiteSlotTopLeft): @"",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, NiceBarLiteSlotTopRight): @"",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, NiceBarLiteSlotBottomLeft): @"",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, NiceBarLiteSlotBottomCenter): @"",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, NiceBarLiteSlotBottomRight): @"",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, NiceBarLiteSlotTopLeft): @"HH:mm",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, NiceBarLiteSlotTopRight): @"HH:mm",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, NiceBarLiteSlotBottomLeft): @"HH:mm",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, NiceBarLiteSlotBottomCenter): @"HH:mm",
        settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, NiceBarLiteSlotBottomRight): @"HH:mm",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, NiceBarLiteSlotTopLeft): @"--",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, NiceBarLiteSlotTopRight): @"--",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, NiceBarLiteSlotBottomLeft): @"--",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, NiceBarLiteSlotBottomCenter): @"--",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherPrefix, NiceBarLiteSlotBottomRight): @"--",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotTopLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotTopRight): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotBottomLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotBottomCenter): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, NiceBarLiteSlotBottomRight): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotTopLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotTopRight): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotBottomLeft): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotBottomCenter): @"en",
        settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, NiceBarLiteSlotBottomRight): @"en",
        kSettingsNiceBarLiteWeatherCache: @"Weather --",

        kSettingsRSSIDisplayEnabled: @NO,
        kSettingsRSSIDisplayWifi:    @YES,
        kSettingsRSSIDisplayCell:    @YES,

        kSettingsAxonLiteEnabled: @NO,

        kSettingsTypeBannerEnabled: @NO,

        kSettingsAppSwitcherGridEnabled: @NO,

        kSettingsGravityLiteEnabled: @NO,
        kSettingsGravityLiteDockEnabled: @YES,
        kSettingsGravityLiteMagnitudePct: @100,
        kSettingsGravityLiteBouncePct: @50,
        kSettingsGravityLiteFrictionPct: @50,
        kSettingsGravityLiteResistancePct: @50,
        kSettingsGravityLiteAngularResistancePct: @0,

        kSettingsThemerEnabled: @NO,
        kSettingsThemerThemeID: kThemerThemeNone,
        kSettingsThemerCustomThemePath: @"",
        kSettingsThemerCustomThemeName: @"",

        kSettingsSnowBoardLiteEnabled: @NO,
        kSettingsSnowBoardLiteSelectedThemeID: @"",

        kSettingsLiveWPEnabled: @NO,
        kSettingsLiveWPVideoPath: @"",

        kSettingsExperimentalTweaksEnabled: @NO,

        kSettingsNanoMaxPairing:       @(kNanoDefaultMaxPairing),
        kSettingsNanoMinPairing:       @(kNanoDefaultMinPairing),
        kSettingsNanoMinPairingChipID: @(kNanoDefaultMinPairingChipID),
        kSettingsNanoMinQuickSwitch:   @(kNanoDefaultMinQuickSwitch),
    }];
    // Experimental tweaks must not survive after the master gate is disabled.
    if (![defaults boolForKey:kSettingsExperimentalTweaksEnabled]) {
        BOOL changed = NO;
        for (NSString *key in @[ kSettingsRSSIDisplayEnabled,
                                 kSettingsTypeBannerEnabled,
                                 kSettingsAppSwitcherGridEnabled ]) {
            if ([defaults boolForKey:key]) {
                [defaults setBool:NO forKey:key];
                changed = YES;
            }
        }
        if (changed) [defaults synchronize];
    }
    if ([defaults boolForKey:kSettingsThemerEnabled] &&
        !settings_themer_has_selected_theme()) {
        [defaults setBool:NO forKey:kSettingsThemerEnabled];
        [defaults synchronize];
    }
    if ([defaults boolForKey:kSettingsSnowBoardLiteEnabled] &&
        !settings_snowboardlite_has_selected_theme()) {
        [defaults setBool:NO forKey:kSettingsSnowBoardLiteEnabled];
        [defaults synchronize];
    }
    settings_install_screen_awake_observers();
}

static void settings_run_actions_internal(BOOL pendingOnly)
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] run blocked: %s\n", settings_unsupported_message().UTF8String);
        log_user("[RUN] %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
            __sync_lock_test_and_set(&g_settings_actions_rerun_requested, 1);
            printf("[SETTINGS] actions already running; queued one follow-up run\n");
            log_user("[RUN] Already running. Queued one follow-up run for the latest package state.\n");
            return;
        }
        if (!pendingOnly &&
            (g_statbar_live_running || g_nsbar_live_running || g_nicebarlite_live_running ||
             g_rssi_live_running || g_axonlite_live_running || g_typebanner_live_running)) {
            settings_request_all_live_loops_stop("Apply Tweaks");
            settings_wait_live_loops_stopped_for_switch("Apply Tweaks");
        }
        log_session_begin();
        cyanide_start_session_uploads();
        BOOL runSucceeded = NO;
        NSString *runCompletionMessage = @"Run failed. Check the log for details.";
        @try {
            BOOL patchSandboxExt = [d boolForKey:kSettingsRunPatchSandboxExt];
            BOOL runPowercuff = settings_enabled_tweak_should_run(d, kSettingsPowercuffEnabled, pendingOnly);
            BOOL forceSpringBoardRefresh = pendingOnly &&
                                           runPowercuff &&
                                           settings_has_persistent_springboard_remote_call_user();
            BOOL springBoardPendingOnly = pendingOnly && !forceSpringBoardRefresh;
            BOOL statBarEnabled = [d boolForKey:kSettingsStatBarEnabled];
            BOOL nsBarEnabled = [d boolForKey:kSettingsNSBarEnabled];
            BOOL niceBarLiteEnabled = [d boolForKey:kSettingsNiceBarLiteEnabled];
            BOOL rssiEnabled = settings_rssi_install_allowed() && [d boolForKey:kSettingsRSSIDisplayEnabled];
            BOOL axonLiteEnabled = [d boolForKey:kSettingsAxonLiteEnabled];
            BOOL typeBannerEnabled = [d boolForKey:kSettingsTypeBannerEnabled];
            BOOL appSwitcherGridEnabled = [d boolForKey:kSettingsAppSwitcherGridEnabled];
            BOOL gravityLiteEnabled = [d boolForKey:kSettingsGravityLiteEnabled];
            BOOL liveWPEnabled = [d boolForKey:kSettingsLiveWPEnabled];
            BOOL runSBC = settings_enabled_tweak_should_run(d, kSettingsSBCEnabled, springBoardPendingOnly);
            BOOL runDarkTweaks = settings_dark_tweaks_should_run(d, springBoardPendingOnly);
            BOOL runStatBar = settings_enabled_tweak_should_run(d, kSettingsStatBarEnabled, springBoardPendingOnly);
            BOOL runNSBar = settings_enabled_tweak_should_run(d, kSettingsNSBarEnabled, springBoardPendingOnly);
            BOOL runNiceBarLite = settings_enabled_tweak_should_run(d, kSettingsNiceBarLiteEnabled, springBoardPendingOnly);
            BOOL runRSSI = settings_rssi_install_allowed() && settings_enabled_tweak_should_run(d, kSettingsRSSIDisplayEnabled, springBoardPendingOnly);
            BOOL runAxonLite = settings_enabled_tweak_should_run(d, kSettingsAxonLiteEnabled, springBoardPendingOnly);
            BOOL runTypeBanner = settings_enabled_tweak_should_run(d, kSettingsTypeBannerEnabled, springBoardPendingOnly);
            BOOL runAppSwitcherGrid = settings_enabled_tweak_should_run(d, kSettingsAppSwitcherGridEnabled, springBoardPendingOnly);
            BOOL runGravityLite = settings_enabled_tweak_should_run(d, kSettingsGravityLiteEnabled, springBoardPendingOnly);
            BOOL runThemer = settings_enabled_tweak_should_run(d, kSettingsThemerEnabled, springBoardPendingOnly);
            BOOL runSnowBoardLite = settings_enabled_tweak_should_run(d, kSettingsSnowBoardLiteEnabled, springBoardPendingOnly);
            BOOL runLayoutExtras = settings_enabled_tweak_should_run(d, kSettingsLayoutExtrasEnabled, springBoardPendingOnly);
            BOOL runLiveWP = settings_enabled_tweak_should_run(d, kSettingsLiveWPEnabled, springBoardPendingOnly);
            BOOL needsSpringBoardWork = runSBC || runDarkTweaks || runStatBar || runNSBar || runNiceBarLite || runRSSI || runAxonLite || runLayoutExtras || runTypeBanner || runAppSwitcherGrid || runGravityLite || runThemer || runSnowBoardLite || runLiveWP;
            BOOL runSandboxEscape = [d boolForKey:kSettingsRunSandboxEscape] && (!pendingOnly || needsSpringBoardWork);
            // TypeBanner prewarms its hidden SpringBoard window during Apply
            // and reuses the open SpringBoard session for text-only updates.
            BOOL needsSpringBoard = runSandboxEscape || needsSpringBoardWork;

            BOOL hasRunWork = patchSandboxExt || runPowercuff || needsSpringBoard;
            NSUInteger total = hasRunWork ? 1 : 0;
            if (patchSandboxExt) total++;
            if (runPowercuff) total++;
            if (needsSpringBoard) total++;
            if (runSandboxEscape) total++;
            if (runSBC) total++;
            if (runDarkTweaks) total++;
            if (runLayoutExtras) total++;
            if (runThemer) total++;
            if (runSnowBoardLite) total++;
            if (runStatBar) total++;
            if (runNSBar) total++;
            if (runNiceBarLite) total++;
            if (runRSSI) total++;
            if (runAxonLite) total++;
            if (runTypeBanner) total++;
            if (runAppSwitcherGrid) total++;
            if (runGravityLite) total++;
            if (runLiveWP) total++;
            NSUInteger step = 0;

            settings_log_run_context();
            log_user("[RUN] Verbose trace active; raw debug stream is mirrored into the app log.\n");
            log_user("[PLAN] stages=%lu springboard=%s sbc=%s dark=%s statbar=%s nicebar=%s rssi=%s axon=%s switcherGrid=%s gravity=%s power=%s livewp=%s\n",
                     (unsigned long)total,
                     needsSpringBoard ? "yes" : "no",
                     runSBC ? "yes" : "no",
                     runDarkTweaks ? "yes" : "no",
                     runStatBar ? "yes" : "no",
                     runNiceBarLite ? "yes" : "no",
                     runRSSI ? "yes" : "no",
                     runAxonLite ? "yes" : "no",
                     runAppSwitcherGrid ? "yes" : "no",
                     runGravityLite ? "yes" : "no",
                     runPowercuff ? "yes" : "no",
                     runLiveWP ? "yes" : "no");
            if (forceSpringBoardRefresh) {
                log_user("[PLAN] Powercuff will refresh active SpringBoard live tweaks after process switch.\n");
            }
            if (runSBC) {
                log_user("[PLAN] Home layout target: dock=%ld home=%ldx%ld labels=%s\n",
                         (long)[d integerForKey:kSettingsSBCDockIcons],
                         (long)[d integerForKey:kSettingsSBCCols],
                         (long)[d integerForKey:kSettingsSBCRows],
                         [d boolForKey:kSettingsSBCHideLabels] ? "hidden" : "shown");
            }
            if (runLayoutExtras) {
                log_user("[PLAN] Layout extras: home=+L%ld/R%ld/T%ld/B%ld dock=+H%ld scale=home%ld%%/dock%ld%%\n",
                         (long)[d integerForKey:kSettingsLayoutHomeExtraLeft],
                         (long)[d integerForKey:kSettingsLayoutHomeExtraRight],
                         (long)[d integerForKey:kSettingsLayoutHomeExtraTop],
                         (long)[d integerForKey:kSettingsLayoutHomeExtraBottom],
                         (long)[d integerForKey:kSettingsLayoutDockExtraHorizontal],
                         (long)[d integerForKey:kSettingsLayoutHomeScalePct],
                         (long)[d integerForKey:kSettingsLayoutDockScalePct]);
            }
            if (runStatBar) {
                log_user("[PLAN] StatBar target: temp=%s cpu=%s ram=%s network=%s refresh=1s\n",
                         [d boolForKey:kSettingsStatBarShowTemp] ? ([d boolForKey:kSettingsStatBarCelsius] ? "C" : "F") : "hidden",
                         [d boolForKey:kSettingsStatBarShowCPU] ? "shown" : "hidden",
                         [d boolForKey:kSettingsStatBarShowRAM] ? "shown" : "hidden",
                         [d boolForKey:kSettingsStatBarShowNet] ? "shown" : "hidden");
            }
            if (runNiceBarLite) {
                log_user("[PLAN] NiceBar Lite target: status-bar slots refresh=0.5s foreground / 1.0s background\n");
            }
            if (runRSSI) {
                log_user("[PLAN] RSSI display target: wifi=%s cell=%s refresh=1s\n",
                         [d boolForKey:kSettingsRSSIDisplayWifi] ? "on" : "off",
                         [d boolForKey:kSettingsRSSIDisplayCell] ? "on" : "off");
            }
            if (runAxonLite) {
                log_user("[PLAN] Axon Lite target: segmented notification hub refresh=15s\n");
            }
            if (runGravityLite) {
                log_user("[PLAN] Gravity Lite target: strength=%ld%% dock=%s\n",
                         (long)[d integerForKey:kSettingsGravityLiteMagnitudePct],
                         [d boolForKey:kSettingsGravityLiteDockEnabled] ? "included" : "home-only");
            }
            if (runPowercuff) {
                NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
                log_user("[PLAN] Powercuff target: thermalmonitord level=%s\n", lvl.UTF8String);
            }
            cyanide_upload_log_milestone(@"run-plan");

            if (!hasRunWork) {
                if (!statBarEnabled) g_statbar_live_stop_requested = 1;
                if (!nsBarEnabled) g_nsbar_live_stop_requested = 1;
                if (!niceBarLiteEnabled) g_nicebarlite_live_stop_requested = 1;
                if (!rssiEnabled) g_rssi_live_stop_requested = 1;
                if (!axonLiteEnabled) g_axonlite_live_stop_requested = 1;
                if (!typeBannerEnabled) g_typebanner_live_stop_requested = 1;
                if (!appSwitcherGridEnabled && g_springboard_rc_ready) {
                    @synchronized (settings_rc_lock()) {
                        if (g_springboard_rc_ready) appswitchergrid_stop_in_session();
                    }
                }
                if (!gravityLiteEnabled) {
                    __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
                    settings_stop_gravity_motion();
                }
                if (!liveWPEnabled) g_livewp_live_stop_requested = 1;
                log_user("[DONE] No pending runtime changes to apply.\n");
                runSucceeded = YES;
                runCompletionMessage = @"Done. No pending runtime changes to apply.";
                cyanide_upload_log_milestone(@"run-noop");
                return;
            }

            settings_progress(&step, total, "Preparing KRW primitives (socket/IOSurface path)");
            if (!settings_ensure_kexploit()) {
                log_user("[RUN] Failed: kernel primitives were not acquired.\n");
                runCompletionMessage = @"Failed: kernel primitives were not acquired.";
                cyanide_upload_log_milestone(@"krw-failed");
                return;
            }
            log_user("[OK] Kernel primitives ready; RemoteCall can be staged.\n");
            cyanide_upload_log_milestone(@"krw-ready");

            if (patchSandboxExt) {
                settings_progress(&step, total, "Patching sandbox-extension issue path");
                escape_sbx_demo3();
                log_user("[OK] Sandbox-extension patch stage finished.\n");
                cyanide_upload_log_milestone(@"sandbox-ext-patched");
            }
            printf("[SETTINGS] actions escape=%d patch=%d sbc=%d dock=%ld hs=%ldx%ld hideLabels=%d dark=%d power=%d level=%s statbar=%d showTemp=%d celsius=%d showCPU=%d showRAM=%d showNet=%d rssi=%d rssiWifi=%d rssiCell=%d axon=%d appSwitcherGrid=%d rcReady=%d\n",
                   runSandboxEscape,
                   patchSandboxExt,
                   runSBC,
                   (long)[d integerForKey:kSettingsSBCDockIcons],
                   (long)[d integerForKey:kSettingsSBCCols],
                   (long)[d integerForKey:kSettingsSBCRows],
                   [d boolForKey:kSettingsSBCHideLabels],
                   runDarkTweaks,
                   runPowercuff,
                   ([d stringForKey:kSettingsPowercuffLevel] ?: @"").UTF8String,
                   runStatBar,
                   [d boolForKey:kSettingsStatBarShowTemp],
                   [d boolForKey:kSettingsStatBarCelsius],
                   [d boolForKey:kSettingsStatBarShowCPU],
                   [d boolForKey:kSettingsStatBarShowRAM],
                   [d boolForKey:kSettingsStatBarShowNet],
                   runRSSI,
                   [d boolForKey:kSettingsRSSIDisplayWifi],
                   [d boolForKey:kSettingsRSSIDisplayCell],
                   runAxonLite,
                   runAppSwitcherGrid,
                   g_springboard_rc_ready);

            if (runPowercuff) {
                settings_progress(&step, total, "Applying Powercuff via thermalmonitord");
                if (g_springboard_rc_ready ||
                    g_statbar_live_running ||
                    g_nsbar_live_running ||
                    g_nicebarlite_live_running ||
                    g_rssi_live_running ||
                    g_axonlite_live_running) {
                    settings_request_all_live_loops_stop("Powercuff process switch");
                    settings_wait_live_loops_stopped_for_switch("Powercuff process switch");
                }
                @synchronized (settings_rc_lock()) {
                    // This is only a transient RemoteCall target switch. Do
                    // not run SpringBoard tweak stop paths or clear applied
                    // package state; enabled tweaks are reapplied below.
                    settings_destroy_springboard_remote_call_locked_internal("switching to thermalmonitord", NO);
                    NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
                    bool ok = powercuff_apply(lvl.UTF8String);
                    settings_mark_tweak_applied(kSettingsPowercuffEnabled,
                                                ok && [d boolForKey:kSettingsPowercuffEnabled]);
                    log_user("%s Powercuff %s through thermalmonitord.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "applied" : "did not apply cleanly");
                    cyanide_upload_log_milestone(ok ? @"powercuff-applied" : @"powercuff-failed");
                }
            }

            if (needsSpringBoard) {
                @synchronized (settings_rc_lock()) {
                    settings_progress(&step, total, "Opening SpringBoard RemoteCall session");
                    if (!settings_ensure_springboard_remote_call_locked()) {
                        log_user("[RUN] Failed: could not open the SpringBoard control session.\n");
                        runCompletionMessage = @"Failed: could not open the SpringBoard control session.";
                        cyanide_upload_log_milestone(@"springboard-remote-call-failed");
                        return;
                    }
                    log_user("[OK] SpringBoard RemoteCall ready.\n");
                    cyanide_upload_log_milestone(@"springboard-remote-call-ready");

                    if (runSandboxEscape && !g_springboard_sandbox_escaped) {
                        settings_progress(&step, total, "Consuming SpringBoard sandbox extension");
                        int sbx = escape_sbx_demo2_in_session();
                        g_springboard_sandbox_escaped = (sbx == 0);
                        printf("[SETTINGS] sandbox escape in session result=%d\n", sbx);
                        log_user("%s SpringBoard filesystem token %s.\n",
                                 sbx == 0 ? "[OK]" : "[WARN]",
                                 sbx == 0 ? "consumed" : "returned a warning");
                        cyanide_upload_log_milestone(sbx == 0 ? @"springboard-sandbox-token-ready" : @"springboard-sandbox-token-warning");
                    } else if (runSandboxEscape) {
                        printf("[SETTINGS] sandbox escape already consumed for this SpringBoard session\n");
                        settings_progress(&step, total, "Reusing SpringBoard sandbox token");
                        log_user("[OK] SpringBoard filesystem token already consumed.\n");
                        cyanide_upload_log_milestone(@"springboard-sandbox-token-reused");
                    }

                    if (runTypeBanner) {
                        bool ok = typebanner_prepare_in_springboard_session();
                        printf("[SETTINGS] TypeBanner SpringBoard prewarm result=%d\n", ok);
                        log_user("%s TypeBanner overlay window %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "prewarmed" : "did not prewarm");
                        cyanide_upload_log_milestone(ok ? @"typebanner-overlay-prewarmed" : @"typebanner-overlay-prewarm-failed");
                    }

                    if (runSBC) {
                        settings_progress(&step, total, "Applying icon layout caches");
                        bool ok = settings_apply_sbc_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsSBCEnabled,
                                                    ok && [d boolForKey:kSettingsSBCEnabled]);
                        printf("[SETTINGS] SBC result=%d\n", ok);
                        log_user("%s Home screen layout %s; dock=%ld home=%ldx%ld.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "may need a refresh",
                                 (long)[d integerForKey:kSettingsSBCDockIcons],
                                 (long)[d integerForKey:kSettingsSBCCols],
                                 (long)[d integerForKey:kSettingsSBCRows]);
                        cyanide_upload_log_milestone(ok ? @"sbc-applied" : @"sbc-warning");
                    }

                    if (runDarkTweaks) {
                        settings_progress(&step, total, "Applying DarkSword runtime hooks");
                        bool ok = settings_apply_dark_tweaks_from_defaults_locked(d);
                        for (NSString *key in @[
                            kSettingsDSDisableAppLibrary,
                            kSettingsDSDisableIconFlyIn,
                            kSettingsDSZeroWakeAnimation,
                            kSettingsDSZeroBacklightFade,
                            kSettingsDSDoubleTapToLock,
                            kSettingsDSDragCoefficientEnabled,
                        ]) {
                            if ([d boolForKey:key]) settings_mark_tweak_applied(key, ok);
                        }
                        printf("[SETTINGS] DarkSword tweaks result=%d\n", ok);
                        log_user("%s DarkSword hooks %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "may need a refresh");
                        cyanide_upload_log_milestone(ok ? @"darksword-tweaks-applied" : @"darksword-tweaks-warning");
                    }

                    if ([d boolForKey:kSettingsLayoutExtrasEnabled]) {
                        settings_progress(&step, total, "Applying Home Layout Extras");
                        bool ok = settings_apply_layout_extras_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsLayoutExtrasEnabled, ok);
                        printf("[SETTINGS] Layout extras result=%d\n", ok);
                        log_user("%s Home Layout Extras %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"layout-extras-applied" : @"layout-extras-warning");
                    }

                    if (runThemer) {
                        settings_progress(&step, total, "Applying Cyanide Themer");
                        bool ok = settings_apply_themer_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsThemerEnabled, ok);
                        printf("[SETTINGS] Themer result=%d\n", ok);
                        log_user("%s Cyanide Themer %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"themer-applied" : @"themer-warning");
                        if (ok) {
                            settings_start_themer_live_loop();
                        }
                    }

                    if (runSnowBoardLite) {
                        settings_progress(&step, total, "Applying SnowBoard Lite");
                        bool ok = settings_apply_snowboardlite_from_defaults_locked(d);
                        settings_mark_tweak_applied(kSettingsSnowBoardLiteEnabled, ok);
                        printf("[SETTINGS] SnowBoard Lite result=%d\n", ok);
                        log_user("%s SnowBoard Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "applied" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"snowboardlite-applied" : @"snowboardlite-warning");
                        if (ok) {
                            settings_start_themer_live_loop();
                        }
                    }

                    if (runGravityLite) {
                        settings_progress(&step, total, "Starting Gravity Lite icon physics");
                        log_user("[GRAVITY] Preparing icon physics state...\n");
                        __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
                        settings_stop_gravity_motion();
                        gravitylite_stop_in_session();
                        GravityLiteConfig config = settings_gravitylite_config_from_defaults(d);
                        bool ok = gravitylite_apply_in_session(config);
                        settings_mark_tweak_applied(kSettingsGravityLiteEnabled,
                                                    ok && [d boolForKey:kSettingsGravityLiteEnabled]);
                        if (ok) {
                            settings_start_gravity_motion(config.magnitude);
                        }
                        printf("[SETTINGS] Gravity Lite result=%d\n", ok);
                        log_user("%s Gravity Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "active" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"gravity-lite-applied" : @"gravity-lite-warning");
                        if (!ok) {
                            runCompletionMessage = @"Gravity Lite did not start cleanly.";
                        }
                    } else if (!gravityLiteEnabled) {
                        __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
                        settings_stop_gravity_motion();
                        gravitylite_stop_in_session();
                    }

                    if (runStatBar) {
                        settings_progress(&step, total, "Starting StatBar overlay and live feed");
                        bool ok = statbar_apply_in_session([d boolForKey:kSettingsStatBarCelsius],
                                                           [d boolForKey:kSettingsStatBarShowTemp],
                                                           [d boolForKey:kSettingsStatBarShowCPU],
                                                           [d boolForKey:kSettingsStatBarShowRAM],
                                                           [d boolForKey:kSettingsStatBarShowNet],
                                                           [d boolForKey:kSettingsStatBarShowLabels]);
                        settings_mark_tweak_applied(kSettingsStatBarEnabled,
                                                    ok && [d boolForKey:kSettingsStatBarEnabled]);
                        printf("[SETTINGS] StatBar result=%d\n", ok);
                        log_user("%s StatBar %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "showing thermal + memory overlay" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"statbar-initial-applied" : @"statbar-initial-failed");
                    }

                    if (runNSBar) {
                        settings_progress(&step, total, "Starting NSBar network speed overlay and live feed");
                        NSBarPosition position = (NSBarPosition)[d integerForKey:kSettingsNSBarPosition];
                        bool ok = nsbar_apply_in_session(position);
                        settings_mark_tweak_applied(kSettingsNSBarEnabled,
                                                    ok && [d boolForKey:kSettingsNSBarEnabled]);
                        printf("[SETTINGS] NSBar result=%d\n", ok);
                        log_user("%s NSBar %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "receiving live data" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"nsbar-initial-applied" : @"nsbar-initial-failed");
                    }

                    if (runNiceBarLite) {
                        settings_progress(&step, total, "Starting NiceBar Lite corner labels");
                        uint64_t beginUS = settings_now_us();
                        log_user("[NICEBAR] Run: initial apply requested.\n");
                        settings_log_nicebar_config(d, "run config");
                        settings_nicebar_refresh_weather_if_needed(NO, nil);
                        uint64_t applyStartUS = settings_now_us();
                        bool ok = settings_apply_nicebarlite_from_defaults_locked(d);
                        uint64_t endUS = settings_now_us();
                        settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled,
                                                    ok && [d boolForKey:kSettingsNiceBarLiteEnabled]);
                        printf("[SETTINGS] NiceBar Lite result=%d\n", ok);
                        log_user("%s NiceBar Lite %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "receiving live data" : "did not start cleanly");
                        log_user("[NICEBAR] Run: initial apply result=%d apply=%llums total=%llums\n",
                                 ok ? 1 : 0,
                                 (unsigned long long)((endUS >= applyStartUS) ? ((endUS - applyStartUS) / 1000ULL) : 0ULL),
                                 (unsigned long long)((endUS >= beginUS) ? ((endUS - beginUS) / 1000ULL) : 0ULL));
                        cyanide_upload_log_milestone(ok ? @"nicebarlite-initial-applied" : @"nicebarlite-initial-failed");
                    }

                    if (runRSSI) {
                        settings_progress(&step, total, "Starting RSSI dBm signal overlays");
                        bool ok = rssidisplay_apply_in_session([d boolForKey:kSettingsRSSIDisplayWifi],
                                                               [d boolForKey:kSettingsRSSIDisplayCell]);
                        settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled,
                                                    ok && [d boolForKey:kSettingsRSSIDisplayEnabled]);
                        printf("[SETTINGS] RSSI result=%d\n", ok);
                        log_user("%s RSSI signal overlays %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "live" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"rssi-initial-applied" : @"rssi-initial-failed");
                    }

                    if (runAppSwitcherGrid) {
                        settings_progress(&step, total, "Enabling App Switcher Grid");
                        bool ok = appswitchergrid_apply_in_session();
                        settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled,
                                                    ok && [d boolForKey:kSettingsAppSwitcherGridEnabled]);
                        printf("[SETTINGS] App Switcher Grid result=%d\n", ok);
                        log_user("%s App Switcher Grid %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "enabled for this SpringBoard session" : "did not apply cleanly");
                        cyanide_upload_log_milestone(ok ? @"app-switcher-grid-applied" : @"app-switcher-grid-failed");
                    } else if (!appSwitcherGridEnabled) {
                        appswitchergrid_stop_in_session();
                    }

                    if (runAxonLite) {
                        settings_progress(&step, total, "Starting Axon Lite notification hub");
                        bool ok = false;
                        bool deferred = false;
                        if (settings_axonlite_can_poll_springboard()) {
                            ok = axonlite_apply_in_session();
                            deferred = !ok && !axonlite_initial_cache_ready();
                        } else {
                            deferred = true;
                            printf("[SETTINGS] Axon Lite initial apply skipped: %s\n",
                                   settings_axonlite_pause_reason());
                        }
                        settings_mark_tweak_applied(kSettingsAxonLiteEnabled,
                                                    (ok || deferred) && [d boolForKey:kSettingsAxonLiteEnabled]);
                        printf("[SETTINGS] Axon Lite result=%d deferred=%d\n", ok, deferred);
                        log_user("%s Axon Lite %s.\n",
                                 (ok || deferred) ? "[OK]" : "[WARN]",
                                 ok ? "overlay is live" :
                                 (deferred ? "will start when notifications are visible" : "did not start cleanly"));
                        cyanide_upload_log_milestone(ok ? @"axon-lite-initial-applied" :
                                                     (deferred ? @"axon-lite-initial-deferred" : @"axon-lite-initial-failed"));
                    }

                    if (runLiveWP) {
                        settings_progress(&step, total, "Starting LiveWP dynamic wallpaper");
                        bool ok = livewp_apply_in_session();
                        settings_mark_tweak_applied(kSettingsLiveWPEnabled,
                                                    ok && [d boolForKey:kSettingsLiveWPEnabled]);
                        printf("[SETTINGS] LiveWP result=%d\n", ok);
                        log_user("%s LiveWP dynamic wallpaper %s.\n",
                                 ok ? "[OK]" : "[WARN]",
                                 ok ? "is playing" : "did not start cleanly");
                        cyanide_upload_log_milestone(ok ? @"livewp-applied" : @"livewp-failed");
                    }
                }

                if (runStatBar) {
                    settings_start_statbar_live_loop();
                } else {
                    g_statbar_live_stop_requested = 1;
                }
                if (runNSBar) {
                    settings_start_nsbar_live_loop();
                } else {
                    g_nsbar_live_stop_requested = 1;
                }
                if (runNiceBarLite) {
                    settings_start_nicebarlite_live_loop();
                } else {
                    g_nicebarlite_live_stop_requested = 1;
                }
                if (runRSSI) {
                    settings_start_rssi_live_loop();
                } else {
                    g_rssi_live_stop_requested = 1;
                }
                if (runAxonLite) {
                    settings_start_axonlite_live_loop();
                } else {
                    g_axonlite_live_stop_requested = 1;
                }
                if (runLiveWP) {
                    settings_start_livewp_live_loop();
                } else {
                    g_livewp_live_stop_requested = 1;
                }
            }

            if (runTypeBanner) {
                settings_progress(&step, total, "Starting TypeBanner daemon poll");
                settings_mark_tweak_applied(kSettingsTypeBannerEnabled, YES);
                log_user("[OK] TypeBanner polling imagent every ~1s.\n");
                cyanide_upload_log_milestone(@"typebanner-live-starting");
                // Daemon-only detection avoids foregrounding Messages and
                // avoids the MobileSMS synthetic-thread PAC/0x401 crash path.
                printf("[TYPEBANNER] daemon-only: starting live loop without sms launch\n");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)kTypeBannerInitialDaemonSettleUS * NSEC_PER_USEC),
                               dispatch_get_global_queue(0, 0), ^{
                    settings_start_typebanner_live_loop();
                });
            } else {
                g_typebanner_live_stop_requested = 1;
            }
            if (runStatBar || runNiceBarLite || runRSSI || runAxonLite || runTypeBanner || runGravityLite || runLiveWP)
                cyanide_upload_log_milestone(@"live-tweaks-started");

            if (!settings_has_persistent_springboard_remote_call_user()) {
                BOOL closedNonLiveRemoteCall = NO;
                @synchronized (settings_rc_lock()) {
                    if (!settings_has_persistent_springboard_remote_call_user() &&
                        g_springboard_rc_ready) {
                        settings_destroy_springboard_remote_call_locked("non-live run complete");
                        closedNonLiveRemoteCall = YES;
                    }
                }
                if (closedNonLiveRemoteCall) {
                    log_user("[OK] SpringBoard RemoteCall closed; no live tweak needs it.\n");
                    cyanide_upload_log_milestone(@"springboard-remote-call-closed");
                }
            }

            log_user("[DONE] Run complete. Verbose trace captured the raw call stream.\n");
            runSucceeded = YES;
            runCompletionMessage = @"Done. All tweaks applied in-session.";
            cyanide_upload_log_milestone(@"run-complete");
        } @finally {
            // Close any legacy uploader state before the final snapshot.
            cyanide_stop_session_uploads();
            log_session_end();
            __sync_lock_release(&g_settings_actions_running);
            settings_reconcile_applied_from_defaults();
            if (__sync_bool_compare_and_swap(&g_settings_actions_rerun_requested, 1, 0)) {
                log_user("[RUN] Applying queued follow-up run.\n");
                settings_run_actions_internal(pendingOnly);
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary *completionInfo = @{
                    kSettingsActionsDidCompleteSuccessKey: @(runSucceeded),
                    kSettingsActionsDidCompleteMessageKey: runCompletionMessage ?: @""
                };
                [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                                    object:[PackageQueue sharedQueue]];
                [[NSNotificationCenter defaultCenter] postNotificationName:kSettingsActionsDidCompleteNotification
                                                                    object:nil
                                                                  userInfo:completionInfo];
                cyanide_upload_log_if_enabled();
            });
        }
    });
}

void settings_run_actions(void)
{
    settings_run_actions_internal(NO);
}

void settings_run_pending_actions(void)
{
    settings_run_actions_internal(YES);
}

typedef NS_ENUM(NSInteger, SettingsSection) {
    SectionWarning = 0,
    SectionLaunch,
    SectionActions,
    SectionOTA,
    SectionSBC,
    SectionStatBar,
    SectionNSBar,
    SectionNiceBarLite,
    SectionRSSI,
    SectionAxonLite,
    SectionTypeBanner,
    SectionPowercuff,
    SectionDarkSwordTweaks,
    SectionLayoutExtras,
    SectionNanoRegistry,
    SectionThemer,
    SectionSnowBoardLite,
    SectionLiveWP,
    SectionGravityLite,
    SectionDragCoefficient,
    SectionAppSwitcherGrid,
    SectionCount,
};

typedef NS_ENUM(NSInteger, RootSection) {
    RootSectionChangelog = 0,
    RootSectionActions,
    RootSectionTweakBundles,
    RootSectionSystemBundles,
    RootSectionAppIcon,
    RootSectionDocs,
    RootSectionAbout,
    RootSectionExperimental,
    RootSectionWarning,
    RootSectionCount,
};

// Loads Cyanide/Changelog.plist (generated at build time by
// scripts/gen-changelog.sh from the last N release tags). Each entry is a
// dict with keys "version" (NSString), "date" (ISO yyyy-MM-dd NSString), and
// "changes" (NSArray<NSString *>). Empty array when the plist is missing or
// malformed — the "What's New" section silently hides itself in that case.
static NSArray<NSDictionary *> *settings_changelog_entries(void)
{
    static NSArray<NSDictionary *> *entries = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Changelog" ofType:@"plist"];
        NSArray *raw = path ? [NSArray arrayWithContentsOfFile:path] : nil;
        NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
        for (id obj in raw) {
            if (![obj isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *d = (NSDictionary *)obj;
            NSString *version = d[@"version"];
            NSArray *changes = d[@"changes"];
            if (![version isKindOfClass:[NSString class]] || version.length == 0) continue;
            if (![changes isKindOfClass:[NSArray class]] || changes.count == 0) continue;
            [out addObject:d];
        }
        entries = [out copy];
    });
    return entries;
}

// "2026-05-15" -> "May 15". Falls back to the raw string on parse failure.
static NSString *settings_pretty_date_for_iso(NSString *iso)
{
    if (!iso.length) return @"";
    static NSDateFormatter *in = nil;
    static NSDateFormatter *out = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        in  = [[NSDateFormatter alloc] init];
        in.dateFormat = @"yyyy-MM-dd";
        in.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        out = [[NSDateFormatter alloc] init];
        out.dateFormat = @"MMM d";
        out.locale = [NSLocale currentLocale];
    });
    NSDate *date = [in dateFromString:iso];
    return date ? [out stringFromDate:date] : iso;
}

static BOOL livewp_url_has_video_extension(NSURL *url)
{
    NSString *ext = url.pathExtension.lowercaseString ?: @"";
    return [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
}

static BOOL livewp_response_is_video_download(NSURLResponse *response)
{
    if (!response) return NO;
    if (livewp_url_has_video_extension(response.URL)) return YES;

    NSString *mime = response.MIMEType.lowercaseString ?: @"";
    if ([mime hasPrefix:@"video/"]) return YES;

    if (![response isKindOfClass:NSHTTPURLResponse.class]) return NO;
    NSDictionary *headers = ((NSHTTPURLResponse *)response).allHeaderFields;
    NSString *disposition = @"";
    for (id key in headers) {
        if ([[key description].lowercaseString isEqualToString:@"content-disposition"]) {
            disposition = [headers[key] description].lowercaseString;
            break;
        }
    }
    if (![disposition containsString:@"attachment"]) return NO;
    return [disposition containsString:@".mp4"] ||
           [disposition containsString:@".mov"] ||
           [disposition containsString:@".m4v"] ||
           [mime isEqualToString:@"application/octet-stream"];
}

@interface CyanideCenteredLoadingViewController : UIViewController
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, copy) NSString *iconSymbolName;
@property (nonatomic, strong) UIColor *accentColor;
@end

@implementation CyanideCenteredLoadingViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.14];

    UIView *shadow = [[UIView alloc] init];
    shadow.translatesAutoresizingMaskIntoConstraints = NO;
    shadow.backgroundColor = UIColor.clearColor;
    shadow.layer.shadowColor = UIColor.blackColor.CGColor;
    shadow.layer.shadowOpacity = 0.20;
    shadow.layer.shadowRadius = 28.0;
    shadow.layer.shadowOffset = CGSizeMake(0, 14.0);
    [self.view addSubview:shadow];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 26.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    [shadow addSubview:card];

    UIView *content = card.contentView;
    UIColor *accent = self.accentColor ?: UIColor.systemBlueColor;

    UIView *iconPlate = [[UIView alloc] init];
    iconPlate.translatesAutoresizingMaskIntoConstraints = NO;
    iconPlate.backgroundColor = [accent colorWithAlphaComponent:0.13];
    iconPlate.layer.cornerRadius = 22.0;
    iconPlate.layer.cornerCurve = kCACornerCurveContinuous;
    [content addSubview:iconPlate];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.iconSymbolName.length ? self.iconSymbolName : @"archivebox.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = accent;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [iconPlate addSubview:icon];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [content addSubview:spinner];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = self.titleText.length ? self.titleText : @"Working";
    title.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    title.textColor = UIColor.labelColor;
    [content addSubview:title];

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.text = self.statusText.length ? self.statusText : @"Please wait...";
    status.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    status.textColor = UIColor.secondaryLabelColor;
    status.numberOfLines = 2;
    [content addSubview:status];

    [NSLayoutConstraint activateConstraints:@[
        [shadow.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [shadow.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [shadow.widthAnchor constraintLessThanOrEqualToConstant:332.0],
        [shadow.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.84],

        [card.leadingAnchor constraintEqualToAnchor:shadow.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:shadow.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:shadow.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:shadow.bottomAnchor],

        [iconPlate.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22.0],
        [iconPlate.topAnchor constraintEqualToAnchor:content.topAnchor constant:22.0],
        [iconPlate.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-22.0],
        [iconPlate.widthAnchor constraintEqualToConstant:44.0],
        [iconPlate.heightAnchor constraintEqualToConstant:44.0],

        [icon.centerXAnchor constraintEqualToAnchor:iconPlate.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconPlate.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:25.0],
        [icon.heightAnchor constraintEqualToConstant:25.0],

        [spinner.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [spinner.centerYAnchor constraintEqualToAnchor:iconPlate.centerYAnchor],

        [title.leadingAnchor constraintEqualToAnchor:iconPlate.trailingAnchor constant:14.0],
        [title.trailingAnchor constraintEqualToAnchor:spinner.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:iconPlate.topAnchor constant:1.0],

        [status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0],
    ]];
}

@end

@interface CyanideLiveWPDownloadProgressViewController : UIViewController
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UIView *progressTrackView;
@property (nonatomic, strong) UIView *progressFillView;
@property (nonatomic, strong) NSLayoutConstraint *progressFillWidthConstraint;
@property (nonatomic, strong) UIActivityIndicatorView *activityView;
@property (nonatomic, strong) UIView *cardShadowView;
@property (nonatomic, strong) UIVisualEffectView *cardView;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *savingStatusText;
@property (nonatomic, copy) NSString *iconSymbolName;
@property (nonatomic, strong) UIColor *accentColor;
@property (nonatomic, copy) void (^cancelHandler)(void);
- (void)updateWithReceivedBytes:(int64_t)received expectedBytes:(int64_t)expected host:(NSString *)host;
@end

@implementation CyanideLiveWPDownloadProgressViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.14];

    self.cardShadowView = [[UIView alloc] init];
    self.cardShadowView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardShadowView.backgroundColor = UIColor.clearColor;
    self.cardShadowView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.cardShadowView.layer.shadowOpacity = 0.20;
    self.cardShadowView.layer.shadowRadius = 28.0;
    self.cardShadowView.layer.shadowOffset = CGSizeMake(0, 14.0);
    [self.view addSubview:self.cardShadowView];

    self.cardView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.layer.cornerRadius = 26.0;
    self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardView.clipsToBounds = YES;
    [self.cardShadowView addSubview:self.cardView];

    UIView *content = self.cardView.contentView;

    UIColor *accent = self.accentColor ?: UIColor.systemBlueColor;
    NSString *iconName = self.iconSymbolName.length ? self.iconSymbolName : @"arrow.down.circle.fill";

    UIView *iconPlate = [[UIView alloc] init];
    iconPlate.translatesAutoresizingMaskIntoConstraints = NO;
    iconPlate.backgroundColor = [accent colorWithAlphaComponent:0.13];
    iconPlate.layer.cornerRadius = 22.0;
    iconPlate.layer.cornerCurve = kCACornerCurveContinuous;
    [content addSubview:iconPlate];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = accent;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [iconPlate addSubview:icon];

    self.activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityView.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityView.hidesWhenStopped = YES;
    [self.activityView startAnimating];
    [content addSubview:self.activityView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = self.titleText.length ? self.titleText : @"Downloading Video";
    titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = UIColor.labelColor;
    [content addSubview:titleLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Starting...";
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 2;
    [content addSubview:self.statusLabel];

    self.progressTrackView = [[UIView alloc] init];
    self.progressTrackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressTrackView.backgroundColor = UIColor.quaternarySystemFillColor;
    self.progressTrackView.layer.cornerRadius = 3.0;
    self.progressTrackView.layer.cornerCurve = kCACornerCurveContinuous;
    self.progressTrackView.clipsToBounds = YES;
    self.progressTrackView.hidden = YES;
    [content addSubview:self.progressTrackView];

    self.progressFillView = [[UIView alloc] init];
    self.progressFillView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFillView.backgroundColor = accent;
    self.progressFillView.layer.cornerRadius = 3.0;
    self.progressFillView.layer.cornerCurve = kCACornerCurveContinuous;
    self.progressFillView.hidden = YES;
    [self.progressTrackView addSubview:self.progressFillView];

    self.progressLabel = [[UILabel alloc] init];
    self.progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressLabel.text = @"";
    self.progressLabel.textColor = UIColor.secondaryLabelColor;
    self.progressLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.progressLabel.textAlignment = NSTextAlignmentLeft;
    self.progressLabel.hidden = YES;
    [content addSubview:self.progressLabel];

    self.percentLabel = [[UILabel alloc] init];
    self.percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.percentLabel.text = @"";
    self.percentLabel.textColor = UIColor.secondaryLabelColor;
    self.percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    self.percentLabel.textAlignment = NSTextAlignmentRight;
    self.percentLabel.hidden = YES;
    [content addSubview:self.percentLabel];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.title = @"Cancel";
    config.baseForegroundColor = UIColor.systemRedColor;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.contentInsets = NSDirectionalEdgeInsetsMake(10.0, 14.0, 10.0, 14.0);
    cancel.configuration = config;
    cancel.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:cancel];

    self.progressFillWidthConstraint = [self.progressFillView.widthAnchor constraintEqualToConstant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardShadowView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.cardShadowView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.cardShadowView.widthAnchor constraintLessThanOrEqualToConstant:332.0],
        [self.cardShadowView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.84],

        [self.cardView.leadingAnchor constraintEqualToAnchor:self.cardShadowView.leadingAnchor],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.cardShadowView.trailingAnchor],
        [self.cardView.topAnchor constraintEqualToAnchor:self.cardShadowView.topAnchor],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.cardShadowView.bottomAnchor],

        [iconPlate.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22.0],
        [iconPlate.topAnchor constraintEqualToAnchor:content.topAnchor constant:22.0],
        [iconPlate.widthAnchor constraintEqualToConstant:44.0],
        [iconPlate.heightAnchor constraintEqualToConstant:44.0],

        [icon.centerXAnchor constraintEqualToAnchor:iconPlate.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconPlate.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:25.0],
        [icon.heightAnchor constraintEqualToConstant:25.0],

        [self.activityView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [self.activityView.centerYAnchor constraintEqualToAnchor:iconPlate.centerYAnchor],

        [titleLabel.leadingAnchor constraintEqualToAnchor:iconPlate.trailingAnchor constant:14.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:self.activityView.leadingAnchor constant:-12.0],
        [titleLabel.topAnchor constraintEqualToAnchor:iconPlate.topAnchor constant:1.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [self.statusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],

        [self.progressTrackView.topAnchor constraintEqualToAnchor:iconPlate.bottomAnchor constant:22.0],
        [self.progressTrackView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22.0],
        [self.progressTrackView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [self.progressTrackView.heightAnchor constraintEqualToConstant:6.0],

        [self.progressFillView.leadingAnchor constraintEqualToAnchor:self.progressTrackView.leadingAnchor],
        [self.progressFillView.topAnchor constraintEqualToAnchor:self.progressTrackView.topAnchor],
        [self.progressFillView.bottomAnchor constraintEqualToAnchor:self.progressTrackView.bottomAnchor],
        self.progressFillWidthConstraint,

        [self.progressLabel.topAnchor constraintEqualToAnchor:self.progressTrackView.bottomAnchor constant:10.0],
        [self.progressLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22.0],
        [self.progressLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.percentLabel.leadingAnchor constant:-12.0],

        [self.percentLabel.firstBaselineAnchor constraintEqualToAnchor:self.progressLabel.firstBaselineAnchor],
        [self.percentLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [self.percentLabel.widthAnchor constraintGreaterThanOrEqualToConstant:48.0],

        [cancel.topAnchor constraintEqualToAnchor:self.progressLabel.bottomAnchor constant:16.0],
        [cancel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:22.0],
        [cancel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-22.0],
        [cancel.heightAnchor constraintEqualToConstant:42.0],
        [cancel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18.0],
    ]];
}

- (void)cancelTapped
{
    if (self.cancelHandler) self.cancelHandler();
}

- (void)updateWithReceivedBytes:(int64_t)received expectedBytes:(int64_t)expected host:(NSString *)host
{
    if (expected > 0) {
        [self.activityView stopAnimating];
        self.progressTrackView.hidden = NO;
        self.progressFillView.hidden = NO;
        self.progressLabel.hidden = NO;
        self.percentLabel.hidden = NO;
        float progress = (float)MIN(1.0, MAX(0.0, (double)received / (double)expected));
        self.statusLabel.text = self.savingStatusText.length
            ? self.savingStatusText
            : @"Saving to LiveWP Downloads";
        self.progressLabel.text = [NSString stringWithFormat:@"%@ of %@",
                                   [NSByteCountFormatter stringFromByteCount:received countStyle:NSByteCountFormatterCountStyleFile],
                                   [NSByteCountFormatter stringFromByteCount:expected countStyle:NSByteCountFormatterCountStyleFile]];
        self.percentLabel.text = [NSString stringWithFormat:@"%.0f%%", progress * 100.0];
        [self.view layoutIfNeeded];
        CGFloat width = CGRectGetWidth(self.progressTrackView.bounds) * progress;
        self.progressFillWidthConstraint.constant = width;
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            [self.progressTrackView layoutIfNeeded];
        } completion:nil];
    } else if (received <= 0) {
        [self.activityView startAnimating];
        self.progressTrackView.hidden = YES;
        self.progressFillView.hidden = YES;
        self.progressLabel.hidden = YES;
        self.percentLabel.hidden = YES;
        self.statusLabel.text = host.length ? [NSString stringWithFormat:@"Connecting to %@", host] : @"Preparing download";
    } else {
        [self.activityView startAnimating];
        self.progressTrackView.hidden = YES;
        self.progressFillView.hidden = YES;
        self.progressLabel.hidden = NO;
        self.percentLabel.hidden = YES;
        self.statusLabel.text = @"Downloading";
        self.progressLabel.text = [NSString stringWithFormat:@"%@ received",
                                   [NSByteCountFormatter stringFromByteCount:received countStyle:NSByteCountFormatterCountStyleFile]];
    }
}

@end

@interface CyanideLiveWPBrowserViewController : UIViewController <WKNavigationDelegate, WKUIDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *catalogues;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIView *toolbarView;
@property (nonatomic, strong) UIScrollView *tabsScrollView;
@property (nonatomic, strong) UIStackView *tabsStackView;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UIProgressView *loadProgressView;
@property (nonatomic, copy) void (^downloadHandler)(NSURLRequest *request);
@property (nonatomic, copy) void (^closeHandler)(void);
@property (nonatomic, assign) BOOL didNotifyClose;
- (instancetype)initWithCatalogues:(NSArray<NSDictionary<NSString *, NSString *> *> *)catalogues
                      selectedIndex:(NSInteger)selectedIndex;
@end

@implementation CyanideLiveWPBrowserViewController

- (instancetype)initWithCatalogues:(NSArray<NSDictionary<NSString *, NSString *> *> *)catalogues
                      selectedIndex:(NSInteger)selectedIndex
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _catalogues = [catalogues copy];
    _selectedIndex = MAX(0, MIN((NSInteger)catalogues.count - 1, selectedIndex));
    self.title = @"Online Video";
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.toolbarView = [[UIView alloc] init];
    self.toolbarView.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolbarView.backgroundColor = UIColor.systemBackgroundColor;
    [self.view addSubview:self.toolbarView];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.tintColor = UIColor.labelColor;
    closeButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    closeButton.layer.cornerRadius = 18.0;
    closeButton.layer.cornerCurve = kCACornerCurveContinuous;
    [closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:closeButton];

    UIButton *reloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    reloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    reloadButton.tintColor = UIColor.labelColor;
    reloadButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    reloadButton.layer.cornerRadius = 18.0;
    reloadButton.layer.cornerCurve = kCACornerCurveContinuous;
    [reloadButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:UIControlStateNormal];
    [reloadButton addTarget:self action:@selector(reloadTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.toolbarView addSubview:reloadButton];

    self.tabsScrollView = [[UIScrollView alloc] init];
    self.tabsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabsScrollView.showsHorizontalScrollIndicator = NO;
    self.tabsScrollView.alwaysBounceHorizontal = YES;
    self.tabsScrollView.backgroundColor = UIColor.clearColor;
    [self.toolbarView addSubview:self.tabsScrollView];

    self.tabsStackView = [[UIStackView alloc] init];
    self.tabsStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabsStackView.axis = UILayoutConstraintAxisHorizontal;
    self.tabsStackView.alignment = UIStackViewAlignmentCenter;
    self.tabsStackView.spacing = 8.0;
    [self.tabsScrollView addSubview:self.tabsStackView];

    self.tabButtons = [NSMutableArray array];
    for (NSInteger i = 0; i < self.catalogues.count; i++) {
        NSDictionary<NSString *, NSString *> *item = self.catalogues[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = i;
        button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 14.0, 8.0, 14.0);
        button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.82;
        button.layer.cornerRadius = 16.0;
        button.layer.cornerCurve = kCACornerCurveContinuous;
        button.layer.borderWidth = 1.0;
        [button setTitle:item[@"title"] ?: item[@"url"] ?: @"Source" forState:UIControlStateNormal];
        [button addTarget:self action:@selector(sourceTabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [button.widthAnchor constraintLessThanOrEqualToConstant:178.0].active = YES;
        [self.tabsStackView addArrangedSubview:button];
        [self.tabButtons addObject:button];
    }

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.allowsInlineMediaPlayback = YES;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    [self.view addSubview:self.webView];

    self.loadProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.loadProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadProgressView.progress = 0.0;
    self.loadProgressView.hidden = YES;
    [self.view addSubview:self.loadProgressView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.toolbarView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.toolbarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.toolbarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.toolbarView.heightAnchor constraintEqualToConstant:54.0],

        [closeButton.leadingAnchor constraintEqualToAnchor:self.toolbarView.leadingAnchor constant:12.0],
        [closeButton.centerYAnchor constraintEqualToAnchor:self.toolbarView.centerYAnchor],
        [closeButton.widthAnchor constraintEqualToConstant:36.0],
        [closeButton.heightAnchor constraintEqualToConstant:36.0],

        [reloadButton.trailingAnchor constraintEqualToAnchor:self.toolbarView.trailingAnchor constant:-12.0],
        [reloadButton.centerYAnchor constraintEqualToAnchor:self.toolbarView.centerYAnchor],
        [reloadButton.widthAnchor constraintEqualToConstant:36.0],
        [reloadButton.heightAnchor constraintEqualToConstant:36.0],

        [self.tabsScrollView.leadingAnchor constraintEqualToAnchor:closeButton.trailingAnchor constant:10.0],
        [self.tabsScrollView.trailingAnchor constraintEqualToAnchor:reloadButton.leadingAnchor constant:-10.0],
        [self.tabsScrollView.topAnchor constraintEqualToAnchor:self.toolbarView.topAnchor],
        [self.tabsScrollView.bottomAnchor constraintEqualToAnchor:self.toolbarView.bottomAnchor],

        [self.tabsStackView.leadingAnchor constraintEqualToAnchor:self.tabsScrollView.contentLayoutGuide.leadingAnchor],
        [self.tabsStackView.trailingAnchor constraintEqualToAnchor:self.tabsScrollView.contentLayoutGuide.trailingAnchor],
        [self.tabsStackView.topAnchor constraintEqualToAnchor:self.tabsScrollView.contentLayoutGuide.topAnchor constant:9.0],
        [self.tabsStackView.bottomAnchor constraintEqualToAnchor:self.tabsScrollView.contentLayoutGuide.bottomAnchor constant:-9.0],
        [self.tabsStackView.heightAnchor constraintEqualToAnchor:self.tabsScrollView.frameLayoutGuide.heightAnchor constant:-18.0],

        [self.loadProgressView.topAnchor constraintEqualToAnchor:self.toolbarView.bottomAnchor],
        [self.loadProgressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.loadProgressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [self.webView.topAnchor constraintEqualToAnchor:self.loadProgressView.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    [self updateSourceTabs];
    [self loadCatalogueAtIndex:self.selectedIndex];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.presentationController.delegate = self;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || self.presentationController == nil) {
        [self notifyCloseIfNeeded];
    }
}

- (void)dealloc
{
    @try {
        [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    } @catch (__unused NSException *exception) {
    }
}

- (void)notifyCloseIfNeeded
{
    if (self.didNotifyClose) return;
    self.didNotifyClose = YES;
    if (self.closeHandler) self.closeHandler();
}

- (void)closeTapped
{
    [self notifyCloseIfNeeded];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
    [self notifyCloseIfNeeded];
}

- (void)reloadTapped
{
    [self.webView reload];
}

- (void)sourceTabTapped:(UIButton *)button
{
    [self loadCatalogueAtIndex:button.tag];
}

- (void)loadCatalogueAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.catalogues.count) return;
    self.selectedIndex = index;
    [self updateSourceTabs];

    NSDictionary<NSString *, NSString *> *item = self.catalogues[index];
    NSURL *url = [NSURL URLWithString:item[@"url"] ?: @""];
    if (!url) return;
    self.title = item[@"title"] ?: url.host ?: @"Online Video";
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)updateSourceTabs
{
    for (UIButton *button in self.tabButtons) {
        BOOL selected = button.tag == self.selectedIndex;
        button.backgroundColor = selected ? UIColor.labelColor : UIColor.secondarySystemBackgroundColor;
        button.layer.borderColor = selected ? UIColor.labelColor.CGColor : [UIColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
        [button setTitleColor:(selected ? UIColor.systemBackgroundColor : UIColor.labelColor) forState:UIControlStateNormal];
    }
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.tabButtons.count) {
        UIButton *button = self.tabButtons[self.selectedIndex];
        CGRect rect = [button convertRect:button.bounds toView:self.tabsScrollView];
        [self.tabsScrollView scrollRectToVisible:CGRectInset(rect, -16.0, 0.0) animated:YES];
    }
}

- (NSArray<NSHTTPCookie *> *)cookiesForURL:(NSURL *)url fromCookies:(NSArray<NSHTTPCookie *> *)cookies
{
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *path = url.path.length ? url.path : @"/";
    NSMutableArray<NSHTTPCookie *> *matches = [NSMutableArray array];
    for (NSHTTPCookie *cookie in cookies) {
        NSString *domain = cookie.domain.lowercaseString ?: @"";
        if ([domain hasPrefix:@"."]) domain = [domain substringFromIndex:1];
        BOOL domainMatch = [host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]];
        BOOL pathMatch = cookie.path.length == 0 || [path hasPrefix:cookie.path];
        if (domainMatch && pathMatch) [matches addObject:cookie];
    }
    return matches;
}

- (NSMutableURLRequest *)nativeDownloadRequestFromRequest:(NSURLRequest *)request
{
    NSURL *url = request.URL;
    NSMutableURLRequest *native = [request mutableCopy] ?: [NSMutableURLRequest requestWithURL:url];
    native.URL = url;
    native.HTTPMethod = @"GET";
    native.HTTPBody = nil;
    native.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    native.timeoutInterval = 30.0;

    NSString *referer = self.webView.URL.absoluteString;
    if (referer.length && ![native valueForHTTPHeaderField:@"Referer"]) {
        [native setValue:referer forHTTPHeaderField:@"Referer"];
    }
    if (![native valueForHTTPHeaderField:@"User-Agent"]) {
        [native setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
      forHTTPHeaderField:@"User-Agent"];
    }
    if (![native valueForHTTPHeaderField:@"Accept"]) {
        [native setValue:@"video/*,*/*;q=0.8" forHTTPHeaderField:@"Accept"];
    }
    if (![native valueForHTTPHeaderField:@"Accept-Language"]) {
        [native setValue:[NSLocale preferredLanguages].firstObject ?: @"en-US" forHTTPHeaderField:@"Accept-Language"];
    }
    return native;
}

- (void)beginNativeDownloadForRequest:(NSURLRequest *)request
{
    if (!request.URL || !self.downloadHandler) return;
    NSMutableURLRequest *native = [self nativeDownloadRequestFromRequest:request];

    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    __weak typeof(self) weakSelf = self;
    [store getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (![native valueForHTTPHeaderField:@"Cookie"]) {
            NSArray<NSHTTPCookie *> *matches = [self cookiesForURL:native.URL fromCookies:cookies];
            NSDictionary<NSString *, NSString *> *headers = [NSHTTPCookie requestHeaderFieldsWithCookies:matches];
            NSString *cookieHeader = headers[@"Cookie"];
            if (cookieHeader.length) [native setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.downloadHandler(native);
        });
    }];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (object == self.webView && [keyPath isEqualToString:@"estimatedProgress"]) {
        self.loadProgressView.hidden = self.webView.estimatedProgress >= 1.0;
        [self.loadProgressView setProgress:(float)self.webView.estimatedProgress animated:YES];
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;
    NSString *scheme = url.scheme.lowercaseString ?: @"";
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if (livewp_url_has_video_extension(url)) {
        [self beginNativeDownloadForRequest:navigationAction.request];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if (!navigationAction.targetFrame) {
        [webView loadRequest:navigationAction.request];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
    if (livewp_response_is_video_download(navigationResponse.response)) {
        NSURL *url = navigationResponse.response.URL;
        if (url) {
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [self beginNativeDownloadForRequest:request];
        }
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures
{
    if (!navigationAction.targetFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

@end

@interface SettingsViewController () <UIDocumentPickerDelegate, NSURLSessionDownloadDelegate, UIContextMenuInteractionDelegate>
@property (nonatomic, strong) UISegmentedControl *powercuffSegmented;
@property (nonatomic, assign) BOOL pendingManualActionsReload;
@property (nonatomic, assign) BOOL detailMode;
@property (nonatomic, assign) NSInteger underlyingSection;
@property (nonatomic, copy)   NSString *bundleTitle;
@property (nonatomic, strong) NSURLSession *livewpDownloadSession;
@property (nonatomic, strong) NSURLSessionDownloadTask *livewpDownloadTask;
@property (nonatomic, strong) CyanideLiveWPDownloadProgressViewController *livewpDownloadProgressController;
@property (nonatomic, strong) NSURL *livewpDownloadURL;
@property (nonatomic, strong) NSURLRequest *livewpDownloadRequest;
@property (nonatomic, strong) NSURLSession *sblDownloadSession;
@property (nonatomic, strong) NSURLSessionDownloadTask *sblDownloadTask;
@property (nonatomic, strong) CyanideLiveWPDownloadProgressViewController *sblDownloadProgressController;
@property (nonatomic, strong) NSURL *sblDownloadURL;
@property (nonatomic, strong) NSURLRequest *sblDownloadRequest;
@property (nonatomic, copy) NSString *sblDownloadDisplayName;
@property (nonatomic, weak) UIStackView *sblOnlineDownloadsStack;
@property (nonatomic, strong) CyanideCenteredLoadingViewController *sblLocalImportLoadingController;
@property (nonatomic, copy) NSString *pendingThemeImportMode;
@property (nonatomic, copy) NSString *pendingSnowBoardLiteImportName;
@end

// Singleton delegate so MFMailCompose's host VC doesn't need to conform. Lives
// for the app's lifetime — a single instance handles every dismissal across
// every entry point (Settings → Contact, Installer → Contact button, etc.).
@interface _CyanideMailDelegate : NSObject <MFMailComposeViewControllerDelegate>
@end
@implementation _CyanideMailDelegate
- (void)mailComposeController:(MFMailComposeViewController *)c
          didFinishWithResult:(MFMailComposeResult)r error:(NSError *)e
{
    (void)r; (void)e;
    [c dismissViewControllerAnimated:YES completion:nil];
}
@end
static _CyanideMailDelegate *_cyanide_mail_delegate(void) {
    static _CyanideMailDelegate *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[_CyanideMailDelegate alloc] init]; });
    return d;
}

@interface _NiceBarTimePresetPickerViewController : UITableViewController
@property (nonatomic, copy) NSString *slotTitle;
@property (nonatomic, copy) NSString *selectedFormat;
@property (nonatomic, copy) void (^onSelect)(NSString *format);
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *sections;
- (instancetype)initWithSlotTitle:(NSString *)slotTitle
                   selectedFormat:(NSString *)selectedFormat
                         onSelect:(void (^)(NSString *format))onSelect;
@end

@implementation _NiceBarTimePresetPickerViewController

- (instancetype)initWithSlotTitle:(NSString *)slotTitle
                   selectedFormat:(NSString *)selectedFormat
                         onSelect:(void (^)(NSString *format))onSelect
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _slotTitle = [slotTitle copy];
        _selectedFormat = [selectedFormat copy];
        _onSelect = [onSelect copy];

        NSMutableArray<NSDictionary<NSString *, id> *> *builtSections = [NSMutableArray array];
        NSMutableArray<NSDictionary<NSString *, NSString *> *> *currentRows = nil;
        NSString *currentSection = nil;
        for (NSDictionary<NSString *, NSString *> *preset in settings_nicebar_time_presets()) {
            NSString *section = preset[@"section"] ?: @"";
            if (![section isEqualToString:currentSection]) {
                currentSection = section;
                currentRows = [NSMutableArray array];
                [builtSections addObject:@{ @"title": currentSection, @"rows": currentRows }];
            }
            [currentRows addObject:preset];
        }
        _sections = [builtSections copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.slotTitle.length ? self.slotTitle : @"Date / Time";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56.0;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(closePicker)];
}

- (void)closePicker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *rows = self.sections[(NSUInteger)section][@"rows"];
    return rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    return self.sections[(NSUInteger)section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"nicebar-time-preset"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"nicebar-time-preset"];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.numberOfLines = 1;
    }
    NSDictionary *preset = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    NSString *title = preset[@"title"] ?: @"Preset";
    NSString *format = preset[@"format"] ?: @"HH:mm";
    cell.textLabel.text = title;
    cell.detailTextLabel.text = settings_nicebar_preview_for_time_format(format);
    cell.accessoryType = [self.selectedFormat isEqualToString:format] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *preset = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    NSString *format = preset[@"format"] ?: @"HH:mm";
    if (self.onSelect) self.onSelect(format);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface _NiceBarSystemItemPickerViewController : UITableViewController
@property (nonatomic, copy) NSString *slotTitle;
@property (nonatomic, assign) NSInteger selectedItem;
@property (nonatomic, copy) NSString *selectedLanguage;
@property (nonatomic, copy) void (^onSelect)(NSInteger item, NSString *language);
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *sections;
- (instancetype)initWithSlotTitle:(NSString *)slotTitle
                     selectedItem:(NSInteger)selectedItem
                 selectedLanguage:(NSString *)selectedLanguage
                          onSelect:(void (^)(NSInteger item, NSString *language))onSelect;
@end

@implementation _NiceBarSystemItemPickerViewController

- (instancetype)initWithSlotTitle:(NSString *)slotTitle
                     selectedItem:(NSInteger)selectedItem
                 selectedLanguage:(NSString *)selectedLanguage
                          onSelect:(void (^)(NSInteger item, NSString *language))onSelect
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _slotTitle = [slotTitle copy];
        _selectedItem = selectedItem;
        _selectedLanguage = [selectedLanguage isEqualToString:@"zh"] ? @"zh" : @"en";
        _onSelect = [onSelect copy];
        _sections = @[
            @{ @"title": @"Device", @"rows": @[
                @{ @"item": @(NiceBarLiteSystemBatteryTemp) },
                @{ @"item": @(NiceBarLiteSystemBatteryPercent) },
                @{ @"item": @(NiceBarLiteSystemFreeRAM) },
                @{ @"item": @(NiceBarLiteSystemUptime) },
                @{ @"item": @(NiceBarLiteSystemThermalState), @"language": @"en", @"title": @"Thermal state · English" },
                @{ @"item": @(NiceBarLiteSystemThermalState), @"language": @"zh", @"title": @"Thermal state · 中文" },
            ] },
            @{ @"title": @"Network", @"rows": @[
                @{ @"item": @(NiceBarLiteSystemNetworkSpeed) },
                @{ @"item": @(NiceBarLiteSystemTodayTraffic) },
                @{ @"item": @(NiceBarLiteSystemCurrentIP) },
            ] },
            @{ @"title": @"Storage", @"rows": @[
                @{ @"item": @(NiceBarLiteSystemFreeDisk) },
            ] },
        ];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.slotTitle.length ? self.slotTitle : @"System Item";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(closePicker)];
}

- (void)closePicker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    (void)tableView;
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *rows = self.sections[(NSUInteger)section][@"rows"];
    return rows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    (void)tableView;
    return self.sections[(NSUInteger)section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"nicebar-system-item"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"nicebar-system-item"];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.numberOfLines = 0;
    }
    NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    NSInteger item = [row[@"item"] integerValue];
    NSString *language = row[@"language"] ?: @"en";
    NSString *title = row[@"title"] ?: settings_nicebar_system_name(item);
    cell.textLabel.text = title;
    cell.detailTextLabel.text = settings_nicebar_system_description(item);

    BOOL sameItem = self.selectedItem == item;
    BOOL sameLanguage = item != NiceBarLiteSystemThermalState ||
                        [self.selectedLanguage isEqualToString:language];
    cell.accessoryType = (sameItem && sameLanguage) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    NSInteger item = [row[@"item"] integerValue];
    NSString *language = row[@"language"] ?: @"en";
    if (self.onSelect) self.onSelect(item, language);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation _CyanideNiceBarWeatherRefresher

- (instancetype)init
{
    self = [super init];
    if (!self) return nil;
    _pendingCompletions = [NSMutableArray array];
    return self;
}

- (void)refreshWeatherForce:(BOOL)force completion:(CyanideNiceBarWeatherCompletion)completion
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshWeatherForce:force completion:completion];
        });
        return;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *cached = [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?: @"";
    NSDate *lastAttempt = [d objectForKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
    if (!force && lastAttempt &&
        [[NSDate date] timeIntervalSinceDate:lastAttempt] < kNiceBarLiteWeatherRefreshInterval) {
        NSNumber *temp = [d objectForKey:kSettingsNiceBarLiteWeatherTemp];
        NSNumber *code = [d objectForKey:kSettingsNiceBarLiteWeatherCode];
        if (completion) completion(cached.length > 0, cached, temp, code, NO);
        return;
    }

    if (completion) {
        @synchronized (self) {
            [self.pendingCompletions addObject:[completion copy]];
        }
    }

    self.requestUsesCelsius = [d boolForKey:kSettingsNiceBarLiteCelsius];
    [d setObject:[NSDate date] forKey:kSettingsNiceBarLiteWeatherLastAttemptAt];
    [d synchronize];
    log_user("[NICEBAR] Weather flow starting celsius=%d.\n", self.requestUsesCelsius ? 1 : 0);

    [self continueRefreshFlow];
}

- (void)continueRefreshFlow
{
    if (self.locationRequestInFlight || self.weatherFetchInFlight) return;

    if (!self.locationManager) {
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.delegate = self;
        self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;
    }

    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }

    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        log_user("[NICEBAR] Weather location denied/restricted status=%d.\n", (int)status);
        [self finishWithSuccess:NO text:@"Loc denied" temp:nil code:nil];
        return;
    }
    if (status == kCLAuthorizationStatusNotDetermined) {
        log_user("[NICEBAR] Weather requesting location authorization.\n");
        [self.locationManager requestWhenInUseAuthorization];
        return;
    }

    self.locationRequestInFlight = YES;
    log_user("[NICEBAR] Weather requesting GPS location.\n");
    [self.locationManager requestLocation];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    (void)manager;
    [self continueRefreshFlow];
}

- (void)locationManager:(CLLocationManager *)manager
didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    (void)manager;
    (void)status;
    [self continueRefreshFlow];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    (void)manager;
    self.locationRequestInFlight = NO;
    printf("[NICEBAR] location request failed: %s\n", error.localizedDescription.UTF8String);
    [self finishWithSuccess:NO text:@"Weather --" temp:nil code:nil];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    (void)manager;
    self.locationRequestInFlight = NO;

    CLLocation *location = locations.lastObject;
    if (!location) {
        [self finishWithSuccess:NO text:@"Weather --" temp:nil code:nil];
        return;
    }

    self.weatherFetchInFlight = YES;
    BOOL celsius = self.requestUsesCelsius;
    NSString *unit = celsius ? @"celsius" : @"fahrenheit";
    log_user("[NICEBAR] Weather fetching lat=%.4f lon=%.4f unit=%s.\n",
             location.coordinate.latitude,
             location.coordinate.longitude,
             unit.UTF8String);
    NSString *urlString = [NSString stringWithFormat:
                           @"https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,weather_code&temperature_unit=%@",
                           location.coordinate.latitude,
                           location.coordinate.longitude,
                           unit];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        self.weatherFetchInFlight = NO;
        [self finishWithSuccess:NO text:@"Weather --" temp:nil code:nil];
        return;
    }

    [[[NSURLSession sharedSession] dataTaskWithURL:url
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        NSString *text = @"Weather --";
        NSNumber *resolvedTemp = nil;
        NSNumber *resolvedCode = nil;
        BOOL ok = NO;
        if (error) {
            printf("[NICEBAR] weather fetch failed: %s\n", error.localizedDescription.UTF8String);
        } else if (data.length > 0) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *current = [json isKindOfClass:NSDictionary.class] ? json[@"current"] : nil;
            NSNumber *temp = [current isKindOfClass:NSDictionary.class] ? current[@"temperature_2m"] : nil;
            NSNumber *code = [current isKindOfClass:NSDictionary.class] ? current[@"weather_code"] : nil;
            if ([temp isKindOfClass:NSNumber.class] && [code isKindOfClass:NSNumber.class]) {
                NSString *summary = [_CyanideNiceBarWeatherRefresher summaryForWeatherCode:code.integerValue];
                text = [NSString stringWithFormat:@"%@ %.0f°", summary, temp.doubleValue];
                resolvedTemp = temp;
                resolvedCode = code;
                ok = YES;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.weatherFetchInFlight = NO;
            [self finishWithSuccess:ok text:text temp:resolvedTemp code:resolvedCode];
        });
    }] resume];
}

+ (NSString *)summaryForWeatherCode:(NSInteger)code
{
    return settings_nicebar_weather_summary(code, NO);
}

- (void)finishWithSuccess:(BOOL)ok text:(NSString *)text temp:(NSNumber *)temp code:(NSNumber *)code
{
    NSString *resolved = text.length ? text : @"Weather --";
    NSArray<CyanideNiceBarWeatherCompletion> *callbacks = nil;
    @synchronized (self) {
        callbacks = self.pendingCompletions.copy;
        [self.pendingCompletions removeAllObjects];
    }
    for (CyanideNiceBarWeatherCompletion callback in callbacks) {
        callback(ok, resolved, temp, code, YES);
    }
}

@end

@interface ThemerFormatGuideViewController : UITableViewController
@end

@implementation ThemerFormatGuideViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Theme Format";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 2 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0: return @"Folder Theme";
        case 1: return @"Plist Theme";
        case 2: return @"Files";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return @"Only icons with matching bundle IDs change. Missing apps keep their stock icon.";
    }
    if (section == 1) {
        return @"Use a binary plist when you want one portable file instead of a folder of PNGs.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"guide"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"guide"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"PNG Files";
        cell.detailTextLabel.text =
            @"Make a folder containing PNG files named by app bundle ID:\n"
             "com.apple.mobilesafari.png\n"
             "com.apple.MobileSMS.png\n"
             "com.apple.mobiletimer.png";
    } else if (indexPath.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = @"Bundle ID → PNG Data";
        cell.detailTextLabel.text =
            @"Make a dictionary plist. Each key is a bundle ID. Each value is raw PNG data. "
             "Cyanide imports the plist and copies it into Documents/Themes.";
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Share Sample Theme Plist";
            cell.detailTextLabel.text = @"Exports a small binary plist template with example bundle IDs.";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Share iOS 6 Theme Plist";
            cell.detailTextLabel.text = @"Exports the iOS 6 Theme plist. Icons by zagnut531/iOS-6-Icons.";
        } else {
            cell.textLabel.text = @"Share App Info.plist";
            cell.detailTextLabel.text = @"Exports Cyanide's bundled Info.plist for reference.";
        }
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (NSData *)sampleIconPNGWithText:(NSString *)text color:(UIColor *)color
{
    CGSize size = CGSizeMake(120.0, 120.0);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                                               format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:27.0] addClip];
        [color setFill];
        UIRectFill(rect);

        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:48.0 weight:UIFontWeightBold],
            NSForegroundColorAttributeName: UIColor.whiteColor,
        };
        CGSize textSize = [text sizeWithAttributes:attrs];
        CGRect textRect = CGRectMake((size.width - textSize.width) / 2.0,
                                     (size.height - textSize.height) / 2.0,
                                     textSize.width,
                                     textSize.height);
        [text drawInRect:textRect withAttributes:attrs];
    }];
    return UIImagePNGRepresentation(image);
}

- (NSURL *)writeSamplePlist:(NSError **)error
{
    NSData *safari = [self sampleIconPNGWithText:@"S"
                                           color:[UIColor colorWithRed:0.05 green:0.45 blue:0.95 alpha:1.0]];
    NSData *sms = [self sampleIconPNGWithText:@"M"
                                        color:[UIColor colorWithRed:0.10 green:0.65 blue:0.25 alpha:1.0]];
    NSDictionary *plist = @{
        @"com.apple.mobilesafari": safari ?: [NSData data],
        @"com.apple.MobileSMS": sms ?: [NSData data],
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:error];
    if (!data) return nil;

    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"CyanideThemeTemplate.plist"]];
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    return url;
}

- (NSURL *)copyBuiltInIOS6Plist:(NSError **)error
{
    NSString *src = [[NSBundle mainBundle] pathForResource:@"Themes-iOS6" ofType:@"plist"];
    if (!src) {
        if (error) {
            *error = [NSError errorWithDomain:@"CyanideThemerGuide"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bundled iOS 6 plist was not found."}];
        }
        return nil;
    }

    NSURL *dst = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"Cyanide-iOS6-Theme.plist"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:dst.path]) {
        [fm removeItemAtURL:dst error:nil];
    }
    if (![fm copyItemAtURL:[NSURL fileURLWithPath:src] toURL:dst error:error]) return nil;
    return dst;
}

- (NSURL *)copyAppInfoPlist:(NSError **)error
{
    NSString *src = [[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"];
    if (!src) {
        if (error) {
            *error = [NSError errorWithDomain:@"CyanideThemerGuide"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Bundled Info.plist was not found."}];
        }
        return nil;
    }

    NSURL *dst = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"Cyanide-Info.plist"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:dst.path]) {
        [fm removeItemAtURL:dst error:nil];
    }
    if (![fm copyItemAtURL:[NSURL fileURLWithPath:src] toURL:dst error:error]) return nil;
    return dst;
}

- (void)dismissGuide
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareURL:(NSURL *)url sourceView:(UIView *)sourceView
{
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                                     applicationActivities:nil];
    UIView *anchor = sourceView ?: self.view;
    vc.popoverPresentationController.sourceView = anchor;
    vc.popoverPresentationController.sourceRect = anchor.bounds;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)showExportError:(NSError *)error
{
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Export Failed"
                                                                message:error.localizedDescription ?: @"Could not write the plist."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 2) return;

    NSError *error = nil;
    NSURL *url = nil;
    if (indexPath.row == 0) {
        url = [self writeSamplePlist:&error];
    } else if (indexPath.row == 1) {
        url = [self copyBuiltInIOS6Plist:&error];
    } else {
        url = [self copyAppInfoPlist:&error];
    }
    if (!url) {
        [self showExportError:error];
        return;
    }

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [self shareURL:url sourceView:cell.contentView ?: tableView];
}

@end

@implementation SettingsViewController

- (instancetype)initWithCoder:(NSCoder *)coder
{
    // Calling [super initWithCoder:] (not initWithStyle:) so UIViewController's
    // unarchiving runs: that's what wires up the parentViewController and
    // navigationController relationships established by the storyboard's
    // rootViewController segue. Going through initWithStyle leaves nav nil.
    if ((self = [super initWithCoder:coder])) {
        _underlyingSection = NSIntegerMax;
    }
    return self;
}

- (instancetype)initWithUnderlyingSection:(NSInteger)underlyingSection
                              bundleTitle:(NSString *)bundleTitle
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _detailMode = YES;
        _underlyingSection = underlyingSection;
        _bundleTitle = [bundleTitle copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.detailMode ? (self.bundleTitle ?: @"Settings") : @"Settings";
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAlways;
    self.tableView.rowHeight                      = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight             = 44.0;
    self.tableView.sectionHeaderHeight            = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight   = 20.0;
    self.tableView.sectionFooterHeight            = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight   = 10.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"toggle"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"stepper"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"slider"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"segmented"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"action"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"button"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"warning"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"bundle"];
    [self installInstallerReturnButtonIfNeeded];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(remoteCallStateDidChange:)
                                                 name:kSettingsRemoteCallStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cleanupStateDidChange:)
                                                 name:kSettingsCleanupStateDidChangeNotification
                                               object:nil];
}

- (void)cleanupStateDidChange:(NSNotification *)note
{
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)installInstallerReturnButtonIfNeeded
{
    if (!self.installerReturnPackageName) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightSemibold];
    UIImage *chevron = [UIImage systemImageNamed:@"chevron.backward" withConfiguration:cfg];
    [btn setImage:chevron forState:UIControlStateNormal];
    [btn setTitle:[@" " stringByAppendingString:self.installerReturnPackageName] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    btn.tintColor = self.view.tintColor;
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 4);
    [btn addTarget:self action:@selector(returnToInstaller) forControlEvents:UIControlEventTouchUpInside];
    [btn sizeToFit];

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:btn];
    self.navigationItem.leftBarButtonItem = backItem;
    self.navigationItem.hidesBackButton = YES;
}

- (void)returnToInstaller
{
    UITabBarController *tab = self.tabBarController;
    UINavigationController *settingsNav = self.navigationController;
    NSUInteger installerIdx = NSNotFound;
    for (NSUInteger i = 0; i < tab.viewControllers.count; i++) {
        UIViewController *vc = tab.viewControllers[i];
        if ([vc.tabBarItem.title isEqualToString:@"Installer"]) {
            installerIdx = i;
            break;
        }
    }
    [settingsNav popToRootViewControllerAnimated:NO];
    if (installerIdx != NSNotFound) {
        tab.selectedIndex = installerIdx;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadManualActions];

    // The NanoRegistry plist lives behind a sandbox wall on-device. Keep the
    // detail panel passive; the explicit "Load Current" button performs the
    // privileged KRW/sandbox setup before reading it.
    if (self.detailMode && self.underlyingSection == SectionNanoRegistry) {
        if (self.isViewLoaded) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self restoreSettingsInteractionAfterModal];
    [self presentPowercuffNominalNoticeIfNeeded];
    if (!self.pendingManualActionsReload) return;
    self.pendingManualActionsReload = NO;
    [self reloadManualActions];
}

- (void)restoreSettingsInteractionAfterModal
{
    self.view.userInteractionEnabled = YES;
    self.tableView.userInteractionEnabled = YES;
    self.view.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
    self.tableView.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
}

- (void)presentPowercuffNominalNoticeIfNeeded
{
    if (!self.detailMode || self.underlyingSection != SectionPowercuff) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d boolForKey:kSettingsPowercuffNominalNoticeShown]) return;

    NSString *level = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
    BOOL alreadyNominal = [level isEqualToString:@"nominal"];
    NSString *message = @"Powercuff now defaults to Nominal.\n\nLight, Moderate, and Heavy intentionally underclock the CPU. That means lag or slower app launches can happen, especially on older devices. The lag means Powercuff is working, but those levels may be too slow for comfortable day-to-day use.\n\nUse Nominal for daily use, then raise it only when you want stronger throttling.";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Powercuff Level"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    if (!alreadyNominal) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Use Nominal"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *_) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:@"nominal" forKey:kSettingsPowercuffLevel];
            [defaults setBool:YES forKey:kSettingsPowercuffNominalNoticeShown];
            [defaults synchronize];
            [weakSelf.tableView reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:alreadyNominal ? @"OK" : @"Keep Current"
                                             style:UIAlertActionStyleCancel
                                           handler:^(UIAlertAction *_) {
        [d setBool:YES forKey:kSettingsPowercuffNominalNoticeShown];
        [d synchronize];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)remoteCallStateDidChange:(NSNotification *)notification
{
    [self reloadManualActions];
}

- (void)reloadManualActions
{
    if (!self.isViewLoaded) return;
    if (self.detailMode) return;
    if (!self.tableView.window) {
        self.pendingManualActionsReload = YES;
        return;
    }
    NSIndexSet *sections = [NSIndexSet indexSetWithIndex:RootSectionActions];
    [self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCell *)buildWarningCell:(UITableViewCell *)cell
{
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"info.circle.fill"]];
    icon.tintColor = UIColor.systemOrangeColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [icon setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Cyanide is a limited tweak environment — tweaks apply this session only and reset on reboot. Live tweaks like StatBar and Axon Lite stop if you force-quit Cyanide from the App Switcher. A progress log opens automatically while changes are applying; tap Hide to dismiss.";
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:icon];
    [cell.contentView addSubview:label];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
        [icon.centerYAnchor   constraintEqualToAnchor:label.centerYAnchor],
        [icon.widthAnchor     constraintEqualToConstant:22],
        [icon.heightAnchor    constraintEqualToConstant:22],
        [label.leadingAnchor  constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [label.topAnchor      constraintEqualToAnchor:m.topAnchor constant:4],
        [label.bottomAnchor   constraintEqualToAnchor:m.bottomAnchor constant:-4],
    ]];
    return cell;
}

- (NSString *)nicebarSubtitleForSlot:(NSInteger)slot
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    switch (kind) {
        case NiceBarLiteContentCustomText: {
            NSString *text = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTextPrefix, slot)] ?: @"";
            return text.length ? text : @"Text";
        }
        case NiceBarLiteContentSystem: {
            NSInteger item = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot)];
            if (item == NiceBarLiteSystemThermalState) {
                NSString *language = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, slot)] ?: @"en";
                return [NSString stringWithFormat:@"%@ · %@",
                        settings_nicebar_system_name(item),
                        settings_nicebar_system_language_name(language)];
            }
            return settings_nicebar_system_name(item);
        }
        case NiceBarLiteContentTimeFormat: {
            NSString *format = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot)] ?: @"HH:mm";
            return settings_nicebar_time_format_name(format);
        }
        case NiceBarLiteContentWeather: {
            NSString *text = settings_nicebar_weather_text_for_slot(d, slot);
            return text.length ? text : @"Weather --";
        }
        case NiceBarLiteContentOff:
        default:
            return @"Off";
    }
}

- (UIButton *)nicebarSlotButton:(NSInteger)slot
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = slot;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 9, 8, 9);
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = UIColor.separatorColor.CGColor;
    [button addTarget:self action:@selector(nicebarSlotButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    NSString *title = [NSString stringWithFormat:@"%@\n%@\n%@",
                       settings_nicebar_slot_name(slot),
                       settings_nicebar_kind_name(kind),
                       [self nicebarSubtitleForSlot:slot]];
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.lineSpacing = 1.5;
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: paragraph,
    };
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:title
                                                                                   attributes:attrs];
    NSRange firstNewline = [title rangeOfString:@"\n"];
    NSRange secondNewline = [title rangeOfString:@"\n"
                                         options:0
                                           range:NSMakeRange(firstNewline.location != NSNotFound ? firstNewline.location + 1 : 0,
                                                            firstNewline.location != NSNotFound ? title.length - firstNewline.location - 1 : title.length)];
    if (firstNewline.location != NSNotFound) {
        [attributed addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        } range:NSMakeRange(firstNewline.location + 1,
                            (secondNewline.location != NSNotFound ? secondNewline.location : title.length) - firstNewline.location - 1)];
    }
    if (secondNewline.location != NSNotFound) {
        [attributed addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
        } range:NSMakeRange(secondNewline.location + 1, title.length - secondNewline.location - 1)];
    }
    [button setAttributedTitle:attributed forState:UIControlStateNormal];
    button.titleLabel.numberOfLines = 3;
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.82;
    return button;
}

- (UITableViewCell *)buildNiceBarGridCellInTableView:(UITableView *)tableView
                                      indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"nicebar-grid"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"nicebar-grid"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.contentConfiguration = nil;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self nicebarSlotButton:NiceBarLiteSlotTopLeft],
        [self nicebarSlotButton:NiceBarLiteSlotTopRight],
    ]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.spacing = 10.0;
    top.distribution = UIStackViewDistributionFillEqually;

    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self nicebarSlotButton:NiceBarLiteSlotBottomLeft],
        [self nicebarSlotButton:NiceBarLiteSlotBottomCenter],
        [self nicebarSlotButton:NiceBarLiteSlotBottomRight],
    ]];
    bottom.axis = UILayoutConstraintAxisHorizontal;
    bottom.spacing = 10.0;
    bottom.distribution = UIStackViewDistributionFillEqually;

    UIStackView *grid = [[UIStackView alloc] initWithArrangedSubviews:@[top, bottom]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 10.0;
    grid.distribution = UIStackViewDistributionFillEqually;
    [cell.contentView addSubview:grid];

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [grid.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [grid.topAnchor constraintEqualToAnchor:m.topAnchor constant:6.0],
        [grid.bottomAnchor constraintEqualToAnchor:m.bottomAnchor constant:-6.0],
        [grid.heightAnchor constraintEqualToConstant:164.0],
    ]];
    (void)indexPath;
    return cell;
}

- (NSString *)nsbarPositionTitle:(NSBarPosition)position
{
    switch (position) {
        case NSBarPositionTopLeft: return @"Top left";
        case NSBarPositionTopRight: return @"Top right";
        case NSBarPositionBottomLeft: return @"Bottom left";
        case NSBarPositionBottomRight: return @"Bottom right";
        case NSBarPositionCenter: return @"Center";
        default: return @"Top left";
    }
}

- (UIButton *)nsbarPositionButton:(NSBarPosition)position selected:(BOOL)selected
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = (NSInteger)position;
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = (selected ? UIColor.systemGreenColor : UIColor.separatorColor).CGColor;
    button.backgroundColor = selected
        ? [UIColor.systemGreenColor colorWithAlphaComponent:0.18]
        : UIColor.secondarySystemGroupedBackgroundColor;
    [button setTitle:[self nsbarPositionTitle:position] forState:UIControlStateNormal];
    [button setTitleColor:selected ? UIColor.systemGreenColor : UIColor.labelColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:selected ? UIFontWeightSemibold : UIFontWeightRegular];
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.75;
    [button addTarget:self action:@selector(nsbarPositionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UITableViewCell *)buildNSBarGridCellInTableView:(UITableView *)tableView
                                        indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"nsbar-grid"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"nsbar-grid"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.contentConfiguration = nil;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    NSInteger selected = [[NSUserDefaults standardUserDefaults] integerForKey:kSettingsNSBarPosition];
    if (selected < NSBarPositionTopLeft || selected > NSBarPositionCenter) selected = NSBarPositionTopLeft;

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self nsbarPositionButton:NSBarPositionTopLeft selected:selected == NSBarPositionTopLeft],
        [self nsbarPositionButton:NSBarPositionTopRight selected:selected == NSBarPositionTopRight],
    ]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.spacing = 10.0;
    top.distribution = UIStackViewDistributionFillEqually;

    UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self nsbarPositionButton:NSBarPositionBottomLeft selected:selected == NSBarPositionBottomLeft],
        [self nsbarPositionButton:NSBarPositionCenter selected:selected == NSBarPositionCenter],
        [self nsbarPositionButton:NSBarPositionBottomRight selected:selected == NSBarPositionBottomRight],
    ]];
    bottom.axis = UILayoutConstraintAxisHorizontal;
    bottom.spacing = 10.0;
    bottom.distribution = UIStackViewDistributionFillEqually;

    UIStackView *grid = [[UIStackView alloc] initWithArrangedSubviews:@[top, bottom]];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 10.0;
    grid.distribution = UIStackViewDistributionFillEqually;
    [cell.contentView addSubview:grid];

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [grid.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [grid.topAnchor constraintEqualToAnchor:m.topAnchor constant:6.0],
        [grid.bottomAnchor constraintEqualToAnchor:m.bottomAnchor constant:-6.0],
        [grid.heightAnchor constraintEqualToConstant:108.0],
    ]];
    (void)indexPath;
    return cell;
}

- (NSArray<NSDictionary *> *)layoutCalibrationItemsForScope:(NSString *)scope
{
    (void)scope;
    return @[
        @{ @"title": @"Top spacing",
           @"key": kSettingsNiceBarLiteLayoutTopSideInset,
           @"legacyKey": kSettingsNiceBarLiteLayoutSideInset,
           @"hint": @"Move top items toward or away from the edges",
           @"min": @-24, @"max": @36 },
        @{ @"title": @"Bottom spacing",
           @"key": kSettingsNiceBarLiteLayoutBottomSideInset,
           @"legacyKey": kSettingsNiceBarLiteLayoutSideInset,
           @"hint": @"Tune the bottom row separately",
           @"min": @-24, @"max": @36 },
        @{ @"title": @"Top height",
           @"key": kSettingsNiceBarLiteLayoutTopY,
           @"hint": @"Raise or lower the top row",
           @"min": @-18, @"max": @36 },
        @{ @"title": @"Bottom height",
           @"key": kSettingsNiceBarLiteLayoutBottomY,
           @"hint": @"Raise or lower the bottom row",
           @"min": @-24, @"max": @44 },
        @{ @"title": @"Center position",
           @"key": kSettingsNiceBarLiteLayoutCenterX,
           @"hint": @"Move only the middle item",
           @"min": @-40, @"max": @40 },
    ];
}

- (NSString *)layoutCalibrationValueText:(NSInteger)value
{
    if (value == 0) return @"0 px";
    return [NSString stringWithFormat:@"%+ld px", (long)value];
}

- (NSInteger)layoutCalibrationValueForItem:(NSDictionary *)item
{
    NSString *key = item[@"key"];
    NSString *legacyKey = item[@"legacyKey"];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [d persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    if (key.length > 0 && domain[key]) return [d integerForKey:key];
    if (legacyKey.length > 0) return [d integerForKey:legacyKey];
    return key.length > 0 ? [d integerForKey:key] : 0;
}

- (UIView *)layoutCalibrationControlWithItem:(NSDictionary *)item
                                   supported:(BOOL)supported
                                     preview:(CyanideLayoutCalibrationPreviewView *)preview
{
    NSString *key = item[@"key"];
    NSInteger minV = [item[@"min"] integerValue];
    NSInteger maxV = [item[@"max"] integerValue];
    NSInteger value = [self layoutCalibrationValueForItem:item];
    if (value < minV) value = minV;
    if (value > maxV) value = maxV;

    UIView *wrap = [[UIView alloc] init];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = item[@"title"];
    title.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    title.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = item[@"hint"];
    hint.textColor = supported ? UIColor.tertiaryLabelColor : UIColor.tertiaryLabelColor;
    hint.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    hint.numberOfLines = 1;

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.text = [self layoutCalibrationValueText:value];
    valueLabel.textColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
    valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightMedium];
    valueLabel.textAlignment = NSTextAlignmentRight;

    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = (float)minV;
    slider.maximumValue = (float)maxV;
    slider.value = (float)value;
    slider.continuous = YES;
    slider.enabled = supported;
    slider.tintColor = UIColor.systemBlueColor;
    [slider addTarget:self action:@selector(layoutCalibrationSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(layoutCalibrationSliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    objc_setAssociatedObject(slider, "cyanideLayoutKey", key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, "cyanideLayoutValueLabel", valueLabel, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(slider, "cyanideLayoutPreview", preview, OBJC_ASSOCIATION_ASSIGN);

    [wrap addSubview:title];
    [wrap addSubview:hint];
    [wrap addSubview:valueLabel];
    [wrap addSubview:slider];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [valueLabel.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:valueLabel.leadingAnchor constant:-8.0],
        [hint.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [hint.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor],
        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1.0],
        [slider.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor],
        [slider.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [slider.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:2.0],
        [slider.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
    ]];
    return wrap;
}

- (UITableViewCell *)buildLayoutCalibrationCellInTableView:(UITableView *)tableView
                                                       row:(NSDictionary *)row
                                                 indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"layout-calibration"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"layout-calibration"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.textLabel.text = nil;
    cell.contentConfiguration = nil;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    BOOL supported = settings_device_supported();
    NSString *scope = row[@"scope"] ?: @"nicebar";

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"Fine Tune Layout";
    title.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = row[@"subtitle"] ?: @"Adjust the preview, then check the live status bar.";
    subtitle.textColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    subtitle.numberOfLines = 0;

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [reset setTitle:@"Reset" forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    reset.enabled = supported;
    reset.contentEdgeInsets = UIEdgeInsetsMake(5, 10, 5, 10);
    reset.backgroundColor = UIColor.tertiarySystemFillColor;
    reset.layer.cornerRadius = 11.0;
    reset.layer.cornerCurve = kCACornerCurveContinuous;
    [reset addTarget:self action:@selector(layoutCalibrationResetTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(reset, "cyanideLayoutScope", scope, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIStackView *headerText = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
    headerText.translatesAutoresizingMaskIntoConstraints = NO;
    headerText.axis = UILayoutConstraintAxisVertical;
    headerText.spacing = 2.0;

    CyanideLayoutCalibrationPreviewView *preview = [[CyanideLayoutCalibrationPreviewView alloc] init];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.scope = scope;
    preview.backgroundColor = UIColor.clearColor;
    preview.contentMode = UIViewContentModeRedraw;

    UIStackView *controls = [[UIStackView alloc] init];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    controls.axis = UILayoutConstraintAxisVertical;
    controls.spacing = 10.0;
    for (NSDictionary *item in [self layoutCalibrationItemsForScope:scope]) {
        [controls addArrangedSubview:[self layoutCalibrationControlWithItem:item
                                                                  supported:supported
                                                                    preview:preview]];
    }

    [cell.contentView addSubview:headerText];
    [cell.contentView addSubview:reset];
    [cell.contentView addSubview:preview];
    [cell.contentView addSubview:controls];

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [headerText.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [headerText.topAnchor constraintEqualToAnchor:m.topAnchor constant:8.0],
        [headerText.trailingAnchor constraintLessThanOrEqualToAnchor:reset.leadingAnchor constant:-12.0],

        [reset.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [reset.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],

        [preview.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [preview.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [preview.topAnchor constraintEqualToAnchor:headerText.bottomAnchor constant:12.0],
        [preview.heightAnchor constraintEqualToConstant:104.0],

        [controls.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [controls.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:12.0],
        [controls.bottomAnchor constraintEqualToAnchor:m.bottomAnchor constant:-10.0],
    ]];
    (void)indexPath;
    return cell;
}

#pragma mark - Row models

- (NSArray<NSDictionary *> *)launchRows
{
    return @[
        @{ @"key": kSettingsAutoRunKexploit,    @"title": @"Auto-run kexploit on launch" },
        @{ @"key": kSettingsRunSandboxEscape,   @"title": @"Sandbox escape (escape_sbx_demo2)" },
        @{ @"key": kSettingsKeepAlive,          @"title": @"Keep app alive in background",
           @"subtitle": @"Required for app-driven live tweaks to persist while minimized, including StatBar receiving fresh live data." },
    ];
}

// The master enable / install-equivalent rows have been removed from each
// tweak's row list — install/uninstall is handled by the Installer tab's
// Install button. Settings only shows configuration knobs.

- (NSArray<NSDictionary *> *)sbcRows
{
    return @[
        @{ @"kind": @"stepper", @"key": kSettingsSBCDockIcons,  @"title": @"Dock icons", @"min": @4, @"max": @7, @"default": @(kSBCDefaultDockIcons) },
        @{ @"kind": @"stepper", @"key": kSettingsSBCCols,       @"title": @"Home columns", @"min": @3, @"max": @7, @"default": @(kSBCDefaultCols) },
        @{ @"kind": @"stepper", @"key": kSettingsSBCRows,       @"title": @"Home rows", @"min": @4, @"max": @8, @"default": @(kSBCDefaultRows) },
        @{ @"kind": @"toggle",  @"key": kSettingsSBCHideLabels, @"title": @"Hide icon labels" },
        @{ @"kind": @"button",  @"title": @"Reset to Defaults" },
    ];
}

- (NSArray<NSDictionary *> *)powercuffRows
{
    return @[
        @{ @"kind": @"segmented", @"key": kSettingsPowercuffLevel,   @"title": @"Level" },
    ];
}

- (NSArray<NSDictionary *> *)otaRows
{
    return @[
        @{ @"kind": @"button", @"title": @"Disable OTA Updates" },
        @{ @"kind": @"button", @"title": @"Enable OTA Updates" },
    ];
}

- (NSArray<NSDictionary *> *)nanoRegistryRows
{
    return @[
        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMaxPairing,
           @"title": @"watchOS Pairing Limit",
           @"subtitle": @"Highest watchOS pairing generation this iPhone will accept. 99 raises the phone-side ceiling for newer watchOS releases.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMaxPairing) },

        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMinPairing,
           @"title": @"Setup Protocol Floor",
           @"subtitle": @"Lowest pairing setup generation this iPhone will accept. Keep this at 23 so generation-23 setup messages are not rejected.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMinPairing) },

        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMinPairingChipID,
           @"title": @"Legacy Chip Floor",
           @"subtitle": @"Leave this alone unless you are trying to pair an old S-chip watch, such as a Series 3.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMinPairingChipID) },

        @{ @"kind": @"stepper",
           @"key": kSettingsNanoMinQuickSwitch,
           @"title": @"Multi-Watch Switching",
           @"subtitle": @"Leave this alone unless switching between multiple older paired watches is not working.",
           @"min": @(kNanoUIRowMin),
           @"max": @(kNanoUIRowMax),
           @"default": @(kNanoDefaultMinQuickSwitch) },

        @{ @"kind": @"button",
           @"title": @"Load Saved Override",
           @"action": @"nano-load" },

        @{ @"kind": @"button",
           @"title": @"Use watchOS Range 99/23/10/6",
           @"action": @"nano-preset-newer" },

        @{ @"kind": @"button",
           @"title": @"Apply Pairing Override",
           @"action": @"nano-apply" },

        @{ @"kind": @"button",
           @"title": @"Remove Override",
           @"action": @"nano-clear",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)darkSwordTweakRows
{
    return @[];
}

- (NSArray<NSDictionary *> *)dragCoefficientRows
{
    return @[
        @{ @"kind": @"slider",
           @"key": kSettingsDSDragCoefficientValue,
           @"title": @"Coefficient",
           @"subtitle": @"100 = stock, 50 = 2x faster, 25 = 4x faster",
           @"min": @5, @"max": @200, @"step": @5,
           @"unit": @"%", @"default": @50 },
    ];
}

- (NSArray<NSDictionary *> *)layoutExtrasRows
{
    return @[
        @{ @"kind": @"slider", @"key": kSettingsLayoutHomeExtraLeft,
           @"title": @"Home extra left",   @"min": @0,  @"max": @300, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsLayoutHomeExtraRight,
           @"title": @"Home extra right",  @"min": @0,  @"max": @300, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsLayoutHomeExtraTop,
           @"title": @"Home extra top",    @"min": @0,  @"max": @400, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsLayoutHomeExtraBottom,
           @"title": @"Home extra bottom", @"min": @0,  @"max": @400, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsLayoutDockExtraHorizontal,
           @"title": @"Dock extra horizontal", @"min": @0,  @"max": @200, @"step": @1, @"unit": @"pt", @"default": @0 },
        @{ @"kind": @"slider", @"key": kSettingsLayoutHomeScalePct,
           @"title": @"Home icon scale",   @"min": @25, @"max": @250, @"step": @1, @"unit": @"%", @"default": @100 },
        @{ @"kind": @"slider", @"key": kSettingsLayoutDockScalePct,
           @"title": @"Dock icon scale",   @"min": @25, @"max": @250, @"step": @1, @"unit": @"%", @"default": @100 },
    ];
}

- (NSArray<NSDictionary *> *)statbarRows
{
    return @[
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowTemp,    @"title": @"Show Temperature" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarCelsius,     @"title": @"Celsius" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowCPU,     @"title": @"Show CPU %" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowRAM,     @"title": @"Show RAM" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowLabels,  @"title": @"Show CPU / RAM labels" },
        @{ @"kind": @"toggle", @"key": kSettingsStatBarShowNet,     @"title": @"Show network speed" },
        @{ @"kind": @"slider", @"key": kSettingsStatBarRefreshRateSec,
           @"title": @"Refresh rate", @"min": @1, @"max": @30, @"step": @1,
           @"unit": @"s", @"default": @(kStatBarDefaultRefreshRateSec) },
    ];
}

- (NSArray<NSDictionary *> *)nsbarRows
{
    return @[
        @{ @"kind": @"nsbar-grid" },
    ];
}

- (NSArray<NSDictionary *> *)nicebarLiteRows
{
    return @[
        @{ @"kind": @"nicebar-grid" },
        @{ @"kind": @"layout-calibration",
           @"scope": @"nicebar",
           @"title": @"Fine Tune Layout",
           @"subtitle": @"Top and bottom rows move separately. Changes update live while NiceBar Lite is running." },
        @{ @"kind": @"toggle", @"key": kSettingsNiceBarLiteCelsius, @"title": @"Use Celsius" },
        @{ @"kind": @"button", @"title": @"Traffic History", @"action": @"nicebar-traffic-history" },
        @{ @"kind": @"button", @"title": @"Apply Now", @"action": @"nicebar-apply" },
    ];
}

- (NSArray<NSDictionary *> *)rssiRows
{
    return @[
        @{ @"kind": @"toggle", @"key": kSettingsRSSIDisplayWifi, @"title": @"WiFi (bar count)" },
        @{ @"kind": @"toggle", @"key": kSettingsRSSIDisplayCell, @"title": @"Cellular (dBm)" },
    ];
}

- (NSArray<NSDictionary *> *)axonLiteRows
{
    return @[];
}

- (NSArray<NSDictionary *> *)typebannerRows
{
    return @[
        @{ @"kind": @"button",
           @"title": @"Test: Poll Daemon & Show Banner",
           @"subtitle": @"Runs the live imagent detection path once. Banner shows the result; the [TYPEBANNER] log lines explain what was/wasn't found.",
           @"action": @"typebanner-test" },
    ];
}

- (NSArray<NSDictionary *> *)appSwitcherGridRows
{
    BOOL applied = settings_tweak_is_applied(kSettingsAppSwitcherGridEnabled);
    return @[
        @{ @"kind": @"info",
           @"title": applied ? @"Current Session: Grid" : @"Current Session: Stock",
           @"subtitle": @"This is a runtime-only SpringBoard method patch. It does not write system files; respring restores the stock app switcher." },
        @{ @"kind": @"button",
           @"title": @"Restore Stock Switcher",
           @"subtitle": @"Restores the original switcher style in the active SpringBoard session when available.",
           @"action": @"appswitchergrid-restore",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)gravityLiteRows
{
    return @[
        @{ @"kind": @"toggle",
           @"key": kSettingsGravityLiteDockEnabled,
           @"title": @"Include Dock" },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteMagnitudePct,
           @"title": @"Gravity strength",
           @"min": @25,
           @"max": @300,
           @"step": @5,
           @"unit": @"%",
           @"default": @100 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteBouncePct,
           @"title": @"Bounce",
           @"min": @0,
           @"max": @100,
           @"step": @5,
           @"unit": @"%",
           @"default": @50 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteFrictionPct,
           @"title": @"Friction",
           @"min": @0,
           @"max": @100,
           @"step": @5,
           @"unit": @"%",
           @"default": @50 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteResistancePct,
           @"title": @"Resistance",
           @"min": @0,
           @"max": @200,
           @"step": @5,
           @"unit": @"%",
           @"default": @50 },
        @{ @"kind": @"slider",
           @"key": kSettingsGravityLiteAngularResistancePct,
           @"title": @"Spin resistance",
           @"min": @0,
           @"max": @200,
           @"step": @5,
           @"unit": @"%",
           @"default": @0 },
        @{ @"kind": @"button",
           @"title": @"Explosion Pulse",
           @"action": @"gravitylite-explosion" },
        @{ @"kind": @"button",
           @"title": @"Restore Icon Layout",
           @"action": @"gravitylite-restore",
           @"destructive": @YES },
    ];
}

- (NSArray<NSDictionary *> *)livewpRows
{
    NSString *absPath = settings_livewp_absolute_path();
    BOOL hasVideo = (absPath && absPath.length > 0);
    NSString *videoName = hasVideo ? [absPath lastPathComponent] : @"No video selected";
    NSString *detail = settings_livewp_video_detail(absPath);

    return @[
        @{ @"kind": @"preview",
           @"title": videoName,
           @"subtitle": detail,
           @"videoPath": absPath ?: @"" },
        @{ @"kind": @"info",
           @"title": @"Online Downloads",
           @"subtitle": @"Downloaded videos are saved to Files > On My iPhone > Cyanide > LiveWP > Downloads. They are not applied automatically; use Select Video File to import one manually." },
        @{ @"kind": @"button",
           @"title": hasVideo ? @"Replace Video File" : @"Select Video File",
           @"action": @"livewp-select-video" },
        @{ @"kind": @"button",
           @"title": @"Download Online Video",
           @"action": @"livewp-online-video" },
    ];
}

- (NSArray<NSDictionary *> *)themerRows
{
    BOOL hasSelection = settings_themer_has_selected_theme();
    NSString *selected = settings_themer_selected_theme_display_name();
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithArray:@[
        @{ @"kind": @"info",
           @"title": @"Selected Theme",
           @"subtitle": hasSelection ? selected : @"None selected. Pick a theme before running Cyanide Themer." },

        @{ @"kind": @"button",
           @"title": [selected isEqualToString:@"iOS 6 Theme"]
                ? @"iOS 6 Theme ✓" : @"Use iOS 6 Theme",
           @"action": @"themer-select-ios6" },

        @{ @"kind": @"button",
           @"title": @"Import Custom Theme…",
           @"action": @"themer-import" },

        @{ @"kind": @"button",
           @"title": @"Theme Format Guide",
           @"action": @"themer-guide" },
    ]];
    if (hasSelection) {
        [rows addObject:@{ @"kind": @"button",
                           @"title": @"Clear Selected Theme",
                           @"action": @"themer-clear",
                           @"destructive": @YES }];
    }
    return rows;
}

- (NSArray<NSDictionary *> *)snowBoardLiteOnlineDownloadItems
{
    return @[
        @{ @"title": @"锤子图标",
           @"subtitle": @"Smartisan OS icon pack from GitHub",
           @"symbol": @"hammer.fill",
           @"color": UIColor.systemOrangeColor,
           @"url": @"https://github.com/Sunbelife/Snowboard-IconPack-for-Smartisan-OS/archive/refs/heads/master.zip",
           @"previewURLs": @[
               @"https://camo.githubusercontent.com/74d7a2c38624363d411bfb835bf12ef1d6565a796e171fb1a176102b4349a541/68747470733a2f2f747661312e73696e61696d672e636e2f6c617267652f30303753385a496c67793167663930633861706f626a3331696a3075306b38762e6a7067",
           ] },
        @{ @"title": @"Junipero",
           @"subtitle": @"Havoc theme by XerusDesign",
           @"symbol": @"leaf.fill",
           @"color": UIColor.systemGreenColor,
           @"url": @"https://havoc.app/api/download/package/65c502227f817e1cfc99c962/com.xerusdesign.junipero_1.2_iphoneos-arm64.deb",
           @"previewURLs": @[
               @"https://media.havoc.app/63ba128b15250baf94106f88",
               @"https://media.havoc.app/63ba129915250baf941070df",
               @"https://media.havoc.app/63b8c3adfcedf02b6a93e8f9",
               @"https://media.havoc.app/63b8c3bbfcedf02b6a93e9ce",
               @"https://media.havoc.app/63b8c3f1fcedf02b6a93ec75",
           ] },
        @{ @"title": @"Miso",
           @"subtitle": @"Havoc cartoon glyph theme",
           @"symbol": @"face.smiling.fill",
           @"color": UIColor.systemYellowColor,
           @"url": @"https://havoc.app/api/download/package/6222d5091cee0e538b47d1cf/co.shoyu.miso_1.0_iphoneos-arm64.deb",
           @"previewURLs": @[
               @"https://media.havoc.app/6222d70bb1aa0e8855a5a272",
           ] },
        @{ @"title": @"Oxyg3n",
           @"subtitle": @"Havoc colorful iOS theme",
           @"symbol": @"paintpalette.fill",
           @"color": UIColor.systemCyanColor,
           @"url": @"https://havoc.app/api/download/package/620bfb17325c9a748303d7a1/com.cachetes.oxyg3n_2.4_iphoneos-arm64.deb",
           @"previewURLs": @[
               @"https://media.havoc.app/620bfafc325c9a748303d72b",
               @"https://media.havoc.app/620bfafd325c9a748303d72d",
               @"https://media.havoc.app/620bfafd325c9a748303d72f",
           ] },
        @{ @"title": @"Felicity Pro",
           @"subtitle": @"Havoc detailed icon theme",
           @"symbol": @"sparkle",
           @"color": UIColor.systemIndigoColor,
           @"url": @"https://havoc.app/api/download/package/6456d857fd175b7b49aba4fb/com.xandesign.felicitypro_4.1_iphoneos-arm64.deb",
           @"previewURLs": @[
               @"https://media.havoc.app/6456df8afd175b7b49abd6c9",
               @"https://media.havoc.app/6456dfd7fd175b7b49abdaf0",
           ] },
        @{ @"title": @"shitboard",
           @"subtitle": @"a 'very good' snowboard ios theme",
           @"symbol": @"sparkles",
           @"color": UIColor.systemPinkColor,
           @"url": @"https://github.com/machineonamission/shitboard/releases/download/1.2/shitboard.deb",
           @"previewURLs": @[
               @"https://raw.githubusercontent.com/machineonamission/shitboard/refs/heads/master/preview.png",
           ] },
    ];
}

- (NSArray<NSDictionary *> *)snowBoardLiteRows
{
    NSArray<NSDictionary *> *themes = settings_sbl_load_manifest();
    NSDictionary *selectedTheme = settings_sbl_selected_theme();
    BOOL selectedBuiltinIOS6 = settings_sbl_selected_builtin_ios6();
    BOOL hasActiveTheme = settings_snowboardlite_has_selected_theme();

    NSMutableArray<NSDictionary *> *libraryItems = [NSMutableArray array];
    [libraryItems addObject:@{
        @"id": kSnowBoardLiteThemeBuiltinIOS6,
        @"title": @"iOS 6 Theme",
        @"sourceType": @"built-in",
        @"iconCount": @(settings_themer_builtin_ios6_icon_count()),
        @"subtitle": @"Built-in classic icon set",
        @"builtIn": @YES,
        @"selected": @(selectedBuiltinIOS6),
    }];

    NSString *selectedID = selectedBuiltinIOS6 ? nil : selectedTheme[@"id"];
    for (NSDictionary *theme in themes) {
        [libraryItems addObject:@{
            @"id": theme[@"id"] ?: @"",
            @"title": theme[@"name"] ?: @"Imported Theme",
            @"sourceType": theme[@"sourceType"] ?: @"folder",
            @"theme": theme,
            @"importedAt": theme[@"importedAt"] ?: @"",
            @"iconCount": theme[@"iconCount"] ?: @0,
            @"iconBundlesCount": theme[@"iconBundlesCount"] ?: @0,
            @"aliasMappedCount": theme[@"aliasMappedCount"] ?: @0,
            @"skippedCount": theme[@"skippedCount"] ?: @0,
            @"duplicateCount": theme[@"duplicateCount"] ?: @0,
            @"skippedSamples": theme[@"skippedSamples"] ?: @[],
            @"builtIn": @NO,
            @"selected": @([selectedID isEqualToString:theme[@"id"]]),
        }];
    }

    return @[
        @{ @"kind": @"sbl-online-entry",
           @"title": @"Online Themes",
           @"subtitle": @"Preview and download curated themes.",
           @"action": @"sbl-online" },
        @{ @"kind": @"sbl-carousel",
           @"title": @"Theme Library",
           @"subtitle": themes.count > 0
                ? @"Tap a card to activate. Long-press a card for options."
                : @"Start with iOS 6 or import a SnowBoard IconBundles theme.",
           @"items": libraryItems },
        @{ @"kind": @"sbl-help",
           @"title": @"Import & Help",
           @"subtitle": @"Import a named local folder/.zip/.deb, paste a direct archive URL, or open the format guide.",
           @"active": @(hasActiveTheme) },
    ];
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)settingsSummaryForSection:(NSInteger)section
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSMutableArray *out = [NSMutableArray array];
    if (section == SectionSBC) {
        [out addObject:@{@"title": @"Dock icons",       @"value": [@([d integerForKey:kSettingsSBCDockIcons])  stringValue]}];
        [out addObject:@{@"title": @"Home columns",     @"value": [@([d integerForKey:kSettingsSBCCols])        stringValue]}];
        [out addObject:@{@"title": @"Home rows",        @"value": [@([d integerForKey:kSettingsSBCRows])        stringValue]}];
        [out addObject:@{@"title": @"Hide icon labels", @"value": [d boolForKey:kSettingsSBCHideLabels] ? @"On" : @"Off"}];
    } else if (section == SectionDragCoefficient) {
        NSInteger value = [d integerForKey:kSettingsDSDragCoefficientValue];
        [out addObject:@{@"title": @"Coefficient",
                         @"value": [NSString stringWithFormat:@"%ld%%", (long)value]}];
    } else if (section == SectionLayoutExtras) {
        [out addObject:@{@"title": @"Home extra L/R",   @"value": [NSString stringWithFormat:@"%ld/%ld",
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraLeft],
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraRight]]}];
        [out addObject:@{@"title": @"Home extra T/B",   @"value": [NSString stringWithFormat:@"%ld/%ld",
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraTop],
                                                                    (long)[d integerForKey:kSettingsLayoutHomeExtraBottom]]}];
        [out addObject:@{@"title": @"Dock extra H",     @"value": [@([d integerForKey:kSettingsLayoutDockExtraHorizontal]) stringValue]}];
        [out addObject:@{@"title": @"Home scale %",     @"value": [@([d integerForKey:kSettingsLayoutHomeScalePct]) stringValue]}];
        [out addObject:@{@"title": @"Dock scale %",     @"value": [@([d integerForKey:kSettingsLayoutDockScalePct]) stringValue]}];
    } else if (section == SectionStatBar) {
        [out addObject:@{@"title": @"Celsius",             @"value": [d boolForKey:kSettingsStatBarCelsius]    ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Show CPU %",          @"value": [d boolForKey:kSettingsStatBarShowCPU]    ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Show CPU/RAM labels", @"value": [d boolForKey:kSettingsStatBarShowLabels] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Show net speed",      @"value": [d boolForKey:kSettingsStatBarShowNet]    ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Refresh rate",        @"value": [NSString stringWithFormat:@"%lds",
                                                                       (long)[d integerForKey:kSettingsStatBarRefreshRateSec]]}];
    } else if (section == SectionNSBar) {
        NSArray<NSString *> *positions = nsbar_positions();
        NSInteger pos = [d integerForKey:kSettingsNSBarPosition];
        NSString *value = (pos >= 0 && pos < (NSInteger)positions.count) ? positions[(NSUInteger)pos] : positions.firstObject;
        [out addObject:@{@"title": @"Position", @"value": value ?: @"Top Left"}];
    } else if (section == SectionNiceBarLite) {
        for (NSInteger i = 0; i < NiceBarLiteSlotCount; i++) {
            NSInteger kind = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, i)];
            [out addObject:@{@"title": settings_nicebar_slot_name(i),
                             @"value": settings_nicebar_kind_name(kind)}];
        }
    } else if (section == SectionRSSI) {
        [out addObject:@{@"title": @"WiFi (bar count)", @"value": [d boolForKey:kSettingsRSSIDisplayWifi] ? @"On" : @"Off"}];
        [out addObject:@{@"title": @"Cellular (dBm)",   @"value": [d boolForKey:kSettingsRSSIDisplayCell] ? @"On" : @"Off"}];
    } else if (section == SectionAppSwitcherGrid) {
        [out addObject:@{@"title": @"Session style",
                         @"value": settings_tweak_is_applied(kSettingsAppSwitcherGridEnabled) ? @"Grid" : @"Stock"}];
    } else if (section == SectionPowercuff) {
        NSString *lvl = [d stringForKey:kSettingsPowercuffLevel] ?: @"nominal";
        [out addObject:@{@"title": @"Level", @"value": lvl}];
    } else if (section == SectionNanoRegistry) {
        [out addObject:@{@"title": @"watchOS limit",      @"value": [@([d integerForKey:kSettingsNanoMaxPairing])       stringValue]}];
        [out addObject:@{@"title": @"Setup floor",        @"value": [@([d integerForKey:kSettingsNanoMinPairing])       stringValue]}];
        [out addObject:@{@"title": @"Legacy chip floor",  @"value": [@([d integerForKey:kSettingsNanoMinPairingChipID]) stringValue]}];
        [out addObject:@{@"title": @"Multi-watch switch", @"value": [@([d integerForKey:kSettingsNanoMinQuickSwitch])   stringValue]}];
    } else if (section == SectionThemer) {
        [out addObject:@{@"title": @"Theme", @"value": settings_themer_selected_theme_display_name()}];
    } else if (section == SectionSnowBoardLite) {
        [out addObject:@{@"title": @"Theme", @"value": settings_snowboardlite_selected_theme_display_name()}];
    } else if (section == SectionLiveWP) {
        NSString *absPath = settings_livewp_absolute_path();
        NSString *videoName = (absPath && absPath.length > 0) ? [absPath lastPathComponent] : @"None";
        [out addObject:@{@"title": @"Video", @"value": videoName}];
    } else if (section == SectionGravityLite) {
        [out addObject:@{@"title": @"Dock", @"value": [d boolForKey:kSettingsGravityLiteDockEnabled] ? @"Included" : @"Home only"}];
        [out addObject:@{@"title": @"Strength", @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteMagnitudePct]]}];
        [out addObject:@{@"title": @"Bounce", @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteBouncePct]]}];
        [out addObject:@{@"title": @"Friction", @"value": [NSString stringWithFormat:@"%ld%%", (long)[d integerForKey:kSettingsGravityLiteFrictionPct]]}];
    }
    return out;
}

- (NSArray<NSDictionary *> *)rowsForSection:(NSInteger)s
{
    switch (s) {
        case SectionLaunch:    return self.launchRows;
        case SectionSBC:       return self.sbcRows;
        case SectionDarkSwordTweaks: return self.darkSwordTweakRows;
        case SectionDragCoefficient: return self.dragCoefficientRows;
        case SectionLayoutExtras: return self.layoutExtrasRows;
        case SectionOTA:       return self.otaRows;
        case SectionNanoRegistry: return self.nanoRegistryRows;
        case SectionThemer:  return self.themerRows;
        case SectionSnowBoardLite: return self.snowBoardLiteRows;
        case SectionPowercuff: return self.powercuffRows;
        case SectionStatBar:   return self.statbarRows;
        case SectionNSBar:     return self.nsbarRows;
        case SectionNiceBarLite: return self.nicebarLiteRows;
        case SectionRSSI:      return self.rssiRows;
        case SectionAxonLite:  return self.axonLiteRows;
        case SectionTypeBanner: return self.typebannerRows;
        case SectionAppSwitcherGrid: return self.appSwitcherGridRows;
        case SectionLiveWP:    return self.livewpRows;
        case SectionGravityLite: return self.gravityLiteRows;
        default: return @[];
    }
}

#pragma mark - Bundle rows (root mode)

// Bundles whose underlying section has zero configuration rows are filtered
// out — install/uninstall is the only operation those tweaks expose, and
// that's already in the Installer tab.

- (NSArray<NSDictionary *> *)allTweakBundleRows
{
    return @[
        @{ @"title": @"Launch Options",     @"icon": @"bolt.fill",                          @"color": [UIColor systemRedColor],    @"section": @(SectionLaunch) },
        @{ @"title": @"SBCustomizer",       @"icon": @"square.grid.3x3.fill",                @"color": [UIColor systemBlueColor],   @"section": @(SectionSBC) },
        @{ @"title": @"StatBar",            @"icon": @"thermometer.medium",                  @"color": [UIColor systemRedColor],    @"section": @(SectionStatBar) },
        @{ @"title": @"NSBar",              @"icon": @"network",                             @"color": [UIColor systemGreenColor],  @"section": @(SectionNSBar) },
        @{ @"title": @"NiceBar Lite",       @"icon": @"textformat.size",                     @"color": [UIColor systemCyanColor],   @"section": @(SectionNiceBarLite) },
        @{ @"title": @"Signal Display",     @"icon": @"antenna.radiowaves.left.and.right",   @"color": [UIColor systemBlueColor],   @"section": @(SectionRSSI), @"experimental": @YES },
        @{ @"title": @"Axon Lite",          @"icon": @"bell.badge.fill",                     @"color": [UIColor systemRedColor],    @"section": @(SectionAxonLite) },
        @{ @"title": @"TypeBanner",         @"icon": @"ellipsis.bubble.fill",                @"color": [UIColor systemTealColor],   @"section": @(SectionTypeBanner), @"experimental": @YES },
        @{ @"title": @"App Switcher Grid",  @"icon": @"square.grid.2x2.fill",                @"color": [UIColor systemOrangeColor], @"section": @(SectionAppSwitcherGrid), @"experimental": @YES },
        @{ @"title": @"Cyanide Themer",     @"icon": @"paintpalette.fill",                   @"color": [UIColor systemPinkColor],   @"section": @(SectionThemer) },
        @{ @"title": @"SnowBoard Lite",     @"icon": @"square.stack.3d.up.fill",             @"color": [UIColor systemMintColor],   @"section": @(SectionSnowBoardLite) },
        @{ @"title": @"LiveWP",             @"icon": @"play.rectangle.fill",                 @"color": [UIColor systemPurpleColor], @"section": @(SectionLiveWP) },
        @{ @"title": @"Gravity Lite",       @"icon": @"arrow.down.circle.fill",              @"color": [UIColor systemGreenColor],  @"section": @(SectionGravityLite) },
        @{ @"title": @"Powercuff",          @"icon": @"bolt.slash.fill",                     @"color": [UIColor systemOrangeColor], @"section": @(SectionPowercuff) },
        @{ @"title": @"SpringBoard Tweaks", @"icon": @"apps.iphone",                         @"color": [UIColor systemIndigoColor], @"section": @(SectionDarkSwordTweaks) },
        @{ @"title": @"Drag Coefficient",   @"icon": @"dial.medium.fill",                     @"color": [UIColor systemIndigoColor], @"section": @(SectionDragCoefficient) },
        @{ @"title": @"Home Layout Extras", @"icon": @"square.dashed.inset.filled",          @"color": [UIColor systemPurpleColor], @"section": @(SectionLayoutExtras) },
    ];
}

- (NSArray<NSDictionary *> *)allSystemBundleRows
{
    return @[
        @{ @"title": @"OTA Updates",       @"icon": @"icloud.slash.fill",    @"color": [UIColor systemGrayColor],   @"section": @(SectionOTA) },
        @{ @"title": @"Watch Pairing",     @"icon": @"applewatch.radiowaves.left.and.right", @"color": [UIColor systemPurpleColor], @"section": @(SectionNanoRegistry) },
    ];
}

- (NSArray<NSDictionary *> *)filterBundles:(NSArray<NSDictionary *> *)bundles
{
    BOOL experimentalOn = [[NSUserDefaults standardUserDefaults]
                            boolForKey:kSettingsExperimentalTweaksEnabled];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *bundle in bundles) {
        if ([bundle[@"experimental"] boolValue] && !experimentalOn) continue;
        NSInteger sec = [bundle[@"section"] integerValue];
        if ([self rowsForSection:sec].count > 0) {
            [out addObject:bundle];
        }
    }
    return out;
}

- (NSArray<NSDictionary *> *)tweakBundleRows
{
    return [self filterBundles:[self allTweakBundleRows]];
}

- (NSArray<NSDictionary *> *)systemBundleRows
{
    return [self filterBundles:[self allSystemBundleRows]];
}

- (NSArray<NSDictionary *> *)bundleRowsForRootSection:(RootSection)section
{
    if (section == RootSectionTweakBundles)  return self.tweakBundleRows;
    if (section == RootSectionSystemBundles) return self.systemBundleRows;
    return @[];
}

#pragma mark - Table data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.detailMode ? 1 : RootSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.detailMode) {
        return (NSInteger)[self rowsForSection:self.underlyingSection].count;
    }
    switch ((RootSection)section) {
        case RootSectionChangelog: {
            // Entries + one "See all releases on GitHub" footer row when the
            // section is non-empty.
            NSInteger n = (NSInteger)settings_changelog_entries().count;
            return n > 0 ? n + 1 : 0;
        }
        case RootSectionActions:        return 5;
        case RootSectionTweakBundles:   return (NSInteger)self.tweakBundleRows.count;
        case RootSectionSystemBundles:  return (NSInteger)self.systemBundleRows.count;
        case RootSectionAppIcon:        return 2;
        case RootSectionDocs:           return 1;
        case RootSectionAbout:          return 3;
        case RootSectionExperimental:   return 1;
        case RootSectionWarning:        return 1;
        case RootSectionCount:          return 0;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (self.detailMode) return nil;
    switch ((RootSection)section) {
        case RootSectionChangelog:      return settings_changelog_entries().count > 0 ? @"What's New" : nil;
        case RootSectionActions:        return @"Quick Actions";
        case RootSectionTweakBundles:   return self.tweakBundleRows.count   > 0 ? @"Tweaks" : nil;
        case RootSectionSystemBundles:  return self.systemBundleRows.count  > 0 ? @"System" : nil;
        case RootSectionAppIcon:        return @"App Icon";
        case RootSectionDocs:           return @"Docs";
        case RootSectionAbout:          return @"About";
        case RootSectionExperimental:   return @"Experimental";
        default:                        return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (!self.detailMode) {
        if ((RootSection)section == RootSectionExperimental) {
            return @"⚠️ These tweaks are unfinished and may not work at all "
                   @"yet. Installing them only adds risk — SpringBoard "
                   @"crashes, dropped events, layout glitches, battery "
                   @"drain — with no guaranteed feature in return. Leave "
                   @"off unless you're a developer actively testing.";
        }
        if ((RootSection)section == RootSectionWarning) {
            NSString *version = settings_app_version_string();
            NSString *build = settings_app_build_string();
            if (build.length && ![build isEqualToString:@"unknown"]) {
                return [NSString stringWithFormat:@"Cyanide X v%@ (%@)", version, build];
            }
            return [NSString stringWithFormat:@"Cyanide X v%@", version];
        }
        return nil;
    }
    NSInteger s = self.underlyingSection;
    if (s == SectionLaunch) {
        return @"kexploit_opa334 runs once per app lifetime. Keep Alive applies only while Cyanide is minimized; an App Switcher kill still terminates the process.";
    }
    if (s == SectionSBC) {
        return [NSString stringWithFormat:@"Stock iOS defaults: dock %ld, columns %ld, rows %ld.",
                (long)kSBCDefaultDockIcons, (long)kSBCDefaultCols, (long)kSBCDefaultRows];
    }
    if (s == SectionDarkSwordTweaks) {
        return @"Imported from DarkSword-Tweaks. These are SpringBoard runtime patches; turning one off only skips future applies.";
    }
    if (s == SectionDragCoefficient) {
        return @"Overrides _UIAnimationDragCoefficient in SpringBoard. 50% = 2x faster, 25% = 4x faster, 100% = stock. Imported from kolbicz/DarkSword-Tweaks.";
    }
    if (s == SectionLayoutExtras) {
        NSInteger major = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
        if (major >= 26) {
            return [NSString stringWithFormat:
                @"Adds extra padding and per-icon scaling on top of the stock home/dock layout.\n\n"
                @"Running on iOS %ld: the upstream config-mutation path doesn't exist (AMUIInfographIconListLayout has no mutable configuration), so the iOS 26 path instead walks the live SBIconListView/SBIconView hierarchy and adjusts frames + iconImageInfo directly. One-shot at Run; iOS 26 may re-fit on a subsequent layout pass (rotation, page swipe).",
                (long)major];
        }
        return @"Adds extra padding and per-icon scaling on top of the stock home/dock layout. Defaults are zero padding and 100% scale (no change). Toggle Enable on and hit Run to apply; values aren't persisted across respring.";
    }
    if (s == SectionOTA) {
        return @"Edits launchd disabled.plist. A reboot or userspace restart is required for changes to take effect.";
    }
    if (s == SectionNanoRegistry) {
        return @"Changes the watchOS pairing range saved on this iPhone.\n\n"
               @"Most people should tap Use watchOS Range 99/23/10/6, then Apply Pairing Override. "
               @"These are pairing protocol generations, not Apple Watch model numbers. "
               @"99 raises the watchOS pairing ceiling. 23 keeps the generation-23 setup protocol accepted. "
               @"10 and 6 leave the legacy chip and multi-watch floors at their normal values.\n\n"
               @"Apple Watch Ultra 3 cannot pair on iOS versions below 26 at this time.\n\n"
               @"Respring or reboot after applying before you try to pair.";
    }
    if (s == SectionPowercuff) {
        return @"Underclocks the CPU/GPU via thermalmonitord by simulating thermal pressure. Nominal is the daily-use default. Light, Moderate, and Heavy intentionally underclock the CPU more and can make the device feel laggy, especially on older hardware.";
    }
    if (s == SectionStatBar) {
        return @"Live overlay. When enabled, StatBar keeps a SpringBoard RemoteCall session open. Refresh rate applies when Cyanide is minimized but the screen is still awake; StatBar pauses while the screen is locked or asleep.";
    }
    if (s == SectionNSBar) {
        return @"Tap a position box to move the network speed pill. Position changes apply silently during the active SpringBoard session.";
    }
    if (s == SectionNiceBarLite) {
        return @"Tap a box to choose what it shows. NiceBar Lite places plain text in the configured status-bar slots around the notch or Dynamic Island, including the bottom center position. Today traffic is persisted per local date and written to disk with a short throttle. Weather is fetched from your current GPS location through Open-Meteo and follows the Celsius toggle.";
    }
    if (s == SectionRSSI) {
        return @"Adds a UILabel as a sibling of each STUI signal view (no new UIWindow), refreshed every second. Cellular shows live RSRP dBm (sign implicit). WiFi shows the bar count (0-4); the wifid XPC dBm path crashed SpringBoard in prior tests.";
    }
    if (s == SectionAxonLite) {
        return @"RemoteCall-only Axon port. It uses a live app-side loop rather than substrate hooks, so it lasts for the active Cyanide SpringBoard session.";
    }
    if (s == SectionTypeBanner) {
        return @"Partial TypeMillennium port. Detection runs against imagent using original-thread RemoteCall probes, while SpringBoard renders a prewarmed banner window.";
    }
    if (s == SectionAppSwitcherGrid) {
        return @"Experimental session-only runtime patch. It swizzles SpringBoard's switcher style method in memory, writes no system files, and a respring restores stock. App switcher animations may glitch or crash SpringBoard on unsupported builds.";
    }
    if (s == SectionThemer) {
        return @"Note: Cyanide Themer is still rough around the edges and may be glitchy. It will be iteratively improved to be more stable over time.\n\n"
               @"Pick a theme before running Cyanide Themer.\n\n"
               @"Custom themes can be a folder of PNG files named by bundle ID, such as com.apple.mobilesafari.png, or a binary plist mapping bundle IDs to PNG data. Import copies the theme into Cyanide's Documents/Themes folder. Theme Format Guide includes examples and plist exports.";
    }
    if (s == SectionSnowBoardLite) {
        return @"SnowBoard Lite is separate from Cyanide Themer. Use the bundled iOS 6 Theme, import a named local folder/.zip/.deb, or paste a named direct archive URL. Cyanide recursively scans IconBundles, stores a local copy, and lets you switch active themes from this page.\n\nArchive support is intentionally lightweight: .zip supports stored/deflated entries, and .deb supports data.tar/data.tar.gz/data.tar.xz payloads.";
    }
    if (s == SectionLiveWP) {
        return @"Play a video as your dynamic wallpaper on both lock screen and home screen. Select a video file from your device, then toggle Enable and hit Apply Tweaks. The video will loop continuously as your wallpaper.";
    }
    if (s == SectionGravityLite) {
        return @"RemoteCall-only port of the classic Gravity icon physics tweak. Apply it, leave Cyanide with Keep Alive enabled, then tilt the device to steer icons. Restore Icon Layout resets captured icons.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger sec = self.detailMode ? self.underlyingSection : indexPath.section;
    NSArray *rows = [self rowsForSection:sec];
    if (indexPath.row < (NSInteger)rows.count) {
        NSDictionary *row = rows[indexPath.row];
        if ([row[@"kind"] isEqualToString:@"preview"]) {
            return 320;
        }
    }
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (!self.detailMode) {
        if ((RootSection)section == RootSectionWarning) return 18.0; // breathing room above the disclaimer
        if ((RootSection)section == RootSectionChangelog     && settings_changelog_entries().count == 0) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionTweakBundles  && self.tweakBundleRows.count  == 0) return CGFLOAT_MIN;
        if ((RootSection)section == RootSectionSystemBundles && self.systemBundleRows.count == 0) return CGFLOAT_MIN;
    }
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if ([self tableView:tableView titleForFooterInSection:section].length > 0)
        return UITableViewAutomaticDimension;
    return 6.0;
}

#pragma mark - Icon badge

+ (UIImage *)iconBadgeWithSymbol:(NSString *)symbol color:(UIColor *)color size:(CGFloat)size
{
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat radius = size * (7.0 / 29.0);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:radius];
        [color setFill];
        [path fill];

        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.58 weight:UIImageSymbolWeightSemibold];
        UIImage *symbolImage = [UIImage systemImageNamed:symbol withConfiguration:cfg];
        if (symbolImage) {
            UIImage *whiteIcon = [symbolImage imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            CGFloat x = (size - whiteIcon.size.width) / 2.0;
            CGFloat y = (size - whiteIcon.size.height) / 2.0;
            [whiteIcon drawAtPoint:CGPointMake(x, y)];
        }
    }];
}

static NSString * const kTelegramLogoSVG =
@"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"48\" height=\"48\" viewBox=\"0 0 48 48\">"
@"<circle cx=\"24\" cy=\"24\" r=\"24\" fill=\"#229ED9\"/>"
@"<path fill=\"#fff\" d=\"M35.6 13.2 9.9 23.1c-1.8.7-1.8 1.7-.3 2.2l6.6 2.1 2.5 7.8c.3.9.2 1.3 1 .3l3.6-3.5 7.5 5.5c1.4.8 2.4.4 2.7-1.3l4.9-23c.5-2-.8-2.9-2.4-2.2Zm-18.6 13.9 15.1-9.5c.8-.5 1.5-.2.9.4L20.1 29.7l-.5 5.2-2.6-8Z\"/>"
@"</svg>";

+ (UIImage *)telegramLogoImageWithSize:(CGFloat)size
{
    (void)kTelegramLogoSVG; // Keep the real SVG payload colocated with the rendered icon.
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGFloat s = size / 48.0;
        CGContextScaleCTM(c, s, s);

        [[UIColor colorWithRed:0.133 green:0.620 blue:0.851 alpha:1.0] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 48, 48)] fill];

        UIBezierPath *plane = [UIBezierPath bezierPath];
        [plane moveToPoint:CGPointMake(35.6, 13.2)];
        [plane addLineToPoint:CGPointMake(9.9, 23.1)];
        [plane addCurveToPoint:CGPointMake(9.6, 25.3)
                 controlPoint1:CGPointMake(8.1, 23.8)
                 controlPoint2:CGPointMake(8.1, 24.8)];
        [plane addLineToPoint:CGPointMake(16.2, 27.4)];
        [plane addLineToPoint:CGPointMake(18.7, 35.2)];
        [plane addCurveToPoint:CGPointMake(19.7, 35.5)
                 controlPoint1:CGPointMake(19.0, 36.1)
                 controlPoint2:CGPointMake(18.9, 36.5)];
        [plane addLineToPoint:CGPointMake(23.3, 32.0)];
        [plane addLineToPoint:CGPointMake(30.8, 37.5)];
        [plane addCurveToPoint:CGPointMake(33.5, 36.2)
                 controlPoint1:CGPointMake(32.2, 38.3)
                 controlPoint2:CGPointMake(33.2, 37.9)];
        [plane addLineToPoint:CGPointMake(38.4, 13.2)];
        [plane addCurveToPoint:CGPointMake(35.6, 13.2)
                 controlPoint1:CGPointMake(38.9, 11.2)
                 controlPoint2:CGPointMake(37.2, 10.3)];
        [plane closePath];

        [plane moveToPoint:CGPointMake(17.0, 27.1)];
        [plane addLineToPoint:CGPointMake(32.1, 17.6)];
        [plane addCurveToPoint:CGPointMake(33.0, 18.0)
                 controlPoint1:CGPointMake(32.9, 17.1)
                 controlPoint2:CGPointMake(33.6, 17.4)];
        [plane addLineToPoint:CGPointMake(20.1, 29.7)];
        [plane addLineToPoint:CGPointMake(19.6, 34.9)];
        [plane closePath];

        [UIColor.whiteColor setFill];
        [plane fillWithBlendMode:kCGBlendModeNormal alpha:1.0];
    }];
}

+ (UIImage *)circularImageFromData:(NSData *)data size:(CGFloat)size
{
    UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
    if (!image) return nil;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect rect = CGRectMake(0, 0, size, size);
        [[UIBezierPath bezierPathWithOvalInRect:rect] addClip];
        [image drawInRect:rect];
    }];
}

- (NSArray<NSDictionary *> *)aboutAuthors
{
    return @[
        @{ @"name": @"zeroxjf",
           @"avatar": @"https://avatars.githubusercontent.com/u/109935131?s=64&v=4",
           @"x": @"zeroxjf",
           @"color": UIColor.systemBlueColor },
        @{ @"name": @"d1y",
           @"avatar": @"https://avatars.githubusercontent.com/u/45585937?s=64?v=4",
           @"x": @"chenhonzhou",
           @"color": UIColor.systemPinkColor },
    ];
}

- (void)loadAboutAvatarURLString:(NSString *)urlString
                    intoImageView:(UIImageView *)imageView
                    fallbackColor:(UIColor *)fallbackColor
{
    imageView.image = [SettingsViewController iconBadgeWithSymbol:@"person.fill"
                                                            color:fallbackColor ?: UIColor.systemGrayColor
                                                             size:24.0];
    if (!urlString.length) return;

    objc_setAssociatedObject(imageView, "cyanideAboutAvatarURL", urlString, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        if (error || !data.length) return;
        UIImage *avatar = [SettingsViewController circularImageFromData:data size:24.0];
        if (!avatar) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *current = objc_getAssociatedObject(imageView, "cyanideAboutAvatarURL");
            if (![current isEqualToString:urlString]) return;
            imageView.image = avatar;
        });
    }] resume];
}

#pragma mark - Cells

- (UITableViewCell *)buildBundleCellWithRow:(NSDictionary *)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bundle"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"bundle"];
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:row[@"icon"] color:row[@"color"] size:29.0];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UITableViewCell *)buildChangelogCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    NSArray<NSDictionary *> *entries = settings_changelog_entries();
    NSDictionary *entry = (row >= 0 && row < (NSInteger)entries.count) ? entries[row] : nil;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"changelog"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"changelog"];
        cell.detailTextLabel.numberOfLines = 0;
        cell.textLabel.numberOfLines = 1;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    NSString *version = entry[@"version"] ?: @"";
    NSString *date    = settings_pretty_date_for_iso(entry[@"date"]);
    cell.textLabel.text = date.length
        ? [NSString stringWithFormat:@"v%@  ·  %@", version, date]
        : [NSString stringWithFormat:@"v%@", version];

    NSArray *changes = entry[@"changes"];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:changes.count];
    for (id c in changes) {
        if (![c isKindOfClass:[NSString class]]) continue;
        [lines addObject:[@"• " stringByAppendingString:(NSString *)c]];
    }
    cell.detailTextLabel.text = [lines componentsJoinedByString:@"\n"];

    return cell;
}

- (UITableViewCell *)buildChangelogFooterCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"changelog-footer"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"changelog-footer"];
    }
    cell.imageView.image = nil;
    cell.textLabel.text = @"See all releases on GitHub";
    cell.textLabel.font = [UIFont systemFontOfSize:15.0];
    cell.textLabel.textColor = self.view.tintColor;
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)openReleasesPage
{
    NSURL *url = [NSURL URLWithString:@"https://github.com/zeroxjf/cyanide-ios/releases"];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (UITableViewCell *)buildDocsCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"docs"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"docs"];
    }
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"book.closed.fill" color:UIColor.systemPurpleColor size:29.0];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.text = @"Tweak SDK";
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = @"How to write Cyanide tweaks";
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UIControl *)aboutAuthorPillWithAuthor:(NSDictionary *)author
{
    UIControl *pill = [[UIControl alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    pill.layer.cornerRadius = 17.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.10].CGColor;
    objc_setAssociatedObject(pill, "cyanideAboutXAccount", author[@"x"] ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [pill addTarget:self action:@selector(aboutAuthorCardTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 7.0;
    stack.userInteractionEnabled = NO;
    [pill addSubview:stack];

    UIImageView *avatar = [[UIImageView alloc] init];
    avatar.translatesAutoresizingMaskIntoConstraints = NO;
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 12.0;
    [avatar.widthAnchor constraintEqualToConstant:24.0].active = YES;
    [avatar.heightAnchor constraintEqualToConstant:24.0].active = YES;
    [self loadAboutAvatarURLString:author[@"avatar"]
                     intoImageView:avatar
                     fallbackColor:author[@"color"]];
    [stack addArrangedSubview:avatar];

    UILabel *name = [[UILabel alloc] init];
    name.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    name.textColor = UIColor.labelColor;
    name.text = author[@"name"] ?: @"Author";
    name.textAlignment = NSTextAlignmentNatural;
    [name setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [stack addArrangedSubview:name];

    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:34.0],
        [stack.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:8.0],
        [stack.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10.0],
        [stack.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
    ]];
    return pill;
}

- (UIControl *)aboutTelegramPill
{
    UIControl *pill = [[UIControl alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.10];
    pill.layer.cornerRadius = 17.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.12].CGColor;
    [pill addTarget:self action:@selector(aboutTelegramButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 7.0;
    stack.userInteractionEnabled = NO;
    [pill addSubview:stack];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[SettingsViewController telegramLogoImageWithSize:22.0]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconView.widthAnchor constraintEqualToConstant:22.0].active = YES;
    [iconView.heightAnchor constraintEqualToConstant:22.0].active = YES;
    [stack addArrangedSubview:iconView];

    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.systemBlueColor;
    label.text = @"ios_cyanide";
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [stack addArrangedSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:34.0],
        [stack.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:8.0],
        [stack.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-11.0],
        [stack.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
    ]];
    return pill;
}

- (UITableViewCell *)buildAboutProfileCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about-profile"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"about-profile"];
    }
    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;

    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 8.0;
    [cell.contentView addSubview:row];

    for (NSDictionary *author in [self aboutAuthors]) {
        [row addArrangedSubview:[self aboutAuthorPillWithAuthor:author]];
    }
    [row addArrangedSubview:[self aboutTelegramPill]];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:7.0],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-7.0],
    ]];
    return cell;
}

- (UITableViewCell *)buildAboutCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    if (row == 0) {
        return [self buildAboutProfileCellInTableView:tableView];
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"about"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"about"];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;

    if (row == 1) {
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"doc.text.magnifyingglass" color:UIColor.systemGrayColor size:29.0];
        cell.textLabel.text = @"View Log";
    } else {
        cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"square.and.arrow.up" color:UIColor.systemGreenColor size:29.0];
        cell.textLabel.text = @"Share Log";
    }
    return cell;
}

- (void)reloadThemerSectionAndQueue
{
    settings_mark_tweak_applied(kSettingsThemerEnabled, NO);
    settings_notify_package_queue_changed_async();
    if (self.detailMode && self.underlyingSection == SectionThemer) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView reloadData];
    }
}

- (void)selectBuiltInIOS6Theme
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeBuiltinIOS6 forKey:kSettingsThemerThemeID];
    [d synchronize];
    log_user("[THEMER] Selected iOS 6 Theme.\n");
    [self reloadThemerSectionAndQueue];
}

- (void)clearSelectedTheme
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeNone forKey:kSettingsThemerThemeID];
    [d setObject:@"" forKey:kSettingsThemerCustomThemePath];
    [d setObject:@"" forKey:kSettingsThemerCustomThemeName];
    if ([d boolForKey:kSettingsThemerEnabled]) {
        [d setBool:NO forKey:kSettingsThemerEnabled];
        g_themer_live_stop_requested = 1;
    }
    [d synchronize];
    log_user("[THEMER] Cleared selected theme; Cyanide Themer is no longer queued.\n");
    [self reloadThemerSectionAndQueue];
}

- (void)presentThemerFormatGuide
{
    ThemerFormatGuideViewController *vc =
        [[ThemerFormatGuideViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    vc.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:vc
                                                      action:@selector(dismissGuide)];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)presentThemerImporter
{
    self.pendingThemeImportMode = @"themer";
    UIAlertController *hint = [UIAlertController
        alertControllerWithTitle:@"Import Theme Folder"
                         message:@"Navigate into your theme folder so you can see the PNG files inside, then tap Open in the top-right corner to import the folder."
                  preferredStyle:UIAlertControllerStyleAlert];
    [hint addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder, UTTypePropertyList]];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [hint addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:hint animated:YES completion:nil];
}

- (void)reloadSnowBoardLiteSectionAndQueue
{
    settings_mark_tweak_applied(kSettingsSnowBoardLiteEnabled, NO);
    settings_notify_package_queue_changed_async();
    if (self.detailMode && self.underlyingSection == SectionSnowBoardLite) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    } else {
        [self.tableView reloadData];
    }
}

- (void)presentSnowBoardLiteImporter
{
    UIAlertController *namePrompt = [UIAlertController
        alertControllerWithTitle:@"Name Theme"
                         message:@"Give this SnowBoard Lite theme a display name, then choose a folder, .zip, or .deb containing IconBundles."
                  preferredStyle:UIAlertControllerStyleAlert];
    [namePrompt addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Theme name";
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [namePrompt addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    [namePrompt addAction:[UIAlertAction actionWithTitle:@"Choose File"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
        (void)a;
        NSString *name = namePrompt.textFields.firstObject.text ?: @"";
        self.pendingSnowBoardLiteImportName =
            [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        self.pendingThemeImportMode = @"sbl";
        NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObjects:UTTypeFolder, UTTypeData, UTTypeItem, nil];
        NSArray<NSString *> *archiveTypeIDs = @[
            @"public.archive",
            @"public.zip-archive",
            @"com.pkware.zip-archive",
            @"org.debian.binary-package"
        ];
        for (NSString *typeID in archiveTypeIDs) {
            UTType *type = [UTType typeWithIdentifier:typeID];
            if (type) [types addObject:type];
        }
        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                                        asCopy:YES];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [self presentViewController:namePrompt animated:YES completion:nil];
}

- (void)presentSnowBoardLiteFormatGuide
{
    UIAlertController *guide = [UIAlertController
        alertControllerWithTitle:@"SnowBoard Lite Format"
                         message:@"Supported inputs: the bundled iOS 6 Theme, a local folder, a local .zip/.deb, or a direct .zip/.deb URL containing one or more IconBundles folders.\n\nOnly PNG files inside IconBundles are imported. Bundle-ID names work best, for example com.apple.mobilesafari.png or com.apple.MobileSMS-large@3x.png. Lite also maps common SnowBoard aliases such as Alipay, Taobao, Amap, AppStore, Settings, Messages, and Safari.\n\nNot supported in Lite: masks, overlays, Bundles resources, badges, dock/folder assets, UIImages, alternate icon hooks, ZIP64/encrypted ZIP, or data.tar.zst."
                  preferredStyle:UIAlertControllerStyleAlert];
    [guide addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:guide animated:YES completion:nil];
}

- (void)selectSnowBoardLiteBuiltinIOS6Theme
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:kSnowBoardLiteThemeBuiltinIOS6
          forKey:kSettingsSnowBoardLiteSelectedThemeID];
    [d synchronize];
    log_user("[SBL] Selected bundled iOS 6 Theme.\n");
    [self reloadSnowBoardLiteSectionAndQueue];
}

- (void)selectSnowBoardLiteThemeID:(NSString *)themeID
{
    if (themeID.length == 0) return;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:themeID forKey:kSettingsSnowBoardLiteSelectedThemeID];
    [d synchronize];
    log_user("[SBL] Selected theme: %s.\n",
             settings_snowboardlite_selected_theme_display_name().UTF8String);
    [self reloadSnowBoardLiteSectionAndQueue];
}

- (void)snowBoardLiteCarouselThemeTapped:(UIControl *)sender
{
    NSString *themeID = objc_getAssociatedObject(sender, "sblThemeID");
    if ([themeID isEqualToString:kSnowBoardLiteThemeBuiltinIOS6]) {
        [self selectSnowBoardLiteBuiltinIOS6Theme];
    } else {
        [self selectSnowBoardLiteThemeID:themeID];
    }
}

- (NSDictionary *)installedSnowBoardLiteOnlineThemeForItem:(NSDictionary *)item
{
    NSString *url = [item[@"url"] isKindOfClass:NSString.class] ? item[@"url"] : @"";
    NSString *title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"";
    for (NSDictionary *theme in settings_sbl_load_manifest()) {
        NSString *sourceURL = [theme[@"sourceURL"] isKindOfClass:NSString.class] ? theme[@"sourceURL"] : @"";
        if (url.length > 0 && [sourceURL caseInsensitiveCompare:url] == NSOrderedSame) {
            return theme;
        }

        NSString *name = [theme[@"name"] isKindOfClass:NSString.class] ? theme[@"name"] : @"";
        NSString *sourceName = [theme[@"sourceName"] isKindOfClass:NSString.class] ? theme[@"sourceName"] : @"";
        NSString *onlineTitle = [theme[@"onlineTitle"] isKindOfClass:NSString.class] ? theme[@"onlineTitle"] : @"";
        if (title.length > 0 &&
            ([name caseInsensitiveCompare:title] == NSOrderedSame ||
             [sourceName caseInsensitiveCompare:title] == NSOrderedSame ||
             [onlineTitle caseInsensitiveCompare:title] == NSOrderedSame)) {
            return theme;
        }
    }
    return nil;
}

- (void)snowBoardLiteOnlineDownloadTapped:(UIControl *)sender
{
    NSString *url = objc_getAssociatedObject(sender, "sblOnlineURL");
    NSString *name = objc_getAssociatedObject(sender, "sblOnlineName");
    NSString *installedThemeID = objc_getAssociatedObject(sender, "sblOnlineInstalledThemeID");
    if (installedThemeID.length > 0) {
        [self selectSnowBoardLiteThemeID:installedThemeID];
        [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    NSDictionary *installedTheme = [self installedSnowBoardLiteOnlineThemeForItem:@{
        @"url": url ?: @"",
        @"title": name ?: @"",
    }];
    NSString *liveInstalledThemeID = installedTheme[@"id"];
    if (liveInstalledThemeID.length > 0) {
        [self selectSnowBoardLiteThemeID:liveInstalledThemeID];
        [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    if (url.length == 0) return;
    [self startSnowBoardLiteThemeDownloadFromString:url
                                        displayName:(name.length ? name : @"Online Theme")];
}

- (void)refreshSnowBoardLiteOnlineDownloadsPopup
{
    UIStackView *stack = self.sblOnlineDownloadsStack;
    if (!stack) return;

    for (UIView *view in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *item in [self snowBoardLiteOnlineDownloadItems]) {
        [stack addArrangedSubview:[self snowBoardLiteOnlineDownloadCardForItem:item]];
    }
    [stack setNeedsLayout];
    [stack.superview setNeedsLayout];
}

- (void)presentSnowBoardLiteOnlineDownloads
{
    UIViewController *sheet = [[UIViewController alloc] init];
    sheet.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    sheet.preferredContentSize = CGSizeMake(420.0, 680.0);
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *presentation = sheet.sheetPresentationController;
        presentation.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent,
        ];
        presentation.prefersGrabberVisible = YES;
        presentation.preferredCornerRadius = 26.0;
    }

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Online Downloads";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    [sheet.view addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Preview curated SnowBoard themes before downloading.";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    subtitle.numberOfLines = 2;
    [sheet.view addSubview:subtitle];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.tintColor = UIColor.secondaryLabelColor;
    close.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    close.layer.cornerRadius = 17.0;
    close.layer.cornerCurve = kCACornerCurveContinuous;
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    __weak UIViewController *weakSheet = sheet;
    [close addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        (void)action;
        [weakSheet dismissViewControllerAnimated:YES completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [sheet.view addSubview:close];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    [sheet.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [scroll addSubview:stack];
    self.sblOnlineDownloadsStack = stack;

    for (NSDictionary *item in [self snowBoardLiteOnlineDownloadItems]) {
        [stack addArrangedSubview:[self snowBoardLiteOnlineDownloadCardForItem:item]];
    }

    UILayoutGuide *safe = sheet.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18.0],

        [close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18.0],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:34.0],
        [close.heightAnchor constraintEqualToConstant:34.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],

        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14.0],
        [scroll.bottomAnchor constraintEqualToAnchor:sheet.view.bottomAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:14.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-14.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-22.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-28.0],
    ]];

    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentSnowBoardLiteRemoveConfirmationForThemeID:(NSString *)themeID
                                                   title:(NSString *)title
{
    if (themeID.length == 0 ||
        [themeID isEqualToString:kSnowBoardLiteThemeBuiltinIOS6]) {
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Remove Theme?"
                         message:[NSString stringWithFormat:@"Remove \"%@\" from the SnowBoard Lite library?", title.length ? title : @"Imported Theme"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        (void)a;
        [self removeSnowBoardLiteThemeID:themeID];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)renameSnowBoardLiteThemeID:(NSString *)themeID toName:(NSString *)name
{
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (themeID.length == 0 || trimmed.length == 0) return;

    NSArray<NSDictionary *> *themes = settings_sbl_load_manifest();
    NSMutableArray<NSDictionary *> *next = [NSMutableArray arrayWithCapacity:themes.count];
    BOOL renamed = NO;
    for (NSDictionary *theme in themes) {
        if ([theme[@"id"] isEqualToString:themeID]) {
            NSMutableDictionary *copy = [theme mutableCopy];
            copy[@"name"] = trimmed;
            [next addObject:copy];
            renamed = YES;
        } else {
            [next addObject:theme];
        }
    }
    if (!renamed) return;
    if (!settings_sbl_save_manifest(next)) {
        log_user("[SBL] Failed to rename imported theme.\n");
        return;
    }

    log_user("[SBL] Renamed theme to \"%s\".\n", trimmed.UTF8String);
    [self reloadSnowBoardLiteSectionAndQueue];
}

- (void)presentSnowBoardLiteRenamePromptForThemeID:(NSString *)themeID
                                             title:(NSString *)title
{
    if (themeID.length == 0 ||
        [themeID isEqualToString:kSnowBoardLiteThemeBuiltinIOS6]) {
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Rename Theme"
                         message:@"Set the display name shown in SnowBoard Lite."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = title ?: @"";
        field.placeholder = @"Theme name";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        [self renameSnowBoardLiteThemeID:themeID
                                  toName:alert.textFields.firstObject.text ?: @""];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentSnowBoardLiteThemeInfo:(NSDictionary *)item
{
    NSString *title = item[@"title"] ?: @"Theme";
    BOOL builtIn = [item[@"builtIn"] boolValue];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Source: %@",
                      [self snowBoardLiteSourceBadgeText:item[@"sourceType"]]]];
    [lines addObject:[NSString stringWithFormat:@"Icons: %@", item[@"iconCount"] ?: @0]];
    if (!builtIn) {
        NSString *importedAt = item[@"importedAt"] ?: @"";
        if (importedAt.length > 0) {
            [lines addObject:[NSString stringWithFormat:@"Imported: %@", importedAt]];
        }
        [lines addObject:[NSString stringWithFormat:@"IconBundles: %@", item[@"iconBundlesCount"] ?: @0]];
        [lines addObject:[NSString stringWithFormat:@"Aliases: %@", item[@"aliasMappedCount"] ?: @0]];
        [lines addObject:[NSString stringWithFormat:@"Skipped: %@", item[@"skippedCount"] ?: @0]];
        [lines addObject:[NSString stringWithFormat:@"Duplicates: %@", item[@"duplicateCount"] ?: @0]];
        NSArray *samples = [item[@"skippedSamples"] isKindOfClass:NSArray.class]
            ? item[@"skippedSamples"] : @[];
        if (samples.count > 0) {
            NSUInteger count = MIN(samples.count, 4);
            [lines addObject:[NSString stringWithFormat:@"Skipped sample: %@",
                              [[samples subarrayWithRange:NSMakeRange(0, count)]
                               componentsJoinedByString:@", "]]];
        }
    } else {
        [lines addObject:@"Built into Cyanide; cannot be renamed or removed."];
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:[lines componentsJoinedByString:@"\n"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                      configurationForMenuAtLocation:(CGPoint)location
{
    (void)location;
    NSDictionary *item = objc_getAssociatedObject(interaction.view, "sblThemeItem");
    if (![item isKindOfClass:NSDictionary.class]) return nil;

    NSString *themeID = item[@"id"] ?: @"";
    NSString *title = item[@"title"] ?: @"Theme";
    BOOL builtIn = [item[@"builtIn"] boolValue];

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                     previewProvider:nil
                      actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        (void)suggestedActions;

        UIAction *activate = [UIAction actionWithTitle:@"Set Active"
                                                 image:[UIImage systemImageNamed:@"checkmark.circle.fill"]
                                            identifier:nil
                                               handler:^(__kindof UIAction *action) {
            (void)action;
            if ([themeID isEqualToString:kSnowBoardLiteThemeBuiltinIOS6]) {
                [self selectSnowBoardLiteBuiltinIOS6Theme];
            } else {
                [self selectSnowBoardLiteThemeID:themeID];
            }
        }];

        UIAction *info = [UIAction actionWithTitle:@"Show Info"
                                             image:[UIImage systemImageNamed:@"info.circle"]
                                        identifier:nil
                                           handler:^(__kindof UIAction *action) {
            (void)action;
            [self presentSnowBoardLiteThemeInfo:item];
        }];

        if (builtIn) {
            return [UIMenu menuWithTitle:title children:@[activate, info]];
        }

        UIAction *rename = [UIAction actionWithTitle:@"Rename"
                                               image:[UIImage systemImageNamed:@"pencil"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
            (void)action;
            [self presentSnowBoardLiteRenamePromptForThemeID:themeID title:title];
        }];

        UIAction *remove = [UIAction actionWithTitle:@"Delete"
                                               image:[UIImage systemImageNamed:@"trash"]
                                          identifier:nil
                                             handler:^(__kindof UIAction *action) {
            (void)action;
            [self presentSnowBoardLiteRemoveConfirmationForThemeID:themeID title:title];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;

        return [UIMenu menuWithTitle:title children:@[activate, rename, info, remove]];
    }];
}

- (void)snowBoardLiteToolButtonTapped:(UIButton *)sender
{
    NSString *action = objc_getAssociatedObject(sender, "sblAction");
    if ([action isEqualToString:@"sbl-import"]) {
        [self presentSnowBoardLiteImporter];
    } else if ([action isEqualToString:@"sbl-import-url"]) {
        [self promptSnowBoardLiteThemeURL];
    } else if ([action isEqualToString:@"sbl-online"]) {
        [self presentSnowBoardLiteOnlineDownloads];
    } else if ([action isEqualToString:@"sbl-guide"]) {
        [self presentSnowBoardLiteFormatGuide];
    }
}

- (void)scrollToSnowBoardLiteOnlineDownloads
{
    NSArray<NSDictionary *> *rows = [self rowsForSection:SectionSnowBoardLite];
    NSInteger targetRow = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        if ([rows[i][@"kind"] isEqualToString:@"sbl-online"]) {
            targetRow = i;
            break;
        }
    }
    if (targetRow == NSNotFound) return;

    NSInteger tableSection = (self.detailMode && self.underlyingSection == SectionSnowBoardLite)
        ? 0
        : SectionSnowBoardLite;
    if (tableSection >= [self.tableView numberOfSections] ||
        targetRow >= [self.tableView numberOfRowsInSection:tableSection]) {
        return;
    }

    NSIndexPath *path = [NSIndexPath indexPathForRow:targetRow inSection:tableSection];
    [self.tableView scrollToRowAtIndexPath:path
                          atScrollPosition:UITableViewScrollPositionTop
                                  animated:YES];
}

- (void)clearSnowBoardLiteSelectedTheme
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setObject:@"" forKey:kSettingsSnowBoardLiteSelectedThemeID];
    if ([d boolForKey:kSettingsSnowBoardLiteEnabled]) {
        [d setBool:NO forKey:kSettingsSnowBoardLiteEnabled];
        g_themer_live_stop_requested = 1;
    }
    [d synchronize];
    log_user("[SBL] Cleared active theme; SnowBoard Lite is no longer queued.\n");
    [self reloadSnowBoardLiteSectionAndQueue];
}

- (void)removeSnowBoardLiteThemeID:(NSString *)themeID
{
    if (themeID.length == 0) return;
    NSArray<NSDictionary *> *themes = settings_sbl_load_manifest();
    NSMutableArray<NSDictionary *> *next = [NSMutableArray array];
    NSDictionary *removed = nil;
    for (NSDictionary *theme in themes) {
        if ([theme[@"id"] isEqualToString:themeID]) {
            removed = theme;
        } else {
            [next addObject:theme];
        }
    }
    if (!removed) return;

    NSMutableOrderedSet<NSString *> *deleteCandidates = [NSMutableOrderedSet orderedSet];
    NSString *path = removed[@"path"];
    if (path.length > 0) [deleteCandidates addObject:path];
    NSString *iconsPath = removed[@"iconsPath"];
    if (iconsPath.length > 0) [deleteCandidates addObject:iconsPath.stringByDeletingLastPathComponent];
    NSString *root = settings_sbl_themes_root_for_ui();
    if (root.length > 0) [deleteCandidates addObject:[root stringByAppendingPathComponent:themeID]];

    BOOL removedFiles = NO;
    for (NSString *candidate in deleteCandidates) {
        if (settings_sbl_remove_theme_dir_if_safe(candidate)) {
            removedFiles = YES;
        }
    }
    settings_sbl_save_manifest(next);

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([[d stringForKey:kSettingsSnowBoardLiteSelectedThemeID] isEqualToString:themeID]) {
        [d setObject:@"" forKey:kSettingsSnowBoardLiteSelectedThemeID];
        if ([d boolForKey:kSettingsSnowBoardLiteEnabled]) {
            [d setBool:NO forKey:kSettingsSnowBoardLiteEnabled];
            g_themer_live_stop_requested = 1;
        }
        [d synchronize];
    }
    log_user("[SBL] Removed imported theme: %s%s.\n",
             [removed[@"name"] UTF8String] ?: "unknown",
             removedFiles ? "" : " (manifest only)");
    [self reloadSnowBoardLiteSectionAndQueue];
}

- (void)presentSnowBoardLiteRemoveThemePicker
{
    NSArray<NSDictionary *> *themes = settings_sbl_load_manifest();
    if (themes.count == 0) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Remove Theme"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *theme in themes) {
        NSString *themeID = theme[@"id"];
        NSString *name = theme[@"name"] ?: @"Imported Theme";
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *_) {
            [self removeSnowBoardLiteThemeID:themeID];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = self.tableView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)livewpPreviewToggle:(UIButton *)btn
{
    id player = objc_getAssociatedObject(btn, "livewp_btn_player");
    if (!player) return;

    // 用 NSInvocation 获取 rate（float，不是对象）
    float rate = 0;
    NSMethodSignature *sig = [player methodSignatureForSelector:@selector(rate)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:player]; [inv setSelector:@selector(rate)];
    [inv invoke];
    [inv getReturnValue:&rate];

    if (rate > 0) {
        [player performSelector:@selector(pause)];
        [btn setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    } else {
        [player performSelector:@selector(play)];
        [btn setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
    }
}

- (void)livewpPreviewReplay:(UIButton *)btn
{
    id item = objc_getAssociatedObject(btn, "livewp_btn_item");
    id player = objc_getAssociatedObject(btn, "livewp_btn_player");
    UIButton *playBtn = objc_getAssociatedObject(btn, "livewp_btn_play");
    if (!item || !player) return;

    NSMutableData *zeroTime = [NSMutableData dataWithLength:24];
    int32_t timescale = 1;
    uint32_t flags = 0x1;
    [zeroTime replaceBytesInRange:NSMakeRange(8, 4) withBytes:&timescale];
    [zeroTime replaceBytesInRange:NSMakeRange(12, 4) withBytes:&flags];

    NSMethodSignature *sig = [item methodSignatureForSelector:@selector(seekToTime:)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:item];
    [inv setSelector:@selector(seekToTime:)];
    [inv setArgument:(void *)zeroTime.bytes atIndex:2];
    [inv invoke];

    [player performSelector:@selector(play)];
    [playBtn setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
}

- (void)showLiveWPVideoPicker
{
    // Create document picker for video files
    NSArray *videoTypes = @[
        [UTType typeWithFilenameExtension:@"mp4"],
        [UTType typeWithFilenameExtension:@"mov"],
        [UTType typeWithFilenameExtension:@"m4v"]
    ];

    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:videoTypes
                                                                    asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)livewpOnlineCatalogues
{
    return @[
        // @{ @"title": @"MyLiveWallpapers",      @"url": @"https://mylivewallpapers.com" },
        @{ @"title": @"LiveWallpapers4Free",   @"url": @"https://livewallpapers4free.com" },
        @{ @"title": @"LiveWallP",             @"url": @"https://livewallp.com" },
        @{ @"title": @"MotionBGS Mobile",      @"url": @"https://motionbgs.com/mobile/" },
    ];
}

- (void)openLiveWPCatalogueAtIndex:(NSInteger)index
{
    NSArray<NSDictionary<NSString *, NSString *> *> *catalogues = [self livewpOnlineCatalogues];
    if (catalogues.count == 0) return;
    CyanideLiveWPBrowserViewController *browser =
        [[CyanideLiveWPBrowserViewController alloc] initWithCatalogues:catalogues
                                                         selectedIndex:index];
    __weak typeof(self) weakSelf = self;
    browser.downloadHandler = ^(NSURLRequest *downloadRequest) {
        [weakSelf startLiveWPVideoDownloadWithRequest:downloadRequest];
    };
    browser.closeHandler = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self restoreSettingsInteractionAfterModal];
        if (self.detailMode) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        } else {
            [self.tableView reloadData];
        }
    };
    browser.modalPresentationStyle = UIModalPresentationPageSheet;
    browser.presentationController.delegate = browser;
    [self presentViewController:browser animated:YES completion:nil];
}

- (void)showLiveWPOnlineDownloader
{
    [self openLiveWPCatalogueAtIndex:0];
}

- (void)promptLiveWPVideoURL
{
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"Download Video"
                                            message:@"Paste a direct MP4, MOV, or M4V URL."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/video.mp4";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Download"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        NSString *raw = ac.textFields.firstObject.text ?: @"";
        [self startLiveWPVideoDownloadFromString:raw];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (NSString *)livewpSafeDownloadedVideoNameFromURL:(NSURL *)url response:(NSURLResponse *)response
{
    NSString *name = response.suggestedFilename.length ? response.suggestedFilename : url.lastPathComponent;
    if (!name.length) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyyMMdd-HHmmss";
        name = [NSString stringWithFormat:@"LiveWP-%@.mp4", [fmt stringFromDate:[NSDate date]]];
    }

    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    NSArray<NSString *> *parts = [name componentsSeparatedByCharactersInSet:bad];
    name = [[parts componentsJoinedByString:@"-"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) name = @"LiveWP-Download.mp4";

    NSString *ext = name.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:ext]) {
        NSString *mime = response.MIMEType.lowercaseString ?: @"";
        NSString *fallbackExt = [mime containsString:@"quicktime"] ? @"mov" : @"mp4";
        name = [[name stringByDeletingPathExtension] stringByAppendingPathExtension:fallbackExt];
    }
    return name;
}

- (NSString *)livewpDownloadsDirectoryCreating:(BOOL)create error:(NSError **)error
{
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *downloadsDir = [[docsPath stringByAppendingPathComponent:@"LiveWP"] stringByAppendingPathComponent:@"Downloads"];
    if (create) {
        [[NSFileManager defaultManager] createDirectoryAtPath:downloadsDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error];
    }
    return downloadsDir;
}

- (NSString *)uniqueLiveWPDownloadPathForFileName:(NSString *)fileName inDirectory:(NSString *)downloadsDir
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = fileName.stringByDeletingPathExtension.length ? fileName.stringByDeletingPathExtension : @"LiveWP-Download";
    NSString *ext = fileName.pathExtension.length ? fileName.pathExtension : @"mp4";
    NSString *candidate = [downloadsDir stringByAppendingPathComponent:[base stringByAppendingPathExtension:ext]];
    NSInteger index = 2;
    while ([fm fileExistsAtPath:candidate]) {
        NSString *next = [NSString stringWithFormat:@"%@-%ld", base, (long)index++];
        candidate = [downloadsDir stringByAppendingPathComponent:[next stringByAppendingPathExtension:ext]];
    }
    return candidate;
}

- (BOOL)saveLiveWPDownloadedVideoAtURL:(NSURL *)url
                     preferredFileName:(NSString *)preferredFileName
                         savedFileName:(NSString **)savedFileName
                                 error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *downloadsDir = [self livewpDownloadsDirectoryCreating:YES error:error];
    if (error && *error) return NO;

    NSString *fileName = preferredFileName.length ? preferredFileName : url.lastPathComponent;
    if (!fileName.length) fileName = @"LiveWP-Download.mp4";
    NSString *ext = fileName.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:ext]) {
        fileName = [[fileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"];
    }

    NSString *destPath = [self uniqueLiveWPDownloadPathForFileName:fileName inDirectory:downloadsDir];
    if (![fm copyItemAtPath:url.path toPath:destPath error:error]) {
        return NO;
    }

    NSDictionary *attrs = [fm attributesOfItemAtPath:destPath error:nil];
    double mb = attrs ? [attrs fileSize] / (1024.0 * 1024.0) : 0.0;
    if (savedFileName) *savedFileName = destPath.lastPathComponent;
    log_user("[LIVEWP] Download saved for manual import: %s (%.1f MB)\n",
             destPath.lastPathComponent.UTF8String,
             mb);
    return YES;
}

- (void)finishLiveWPVideoImportAndSwapIfRunning
{
    if (self.detailMode) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [self.tableView reloadData];
    }

    BOOL applied = settings_tweak_is_applied(kSettingsLiveWPEnabled);
    log_user("[LIVEWP] import: applied=%d rc_ready=%d\n", applied, g_springboard_rc_ready);
    if (applied && g_springboard_rc_ready) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @synchronized (settings_rc_lock()) {
                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                NSString *absPath = livewp_absolute_path();
                log_user("[LIVEWP] import: swap path=%s\n", absPath ? absPath.UTF8String : "(nil)");
                if (absPath) livewp_swap_video_in_session(absPath);
            }
        });
    }
}

- (void)startLiveWPVideoDownloadFromString:(NSString *)rawURL
{
    NSString *trimmed = [rawURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = [NSURL URLWithString:trimmed];
    if (!url || !([url.scheme.lowercaseString isEqualToString:@"https"] ||
                  [url.scheme.lowercaseString isEqualToString:@"http"])) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Invalid URL"
                                                                     message:@"Enter a valid http or https video URL."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    [self startLiveWPVideoDownloadFromURL:url];
}

- (UIViewController *)livewpPresentationHost
{
    UIViewController *host = self;
    while (host.presentedViewController &&
           ![host.presentedViewController isBeingDismissed] &&
           ![host.presentedViewController isKindOfClass:CyanideLiveWPDownloadProgressViewController.class]) {
        host = host.presentedViewController;
    }
    return host;
}

- (void)startLiveWPVideoDownloadFromURL:(NSURL *)url
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [self startLiveWPVideoDownloadWithRequest:request];
}

- (NSMutableURLRequest *)normalizedLiveWPDownloadRequest:(NSURLRequest *)request
{
    NSMutableURLRequest *native = [request mutableCopy];
    if (!native) return nil;
    native.HTTPMethod = @"GET";
    native.HTTPBody = nil;
    native.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    native.timeoutInterval = 30.0;
    if (![native valueForHTTPHeaderField:@"User-Agent"]) {
        [native setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
      forHTTPHeaderField:@"User-Agent"];
    }
    if (![native valueForHTTPHeaderField:@"Accept"]) {
        [native setValue:@"video/*,*/*;q=0.8" forHTTPHeaderField:@"Accept"];
    }
    if (![native valueForHTTPHeaderField:@"Accept-Language"]) {
        [native setValue:[NSLocale preferredLanguages].firstObject ?: @"en-US" forHTTPHeaderField:@"Accept-Language"];
    }
    return native;
}

- (void)startLiveWPVideoDownloadWithRequest:(NSURLRequest *)request
{
    NSMutableURLRequest *nativeRequest = [self normalizedLiveWPDownloadRequest:request];
    NSURL *url = nativeRequest.URL;
    if (!url || !([url.scheme.lowercaseString isEqualToString:@"https"] ||
                  [url.scheme.lowercaseString isEqualToString:@"http"])) {
        return;
    }
    if (self.livewpDownloadTask) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Download Already Running"
                                                                     message:@"Cancel the current LiveWP download before starting another one."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self livewpPresentationHost] presentViewController:err animated:YES completion:nil];
        return;
    }

    self.livewpDownloadURL = url;
    self.livewpDownloadRequest = nativeRequest;
    CyanideLiveWPDownloadProgressViewController *progress = [[CyanideLiveWPDownloadProgressViewController alloc] init];
    progress.modalPresentationStyle = UIModalPresentationOverFullScreen;
    progress.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    __weak typeof(self) weakSelf = self;
    progress.cancelHandler = ^{
        [weakSelf cancelLiveWPVideoDownload];
    };
    self.livewpDownloadProgressController = progress;

    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 30.0;
    cfg.timeoutIntervalForResource = 600.0;
    self.livewpDownloadSession = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.livewpDownloadTask = [self.livewpDownloadSession downloadTaskWithRequest:nativeRequest];

    [[self livewpPresentationHost] presentViewController:progress animated:YES completion:^{
        [progress updateWithReceivedBytes:0 expectedBytes:0 host:url.host];
        [self.livewpDownloadTask resume];
        log_user("[LIVEWP] Download started: %s\n", url.absoluteString.UTF8String);
    }];
}

- (void)cancelLiveWPVideoDownload
{
    [self.livewpDownloadTask cancel];
    [self.livewpDownloadSession invalidateAndCancel];
    CyanideLiveWPDownloadProgressViewController *progress = self.livewpDownloadProgressController;
    self.livewpDownloadTask = nil;
    self.livewpDownloadSession = nil;
    self.livewpDownloadProgressController = nil;
    self.livewpDownloadURL = nil;
    self.livewpDownloadRequest = nil;
    [self dismissLiveWPDownloadProgressController:progress completion:nil];
    log_user("[LIVEWP] Download cancelled\n");
}

- (void)dismissLiveWPDownloadProgressController:(CyanideLiveWPDownloadProgressViewController *)progress
                                     completion:(dispatch_block_t)completion
{
    void (^finish)(void) = ^{
        self.view.userInteractionEnabled = YES;
        self.tableView.userInteractionEnabled = YES;
        if (completion) completion();
    };

    if (!progress) {
        finish();
        return;
    }

    progress.view.userInteractionEnabled = NO;
    progress.view.hidden = YES;
    if (progress.presentingViewController) {
        [progress dismissViewControllerAnimated:YES completion:finish];
    } else {
        finish();
    }
}

- (void)showLiveWPToast:(NSString *)message
{
    if (!message.length) return;
    UIViewController *host = [self livewpPresentationHost];
    UIView *container = host.view ?: self.view;
    if (!container) return;

    UILabel *toast = [[UILabel alloc] init];
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.text = [NSString stringWithFormat:@"  %@  ", message];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.textColor = UIColor.whiteColor;
    toast.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    toast.numberOfLines = 2;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
    toast.layer.cornerRadius = 14.0;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    toast.clipsToBounds = YES;
    toast.alpha = 0.0;
    toast.userInteractionEnabled = NO;
    [container addSubview:toast];

    UILayoutGuide *safe = container.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [toast.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-24.0],
        [toast.widthAnchor constraintLessThanOrEqualToAnchor:container.widthAnchor multiplier:0.82],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:24.0],
        [toast.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
    ]];

    [UIView animateWithDuration:0.18 animations:^{
        toast.alpha = 1.0;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.22 delay:1.4 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            toast.alpha = 0.0;
        } completion:^(__unused BOOL done) {
            [toast removeFromSuperview];
        }];
    }];
}

- (void)finishLiveWPVideoDownloadWithErrorTitle:(NSString *)title message:(NSString *)message
{
    CyanideLiveWPDownloadProgressViewController *progress = self.livewpDownloadProgressController;
    self.livewpDownloadTask = nil;
    [self.livewpDownloadSession finishTasksAndInvalidate];
    self.livewpDownloadSession = nil;
    self.livewpDownloadProgressController = nil;
    self.livewpDownloadURL = nil;
    self.livewpDownloadRequest = nil;

    [self dismissLiveWPDownloadProgressController:progress completion:^{
        UIAlertController *err = [UIAlertController alertControllerWithTitle:title
                                                                     message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self livewpPresentationHost] presentViewController:err animated:YES completion:nil];
    }];
}

- (void)finishSuccessfulLiveWPVideoDownloadWithFileName:(NSString *)fileName
{
    CyanideLiveWPDownloadProgressViewController *progress = self.livewpDownloadProgressController;
    self.livewpDownloadTask = nil;
    [self.livewpDownloadSession finishTasksAndInvalidate];
    self.livewpDownloadSession = nil;
    self.livewpDownloadProgressController = nil;
    self.livewpDownloadURL = nil;
    self.livewpDownloadRequest = nil;

    [self dismissLiveWPDownloadProgressController:progress completion:^{
        NSString *toast = fileName.length
            ? [NSString stringWithFormat:@"Saved to LiveWP/Downloads/%@", fileName]
            : @"Saved to LiveWP/Downloads";
        [self restoreSettingsInteractionAfterModal];
        [self showLiveWPToast:toast];
        log_user("[LIVEWP] Download finished; saved for manual import.\n");
    }];
}

- (void)promptSnowBoardLiteThemeURL
{
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"Download Theme"
                                            message:@"Name this theme and paste a direct .zip or .deb URL that contains IconBundles."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Theme name";
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"https://example.com/theme.zip";
        textField.keyboardType = UIKeyboardTypeURL;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Download"
                                           style:UIAlertActionStyleDefault
                                         handler:^(__unused UIAlertAction *action) {
        NSString *name = ac.textFields.firstObject.text ?: @"";
        NSString *raw = ac.textFields.count > 1 ? (ac.textFields[1].text ?: @"") : @"";
        [self startSnowBoardLiteThemeDownloadFromString:raw displayName:name];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)startSnowBoardLiteThemeDownloadFromString:(NSString *)rawURL
{
    [self startSnowBoardLiteThemeDownloadFromString:rawURL displayName:nil];
}

- (void)startSnowBoardLiteThemeDownloadFromString:(NSString *)rawURL displayName:(NSString *)displayName
{
    NSString *trimmed = [rawURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *trimmedName = [displayName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = [NSURL URLWithString:trimmed];
    if (!url || !([url.scheme.lowercaseString isEqualToString:@"https"] ||
                  [url.scheme.lowercaseString isEqualToString:@"http"])) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Invalid URL"
                                                                     message:@"Enter a valid http or https theme archive URL."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [self startSnowBoardLiteThemeDownloadWithRequest:request displayName:trimmedName];
}

- (NSMutableURLRequest *)normalizedSnowBoardLiteDownloadRequest:(NSURLRequest *)request
{
    NSMutableURLRequest *native = [request mutableCopy];
    if (!native) return nil;
    native.HTTPMethod = @"GET";
    native.HTTPBody = nil;
    native.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    native.timeoutInterval = 30.0;
    if (![native valueForHTTPHeaderField:@"User-Agent"]) {
        [native setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
      forHTTPHeaderField:@"User-Agent"];
    }
    if (![native valueForHTTPHeaderField:@"Accept"]) {
        [native setValue:@"application/zip,application/vnd.debian.binary-package,application/x-debian-package,application/octet-stream,*/*;q=0.8"
      forHTTPHeaderField:@"Accept"];
    }
    if (![native valueForHTTPHeaderField:@"Accept-Language"]) {
        [native setValue:[NSLocale preferredLanguages].firstObject ?: @"en-US"
      forHTTPHeaderField:@"Accept-Language"];
    }
    return native;
}

- (void)startSnowBoardLiteThemeDownloadWithRequest:(NSURLRequest *)request
{
    [self startSnowBoardLiteThemeDownloadWithRequest:request displayName:nil];
}

- (void)startSnowBoardLiteThemeDownloadWithRequest:(NSURLRequest *)request displayName:(NSString *)displayName
{
    NSMutableURLRequest *nativeRequest = [self normalizedSnowBoardLiteDownloadRequest:request];
    NSURL *url = nativeRequest.URL;
    if (!url || !([url.scheme.lowercaseString isEqualToString:@"https"] ||
                  [url.scheme.lowercaseString isEqualToString:@"http"])) {
        return;
    }
    if (self.sblDownloadTask) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Download Already Running"
                                                                     message:@"Cancel the current SnowBoard Lite download before starting another one."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
        [[self livewpPresentationHost] presentViewController:err animated:YES completion:nil];
        return;
    }

    self.sblDownloadDisplayName = displayName;
    self.sblDownloadURL = url;
    self.sblDownloadRequest = nativeRequest;
    CyanideLiveWPDownloadProgressViewController *progress = [[CyanideLiveWPDownloadProgressViewController alloc] init];
    progress.titleText = @"Downloading Theme";
    progress.savingStatusText = @"Downloading SnowBoard Lite theme";
    progress.iconSymbolName = @"archivebox.fill";
    progress.accentColor = UIColor.systemMintColor;
    progress.modalPresentationStyle = UIModalPresentationOverFullScreen;
    progress.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    __weak typeof(self) weakSelf = self;
    progress.cancelHandler = ^{
        [weakSelf cancelSnowBoardLiteThemeDownload];
    };
    self.sblDownloadProgressController = progress;

    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.timeoutIntervalForRequest = 30.0;
    cfg.timeoutIntervalForResource = 600.0;
    self.sblDownloadSession = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:nil];
    self.sblDownloadTask = [self.sblDownloadSession downloadTaskWithRequest:nativeRequest];

    [[self livewpPresentationHost] presentViewController:progress animated:YES completion:^{
        [progress updateWithReceivedBytes:0 expectedBytes:0 host:url.host];
        [self.sblDownloadTask resume];
        log_user("[SBL] Theme download started: %s\n", url.absoluteString.UTF8String);
    }];
}

- (void)cancelSnowBoardLiteThemeDownload
{
    [self.sblDownloadTask cancel];
    [self.sblDownloadSession invalidateAndCancel];
    CyanideLiveWPDownloadProgressViewController *progress = self.sblDownloadProgressController;
    self.sblDownloadTask = nil;
    self.sblDownloadSession = nil;
    self.sblDownloadProgressController = nil;
    self.sblDownloadURL = nil;
    self.sblDownloadRequest = nil;
    self.sblDownloadDisplayName = nil;
    [self dismissLiveWPDownloadProgressController:progress completion:nil];
    log_user("[SBL] Theme download cancelled\n");
}

- (void)presentSnowBoardLiteLocalImportLoadingWithCompletion:(dispatch_block_t)completion
{
    CyanideCenteredLoadingViewController *loading = [[CyanideCenteredLoadingViewController alloc] init];
    loading.titleText = @"Importing Theme";
    loading.statusText = @"Extracting archive and scanning IconBundles";
    loading.iconSymbolName = @"archivebox.fill";
    loading.accentColor = UIColor.systemMintColor;
    loading.modalPresentationStyle = UIModalPresentationOverFullScreen;
    loading.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    self.sblLocalImportLoadingController = loading;
    [[self livewpPresentationHost] presentViewController:loading animated:YES completion:completion];
}

- (void)dismissSnowBoardLiteLocalImportLoadingWithCompletion:(dispatch_block_t)completion
{
    CyanideCenteredLoadingViewController *loading = self.sblLocalImportLoadingController;
    self.sblLocalImportLoadingController = nil;
    if (!loading) {
        if (completion) completion();
        return;
    }
    loading.view.userInteractionEnabled = NO;
    if (loading.presentingViewController) {
        [loading dismissViewControllerAnimated:YES completion:completion];
    } else if (completion) {
        completion();
    }
}

- (NSString *)sblSafeDownloadedThemeNameFromURL:(NSURL *)url response:(NSURLResponse *)response
{
    NSString *name = response.suggestedFilename.length ? response.suggestedFilename : url.lastPathComponent;
    if (!name.length) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyyMMdd-HHmmss";
        name = [NSString stringWithFormat:@"SnowBoardLite-%@.zip", [fmt stringFromDate:[NSDate date]]];
    }

    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    NSArray<NSString *> *parts = [name componentsSeparatedByCharactersInSet:bad];
    name = [[parts componentsJoinedByString:@"-"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length) name = @"SnowBoardLite-Theme.zip";
    return name;
}

- (BOOL)importSnowBoardLiteArchiveAtURL:(NSURL *)url
                            displayName:(NSString *)displayName
                             sourceType:(NSString *)sourceType
                                  error:(NSError **)error
{
    static const unsigned long long kSnowBoardLiteMaxArchiveBytes = 200ULL * 1024ULL * 1024ULL;
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
    if (!attrs) return NO;
    unsigned long long fileSize = attrs.fileSize;
    if (fileSize > kSnowBoardLiteMaxArchiveBytes) {
        if (error) {
            NSString *message = [NSString stringWithFormat:
                @"SnowBoard Lite archive is %@. Maximum supported size is 200 MB.",
                settings_livewp_file_size_text(fileSize)];
            *error = [NSError errorWithDomain:@"SnowBoardLite"
                                         code:200
                                     userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    NSString *tmpName = [NSString stringWithFormat:@"sbl-download-extract-%llu",
                         (unsigned long long)(NSDate.date.timeIntervalSince1970 * 1000.0)];
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:tmpName];
    BOOL ok = SBLExtractArchiveToDirectory(url, tmp, error);
    if (ok) {
        ok = settings_sbl_import_folder_theme_named([NSURL fileURLWithPath:tmp],
                                                    displayName.length ? displayName : @"Downloaded Theme",
                                                    sourceType.length ? sourceType : @"url",
                                                    error);
    }
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    return ok;
}

- (BOOL)markSelectedSnowBoardLiteThemeWithSourceURLString:(NSString *)sourceURLString
                                             onlineTitle:(NSString *)onlineTitle
{
    NSString *sourceURL = [sourceURLString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (sourceURL.length == 0) return NO;

    NSString *selectedID = [NSUserDefaults.standardUserDefaults
        stringForKey:kSettingsSnowBoardLiteSelectedThemeID];
    if (selectedID.length == 0) return NO;

    NSArray<NSDictionary *> *themes = settings_sbl_load_manifest();
    NSMutableArray<NSDictionary *> *next = [NSMutableArray arrayWithCapacity:themes.count];
    BOOL changed = NO;
    for (NSDictionary *theme in themes) {
        if (!changed && [theme[@"id"] isEqualToString:selectedID]) {
            NSMutableDictionary *updated = [theme mutableCopy];
            updated[@"sourceURL"] = sourceURL;
            if (onlineTitle.length > 0) {
                updated[@"onlineTitle"] = onlineTitle;
            }
            [next addObject:updated];
            changed = YES;
        } else {
            [next addObject:theme];
        }
    }
    return changed ? settings_sbl_save_manifest(next) : NO;
}

- (void)finishSnowBoardLiteThemeDownloadWithErrorTitle:(NSString *)title message:(NSString *)message
{
    CyanideLiveWPDownloadProgressViewController *progress = self.sblDownloadProgressController;
    self.sblDownloadTask = nil;
    [self.sblDownloadSession finishTasksAndInvalidate];
    self.sblDownloadSession = nil;
    self.sblDownloadProgressController = nil;
    self.sblDownloadURL = nil;
    self.sblDownloadRequest = nil;
    self.sblDownloadDisplayName = nil;

    [self dismissLiveWPDownloadProgressController:progress completion:^{
        UIAlertController *err = [UIAlertController alertControllerWithTitle:title
                                                                     message:message
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK"
                                                style:UIAlertActionStyleDefault
                                              handler:nil]];
        [[self livewpPresentationHost] presentViewController:err animated:YES completion:nil];
    }];
}

- (void)finishSuccessfulSnowBoardLiteThemeDownloadWithName:(NSString *)name
{
    CyanideLiveWPDownloadProgressViewController *progress = self.sblDownloadProgressController;
    self.sblDownloadTask = nil;
    [self.sblDownloadSession finishTasksAndInvalidate];
    self.sblDownloadSession = nil;
    self.sblDownloadProgressController = nil;
    self.sblDownloadURL = nil;
    self.sblDownloadRequest = nil;
    self.sblDownloadDisplayName = nil;

    [self dismissLiveWPDownloadProgressController:progress completion:^{
        [self reloadSnowBoardLiteSectionAndQueue];
        [self refreshSnowBoardLiteOnlineDownloadsPopup];
        NSDictionary *theme = settings_sbl_selected_theme();
        NSString *themeName = settings_snowboardlite_selected_theme_display_name();
        NSNumber *iconCount = theme[@"iconCount"] ?: @0;
        NSNumber *iconBundlesCount = theme[@"iconBundlesCount"] ?: @0;
        NSNumber *skippedCount = theme[@"skippedCount"] ?: @0;
        NSNumber *duplicateCount = theme[@"duplicateCount"] ?: @0;
        NSString *sourceType = theme[@"sourceType"] ?: @"url";
        NSString *msg = [NSString stringWithFormat:@"\"%@\" is now active.\n\nImported %@ icons from %@ IconBundles folder(s). Source: %@. Skipped %@ file(s), including %@ duplicate bundle ID(s).\n\nToggle SnowBoard Lite on and tap Apply Tweaks to use it.",
                         themeName.length ? themeName : name,
                         iconCount,
                         iconBundlesCount,
                         sourceType,
                         skippedCount,
                         duplicateCount];
        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Theme Imported"
                                                                     message:msg
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"OK"
                                               style:UIAlertActionStyleDefault
                                             handler:^(__unused UIAlertAction *action) {
            [self refreshSnowBoardLiteOnlineDownloadsPopup];
        }]];
        [[self livewpPresentationHost] presentViewController:ok animated:YES completion:nil];
        log_user("[SBL] Theme download imported: %s\n", name.UTF8String ?: "theme");
    }];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    if (downloadTask != self.livewpDownloadTask &&
        downloadTask != self.sblDownloadTask) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (downloadTask == self.livewpDownloadTask) {
            [self.livewpDownloadProgressController updateWithReceivedBytes:totalBytesWritten
                                                             expectedBytes:totalBytesExpectedToWrite
                                                                      host:self.livewpDownloadURL.host];
        } else if (downloadTask == self.sblDownloadTask) {
            [self.sblDownloadProgressController updateWithReceivedBytes:totalBytesWritten
                                                           expectedBytes:totalBytesExpectedToWrite
                                                                    host:self.sblDownloadURL.host];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{
    if (task != self.livewpDownloadTask &&
        task != self.sblDownloadTask) {
        completionHandler(request);
        return;
    }

    NSMutableURLRequest *next = [request mutableCopy];
    NSURLRequest *originalRequest = (task == self.livewpDownloadTask)
        ? self.livewpDownloadRequest
        : self.sblDownloadRequest;
    NSURL *originalURL = (task == self.livewpDownloadTask)
        ? self.livewpDownloadURL
        : self.sblDownloadURL;
    NSDictionary<NSString *, NSString *> *headers = originalRequest.allHTTPHeaderFields;
    NSString *oldHost = originalURL.host.lowercaseString ?: @"";
    NSString *newHost = next.URL.host.lowercaseString ?: @"";
    BOOL sameHost = oldHost.length && ([oldHost isEqualToString:newHost] ||
                                       [oldHost hasSuffix:[@"." stringByAppendingString:newHost]] ||
                                       [newHost hasSuffix:[@"." stringByAppendingString:oldHost]]);
    for (NSString *key in headers) {
        if ([[key lowercaseString] isEqualToString:@"cookie"] && !sameHost) continue;
        if (![next valueForHTTPHeaderField:key]) {
            [next setValue:headers[key] forHTTPHeaderField:key];
        }
    }
    if (![next valueForHTTPHeaderField:@"Referer"] && originalURL.absoluteString.length) {
        [next setValue:originalURL.absoluteString forHTTPHeaderField:@"Referer"];
    }
    log_user("%s Download redirect %ld -> %s\n",
             (task == self.livewpDownloadTask) ? "[LIVEWP]" : "[SBL]",
             (long)response.statusCode,
             next.URL.absoluteString.UTF8String ?: "(nil)");
    completionHandler(next);
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    if (downloadTask != self.livewpDownloadTask &&
        downloadTask != self.sblDownloadTask) return;

    NSHTTPURLResponse *http = [downloadTask.response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)downloadTask.response : nil;
    if (http && (http.statusCode < 200 || http.statusCode >= 300)) {
        NSString *msg = [NSString stringWithFormat:@"Server returned HTTP %ld.", (long)http.statusCode];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (downloadTask == self.livewpDownloadTask) {
                [self finishLiveWPVideoDownloadWithErrorTitle:@"Download Failed" message:msg];
            } else {
                [self finishSnowBoardLiteThemeDownloadWithErrorTitle:@"Download Failed" message:msg];
            }
        });
        return;
    }

    if (downloadTask == self.sblDownloadTask) {
        NSURL *sourceURL = self.sblDownloadURL ?: downloadTask.originalRequest.URL;
        NSString *fileName = [self sblSafeDownloadedThemeNameFromURL:sourceURL
                                                            response:downloadTask.response];
        NSString *manualName = self.sblDownloadDisplayName;
        NSString *displayName = manualName.length ? manualName : fileName;
        NSString *sourceType = fileName.pathExtension.lowercaseString.length
            ? fileName.pathExtension.lowercaseString
            : @"url";
        NSError *importError = nil;
        BOOL ok = [self importSnowBoardLiteArchiveAtURL:location
                                            displayName:displayName
                                            sourceType:sourceType
                                                  error:&importError];
        if (ok) {
            [self markSelectedSnowBoardLiteThemeWithSourceURLString:sourceURL.absoluteString
                                                        onlineTitle:displayName];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                [self finishSnowBoardLiteThemeDownloadWithErrorTitle:@"Import Failed"
                                                             message:importError.localizedDescription ?: @"The downloaded theme could not be imported."];
                return;
            }
            [self finishSuccessfulSnowBoardLiteThemeDownloadWithName:displayName];
        });
        return;
    }

    NSString *fileName = [self livewpSafeDownloadedVideoNameFromURL:self.livewpDownloadURL ?: downloadTask.originalRequest.URL
                                                           response:downloadTask.response];
    NSError *saveError = nil;
    NSString *savedFileName = nil;
    BOOL ok = [self saveLiveWPDownloadedVideoAtURL:location
                                 preferredFileName:fileName
                                     savedFileName:&savedFileName
                                             error:&saveError];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!ok) {
            [self finishLiveWPVideoDownloadWithErrorTitle:@"Save Failed"
                                                  message:saveError.localizedDescription ?: @"The downloaded file could not be saved."];
            return;
        }
        [self finishSuccessfulLiveWPVideoDownloadWithFileName:savedFileName];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if ((task != self.livewpDownloadTask && task != self.sblDownloadTask) || !error) return;
    if (error.code == NSURLErrorCancelled) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task == self.livewpDownloadTask) {
            [self finishLiveWPVideoDownloadWithErrorTitle:@"Download Failed"
                                                  message:error.localizedDescription ?: @"The video could not be downloaded."];
        } else {
            [self finishSnowBoardLiteThemeDownloadWithErrorTitle:@"Download Failed"
                                                         message:error.localizedDescription ?: @"The theme archive could not be downloaded."];
        }
    });
}


- (BOOL)importLiveWPVideoAtURL:(NSURL *)url error:(NSError **)error
{
    return [self importLiveWPVideoAtURL:url preferredFileName:nil error:error];
}

- (BOOL)importLiveWPVideoAtURL:(NSURL *)url preferredFileName:(NSString *)preferredFileName error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Get file size
    NSDictionary *attrs = [fm attributesOfItemAtPath:url.path error:error];
    if (!attrs) return NO;
    
    unsigned long long fileSize = [attrs fileSize];
    unsigned long long maxSize = 100 * 1024 * 1024; // 100MB
    
    // Warn if file is large
    if (fileSize > maxSize) {
        log_user("[LIVEWP] Warning: Video file is %.1f MB. Large files may impact performance.\n",
                 fileSize / (1024.0 * 1024.0));
    }
    
    // Create Documents/LiveWP directory
    NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *livewpDir = [docsPath stringByAppendingPathComponent:@"LiveWP"];
    [fm createDirectoryAtPath:livewpDir withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;
    
    // Delete old video file if exists
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *oldAbsPath = settings_livewp_absolute_path();
    if (oldAbsPath && oldAbsPath.length > 0) {
        [fm removeItemAtPath:oldAbsPath error:nil];
        log_user("[LIVEWP] Removed old video file: %s\n", oldAbsPath.lastPathComponent.UTF8String);
    }
    
    // Copy new video file
    NSString *fileName = preferredFileName.length ? preferredFileName : url.lastPathComponent;
    if (!fileName.length) fileName = @"LiveWP-Video.mp4";
    NSString *ext = fileName.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:ext]) {
        fileName = [[fileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"];
    }
    NSString *destPath = [livewpDir stringByAppendingPathComponent:fileName];
    
    // Remove existing file with same name
    [fm removeItemAtPath:destPath error:nil];
    
    // Copy file
    if (![fm copyItemAtPath:url.path toPath:destPath error:error]) {
        return NO;
    }
    
    // 保存相对路径（sandbox 容器 UUID 会变，绝对路径不持久）
    NSString *relativePath = [NSString stringWithFormat:@"LiveWP/%@", fileName];
    [d setObject:relativePath forKey:kSettingsLiveWPVideoPath];
    [d synchronize];
    
    log_user("[LIVEWP] Imported video file: %s (%.1f MB)\n",
             fileName.UTF8String, fileSize / (1024.0 * 1024.0));
    
    return YES;
}

- (BOOL)importThemerFolderAtURL:(NSURL *)url error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *target = settings_themer_imported_theme_dir();
    NSString *root = settings_themer_documents_theme_root();
    if (!target || !root) return NO;

    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;

    NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:url
                                includingPropertiesForKeys:nil
                                                   options:0
                                                     error:error];
    if (!files) return NO;

    NSMutableArray<NSURL *> *pngs = [NSMutableArray array];
    for (NSURL *file in files) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"png"]) {
            [pngs addObject:file];
        }
    }
    if (pngs.count == 0) return NO;

    [fm removeItemAtPath:target error:nil];
    [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;
    [fm removeItemAtPath:settings_themer_imported_plist_path() error:nil];

    for (NSURL *png in pngs) {
        NSString *dst = [target stringByAppendingPathComponent:png.lastPathComponent];
        if (![fm copyItemAtURL:png toURL:[NSURL fileURLWithPath:dst] error:error]) {
            return NO;
        }
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeCustom forKey:kSettingsThemerThemeID];
    [d setObject:target forKey:kSettingsThemerCustomThemePath];
    [d setObject:url.lastPathComponent.length ? url.lastPathComponent : @"Imported Theme"
          forKey:kSettingsThemerCustomThemeName];
    [d synchronize];
    log_user("[THEMER] Imported custom folder theme: %lu PNG file(s).\n",
             (unsigned long)pngs.count);
    return YES;
}

- (BOOL)importThemerPlistAtURL:(NSURL *)url error:(NSError **)error
{
    NSDictionary *dict = settings_themer_load_plist_theme(url.path);
    if (dict.count == 0) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = settings_themer_documents_theme_root();
    NSString *target = settings_themer_imported_plist_path();
    if (!root || !target) return NO;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error];
    if (error && *error) return NO;
    [fm removeItemAtPath:target error:nil];
    [fm removeItemAtPath:settings_themer_imported_theme_dir() error:nil];
    if (![fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:target] error:error]) {
        return NO;
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:kThemerThemeCustom forKey:kSettingsThemerThemeID];
    [d setObject:target forKey:kSettingsThemerCustomThemePath];
    [d setObject:url.lastPathComponent.length ? url.lastPathComponent : @"Imported Theme"
          forKey:kSettingsThemerCustomThemeName];
    [d synchronize];
    log_user("[THEMER] Imported custom plist theme: %lu icon entries.\n",
             (unsigned long)dict.count);
    return YES;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;

    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSError *err = nil;
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir];
    NSString *themeImportMode = self.pendingThemeImportMode ?: @"";
    self.pendingThemeImportMode = nil;
    NSString *sblManualName = self.pendingSnowBoardLiteImportName ?: @"";
    self.pendingSnowBoardLiteImportName = nil;
    
    // Check if this is a video file for LiveWP
    NSString *ext = url.pathExtension.lowercaseString;
    if (themeImportMode.length == 0 &&
        ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"])) {
        // Handle LiveWP video selection
        BOOL ok = [self importLiveWPVideoAtURL:url error:&err];
        if (scoped) [url stopAccessingSecurityScopedResource];
        
        if (!ok) {
            NSString *msg = err.localizedDescription ?: @"Failed to import video file. Please choose a valid MP4, MOV, or M4V file.";
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Video Import Failed"
                                                                         message:msg
                                                                  preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ac animated:YES completion:nil];
            return;
        }
        
        [self finishLiveWPVideoImportAndSwapIfRunning];
        return;
    }

    if ([themeImportMode isEqualToString:@"sbl"]) {
        [self presentSnowBoardLiteLocalImportLoadingWithCompletion:^{
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *sblErr = nil;
                BOOL ok = NO;
                NSString *displayName = sblManualName.length ? sblManualName : url.lastPathComponent;
                if (displayName.length == 0) displayName = @"Imported Theme";
                if (isDir) {
                    ok = settings_sbl_import_folder_theme_named(url,
                                                                displayName,
                                                                @"folder",
                                                                &sblErr);
                } else {
                    NSString *sourceType = url.pathExtension.lowercaseString ?: @"archive";
                    if ([sourceType isEqualToString:@"zip"] || [sourceType isEqualToString:@"deb"]) {
                        ok = [self importSnowBoardLiteArchiveAtURL:url
                                                        displayName:displayName
                                                         sourceType:sourceType
                                                              error:&sblErr];
                    } else {
                        sblErr = settings_sbl_error(51, @"Choose a folder, .zip, or .deb that contains IconBundles.");
                    }
                }
                if (scoped) [url stopAccessingSecurityScopedResource];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self dismissSnowBoardLiteLocalImportLoadingWithCompletion:^{
                        if (!ok) {
                            NSString *msg = sblErr.localizedDescription ?: @"Choose a folder, .zip, or .deb that contains IconBundles.";
                            UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Import Failed"
                                                                                         message:msg
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                            [self presentViewController:ac animated:YES completion:nil];
                            return;
                        }
                        [self reloadSnowBoardLiteSectionAndQueue];
                        NSDictionary *theme = settings_sbl_selected_theme();
                        NSString *name = settings_snowboardlite_selected_theme_display_name();
                        NSNumber *iconCount = theme[@"iconCount"] ?: @0;
                        NSNumber *iconBundlesCount = theme[@"iconBundlesCount"] ?: @0;
                        NSNumber *skippedCount = theme[@"skippedCount"] ?: @0;
                        NSNumber *duplicateCount = theme[@"duplicateCount"] ?: @0;
                        NSString *sourceType = theme[@"sourceType"] ?: @"theme";
                        UIAlertController *ac = [UIAlertController
                            alertControllerWithTitle:@"Theme Imported"
                                             message:[NSString stringWithFormat:@"\"%@\" is now active.\n\nImported %@ icons from %@ IconBundles folder(s). Source: %@. Skipped %@ file(s), including %@ duplicate bundle ID(s).\n\nToggle SnowBoard Lite on and tap Apply Tweaks to use it.",
                                                      name,
                                                      iconCount,
                                                      iconBundlesCount,
                                                      sourceType,
                                                      skippedCount,
                                                      duplicateCount]
                                      preferredStyle:UIAlertControllerStyleAlert];
                        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [self presentViewController:ac animated:YES completion:nil];
                    }];
                });
            });
        }];
        return;
    }
    
    // Handle Themer import.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *themeErr = nil;
        BOOL ok = isDir ? [self importThemerFolderAtURL:url error:&themeErr]
                        : [self importThemerPlistAtURL:url error:&themeErr];
        if (scoped) [url stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                NSString *msg = themeErr.localizedDescription ?: @"Choose a folder of bundleID.png files or a binary plist mapping bundle IDs to PNG data.";
                UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Theme Import Failed"
                                                                             message:msg
                                                                      preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:ac animated:YES completion:nil];
                return;
            }
            [self reloadThemerSectionAndQueue];
            NSString *name = settings_themer_selected_theme_display_name();
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Theme Imported"
                                 message:[NSString stringWithFormat:@"\"%@\" is now selected. Toggle Cyanide Themer on and tap Run to apply.", name]
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ac animated:YES completion:nil];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    (void)controller;
    self.pendingThemeImportMode = nil;
    self.pendingSnowBoardLiteImportName = nil;
}

// "Classic" alternate icon is registered in Info.plist with CFBundleIconFiles
// pointing to Cyanide-Classic@{2,3}x.png at the bundle root. Modern is the
// asset-catalog primary, selected by passing nil to setAlternateIconName:.
+ (UIImage *)appIconPreviewForStyle:(NSString *)style
{
    NSString *name = [style isEqualToString:@"classic"] ? @"preview-classic" : @"preview-modern";
    UIImage *raw = [UIImage imageNamed:name];
    if (!raw) return nil;
    // Render with iOS home-screen corner radius (≈22% of side) so the thumb
    // matches what users see on SpringBoard. 52pt fits in the default subtitle
    // cell row height without forcing layout overrides.
    CGFloat side = 52.0;
    CGFloat radius = side * 0.22;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
                                                      cornerRadius:radius];
        [p addClip];
        [raw drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

- (NSString *)currentAppIconStyle
{
    NSString *alt = [UIApplication sharedApplication].alternateIconName;
    return [alt isEqualToString:@"Classic"] ? @"classic" : @"modern";
}

- (UITableViewCell *)buildAppIconCellAtRow:(NSInteger)row tableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"appicon"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"appicon"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    NSString *style = (row == 0) ? @"modern" : @"classic";
    cell.imageView.image = [SettingsViewController appIconPreviewForStyle:style];

    if (row == 0) {
        cell.textLabel.text = @"Modern";
        cell.detailTextLabel.text = @"Default — refreshed v2 mark.";
    } else {
        cell.textLabel.text = @"Classic";
        cell.detailTextLabel.text = @"Original release artwork.";
    }

    BOOL selected = [[self currentAppIconStyle] isEqualToString:style];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)selectAppIconAtRow:(NSInteger)row inTableView:(UITableView *)tableView
{
    NSString *style = (row == 0) ? @"modern" : @"classic";
    if ([[self currentAppIconStyle] isEqualToString:style]) return;

    if (![UIApplication sharedApplication].supportsAlternateIcons) {
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Can't Change Icon"
                             message:@"This iOS build doesn't expose alternate icon switching."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSString *altName = [style isEqualToString:@"classic"] ? @"Classic" : nil;
    [[UIApplication sharedApplication] setAlternateIconName:altName completionHandler:^(NSError * _Nullable error) {
        if (error) {
            printf("[SETTINGS] app icon switch to '%s' failed: %s\n",
                   style.UTF8String,
                   error.localizedDescription.UTF8String);
        } else {
            printf("[SETTINGS] app icon switched to %s\n", style.UTF8String);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexSet *idx = [NSIndexSet indexSetWithIndex:RootSectionAppIcon];
            [tableView reloadSections:idx withRowAnimation:UITableViewRowAnimationNone];
        });
    }];
}

+ (UIImage *)experimentalDangerChip
{
    static UIImage *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *text = @"DANGER";
        UIFont *font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: UIColor.whiteColor,
            NSKernAttributeName: @(0.4),
        };
        CGSize ts = [text sizeWithAttributes:attrs];
        CGFloat padH = 6.5;
        CGFloat padV = 2.5;
        CGSize size = CGSizeMake(ceil(ts.width) + padH * 2.0,
                                 ceil(ts.height) + padV * 2.0);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
        cached = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                          cornerRadius:size.height / 2.0];
            [UIColor.systemRedColor setFill];
            [p fill];
            [text drawAtPoint:CGPointMake(padH, padV) withAttributes:attrs];
        }];
    });
    return cached;
}

- (UITableViewCell *)buildExperimentalCellInTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"experimental"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"experimental"];
        cell.detailTextLabel.numberOfLines = 0;
    }
    BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey:kSettingsExperimentalTweaksEnabled];

    UIColor *iconColor = on ? UIColor.systemRedColor
                            : [UIColor.systemRedColor colorWithAlphaComponent:0.55];
    cell.imageView.image = [SettingsViewController iconBadgeWithSymbol:@"flask.fill"
                                                                  color:iconColor
                                                                   size:29.0];

    NSMutableAttributedString *title = [[NSMutableAttributedString alloc]
        initWithString:@"Experimental Tweaks  "
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:17.0],
                          NSForegroundColorAttributeName: UIColor.labelColor }];
    NSTextAttachment *att = [[NSTextAttachment alloc] init];
    UIImage *chip = [SettingsViewController experimentalDangerChip];
    att.image = chip;
    att.bounds = CGRectMake(0, -2.0, chip.size.width, chip.size.height);
    [title appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
    cell.textLabel.attributedText = title;

    cell.detailTextLabel.text = on
        ? @"Active — in-development tweaks unlocked. These probably don't "
          @"work yet; installing only adds risk, no benefit. Currently "
          @"gates: Signal Readouts, TypeBanner, App Switcher Grid."
        : @"In-development only. These tweaks likely don't work yet and "
          @"may never ship — turning this on only adds risk with no real "
          @"benefit. Currently gates: Signal Readouts, TypeBanner, App Switcher Grid.";
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.detailTextLabel.textColor = on
        ? [UIColor.systemRedColor colorWithAlphaComponent:0.9]
        : UIColor.secondaryLabelColor;

    cell.backgroundColor = on
        ? [UIColor.systemRedColor colorWithAlphaComponent:0.10]
        : nil;

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = UIColor.systemRedColor;
    sw.on = on;
    [sw addTarget:self action:@selector(experimentalSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (void)experimentalSwitchChanged:(UISwitch *)sw
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL enabling = sw.isOn;

    if (enabling) {
        // Hard confirm before flipping master on. If the user cancels, revert
        // the switch and stop here.
        sw.on = NO;
        UIAlertController *ac = [UIAlertController
            alertControllerWithTitle:@"Enable Experimental Tweaks?"
                             message:@"These tweaks are in development and most likely don't work yet. Installing them adds risk — SpringBoard crashes, dropped events, layout glitches, heavy battery drain — with no guaranteed benefit in return. Only turn this on if you're a developer actively testing."
                      preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Enable Anyway"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *_) {
            [d setBool:YES forKey:kSettingsExperimentalTweaksEnabled];
            sw.on = YES;
            printf("[SETTINGS] experimental tweaks enabled\n");
            [self reloadAfterExperimentalChange];
        }]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    [d setBool:NO forKey:kSettingsExperimentalTweaksEnabled];
    printf("[SETTINGS] experimental tweaks disabled; tearing down gated tweaks\n");

    // Force-disable every experimental-gated tweak so the user's setup doesn't
    // silently keep running with the master switch off. Add new gated tweaks
    // here as they're introduced.
    if ([d boolForKey:kSettingsTypeBannerEnabled]) {
        [d setBool:NO forKey:kSettingsTypeBannerEnabled];
        settings_mark_tweak_applied(kSettingsTypeBannerEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsTypeBannerEnabled);
    }
    if ([d boolForKey:kSettingsRSSIDisplayEnabled]) {
        [d setBool:NO forKey:kSettingsRSSIDisplayEnabled];
        settings_mark_tweak_applied(kSettingsRSSIDisplayEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsRSSIDisplayEnabled);
    }
    if ([d boolForKey:kSettingsAppSwitcherGridEnabled]) {
        [d setBool:NO forKey:kSettingsAppSwitcherGridEnabled];
        settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled, NO);
        settings_notify_package_queue_changed_async();
        settings_schedule_live_apply_for_key(kSettingsAppSwitcherGridEnabled);
    }
    [self reloadAfterExperimentalChange];
}

- (void)reloadAfterExperimentalChange
{
    // Tweak bundle list visibility depends on the experimental flag, and the
    // installer's package list is filtered by it too — refresh both.
    [self.tableView reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:PackageQueueDidChangeNotification
                                                        object:[PackageQueue sharedQueue]];
}

static NSString *settings_current_diagnostic_log_text(NSString *path, NSString **outSource);
static NSString *settings_diagnostic_log_with_header(NSString *rawLog,
                                                     NSString *path,
                                                     NSString *source,
                                                     NSString *sessionId,
                                                     NSString *kind,
                                                     NSString *event,
                                                     int seq);
static NSURL *settings_write_snapshot_log_file(NSString *text);

- (void)openXAccount:(NSString *)account
{
    if (!account.length) return;
    NSString *safeAccount = [account stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!safeAccount.length) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://x.com/%@", safeAccount]];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)aboutAuthorCardTapped:(UIControl *)sender
{
    NSString *account = objc_getAssociatedObject(sender, "cyanideAboutXAccount");
    [self openXAccount:account];
}

- (void)openTelegramGroup
{
    NSURL *url = [NSURL URLWithString:@"https://t.me/ios_cyanide"];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)aboutTelegramButtonTapped:(UIControl *)sender
{
    (void)sender;
    [self openTelegramGroup];
}

- (void)openViewLog
{
    NSString *logPath = log_most_recent_session_path();
    NSString *text = settings_current_diagnostic_log_text(logPath, NULL);
    if (!text.length && !logPath.length) {
        text = @"No log yet. Run a chain at least once.";
    } else if (!text.length) {
        NSError *err = nil;
        text = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&err];
        if (!text) text = [NSString stringWithFormat:@"Failed to read log: %@", err.localizedDescription];
    }

    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"Log";
    vc.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    tv.textColor = UIColor.labelColor;
    tv.backgroundColor = UIColor.systemGroupedBackgroundColor;
    tv.text = text;
    [vc.view addSubview:tv];
    [NSLayoutConstraint activateConstraints:@[
        [tv.topAnchor      constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [tv.bottomAnchor   constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor],
        [tv.leadingAnchor  constraintEqualToAnchor:vc.view.leadingAnchor constant:16.0],
        [tv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-16.0],
    ]];

    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openShareLog
{
    NSString *logPath = log_most_recent_session_path();
    NSString *logSource = nil;
    NSString *snapshot = settings_current_diagnostic_log_text(logPath, &logSource);
    if (!snapshot.length) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"No Log Yet"
                                                                     message:@"Run a chain once, then come back to share the latest diagnostic log."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    NSString *appVersion = settings_app_version_string();
    NSString *iosVersion = [UIDevice currentDevice].systemVersion ?: @"unknown";
    struct utsname info; uname(&info);
    NSString *machine = [NSString stringWithUTF8String:info.machine] ?: @"unknown";
    NSString *shareText = settings_diagnostic_log_with_header(snapshot,
                                                              logPath,
                                                              logSource,
                                                              nil,
                                                              @"share",
                                                              nil,
                                                              0);
    NSURL *logURL = settings_write_snapshot_log_file(shareText);
    if (!logURL) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Share Failed"
                                                                     message:@"Failed to prepare the diagnostic snapshot file."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }
    NSString *summary = [NSString stringWithFormat:@"Cyanide diagnostic log\nCyanide %@ · iOS %@ · %@",
                         appVersion, iosVersion, machine];

    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[summary, logURL]
                                                                     applicationActivities:nil];
    UIPopoverPresentationController *popover = vc.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                        CGRectGetMidY(self.view.bounds),
                                        1.0,
                                        1.0);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:vc animated:YES completion:nil];
}

static NSString *settings_current_diagnostic_log_text(NSString *path, NSString **outSource) {
    NSString *snapshot = log_inapp_buffer_snapshot();
    if (snapshot.length) {
        if (outSource) *outSource = @"in_app_snapshot";
        return snapshot;
    }

    if (path.length) {
        NSString *fileLog = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (fileLog.length) {
            if (outSource) *outSource = @"session_file";
            return fileLog;
        }
    }

    if (outSource) *outSource = @"empty";
    return @"";
}

static NSString *settings_diagnostic_log_with_header(NSString *rawLog,
                                                     NSString *path,
                                                     NSString *source,
                                                     NSString *sessionId,
                                                     NSString *kind,
                                                     NSString *event,
                                                     int seq) {
    NSString *appVersion = settings_app_version_string();
    NSString *appBuild = settings_app_build_string();
    NSString *iosVersion = [UIDevice currentDevice].systemVersion ?: @"unknown";

    struct utsname sysInfo;
    uname(&sysInfo);
    NSString *machine = [NSString stringWithUTF8String:sysInfo.machine] ?: @"unknown";

    NSString *header = [NSString stringWithFormat:
        @"=== Cyanide Diagnostic Log ===\n"
        @"app_version : %@\n"
        @"app_build   : %@\n"
        @"ios_version : %@\n"
        @"device      : %@\n"
        @"log_file    : %@\n"
        @"log_source  : %@\n"
        @"session_id  : %@\n"
        @"kind        : %@\n"
        @"event       : %@\n"
        @"seq         : %d\n"
        @"==============================\n\n",
        appVersion, appBuild, iosVersion, machine,
        path.lastPathComponent ?: @"none",
        source ?: @"unknown",
        sessionId ?: @"none",
        kind ?: @"",
        event ?: @"",
        seq];

    return [header stringByAppendingString:rawLog ?: @""];
}

static NSURL *settings_write_snapshot_log_file(NSString *text) {
    if (!text.length) return nil;

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyyMMdd-HHmmss";
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.timeZone = [NSTimeZone localTimeZone];

    NSString *name = [NSString stringWithFormat:@"cyanide-snapshot-%@.log",
                      [df stringFromDate:[NSDate date]]];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *err = nil;
    if (![text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        printf("[LOG] failed to write snapshot share file: %s\n", err.localizedDescription.UTF8String);
        return nil;
    }
    return url;
}

static void cyanide_upload_log_milestone(NSString *event) { (void)event; }
static void cyanide_upload_log_if_enabled(void) {}
static void cyanide_start_session_uploads(void) {}
static void cyanide_stop_session_uploads(void) {}

// Contact owner (zeroxjf) with the diagnostic log inline in the body. Build
// info sits between the user's typing area at the top and the log dump
// below, so the user just types above the signature and hits send.
- (void)openContactEmail
{
    cyanide_present_contact(self);
}

// Public entry point for the Contact flow. Builds the email body (signature
// + inline diagnostic log) and presents MFMailComposeViewController from
// `host` when Mail is set up, else opens a mailto: URL with a truncated log
// tail so third-party mail apps still get useful context.
void cyanide_present_contact(UIViewController *host)
{
    if (!host) return;

    NSString *appVersion = settings_app_version_string();
    NSString *iosVersion = [UIDevice currentDevice].systemVersion ?: @"unknown";
    struct utsname info; uname(&info);
    NSString *machine = [NSString stringWithUTF8String:info.machine];

    // Single-line signature so it reads correctly even in mail clients that
    // collapse newlines from mailto: bodies (Gmail-iOS being the worst offender).
    NSString *signature = [NSString stringWithFormat:@"—— Cyanide %@ · iOS %@ · %@ ——",
                           appVersion, iosVersion, machine];

    NSString *subject = [NSString stringWithFormat:@"Cyanide %@ — Contact", appVersion];

    // CRLF rather than LF so iOS Mail, Gmail, Outlook, and the mailto: URL
    // path all preserve line breaks. Plain LF is fine in MFMailCompose but
    // some third-party clients eat them when the body arrives via mailto:.
    // Log inclusion is intentionally omitted for now — pipeline was unreliable
    // (in-app buffer snapshot wasn't landing in the email). Build/device info
    // still ships in the signature so I can at least see the user's setup.
    NSMutableString *body = [NSMutableString string];
    [body appendString:@"\r\n\r\n\r\n"]; // breathing room at top for the user to type
    [body appendString:signature];
    [body appendString:@"\r\n"];

    if ([MFMailComposeViewController canSendMail]) {
        MFMailComposeViewController *vc = [[MFMailComposeViewController alloc] init];
        vc.mailComposeDelegate = _cyanide_mail_delegate();
        [vc setToRecipients:@[@"zeroxjf@gmail.com"]];
        [vc setSubject:subject];
        [vc setMessageBody:body isHTML:NO];
        [host presentViewController:vc animated:YES completion:nil];
        return;
    }

    // Mail not configured — fall back to mailto:. Bodies get URL-encoded so
    // long logs produce long URLs; in practice iOS LaunchServices accepts
    // ~64KB and third-party mail apps still receive the full body. We send
    // the full log regardless and trust the client to handle it.
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *q = [NSString stringWithFormat:@"subject=%@&body=%@",
        [subject stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"",
        [body stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
    NSURL *url = [NSURL URLWithString:[@"mailto:zeroxjf@gmail.com?" stringByAppendingString:q]];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Mail Not Available"
                         message:@"Set up Mail in iOS Settings to send feedback, or DM @zeroxjf on Twitter. View Log in Settings to copy the latest diagnostic log."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [host presentViewController:ac animated:YES completion:nil];
}

- (UIColor *)snowBoardLiteAccentColorNamed:(NSString *)name
{
    if ([name isEqualToString:@"mint"]) return UIColor.systemMintColor;
    if ([name isEqualToString:@"blue"]) return UIColor.systemBlueColor;
    if ([name isEqualToString:@"amber"]) return UIColor.systemOrangeColor;
    if ([name isEqualToString:@"red"]) return UIColor.systemRedColor;
    if ([name isEqualToString:@"slate"]) return UIColor.systemGrayColor;
    return UIColor.systemMintColor;
}

- (NSString *)snowBoardLiteSourceBadgeText:(NSString *)sourceType
{
    NSString *source = sourceType.lowercaseString ?: @"";
    if ([source isEqualToString:@"built-in"]) return @"BUILT-IN";
    if ([source isEqualToString:@"url"]) return @"URL";
    if ([source isEqualToString:@"zip"]) return @"ZIP";
    if ([source isEqualToString:@"deb"]) return @"DEB";
    if ([source isEqualToString:@"folder"]) return @"FOLDER";
    if (source.length > 0) return source.uppercaseString;
    return @"THEME";
}

- (UIView *)snowBoardLitePreviewGridWithAccent:(UIColor *)accent
                                      selected:(BOOL)selected
                                        images:(NSArray<UIImage *> *)images
{
    UIView *preview = [[UIView alloc] init];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.backgroundColor = [accent colorWithAlphaComponent:selected ? 0.20 : 0.12];
    preview.layer.cornerRadius = 22.0;
    preview.layer.cornerCurve = kCACornerCurveContinuous;

    NSArray<UIColor *> *colors = @[
        UIColor.systemBlueColor,
        UIColor.systemOrangeColor,
        UIColor.systemPinkColor,
        UIColor.systemTealColor,
    ];
    NSArray<NSString *> *symbols = @[@"app.fill", @"safari.fill", @"message.fill", @"music.note"];
    NSMutableArray<UIView *> *tiles = [NSMutableArray arrayWithCapacity:4];
    for (NSUInteger i = 0; i < 4; i++) {
        UIView *tile = [[UIView alloc] init];
        tile.translatesAutoresizingMaskIntoConstraints = NO;
        UIImage *themeIcon = (i < images.count) ? images[i] : nil;
        tile.backgroundColor = themeIcon
            ? UIColor.clearColor
            : [colors[i] colorWithAlphaComponent:0.9];
        tile.layer.cornerRadius = 9.0;
        tile.layer.cornerCurve = kCACornerCurveContinuous;
        tile.clipsToBounds = YES;
        [preview addSubview:tile];
        [tiles addObject:tile];

        UIImageView *glyph = [[UIImageView alloc] initWithImage:themeIcon ?: [UIImage systemImageNamed:symbols[i]]];
        glyph.translatesAutoresizingMaskIntoConstraints = NO;
        glyph.tintColor = themeIcon ? nil : UIColor.whiteColor;
        glyph.contentMode = themeIcon ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        [tile addSubview:glyph];
        if (themeIcon) {
            [NSLayoutConstraint activateConstraints:@[
                [glyph.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
                [glyph.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
                [glyph.topAnchor constraintEqualToAnchor:tile.topAnchor],
                [glyph.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor],
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
                [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
                [glyph.widthAnchor constraintEqualToConstant:13.0],
                [glyph.heightAnchor constraintEqualToConstant:13.0],
            ]];
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [tiles[0].leadingAnchor constraintEqualToAnchor:preview.leadingAnchor constant:13.0],
        [tiles[0].topAnchor constraintEqualToAnchor:preview.topAnchor constant:13.0],
        [tiles[0].widthAnchor constraintEqualToConstant:20.0],
        [tiles[0].heightAnchor constraintEqualToConstant:20.0],
        [tiles[1].trailingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:-13.0],
        [tiles[1].topAnchor constraintEqualToAnchor:tiles[0].topAnchor],
        [tiles[1].widthAnchor constraintEqualToAnchor:tiles[0].widthAnchor],
        [tiles[1].heightAnchor constraintEqualToAnchor:tiles[0].heightAnchor],
        [tiles[2].leadingAnchor constraintEqualToAnchor:tiles[0].leadingAnchor],
        [tiles[2].bottomAnchor constraintEqualToAnchor:preview.bottomAnchor constant:-13.0],
        [tiles[2].widthAnchor constraintEqualToAnchor:tiles[0].widthAnchor],
        [tiles[2].heightAnchor constraintEqualToAnchor:tiles[0].heightAnchor],
        [tiles[3].trailingAnchor constraintEqualToAnchor:tiles[1].trailingAnchor],
        [tiles[3].bottomAnchor constraintEqualToAnchor:tiles[2].bottomAnchor],
        [tiles[3].widthAnchor constraintEqualToAnchor:tiles[0].widthAnchor],
        [tiles[3].heightAnchor constraintEqualToAnchor:tiles[0].heightAnchor],
    ]];

    return preview;
}

- (UILabel *)snowBoardLitePillWithText:(NSString *)text color:(UIColor *)color filled:(BOOL)filled
{
    UILabel *pill = [[UILabel alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.text = [NSString stringWithFormat:@"  %@  ", text ?: @""];
    pill.textColor = filled ? UIColor.whiteColor : color;
    pill.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    pill.backgroundColor = filled ? color : [color colorWithAlphaComponent:0.13];
    pill.layer.cornerRadius = 10.0;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.clipsToBounds = YES;
    return pill;
}

- (UIView *)snowBoardLiteCountCapsuleWithText:(NSString *)text color:(UIColor *)color
{
    UIView *capsule = [[UIView alloc] init];
    capsule.translatesAutoresizingMaskIntoConstraints = NO;
    capsule.backgroundColor = [color colorWithAlphaComponent:0.13];
    capsule.layer.cornerRadius = 13.0;
    capsule.layer.cornerCurve = kCACornerCurveContinuous;
    capsule.clipsToBounds = YES;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text ?: @"";
    label.textColor = color;
    label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightHeavy];
    [capsule addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:10.0],
        [label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-10.0],
        [label.topAnchor constraintEqualToAnchor:capsule.topAnchor constant:5.0],
        [label.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor constant:-5.0],
    ]];

    return capsule;
}

- (UIControl *)snowBoardLiteCarouselCardForItem:(NSDictionary *)item
{
    BOOL selected = [item[@"selected"] boolValue];
    BOOL builtIn = [item[@"builtIn"] boolValue];
    UIColor *accent = selected ? UIColor.systemGreenColor : (builtIn ? UIColor.systemOrangeColor : UIColor.systemMintColor);

    UIControl *card = [[UIControl alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = selected
        ? [accent colorWithAlphaComponent:0.16]
        : UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 24.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = selected ? 1.5 : 1.0;
    card.layer.borderColor = selected
        ? [accent colorWithAlphaComponent:0.62].CGColor
        : [UIColor.separatorColor colorWithAlphaComponent:0.20].CGColor;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = selected ? 0.10 : 0.04;
    card.layer.shadowRadius = selected ? 12.0 : 8.0;
    card.layer.shadowOffset = CGSizeMake(0, selected ? 6.0 : 3.0);
    [card addTarget:self action:@selector(snowBoardLiteCarouselThemeTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(card, "sblThemeID", item[@"id"] ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(card, "sblThemeTitle", item[@"title"] ?: @"Theme", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(card, "sblThemeItem", item ?: @{}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [card addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];

    NSArray<UIImage *> *previewImages =
        settings_sbl_preview_images_for_theme(item[@"theme"], builtIn, 4);
    UIView *preview = [self snowBoardLitePreviewGridWithAccent:accent
                                                      selected:selected
                                                        images:previewImages];
    [card addSubview:preview];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = item[@"title"] ?: @"Theme";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    title.numberOfLines = 2;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:title];

    UILabel *source = [self snowBoardLitePillWithText:[self snowBoardLiteSourceBadgeText:item[@"sourceType"]]
                                                color:accent
                                               filled:NO];
    [card addSubview:source];

    UILabel *count = [[UILabel alloc] init];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    count.text = [NSString stringWithFormat:@"%@ icons", item[@"iconCount"] ?: @0];
    count.textColor = UIColor.secondaryLabelColor;
    count.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    [card addSubview:count];

    UILabel *state = nil;
    if (selected) {
        state = [self snowBoardLitePillWithText:@"ACTIVE" color:accent filled:YES];
        [card addSubview:state];
    }

    [NSLayoutConstraint activateConstraints:@[
        [card.widthAnchor constraintEqualToConstant:158.0],
        [card.heightAnchor constraintEqualToConstant:196.0],

        [preview.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [preview.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [preview.widthAnchor constraintEqualToConstant:70.0],
        [preview.heightAnchor constraintEqualToConstant:70.0],

        [source.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [source.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:12.0],
        [source.heightAnchor constraintGreaterThanOrEqualToConstant:20.0],

        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:source.bottomAnchor constant:7.0],
        [title.bottomAnchor constraintLessThanOrEqualToAnchor:count.topAnchor constant:-5.0],

        [count.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [count.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [count.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];

    if (state) {
        [NSLayoutConstraint activateConstraints:@[
            [state.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10.0],
            [state.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
            [state.heightAnchor constraintGreaterThanOrEqualToConstant:20.0],
        ]];
    }

    return card;
}

- (UITableViewCell *)buildSnowBoardLiteCarouselCellInTableView:(UITableView *)tableView
                                                           row:(NSDictionary *)row
                                                     indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sbl-carousel"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sbl-carousel"];
    }
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"Theme Library";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBlack];
    [cell.contentView addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = row[@"subtitle"] ?: @"";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    subtitle.numberOfLines = 2;
    [cell.contentView addSubview:subtitle];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.alwaysBounceHorizontal = YES;
    [cell.contentView addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 12.0;
    stack.alignment = UIStackViewAlignmentCenter;
    [scroll addSubview:stack];

    NSArray<NSDictionary *> *items = row[@"items"];
    for (NSDictionary *item in items) {
        [stack addArrangedSubview:[self snowBoardLiteCarouselCardForItem:item]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12.0],
        [title.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0],

        [scroll.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12.0],
        [scroll.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
        [scroll.heightAnchor constraintEqualToConstant:208.0],

        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:12.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-12.0],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
    ]];

    return cell;
}

- (void)snowBoardLiteLoadOnlinePreviewURLString:(NSString *)urlString
                                  intoImageView:(UIImageView *)imageView
{
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *url = [NSURL URLWithString:trimmed];
    if (!url || imageView == nil) return;

    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
    });

    NSString *key = url.absoluteString;
    UIImage *cached = [cache objectForKey:key];
    if (cached) {
        NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(imageView, "sblOnlinePreviewWidthConstraint");
        NSNumber *heightNumber = objc_getAssociatedObject(imageView, "sblOnlinePreviewFixedHeight");
        CGFloat fixedHeight = heightNumber.doubleValue > 0.0 ? heightNumber.doubleValue : 172.0;
        if (widthConstraint && cached.size.height > 0.0) {
            CGFloat fittedWidth = ceil(fixedHeight * (cached.size.width / cached.size.height));
            widthConstraint.constant = MAX(72.0, MIN(fittedWidth, 320.0));
        }
        imageView.image = cached;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.tintColor = nil;
        return;
    }

    objc_setAssociatedObject(imageView,
                             "sblOnlinePreviewURL",
                             key,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 20.0;
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
   forHTTPHeaderField:@"User-Agent"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData *data,
                                                         NSURLResponse *response,
                                                         NSError *error) {
        (void)response;
        if (error || data.length == 0) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        [cache setObject:image forKey:key];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *expected = objc_getAssociatedObject(imageView, "sblOnlinePreviewURL");
            if (![expected isEqualToString:key]) return;
            NSLayoutConstraint *widthConstraint = objc_getAssociatedObject(imageView, "sblOnlinePreviewWidthConstraint");
            NSNumber *heightNumber = objc_getAssociatedObject(imageView, "sblOnlinePreviewFixedHeight");
            CGFloat fixedHeight = heightNumber.doubleValue > 0.0 ? heightNumber.doubleValue : 172.0;
            if (widthConstraint && image.size.height > 0.0) {
                CGFloat fittedWidth = ceil(fixedHeight * (image.size.width / image.size.height));
                widthConstraint.constant = MAX(72.0, MIN(fittedWidth, 320.0));
                [imageView.superview.superview setNeedsLayout];
            }
            imageView.image = image;
            imageView.contentMode = UIViewContentModeScaleAspectFill;
            imageView.tintColor = nil;
        });
    }] resume];
}

- (UIView *)snowBoardLiteOnlinePreviewTileWithURLString:(NSString *)urlString
                                                 accent:(UIColor *)accent
                                                 symbol:(NSString *)symbol
{
    (void)accent;
    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    tile.layer.cornerRadius = 18.0;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.clipsToBounds = YES;

    UIImage *placeholder = [UIImage systemImageNamed:symbol ?: @"photo.on.rectangle.angled"] ?:
        [UIImage systemImageNamed:@"photo.on.rectangle.angled"];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:placeholder];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.tintColor = UIColor.tertiaryLabelColor;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [tile addSubview:imageView];

    NSLayoutConstraint *widthConstraint = [tile.widthAnchor constraintEqualToConstant:88.0];
    NSLayoutConstraint *heightConstraint = [tile.heightAnchor constraintEqualToConstant:172.0];
    objc_setAssociatedObject(imageView,
                             "sblOnlinePreviewWidthConstraint",
                             widthConstraint,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(imageView,
                             "sblOnlinePreviewFixedHeight",
                             @(172.0),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [NSLayoutConstraint activateConstraints:@[
        widthConstraint,
        heightConstraint,
        [imageView.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
        [imageView.topAnchor constraintEqualToAnchor:tile.topAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor],
    ]];

    [self snowBoardLiteLoadOnlinePreviewURLString:urlString intoImageView:imageView];
    return tile;
}

- (UIControl *)snowBoardLiteOnlineDownloadCardForItem:(NSDictionary *)item
{
    NSDictionary *installedTheme = [self installedSnowBoardLiteOnlineThemeForItem:item];
    BOOL installed = installedTheme != nil;
    UIControl *card = [[UIControl alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.16].CGColor;
    card.clipsToBounds = YES;
    [card addTarget:self action:@selector(snowBoardLiteOnlineDownloadTapped:)
   forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(card, "sblOnlineURL", item[@"url"] ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(card, "sblOnlineName", item[@"title"] ?: @"Theme", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(card,
                             "sblOnlineInstalledThemeID",
                             installedTheme[@"id"] ?: @"",
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIScrollView *previewScroll = [[UIScrollView alloc] init];
    previewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    previewScroll.showsHorizontalScrollIndicator = NO;
    previewScroll.alwaysBounceHorizontal = YES;
    previewScroll.clipsToBounds = YES;
    [card addSubview:previewScroll];

    UIStackView *previewStack = [[UIStackView alloc] init];
    previewStack.translatesAutoresizingMaskIntoConstraints = NO;
    previewStack.axis = UILayoutConstraintAxisHorizontal;
    previewStack.spacing = 8.0;
    [previewScroll addSubview:previewStack];

    NSArray<NSString *> *previewURLs = [item[@"previewURLs"] isKindOfClass:NSArray.class]
        ? item[@"previewURLs"]
        : @[];
    if (previewURLs.count == 0 && [item[@"previewURL"] isKindOfClass:NSString.class]) {
        previewURLs = @[item[@"previewURL"]];
    }
    if (previewURLs.count == 0) {
        previewURLs = @[@""];
    }
    for (NSString *previewURL in previewURLs) {
        [previewStack addArrangedSubview:[self snowBoardLiteOnlinePreviewTileWithURLString:previewURL
                                                                                    accent:nil
                                                                                    symbol:nil]];
    }

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = item[@"title"] ?: @"Theme";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    title.numberOfLines = 1;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = item[@"subtitle"] ?: @"";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    subtitle.numberOfLines = 2;
    [card addSubview:subtitle];

    UIView *actionPlate = [[UIView alloc] init];
    actionPlate.translatesAutoresizingMaskIntoConstraints = NO;
    actionPlate.backgroundColor = installed
        ? [UIColor.systemGreenColor colorWithAlphaComponent:0.12]
        : UIColor.systemBlueColor;
    actionPlate.layer.cornerRadius = 17.0;
    actionPlate.layer.cornerCurve = kCACornerCurveContinuous;
    actionPlate.layer.borderWidth = installed ? 1.0 : 0.0;
    actionPlate.layer.borderColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.38].CGColor;
    actionPlate.userInteractionEnabled = NO;
    [card addSubview:actionPlate];

    UIImage *actionImage = [UIImage systemImageNamed:installed ? @"checkmark.circle.fill" : @"arrow.down.circle.fill"] ?:
        [UIImage systemImageNamed:@"arrow.down.circle.fill"];
    UIImageView *actionIcon = [[UIImageView alloc] initWithImage:actionImage];
    actionIcon.translatesAutoresizingMaskIntoConstraints = NO;
    actionIcon.tintColor = installed ? UIColor.systemGreenColor : UIColor.whiteColor;
    actionIcon.contentMode = UIViewContentModeScaleAspectFit;
    UILabel *actionLabel = [[UILabel alloc] init];
    actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    actionLabel.text = installed ? @"Installed" : @"Download";
    actionLabel.textColor = installed ? UIColor.systemGreenColor : UIColor.whiteColor;
    actionLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];

    UIStackView *actionStack = [[UIStackView alloc] init];
    actionStack.translatesAutoresizingMaskIntoConstraints = NO;
    actionStack.axis = UILayoutConstraintAxisHorizontal;
    actionStack.alignment = UIStackViewAlignmentCenter;
    actionStack.spacing = 5.0;
    actionStack.userInteractionEnabled = NO;
    [actionStack addArrangedSubview:actionIcon];
    [actionStack addArrangedSubview:actionLabel];
    [actionPlate addSubview:actionStack];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:270.0],

        [previewScroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10.0],
        [previewScroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10.0],
        [previewScroll.topAnchor constraintEqualToAnchor:card.topAnchor constant:10.0],
        [previewScroll.heightAnchor constraintEqualToConstant:172.0],

        [previewStack.leadingAnchor constraintEqualToAnchor:previewScroll.contentLayoutGuide.leadingAnchor],
        [previewStack.trailingAnchor constraintEqualToAnchor:previewScroll.contentLayoutGuide.trailingAnchor],
        [previewStack.topAnchor constraintEqualToAnchor:previewScroll.contentLayoutGuide.topAnchor],
        [previewStack.bottomAnchor constraintEqualToAnchor:previewScroll.contentLayoutGuide.bottomAnchor],
        [previewStack.heightAnchor constraintEqualToAnchor:previewScroll.frameLayoutGuide.heightAnchor],

        [actionPlate.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [actionPlate.topAnchor constraintEqualToAnchor:previewScroll.bottomAnchor constant:16.0],
        [actionPlate.widthAnchor constraintEqualToConstant:112.0],
        [actionPlate.heightAnchor constraintEqualToConstant:34.0],

        [actionStack.centerXAnchor constraintEqualToAnchor:actionPlate.centerXAnchor],
        [actionStack.centerYAnchor constraintEqualToAnchor:actionPlate.centerYAnchor],
        [actionStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:actionPlate.leadingAnchor constant:10.0],
        [actionStack.trailingAnchor constraintLessThanOrEqualToAnchor:actionPlate.trailingAnchor constant:-10.0],
        [actionIcon.widthAnchor constraintEqualToConstant:17.0],
        [actionIcon.heightAnchor constraintEqualToConstant:17.0],

        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:actionPlate.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:previewScroll.bottomAnchor constant:13.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:actionPlate.leadingAnchor constant:-12.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-14.0],
    ]];

    return card;
}

- (UITableViewCell *)buildSnowBoardLiteOnlineDownloadsCellInTableView:(UITableView *)tableView
                                                                  row:(NSDictionary *)row
                                                            indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sbl-online"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sbl-online"];
    }
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"Online Downloads";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBlack];
    [cell.contentView addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = row[@"subtitle"] ?: @"";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    subtitle.numberOfLines = 2;
    [cell.contentView addSubview:subtitle];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10.0;
    [cell.contentView addSubview:stack];

    NSArray<NSDictionary *> *items = row[@"items"];
    for (NSDictionary *item in items) {
        [stack addArrangedSubview:[self snowBoardLiteOnlineDownloadCardForItem:item]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12.0],
        [title.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0],

        [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12.0],
        [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12.0],
        [stack.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12.0],
        [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
    ]];

    return cell;
}

- (UIButton *)snowBoardLiteToolButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(NSString *)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.systemMintColor;
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightHeavy];
    button.backgroundColor = [UIColor.systemMintColor colorWithAlphaComponent:0.12];
    button.layer.cornerRadius = 17.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 10.0, 8.0, 10.0);
    button.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    objc_setAssociatedObject(button, "sblAction", action ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:self action:@selector(snowBoardLiteToolButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UITableViewCell *)buildSnowBoardLiteHelpCellInTableView:(UITableView *)tableView
                                                       row:(NSDictionary *)row
                                                 indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sbl-help"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sbl-help"];
    }
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 24.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.18].CGColor;
    [cell.contentView addSubview:card];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"Import & Help";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBlack];
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = row[@"subtitle"] ?: @"";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:12.8 weight:UIFontWeightMedium];
    subtitle.numberOfLines = 3;
    [card addSubview:subtitle];

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self snowBoardLiteToolButtonWithTitle:@"Local" symbol:@"folder.badge.plus" action:@"sbl-import"],
        [self snowBoardLiteToolButtonWithTitle:@"URL" symbol:@"link.badge.plus" action:@"sbl-import-url"],
        [self snowBoardLiteToolButtonWithTitle:@"Guide" symbol:@"questionmark.circle.fill" action:@"sbl-guide"],
    ]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 8.0;
    buttons.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12.0],
        [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12.0],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8.0],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8.0],

        [title.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6.0],

        [buttons.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [buttons.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [buttons.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14.0],
        [buttons.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18.0],
        [buttons.heightAnchor constraintEqualToConstant:38.0],
    ]];

    return cell;
}

- (UITableViewCell *)buildSnowBoardLiteThemeCardCellInTableView:(UITableView *)tableView
                                                            row:(NSDictionary *)row
                                                      indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sbl-theme-card"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sbl-theme-card"];
    }
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.userInteractionEnabled = YES;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    BOOL selected = [row[@"selected"] boolValue];
    UIColor *accent = selected ? UIColor.systemGreenColor : UIColor.systemMintColor;

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 24.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = selected ? 1.5 : 1.0;
    card.layer.borderColor = selected
        ? [accent colorWithAlphaComponent:0.62].CGColor
        : [UIColor.separatorColor colorWithAlphaComponent:0.18].CGColor;
    card.layer.shadowColor = UIColor.blackColor.CGColor;
    card.layer.shadowOpacity = selected ? 0.11 : 0.06;
    card.layer.shadowRadius = selected ? 14.0 : 10.0;
    card.layer.shadowOffset = CGSizeMake(0, selected ? 7.0 : 4.0);
    [cell.contentView addSubview:card];

    UIView *preview = [[UIView alloc] init];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    preview.backgroundColor = [accent colorWithAlphaComponent:selected ? 0.18 : 0.12];
    preview.layer.cornerRadius = 20.0;
    preview.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:preview];

    NSArray<UIColor *> *tileColors = @[
        [UIColor.systemBlueColor colorWithAlphaComponent:0.88],
        [UIColor.systemOrangeColor colorWithAlphaComponent:0.88],
        [UIColor.systemPinkColor colorWithAlphaComponent:0.88],
        [UIColor.systemTealColor colorWithAlphaComponent:0.88],
    ];
    NSArray<NSString *> *tileSymbols = @[@"app.fill", @"safari.fill", @"message.fill", @"music.note"];
    NSMutableArray<UIView *> *tiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++) {
        UIView *tile = [[UIView alloc] init];
        tile.translatesAutoresizingMaskIntoConstraints = NO;
        tile.backgroundColor = tileColors[i];
        tile.layer.cornerRadius = 8.0;
        tile.layer.cornerCurve = kCACornerCurveContinuous;
        [preview addSubview:tile];
        [tiles addObject:tile];

        UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:tileSymbols[i]]];
        glyph.translatesAutoresizingMaskIntoConstraints = NO;
        glyph.tintColor = UIColor.whiteColor;
        glyph.contentMode = UIViewContentModeScaleAspectFit;
        [tile addSubview:glyph];
        [NSLayoutConstraint activateConstraints:@[
            [glyph.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
            [glyph.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
            [glyph.widthAnchor constraintEqualToConstant:13.0],
            [glyph.heightAnchor constraintEqualToConstant:13.0],
        ]];
    }

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"Imported Theme";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    title.numberOfLines = 1;
    [card addSubview:title];

    UILabel *state = [[UILabel alloc] init];
    state.translatesAutoresizingMaskIntoConstraints = NO;
    state.text = selected ? @"  Active  " : @"  Tap  ";
    state.textColor = selected ? UIColor.whiteColor : accent;
    state.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightHeavy];
    state.backgroundColor = selected ? accent : [accent colorWithAlphaComponent:0.13];
    state.layer.cornerRadius = 12.0;
    state.layer.cornerCurve = kCACornerCurveContinuous;
    state.clipsToBounds = YES;
    [card addSubview:state];

    UILabel *sourceBadge = [[UILabel alloc] init];
    sourceBadge.translatesAutoresizingMaskIntoConstraints = NO;
    sourceBadge.text = [NSString stringWithFormat:@"  %@  ",
                        [self snowBoardLiteSourceBadgeText:row[@"sourceType"]]];
    sourceBadge.textColor = accent;
    sourceBadge.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
    sourceBadge.backgroundColor = [accent colorWithAlphaComponent:0.11];
    sourceBadge.layer.cornerRadius = 10.0;
    sourceBadge.layer.cornerCurve = kCACornerCurveContinuous;
    sourceBadge.clipsToBounds = YES;
    [card addSubview:sourceBadge];

    UILabel *iconCount = [[UILabel alloc] init];
    iconCount.translatesAutoresizingMaskIntoConstraints = NO;
    iconCount.text = [NSString stringWithFormat:@"%@ icons", row[@"iconCount"] ?: @0];
    iconCount.textColor = UIColor.secondaryLabelColor;
    iconCount.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightSemibold];
    [card addSubview:iconCount];

    NSString *importedAt = row[@"importedAt"] ?: @"";
    NSNumber *bundleCount = row[@"iconBundlesCount"] ?: @0;
    NSNumber *skippedCount = row[@"skippedCount"] ?: @0;
    NSNumber *duplicateCount = row[@"duplicateCount"] ?: @0;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (importedAt.length > 0) [parts addObject:[NSString stringWithFormat:@"Imported %@", importedAt]];
    if (bundleCount.integerValue > 0) [parts addObject:[NSString stringWithFormat:@"%@ IconBundles", bundleCount]];
    if (skippedCount.integerValue > 0) [parts addObject:[NSString stringWithFormat:@"%@ skipped", skippedCount]];
    if (duplicateCount.integerValue > 0) [parts addObject:[NSString stringWithFormat:@"%@ duplicate", duplicateCount]];

    UILabel *details = [[UILabel alloc] init];
    details.translatesAutoresizingMaskIntoConstraints = NO;
    details.text = parts.count > 0 ? [parts componentsJoinedByString:@" · "] : @"Ready to activate.";
    details.textColor = UIColor.secondaryLabelColor;
    details.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
    details.numberOfLines = 2;
    [card addSubview:details];

    UIImageView *trash = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"trash"]];
    trash.translatesAutoresizingMaskIntoConstraints = NO;
    trash.tintColor = UIColor.tertiaryLabelColor;
    trash.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:trash];

    UILabel *swipe = [[UILabel alloc] init];
    swipe.translatesAutoresizingMaskIntoConstraints = NO;
    swipe.text = @"Swipe to remove";
    swipe.textColor = UIColor.tertiaryLabelColor;
    swipe.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    [card addSubview:swipe];

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:7.0],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-7.0],

        [preview.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [preview.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [preview.widthAnchor constraintEqualToConstant:68.0],
        [preview.heightAnchor constraintEqualToConstant:68.0],

        [tiles[0].leadingAnchor constraintEqualToAnchor:preview.leadingAnchor constant:12.0],
        [tiles[0].topAnchor constraintEqualToAnchor:preview.topAnchor constant:12.0],
        [tiles[0].widthAnchor constraintEqualToConstant:19.0],
        [tiles[0].heightAnchor constraintEqualToConstant:19.0],
        [tiles[1].trailingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:-12.0],
        [tiles[1].topAnchor constraintEqualToAnchor:tiles[0].topAnchor],
        [tiles[1].widthAnchor constraintEqualToAnchor:tiles[0].widthAnchor],
        [tiles[1].heightAnchor constraintEqualToAnchor:tiles[0].heightAnchor],
        [tiles[2].leadingAnchor constraintEqualToAnchor:tiles[0].leadingAnchor],
        [tiles[2].bottomAnchor constraintEqualToAnchor:preview.bottomAnchor constant:-12.0],
        [tiles[2].widthAnchor constraintEqualToAnchor:tiles[0].widthAnchor],
        [tiles[2].heightAnchor constraintEqualToAnchor:tiles[0].heightAnchor],
        [tiles[3].trailingAnchor constraintEqualToAnchor:tiles[1].trailingAnchor],
        [tiles[3].bottomAnchor constraintEqualToAnchor:tiles[2].bottomAnchor],
        [tiles[3].widthAnchor constraintEqualToAnchor:tiles[0].widthAnchor],
        [tiles[3].heightAnchor constraintEqualToAnchor:tiles[0].heightAnchor],

        [state.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [state.topAnchor constraintEqualToAnchor:card.topAnchor constant:15.0],
        [state.heightAnchor constraintGreaterThanOrEqualToConstant:24.0],

        [title.leadingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:14.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:state.leadingAnchor constant:-10.0],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:15.0],

        [sourceBadge.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sourceBadge.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:7.0],
        [sourceBadge.heightAnchor constraintGreaterThanOrEqualToConstant:20.0],

        [iconCount.leadingAnchor constraintEqualToAnchor:sourceBadge.trailingAnchor constant:8.0],
        [iconCount.centerYAnchor constraintEqualToAnchor:sourceBadge.centerYAnchor],
        [iconCount.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16.0],

        [details.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [details.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [details.topAnchor constraintEqualToAnchor:sourceBadge.bottomAnchor constant:7.0],

        [trash.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [trash.topAnchor constraintEqualToAnchor:details.bottomAnchor constant:8.0],
        [trash.widthAnchor constraintEqualToConstant:12.0],
        [trash.heightAnchor constraintEqualToConstant:12.0],
        [trash.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-15.0],

        [swipe.leadingAnchor constraintEqualToAnchor:trash.trailingAnchor constant:4.0],
        [swipe.centerYAnchor constraintEqualToAnchor:trash.centerYAnchor],
        [swipe.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16.0],
    ]];

    return cell;
}

- (UITableViewCell *)buildSnowBoardLiteOnlineEntryCellInTableView:(UITableView *)tableView
                                                              row:(NSDictionary *)row
                                                        indexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sbl-online-entry"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sbl-online-entry"];
    }
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIColor *accent = UIColor.systemMintColor;
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 24.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [accent colorWithAlphaComponent:0.22].CGColor;
    card.clipsToBounds = YES;
    [cell.contentView addSubview:card];

    UIView *glow = [[UIView alloc] init];
    glow.translatesAutoresizingMaskIntoConstraints = NO;
    glow.backgroundColor = [accent colorWithAlphaComponent:0.13];
    glow.layer.cornerRadius = 28.0;
    glow.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:glow];

    NSArray<NSDictionary *> *items = [self snowBoardLiteOnlineDownloadItems];
    NSMutableArray<UIView *> *previewTiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        NSDictionary *item = i < items.count ? items[i] : @{};
        NSArray *urls = [item[@"previewURLs"] isKindOfClass:NSArray.class] ? item[@"previewURLs"] : @[];
        NSString *url = urls.count > 0 ? urls[0] : @"";
        UIColor *tileAccent = item[@"color"] ?: accent;
        UIView *tile = [[UIView alloc] init];
        tile.translatesAutoresizingMaskIntoConstraints = NO;
        tile.backgroundColor = [tileAccent colorWithAlphaComponent:0.18];
        tile.layer.cornerRadius = 15.0;
        tile.layer.cornerCurve = kCACornerCurveContinuous;
        tile.clipsToBounds = YES;
        tile.layer.borderWidth = 2.0;
        tile.layer.borderColor = UIColor.secondarySystemGroupedBackgroundColor.CGColor;

        UIImage *placeholder = [UIImage systemImageNamed:item[@"symbol"] ?: @"photo.on.rectangle.angled"] ?:
            [UIImage systemImageNamed:@"photo.on.rectangle.angled"];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:placeholder];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.tintColor = [tileAccent colorWithAlphaComponent:0.70];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        [tile addSubview:imageView];
        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
            [imageView.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
            [imageView.topAnchor constraintEqualToAnchor:tile.topAnchor],
            [imageView.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor],
        ]];
        [self snowBoardLiteLoadOnlinePreviewURLString:url intoImageView:imageView];

        [card addSubview:tile];
        [previewTiles addObject:tile];
    }

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"Online Themes";
    title.textColor = UIColor.labelColor;
    title.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBlack];
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = row[@"subtitle"] ?: @"";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:12.8 weight:UIFontWeightSemibold];
    subtitle.numberOfLines = 2;
    [card addSubview:subtitle];

    UIView *pill = [self snowBoardLiteCountCapsuleWithText:[NSString stringWithFormat:@"%lu curated", (unsigned long)items.count]
                                                     color:accent];
    [card addSubview:pill];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = UIColor.tertiaryLabelColor;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12.0],
        [card.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12.0],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8.0],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8.0],
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:118.0],

        [glow.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [glow.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [glow.widthAnchor constraintEqualToConstant:96.0],
        [glow.heightAnchor constraintEqualToConstant:76.0],

        [previewTiles[0].leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0],
        [previewTiles[0].centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [previewTiles[0].widthAnchor constraintEqualToConstant:44.0],
        [previewTiles[0].heightAnchor constraintEqualToConstant:72.0],
        [previewTiles[1].leadingAnchor constraintEqualToAnchor:previewTiles[0].leadingAnchor constant:28.0],
        [previewTiles[1].centerYAnchor constraintEqualToAnchor:previewTiles[0].centerYAnchor constant:-7.0],
        [previewTiles[1].widthAnchor constraintEqualToAnchor:previewTiles[0].widthAnchor],
        [previewTiles[1].heightAnchor constraintEqualToAnchor:previewTiles[0].heightAnchor],
        [previewTiles[2].leadingAnchor constraintEqualToAnchor:previewTiles[0].leadingAnchor constant:50.0],
        [previewTiles[2].centerYAnchor constraintEqualToAnchor:previewTiles[0].centerYAnchor constant:8.0],
        [previewTiles[2].widthAnchor constraintEqualToAnchor:previewTiles[0].widthAnchor],
        [previewTiles[2].heightAnchor constraintEqualToAnchor:previewTiles[0].heightAnchor],

        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:12.0],
        [chevron.heightAnchor constraintEqualToConstant:18.0],

        [title.leadingAnchor constraintEqualToAnchor:glow.trailingAnchor constant:18.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],
        [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],

        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-12.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5.0],

        [pill.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [pill.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:9.0],
        [pill.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-16.0],
    ]];

    return cell;
}

- (UITableViewCell *)buildSnowBoardLiteCardCellInTableView:(UITableView *)tableView
                                                       row:(NSDictionary *)row
                                                 indexPath:(NSIndexPath *)indexPath
{
    NSString *kind = row[@"kind"] ?: @"";
    if ([kind isEqualToString:@"sbl-online-entry"]) {
        return [self buildSnowBoardLiteOnlineEntryCellInTableView:tableView
                                                              row:row
                                                        indexPath:indexPath];
    }
    if ([kind isEqualToString:@"sbl-carousel"]) {
        return [self buildSnowBoardLiteCarouselCellInTableView:tableView
                                                           row:row
                                                     indexPath:indexPath];
    }
    if ([kind isEqualToString:@"sbl-online"]) {
        return [self buildSnowBoardLiteOnlineDownloadsCellInTableView:tableView
                                                                  row:row
                                                            indexPath:indexPath];
    }
    if ([kind isEqualToString:@"sbl-help"]) {
        return [self buildSnowBoardLiteHelpCellInTableView:tableView
                                                       row:row
                                                 indexPath:indexPath];
    }
    if ([kind isEqualToString:@"sbl-theme"]) {
        return [self buildSnowBoardLiteThemeCardCellInTableView:tableView
                                                            row:row
                                                      indexPath:indexPath];
    }

    BOOL hero = [kind isEqualToString:@"sbl-hero"];
    BOOL section = [kind isEqualToString:@"sbl-section"];
    BOOL selected = [row[@"selected"] boolValue];
    BOOL destructive = [row[@"destructive"] boolValue];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sbl-card"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"sbl-card"];
    }
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = (hero || section)
        ? UITableViewCellSelectionStyleNone
        : UITableViewCellSelectionStyleDefault;
    cell.userInteractionEnabled = !hero && !section;
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    UIColor *accent = [self snowBoardLiteAccentColorNamed:row[@"color"] ?: @"mint"];
    NSString *symbol = row[@"icon"] ?: @"square.stack.3d.up.fill";

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = hero ? 26.0 : 20.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.18].CGColor;
    card.backgroundColor = hero
        ? [accent colorWithAlphaComponent:0.16]
        : UIColor.secondarySystemGroupedBackgroundColor;
    [cell.contentView addSubview:card];

    UIView *stripe = [[UIView alloc] init];
    stripe.translatesAutoresizingMaskIntoConstraints = NO;
    stripe.backgroundColor = accent;
    stripe.layer.cornerRadius = 3.0;
    stripe.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:stripe];

    UIView *iconPlate = [[UIView alloc] init];
    iconPlate.translatesAutoresizingMaskIntoConstraints = NO;
    iconPlate.backgroundColor = [accent colorWithAlphaComponent:hero ? 0.22 : 0.14];
    iconPlate.layer.cornerRadius = hero ? 19.0 : 16.0;
    iconPlate.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:iconPlate];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = destructive ? UIColor.systemRedColor : accent;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [iconPlate addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = row[@"title"] ?: @"";
    title.textColor = destructive ? UIColor.systemRedColor : UIColor.labelColor;
    title.font = hero
        ? [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold]
        : [UIFont systemFontOfSize:16.5 weight:UIFontWeightSemibold];
    title.numberOfLines = hero ? 2 : 1;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = row[@"subtitle"] ?: @"";
    subtitle.textColor = destructive
        ? [UIColor.systemRedColor colorWithAlphaComponent:0.78]
        : UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:hero ? 13.5 : 12.8 weight:UIFontWeightMedium];
    subtitle.numberOfLines = hero ? 3 : 2;
    [card addSubview:subtitle];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"chevron.right"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = selected ? accent : UIColor.tertiaryLabelColor;
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.hidden = hero || section;
    [card addSubview:chevron];

    UILabel *kicker = nil;
    if (hero || section) {
        kicker = [[UILabel alloc] init];
        kicker.translatesAutoresizingMaskIntoConstraints = NO;
        NSString *kickerText = hero ? @"SNOWBOARD LITE" : @"LIBRARY";
        kicker.attributedText = [[NSAttributedString alloc]
            initWithString:kickerText
                attributes:@{NSKernAttributeName: @0.8}];
        kicker.textColor = [accent colorWithAlphaComponent:0.95];
        kicker.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
        [card addSubview:kicker];
    }

    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    CGFloat top = hero ? 8.0 : 5.0;
    CGFloat bottom = hero ? -10.0 : -5.0;
    CGFloat cardPadding = hero ? 18.0 : 15.0;
    CGFloat iconSize = hero ? 54.0 : 44.0;
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:top],
        [card.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:bottom],

        [stripe.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:0.0],
        [stripe.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [stripe.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0],
        [stripe.widthAnchor constraintEqualToConstant:5.0],

        [iconPlate.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:cardPadding],
        [iconPlate.topAnchor constraintEqualToAnchor:card.topAnchor constant:cardPadding],
        [iconPlate.widthAnchor constraintEqualToConstant:iconSize],
        [iconPlate.heightAnchor constraintEqualToConstant:iconSize],

        [icon.centerXAnchor constraintEqualToAnchor:iconPlate.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconPlate.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:hero ? 30.0 : 24.0],
        [icon.heightAnchor constraintEqualToConstant:hero ? 30.0 : 24.0],

        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-cardPadding],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:22.0],
        [chevron.heightAnchor constraintEqualToConstant:22.0],
    ]];

    UIView *textTrailing = (hero || section) ? card : chevron;
    if (kicker) {
        [NSLayoutConstraint activateConstraints:@[
            [kicker.leadingAnchor constraintEqualToAnchor:iconPlate.trailingAnchor constant:14.0],
            [kicker.trailingAnchor constraintEqualToAnchor:textTrailing.trailingAnchor constant:(hero || section) ? -cardPadding : -10.0],
            [kicker.topAnchor constraintEqualToAnchor:card.topAnchor constant:cardPadding],
            [title.leadingAnchor constraintEqualToAnchor:kicker.leadingAnchor],
            [title.trailingAnchor constraintEqualToAnchor:kicker.trailingAnchor],
            [title.topAnchor constraintEqualToAnchor:kicker.bottomAnchor constant:5.0],
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:iconPlate.trailingAnchor constant:14.0],
            [title.trailingAnchor constraintEqualToAnchor:textTrailing.leadingAnchor constant:-10.0],
            [title.topAnchor constraintEqualToAnchor:card.topAnchor constant:cardPadding],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-cardPadding],
        [iconPlate.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-cardPadding],
    ]];

    if (section) {
        card.backgroundColor = [accent colorWithAlphaComponent:0.10];
        cell.userInteractionEnabled = NO;
    }

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Preserve the table view's actual indexPath for dequeue calls (which
    // expect a path that exists in the current data source). `indexPath`
    // is remapped to the underlying SettingsSection for content lookup.
    NSIndexPath *dequeuePath = indexPath;

    if (!self.detailMode) {
        switch ((RootSection)indexPath.section) {
            case RootSectionWarning:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionWarning];
                break;
            case RootSectionChangelog: {
                NSInteger entryCount = (NSInteger)settings_changelog_entries().count;
                if (indexPath.row >= entryCount) {
                    return [self buildChangelogFooterCellInTableView:tableView];
                }
                return [self buildChangelogCellAtRow:indexPath.row tableView:tableView];
            }
            case RootSectionActions:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionActions];
                break;
            case RootSectionTweakBundles:
                return [self buildBundleCellWithRow:self.tweakBundleRows[indexPath.row] tableView:tableView];
            case RootSectionSystemBundles:
                return [self buildBundleCellWithRow:self.systemBundleRows[indexPath.row] tableView:tableView];
            case RootSectionAppIcon:
                return [self buildAppIconCellAtRow:indexPath.row tableView:tableView];
            case RootSectionDocs:
                return [self buildDocsCellInTableView:tableView];
            case RootSectionAbout:
                return [self buildAboutCellAtRow:indexPath.row tableView:tableView];
            case RootSectionExperimental:
                return [self buildExperimentalCellInTableView:tableView];
            case RootSectionCount:
                return [[UITableViewCell alloc] init];
        }
    } else {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:self.underlyingSection];
    }

    if (indexPath.section == SectionWarning) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"warning" forIndexPath:dequeuePath];
        return [self buildWarningCell:cell];
    }
    if (indexPath.section == SectionActions) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action" forIndexPath:dequeuePath];
        cell.textLabel.text = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

        BOOL supported = settings_device_supported();
        BOOL cleanupEnabled = supported && (g_kexploit_done ||
                                            g_springboard_rc_ready ||
                                            remote_call_has_local_state());
        BOOL anyInstalledOrQueued = NO;
        for (Package *p in [PackageCatalog allPackages]) {
            if (p.isInstalled || p.isQueuedForApply) { anyInstalledOrQueued = YES; break; }
        }
        if (!anyInstalledOrQueued) {
            anyInstalledOrQueued = [[PackageQueue sharedQueue] pendingCount] > 0;
        }
        BOOL rowEnabled = supported;
        if (indexPath.row == 0) rowEnabled = cleanupEnabled;
        if (indexPath.row == 2) rowEnabled = anyInstalledOrQueued;
        if (indexPath.row == 3) rowEnabled = YES;     // network check is always allowed
        if (indexPath.row == 4) rowEnabled = NO;       // disabled while in development

        UILabel *primary = [[UILabel alloc] init];
        primary.translatesAutoresizingMaskIntoConstraints = NO;
        primary.textAlignment = NSTextAlignmentCenter;
        primary.font = [UIFont systemFontOfSize:17];
        if (indexPath.row == 0) {
            primary.text = g_settings_cleanup_running ? @" " : @"Clean Up";
            primary.textColor = cleanupEnabled ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 1) {
            primary.text = g_settings_respring_cleanup_running ? @" " : @"Respring";
            primary.textColor = supported ? UIColor.systemOrangeColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 2) {
            primary.text = @"Reset All Packages";
            primary.textColor = anyInstalledOrQueued ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 3) {
            primary.text = @"Check for Updates";
            primary.textColor = self.view.tintColor;
        } else {
            primary.text = @"Kill Background Apps (in development)";
            primary.textColor = UIColor.tertiaryLabelColor;
        }
        [cell.contentView addSubview:primary];

        // Clean Up + Respring rows: replace the label with a spinning indicator
        // while cleanup is in progress so the user sees we're not hung.
        BOOL showSpinner =
            (indexPath.row == 0 && g_settings_cleanup_running) ||
            (indexPath.row == 1 && g_settings_respring_cleanup_running);
        if (showSpinner) {
            UIActivityIndicatorView *spin =
                [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
                    UIActivityIndicatorViewStyleMedium];
            spin.translatesAutoresizingMaskIntoConstraints = NO;
            spin.color = (indexPath.row == 1) ? UIColor.systemOrangeColor : UIColor.systemRedColor;
            spin.hidesWhenStopped = YES;
            [spin startAnimating];
            [cell.contentView addSubview:spin];
            [NSLayoutConstraint activateConstraints:@[
                [spin.centerXAnchor constraintEqualToAnchor:primary.centerXAnchor],
                [spin.centerYAnchor constraintEqualToAnchor:primary.centerYAnchor],
            ]];
        }

        if (!rowEnabled) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.userInteractionEnabled = NO;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.userInteractionEnabled = YES;
        }

        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        NSString *detailText = nil;
        UIColor *detailColor = UIColor.secondaryLabelColor;
        if (indexPath.row == 0) {
            if (g_settings_cleanup_running) {
                detailText = @"Cleaning up…";
                detailColor = UIColor.secondaryLabelColor;
            } else {
                detailText = cleanupEnabled
                    ? @"Stops live SpringBoard sessions, parks the KRW socket state, and closes this app's local KRW fds. Next run tries launchd recovery first."
                    : @"No local KRW session.";
                detailColor = cleanupEnabled ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
            }
        } else if (indexPath.row == 1) {
            detailText = g_settings_respring_cleanup_running
                ? @"Cleaning up…"
                : @"Clean up is auto run prior to respring to ensure a clean state.";
            detailColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 2) {
            detailText = anyInstalledOrQueued
                ? @"Uninstall every package and clear the pending queue. SpringBoard patches already applied this session stay until respring/reboot."
                : @"Nothing installed or queued.";
            detailColor = anyInstalledOrQueued ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        } else if (indexPath.row == 3) {
            detailText  = @"Pings GitHub for the latest release. Run this if the launch prompt didn't appear.";
            detailColor = UIColor.secondaryLabelColor;
        } else if (indexPath.row == 4) {
            detailText  = @"In development — still over-kills background services. Disabled until the filter is right.";
            detailColor = UIColor.tertiaryLabelColor;
        }
        if (detailText) {
            UILabel *detail = [[UILabel alloc] init];
            detail.translatesAutoresizingMaskIntoConstraints = NO;
            detail.text = detailText;
            detail.textColor = detailColor;
            detail.font = [UIFont systemFontOfSize:12];
            detail.textAlignment = NSTextAlignmentCenter;
            detail.numberOfLines = 0;
            [cell.contentView addSubview:detail];
            [NSLayoutConstraint activateConstraints:@[
                [primary.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
                [primary.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
                [primary.topAnchor      constraintEqualToAnchor:m.topAnchor constant:2],
                [detail.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
                [detail.trailingAnchor  constraintEqualToAnchor:m.trailingAnchor],
                [detail.topAnchor       constraintEqualToAnchor:primary.bottomAnchor constant:2],
                [detail.bottomAnchor    constraintEqualToAnchor:m.bottomAnchor constant:-2],
            ]];
        } else {
            [NSLayoutConstraint activateConstraints:@[
                [primary.leadingAnchor  constraintEqualToAnchor:m.leadingAnchor],
                [primary.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
                [primary.topAnchor      constraintEqualToAnchor:m.topAnchor],
                [primary.bottomAnchor   constraintEqualToAnchor:m.bottomAnchor],
            ]];
        }
        return cell;
    }

    NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
    NSString *kind = row[@"kind"] ?: @"toggle";
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL supported = settings_device_supported();

    if ([kind hasPrefix:@"sbl-"]) {
        return [self buildSnowBoardLiteCardCellInTableView:tableView
                                                       row:row
                                                 indexPath:dequeuePath];
    }

    if ([kind isEqualToString:@"info"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"info"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"info"];
            cell.detailTextLabel.numberOfLines = 0;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = NO;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = row[@"subtitle"];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
        return cell;
    }

    if ([kind isEqualToString:@"nicebar-grid"]) {
        return [self buildNiceBarGridCellInTableView:tableView indexPath:dequeuePath];
    }

    if ([kind isEqualToString:@"nsbar-grid"]) {
        return [self buildNSBarGridCellInTableView:tableView indexPath:dequeuePath];
    }

    if ([kind isEqualToString:@"layout-calibration"]) {
        return [self buildLayoutCalibrationCellInTableView:tableView
                                                       row:row
                                                 indexPath:dequeuePath];
    }

    if ([kind isEqualToString:@"button"]) {
        BOOL rowSupported = supported ||
                            indexPath.section == SectionOTA ||
                            indexPath.section == SectionThemer ||
                            indexPath.section == SectionSnowBoardLite;
        NSString *action = row[@"action"];
        if (indexPath.section == SectionLiveWP &&
            ([action isEqualToString:@"livewp-select-video"] ||
             [action isEqualToString:@"livewp-online-video"])) {
            rowSupported = YES;
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"livewp-picker"];
            cell.selectionStyle = rowSupported ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
            cell.backgroundColor = UIColor.clearColor;
            cell.contentView.backgroundColor = UIColor.clearColor;
            cell.separatorInset = UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0);

            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.translatesAutoresizingMaskIntoConstraints = NO;
            button.enabled = rowSupported;
            [button setTitle:row[@"title"] forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
            [button setTitleColor:rowSupported ? self.view.tintColor : UIColor.tertiaryLabelColor
                          forState:UIControlStateNormal];
            button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            button.layer.cornerRadius = 24.0;
            button.layer.cornerCurve = kCACornerCurveContinuous;
            button.layer.borderWidth = 1.0;
            button.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.22].CGColor;
            SEL buttonAction = [action isEqualToString:@"livewp-online-video"]
                ? @selector(showLiveWPOnlineDownloader)
                : @selector(showLiveWPVideoPicker);
            [button addTarget:self action:buttonAction forControlEvents:UIControlEventTouchUpInside];
            [cell.contentView addSubview:button];

            UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [button.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
                [button.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
                [button.topAnchor constraintEqualToAnchor:m.topAnchor constant:6.0],
                [button.bottomAnchor constraintEqualToAnchor:m.bottomAnchor constant:-6.0],
                [button.heightAnchor constraintEqualToConstant:50.0],
            ]];
            return cell;
        }
        if (indexPath.section == SectionNanoRegistry &&
            [action isEqualToString:@"nano-load"]) {
            rowSupported = settings_nano_load_override_enabled();
        }
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"button" forIndexPath:dequeuePath];
        cell.selectionStyle = rowSupported ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = rowSupported;
        cell.accessoryView = nil;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = rowSupported
            ? ([row[@"destructive"] boolValue] ? UIColor.systemRedColor : self.view.tintColor)
            : UIColor.tertiaryLabelColor;
        return cell;
    }

    if ([kind isEqualToString:@"stepper"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"stepper" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        NSInteger value = [d integerForKey:row[@"key"]];
        NSString *combined = [NSString stringWithFormat:@"%@: %ld", row[@"title"], (long)value];
        NSString *subtitle = row[@"subtitle"];
        if (subtitle.length > 0) {
            UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
            config.text = combined;
            config.secondaryText = subtitle;
            config.textToSecondaryTextVerticalPadding = 3;
            config.textProperties.color = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
            config.secondaryTextProperties.color = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
            config.secondaryTextProperties.font = [UIFont systemFontOfSize:12];
            config.secondaryTextProperties.numberOfLines = 0;
            cell.contentConfiguration = config;
        } else {
            cell.contentConfiguration = nil;
            cell.textLabel.text = combined;
        }
        UIStepper *stp = [[UIStepper alloc] init];
        stp.minimumValue = [row[@"min"] doubleValue];
        stp.maximumValue = [row[@"max"] doubleValue];
        stp.stepValue = 1;
        stp.value = (double)value;
        stp.enabled = supported;
        stp.tag = (indexPath.section << 16) | indexPath.row;
        [stp addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stp;
        return cell;
    }

    if ([kind isEqualToString:@"slider"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"slider" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryView = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

        NSInteger minV = [row[@"min"] integerValue];
        NSInteger maxV = [row[@"max"] integerValue];
        NSInteger step = [row[@"step"] integerValue]; if (step <= 0) step = 1;
        NSInteger value = [d integerForKey:row[@"key"]];
        if (value < minV) value = minV;
        if (value > maxV) value = maxV;
        NSString *unit = row[@"unit"] ?: @"";

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = row[@"title"];
        title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        title.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;

        UILabel *valueLabel = [[UILabel alloc] init];
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        valueLabel.text = [NSString stringWithFormat:@"%ld%@", (long)value, unit];
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        valueLabel.textColor = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        valueLabel.textAlignment = NSTextAlignmentRight;

        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = (float)minV;
        slider.maximumValue = (float)maxV;
        slider.value = (float)value;
        slider.continuous = YES;
        slider.enabled = supported;
        slider.tag = (indexPath.section << 16) | indexPath.row;
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        // Stash the value label so sliderChanged: can update it without a full reload.
        objc_setAssociatedObject(slider, "cyanideValueLabel", valueLabel, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(slider, "cyanideUnit", unit, OBJC_ASSOCIATION_RETAIN);
        objc_setAssociatedObject(slider, "cyanideStep", @(step), OBJC_ASSOCIATION_RETAIN);

        [cell.contentView addSubview:title];
        [cell.contentView addSubview:valueLabel];
        [cell.contentView addSubview:slider];

        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor      constraintEqualToAnchor:m.leadingAnchor],
            [title.topAnchor          constraintEqualToAnchor:m.topAnchor],
            [valueLabel.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [valueLabel.centerYAnchor  constraintEqualToAnchor:title.centerYAnchor],
            [valueLabel.leadingAnchor  constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8],
            [slider.leadingAnchor   constraintEqualToAnchor:m.leadingAnchor],
            [slider.trailingAnchor  constraintEqualToAnchor:m.trailingAnchor],
            [slider.topAnchor       constraintEqualToAnchor:title.bottomAnchor constant:4],
            [slider.bottomAnchor    constraintEqualToAnchor:m.bottomAnchor],
        ]];
        return cell;
    }

    if ([kind isEqualToString:@"segmented"]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"segmented" forIndexPath:dequeuePath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = nil;
        for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
        
        NSString *key = row[@"key"];
        NSArray<NSString *> *items = nil;
        id currentValue = nil;
        NSUInteger selectedIndex = 0;
        SEL changeAction = nil;
        
        if ([key isEqualToString:kSettingsPowercuffLevel]) {
            items = powercuff_levels();
            currentValue = [d stringForKey:key] ?: @"nominal";
            selectedIndex = [items indexOfObject:currentValue];
            if (selectedIndex == NSNotFound) selectedIndex = [items indexOfObject:@"nominal"];
            changeAction = @selector(powercuffSegChanged:);
        } else if ([key isEqualToString:kSettingsNSBarPosition]) {
            items = nsbar_positions();
            NSInteger pos = [d integerForKey:key];
            selectedIndex = (pos >= 0 && pos < (NSInteger)items.count) ? pos : 0;
            changeAction = @selector(nsbarSegChanged:);
        }
        
        if (!items) items = @[@"Error"];
        
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:items];
        seg.translatesAutoresizingMaskIntoConstraints = NO;
        seg.selectedSegmentIndex = (NSInteger)selectedIndex;
        seg.enabled = supported;
        if (changeAction) {
            [seg addTarget:self action:changeAction forControlEvents:UIControlEventValueChanged];
        }
        [cell.contentView addSubview:seg];
        [NSLayoutConstraint activateConstraints:@[
            [seg.leadingAnchor  constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [seg.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [seg.topAnchor      constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.topAnchor],
            [seg.bottomAnchor   constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.bottomAnchor],
        ]];
        return cell;
    }

    // Inline video preview cell
    if ([kind isEqualToString:@"preview"]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"preview"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;

        NSString *videoPath = row[@"videoPath"];
        BOOL hasVideo = videoPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:videoPath];

        UIView *phoneFrame = [[UIView alloc] init];
        phoneFrame.translatesAutoresizingMaskIntoConstraints = NO;
        phoneFrame.backgroundColor = UIColor.blackColor;
        phoneFrame.clipsToBounds = YES;
        phoneFrame.layer.cornerRadius = 24.0;
        phoneFrame.layer.borderWidth = 1.0;
        phoneFrame.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.35].CGColor;
        UITapGestureRecognizer *previewTap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showLiveWPVideoPicker)];
        [phoneFrame addGestureRecognizer:previewTap];
        phoneFrame.userInteractionEnabled = YES;
        [cell.contentView addSubview:phoneFrame];

        UIStackView *sideStack = [[UIStackView alloc] init];
        sideStack.translatesAutoresizingMaskIntoConstraints = NO;
        sideStack.axis = UILayoutConstraintAxisVertical;
        sideStack.alignment = UIStackViewAlignmentFill;
        sideStack.spacing = 10.0;
        [cell.contentView addSubview:sideStack];

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = row[@"title"];
        titleLabel.textColor = UIColor.labelColor;
        titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        titleLabel.numberOfLines = 2;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [sideStack addArrangedSubview:titleLabel];

        UILabel *detailLabel = [[UILabel alloc] init];
        detailLabel.text = row[@"subtitle"];
        detailLabel.textColor = UIColor.secondaryLabelColor;
        detailLabel.font = [UIFont systemFontOfSize:13.0];
        detailLabel.numberOfLines = 0;
        [sideStack addArrangedSubview:detailLabel];

        UILabel *modeLabel = [[UILabel alloc] init];
        modeLabel.text = hasVideo ? @"Preview only. Enable LiveWP and Apply Tweaks to use it on-device." : @"Pick a video first, then enable LiveWP and apply it.";
        modeLabel.textColor = UIColor.tertiaryLabelColor;
        modeLabel.font = [UIFont systemFontOfSize:12.0];
        modeLabel.numberOfLines = 0;
        [sideStack addArrangedSubview:modeLabel];

        UIStackView *controlStack = [[UIStackView alloc] init];
        controlStack.axis = UILayoutConstraintAxisHorizontal;
        controlStack.alignment = UIStackViewAlignmentCenter;
        controlStack.spacing = 10.0;
        [sideStack addArrangedSubview:controlStack];

        UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [playBtn setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        playBtn.tintColor = UIColor.whiteColor;
        playBtn.backgroundColor = hasVideo ? self.view.tintColor : UIColor.tertiaryLabelColor;
        playBtn.layer.cornerRadius = 20.0;
        playBtn.translatesAutoresizingMaskIntoConstraints = NO;
        playBtn.enabled = hasVideo;
        [controlStack addArrangedSubview:playBtn];

        UIButton *replayBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [replayBtn setImage:[UIImage systemImageNamed:@"gobackward"] forState:UIControlStateNormal];
        replayBtn.tintColor = self.view.tintColor;
        replayBtn.backgroundColor = UIColor.secondarySystemFillColor;
        replayBtn.layer.cornerRadius = 20.0;
        replayBtn.translatesAutoresizingMaskIntoConstraints = NO;
        replayBtn.enabled = hasVideo;
        [controlStack addArrangedSubview:replayBtn];

        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [phoneFrame.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [phoneFrame.topAnchor constraintEqualToAnchor:m.topAnchor constant:8.0],
            [phoneFrame.bottomAnchor constraintEqualToAnchor:m.bottomAnchor constant:-8.0],
            [phoneFrame.widthAnchor constraintEqualToConstant:154.0],

            [sideStack.leadingAnchor constraintEqualToAnchor:phoneFrame.trailingAnchor constant:16.0],
            [sideStack.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [sideStack.centerYAnchor constraintEqualToAnchor:phoneFrame.centerYAnchor],
            [sideStack.topAnchor constraintGreaterThanOrEqualToAnchor:m.topAnchor constant:12.0],
            [sideStack.bottomAnchor constraintLessThanOrEqualToAnchor:m.bottomAnchor constant:-12.0],

            [playBtn.widthAnchor constraintEqualToConstant:40.0],
            [playBtn.heightAnchor constraintEqualToConstant:40.0],
            [replayBtn.widthAnchor constraintEqualToConstant:40.0],
            [replayBtn.heightAnchor constraintEqualToConstant:40.0],
        ]];

        if (!hasVideo) {
            UIImageView *placeholderIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"video.slash"]];
            placeholderIcon.translatesAutoresizingMaskIntoConstraints = NO;
            placeholderIcon.tintColor = UIColor.tertiaryLabelColor;
            placeholderIcon.contentMode = UIViewContentModeScaleAspectFit;
            [phoneFrame addSubview:placeholderIcon];

            UILabel *placeholder = [[UILabel alloc] init];
            placeholder.translatesAutoresizingMaskIntoConstraints = NO;
            placeholder.text = @"No Preview";
            placeholder.textColor = UIColor.tertiaryLabelColor;
            placeholder.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
            placeholder.textAlignment = NSTextAlignmentCenter;
            [phoneFrame addSubview:placeholder];

            [NSLayoutConstraint activateConstraints:@[
                [placeholderIcon.centerXAnchor constraintEqualToAnchor:phoneFrame.centerXAnchor],
                [placeholderIcon.centerYAnchor constraintEqualToAnchor:phoneFrame.centerYAnchor constant:-12.0],
                [placeholderIcon.widthAnchor constraintEqualToConstant:34.0],
                [placeholderIcon.heightAnchor constraintEqualToConstant:34.0],
                [placeholder.leadingAnchor constraintEqualToAnchor:phoneFrame.leadingAnchor constant:8.0],
                [placeholder.trailingAnchor constraintEqualToAnchor:phoneFrame.trailingAnchor constant:-8.0],
                [placeholder.topAnchor constraintEqualToAnchor:placeholderIcon.bottomAnchor constant:8.0],
            ]];

            return cell;
        }

        if (hasVideo) {
            @try {
                static void *avfHandle = NULL;
                if (!avfHandle) avfHandle = dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY | RTLD_GLOBAL);

                Class PlayerItemClass = NSClassFromString(@"AVPlayerItem");
                Class PlayerClass = NSClassFromString(@"AVPlayer");
                Class PlayerLayerClass = NSClassFromString(@"AVPlayerLayer");

                if (PlayerItemClass && PlayerClass && PlayerLayerClass) {
                    NSURL *url = [NSURL fileURLWithPath:videoPath];
                    id item = [PlayerItemClass performSelector:@selector(playerItemWithURL:) withObject:url];
                    id player = [PlayerClass performSelector:@selector(playerWithPlayerItem:) withObject:item];
                    [player setValue:@YES forKey:@"muted"];

                    // 循环
                    NSMutableData *cmtime = [NSMutableData dataWithLength:24];
                    int32_t ts = 1; uint32_t fl = 0x1;
                    [cmtime replaceBytesInRange:NSMakeRange(8, 4) withBytes:&ts];
                    [cmtime replaceBytesInRange:NSMakeRange(12, 4) withBytes:&fl];
                    NSData *capturedCmtime = [cmtime copy];
                    id capturedItem = item;
                    [[NSNotificationCenter defaultCenter] addObserverForName:@"AVPlayerItemDidPlayToEndTimeNotification"
                                                                      object:item queue:NSOperationQueue.mainQueue
                                                                  usingBlock:^(NSNotification *note) {
                        NSMethodSignature *sig = [capturedItem methodSignatureForSelector:@selector(seekToTime:)];
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        [inv setTarget:capturedItem]; [inv setSelector:@selector(seekToTime:)];
                        [inv setArgument:(void *)[capturedCmtime bytes] atIndex:2];
                        [inv invoke];
                    }];

                    id layer = [PlayerLayerClass performSelector:@selector(playerLayerWithPlayer:) withObject:player];
                    [layer setValue:@"AVLayerVideoGravityResizeAspectFill" forKey:@"videoGravity"];
                    [phoneFrame.layer addSublayer:layer];
                    // 布局后更新 layer frame
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [layer setFrame:phoneFrame.bounds];
                    });

                    objc_setAssociatedObject(playBtn, "livewp_btn_player", player, OBJC_ASSOCIATION_ASSIGN);
                    objc_setAssociatedObject(playBtn, "livewp_btn_layer", layer, OBJC_ASSOCIATION_ASSIGN);
                    [playBtn addTarget:self action:@selector(livewpPreviewToggle:) forControlEvents:UIControlEventTouchUpInside];

                    objc_setAssociatedObject(replayBtn, "livewp_btn_player", player, OBJC_ASSOCIATION_ASSIGN);
                    objc_setAssociatedObject(replayBtn, "livewp_btn_item", item, OBJC_ASSOCIATION_ASSIGN);
                    objc_setAssociatedObject(replayBtn, "livewp_btn_play", playBtn, OBJC_ASSOCIATION_ASSIGN);
                    [replayBtn addTarget:self action:@selector(livewpPreviewReplay:) forControlEvents:UIControlEventTouchUpInside];

                    objc_setAssociatedObject(cell, "livewp_preview_player", player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(cell, "livewp_preview_item", item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(cell, "livewp_preview_btn", playBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } @catch (NSException *e) {
                log_user("[LIVEWP] preview error: %s\n", e.reason.UTF8String);
            }
        }

        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"toggle" forIndexPath:dequeuePath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSString *subtitle = row[@"subtitle"];
    if (subtitle.length > 0) {
        UIListContentConfiguration *config = [UIListContentConfiguration cellConfiguration];
        config.text = row[@"title"];
        config.secondaryText = subtitle;
        config.textToSecondaryTextVerticalPadding = 3;
        config.textProperties.color = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        config.secondaryTextProperties.color = supported ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
        config.secondaryTextProperties.font = [UIFont systemFontOfSize:12];
        config.secondaryTextProperties.numberOfLines = 0;
        cell.contentConfiguration = config;
    } else {
        cell.contentConfiguration = nil;
        cell.textLabel.text = row[@"title"];
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
        cell.textLabel.textColor = supported ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    }
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = [d boolForKey:row[@"key"]];
    sw.enabled = supported;
    sw.tag = (indexPath.section << 16) | indexPath.row;
    [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

#pragma mark - Actions

- (NSDictionary *)rowForTag:(NSInteger)tag
{
    NSInteger section = (tag >> 16) & 0xFFFF;
    NSInteger row = tag & 0xFFFF;
    return [self rowsForSection:section][row];
}

- (void)presentApplyLogIfRunning
{
    // Skip if a modal is already up (e.g. the user just toggled a different
    // switch and the log is already visible).
    if (self.presentedViewController) return;
    // Skip if there's no live SpringBoard session — the change won't fire any
    // RemoteCall until the user runs the chain, so there's nothing to watch.
    if (!g_springboard_rc_ready) return;

    InstallProgressViewController *vc = [[InstallProgressViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationAutomatic;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)toggleChanged:(UISwitch *)sender
{
    if (!settings_device_supported()) {
        sender.on = !sender.isOn;
        printf("[SETTINGS] toggle blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSDictionary *row = [self rowForTag:sender.tag];
    NSString *key = row[@"key"];
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    printf("[SETTINGS] toggle %s=%d\n", key.UTF8String, sender.isOn);
    if ([key isEqualToString:kSettingsKeepAlive]) {
        ds_keepalive_apply_enabled(sender.isOn);
        return;
    }
    if (settings_key_affects_package_state(key)) {
        if (!sender.isOn) settings_mark_tweak_applied(key, NO);
        settings_notify_package_queue_changed_async();
    }
    settings_schedule_live_apply_for_key(key);
    if (!settings_key_is_nicebarlite(key)) {
        [self presentApplyLogIfRunning];
    }
}

- (void)sliderChanged:(UISlider *)sender
{
    if (!settings_device_supported()) return;
    NSNumber *stepNum = objc_getAssociatedObject(sender, "cyanideStep");
    NSInteger step = stepNum ? [stepNum integerValue] : 1;
    if (step <= 0) step = 1;
    NSInteger value = (NSInteger)llround((double)sender.value / (double)step) * step;
    UILabel *valueLabel = objc_getAssociatedObject(sender, "cyanideValueLabel");
    NSString *unit = objc_getAssociatedObject(sender, "cyanideUnit") ?: @"";
    if (valueLabel) {
        valueLabel.text = [NSString stringWithFormat:@"%ld%@", (long)value, unit];
    }
}

- (void)sliderEnded:(UISlider *)sender
{
    if (!settings_device_supported()) return;
    NSDictionary *row = [self rowForTag:sender.tag];
    if (!row) return;
    NSString *key = row[@"key"];
    NSInteger step = [row[@"step"] integerValue]; if (step <= 0) step = 1;
    NSInteger value = (NSInteger)llround((double)sender.value / (double)step) * step;
    sender.value = (float)value;  // snap thumb to the step grid
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    printf("[SETTINGS] slider %s=%ld\n", key.UTF8String, (long)value);
    settings_schedule_live_apply_for_key(key);
    [self presentApplyLogIfRunning];
}

- (void)layoutCalibrationApplyKey:(NSString *)key delayed:(BOOL)delayed
{
    if (key.length == 0) return;
    if (!settings_device_supported()) return;

    int64_t serial = __sync_add_and_fetch(&g_layout_slider_apply_serial, 1);
    void (^applyBlock)(void) = ^{
        if (delayed && serial != g_layout_slider_apply_serial) return;
        settings_schedule_live_apply_for_key(key);
    };
    if (delayed) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(),
                       applyBlock);
    } else {
        applyBlock();
    }
}

- (void)layoutCalibrationSliderChanged:(UISlider *)sender
{
    if (!settings_device_supported()) return;
    NSInteger value = (NSInteger)llround((double)sender.value);
    sender.value = (float)value;

    UILabel *valueLabel = objc_getAssociatedObject(sender, "cyanideLayoutValueLabel");
    if (valueLabel) valueLabel.text = [self layoutCalibrationValueText:value];

    NSString *key = objc_getAssociatedObject(sender, "cyanideLayoutKey");
    if (key.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    CyanideLayoutCalibrationPreviewView *preview = objc_getAssociatedObject(sender, "cyanideLayoutPreview");
    [preview setNeedsDisplay];
    [self layoutCalibrationApplyKey:key delayed:YES];
}

- (void)layoutCalibrationSliderEnded:(UISlider *)sender
{
    if (!settings_device_supported()) return;
    NSString *key = objc_getAssociatedObject(sender, "cyanideLayoutKey");
    if (key.length == 0) return;
    NSInteger value = (NSInteger)llround((double)sender.value);
    sender.value = (float)value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    UILabel *valueLabel = objc_getAssociatedObject(sender, "cyanideLayoutValueLabel");
    if (valueLabel) valueLabel.text = [self layoutCalibrationValueText:value];
    CyanideLayoutCalibrationPreviewView *preview = objc_getAssociatedObject(sender, "cyanideLayoutPreview");
    [preview setNeedsDisplay];
    printf("[SETTINGS] layout calibration %s=%ld\n", key.UTF8String, (long)value);
    [self layoutCalibrationApplyKey:key delayed:NO];
}

- (void)layoutCalibrationResetTapped:(UIButton *)sender
{
    if (!settings_device_supported()) return;
    NSString *scope = objc_getAssociatedObject(sender, "cyanideLayoutScope") ?: @"nicebar";
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *lastKey = nil;
    for (NSDictionary *item in [self layoutCalibrationItemsForScope:scope]) {
        NSString *key = item[@"key"];
        [d setInteger:0 forKey:key];
        lastKey = key;
    }
    [d synchronize];
    [self.tableView reloadData];
    [self layoutCalibrationApplyKey:lastKey delayed:NO];
}

- (void)stepperChanged:(UIStepper *)sender
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] stepper blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSDictionary *row = [self rowForTag:sender.tag];
    NSInteger value = (NSInteger)sender.value;
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:row[@"key"]];

    // NanoRegistry steppers are seed values for an explicit Apply button;
    // they don't drive a live SpringBoard RC loop, so skip the auto-apply.
    NSString *key = row[@"key"];
    BOOL isNano = [key isEqualToString:kSettingsNanoMaxPairing]
                || [key isEqualToString:kSettingsNanoMinPairing]
                || [key isEqualToString:kSettingsNanoMinPairingChipID]
                || [key isEqualToString:kSettingsNanoMinQuickSwitch];
    if (!isNano) {
        settings_schedule_live_apply_for_key(key);
        [self presentApplyLogIfRunning];
    }

    UIView *v = sender.superview;
    while (v && ![v isKindOfClass:UITableViewCell.class]) v = v.superview;
    UITableViewCell *cell = (UITableViewCell *)v;
    if (cell) {
        NSString *combined = [NSString stringWithFormat:@"%@: %ld", row[@"title"], (long)value];
        NSString *subtitle = row[@"subtitle"];
        if (subtitle.length > 0 && [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
            UIListContentConfiguration *config = (UIListContentConfiguration *)[(id<NSCopying>)cell.contentConfiguration copyWithZone:nil];
            config.text = combined;
            cell.contentConfiguration = config;
        } else {
            cell.textLabel.text = combined;
        }
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.detailMode || self.underlyingSection != SectionSnowBoardLite) return nil;

    NSArray<NSDictionary *> *rows = [self rowsForSection:SectionSnowBoardLite];
    if (indexPath.row >= (NSInteger)rows.count) return nil;
    NSDictionary *row = rows[indexPath.row];
    if (![row[@"kind"] isEqualToString:@"sbl-theme"]) return nil;

    NSString *themeID = row[@"id"] ?: @"";
    if (themeID.length == 0) return nil;

    UIContextualAction *remove = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"Remove"
                          handler:^(__kindof UIContextualAction *action,
                                    __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
        (void)action;
        (void)sourceView;
        [self removeSnowBoardLiteThemeID:themeID];
        completionHandler(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"trash"];

    UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration
        configurationWithActions:@[remove]];
    cfg.performsFirstActionWithFullSwipe = NO;
    return cfg;
}

- (void)powercuffSegChanged:(UISegmentedControl *)sender
{
    if (!settings_device_supported()) {
        printf("[SETTINGS] powercuff level blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    NSArray<NSString *> *levels = powercuff_levels();
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= (NSInteger)levels.count) return;
    [[NSUserDefaults standardUserDefaults] setObject:levels[sender.selectedSegmentIndex]
                                              forKey:kSettingsPowercuffLevel];
}

- (void)nsbarSegChanged:(UISegmentedControl *)sender
{
    if (sender.selectedSegmentIndex < 0 || sender.selectedSegmentIndex >= 5) return;
    [[NSUserDefaults standardUserDefaults] setInteger:sender.selectedSegmentIndex
                                               forKey:kSettingsNSBarPosition];
    [[NSUserDefaults standardUserDefaults] synchronize];
    printf("[SETTINGS] NSBar position changed to: %ld\n", (long)sender.selectedSegmentIndex);
    settings_schedule_live_apply_for_key(kSettingsNSBarPosition);
}

- (void)nsbarPositionButtonTapped:(UIButton *)sender
{
    NSInteger position = sender.tag;
    if (position < NSBarPositionTopLeft || position > NSBarPositionCenter) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:position forKey:kSettingsNSBarPosition];
    [d synchronize];
    printf("[SETTINGS] NSBar position box changed to: %ld\n", (long)position);
    settings_schedule_live_apply_for_key(kSettingsNSBarPosition);
    [self.tableView reloadData];
}

- (void)presentNiceBarTextEditorForSlot:(NSInteger)slot action:(NSString *)action
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;

    NSString *prefix = kSettingsNiceBarLiteSlotTextPrefix;
    NSString *title = @"Custom Text";
    NSString *placeholder = @"Text";

    NSString *key = settings_nicebar_key(prefix, slot);
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ %@", settings_nicebar_slot_name(slot), title]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = placeholder;
        field.text = [d stringForKey:key] ?: @"";
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        NSString *value = alert.textFields.firstObject.text ?: @"";
        [d setObject:value forKey:key];
        [d synchronize];
        settings_schedule_live_apply_for_key(key);
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)nicebarSetTimeFormat:(NSString *)format forSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:NiceBarLiteContentTimeFormat forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    [d setObject:format.length ? format : @"HH:mm" forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot)];
    [d synchronize];
    settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot));
    [self.tableView reloadData];
}

- (void)nicebarSetKind:(NSInteger)kind forSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:kind forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    [d synchronize];
    settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot));
    [self.tableView reloadData];
}

- (void)presentNiceBarDateTimePickerForSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *selectedFormat = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotTimePrefix, slot)] ?: @"HH:mm";
    __weak typeof(self) weakSelf = self;
    _NiceBarTimePresetPickerViewController *picker =
        [[_NiceBarTimePresetPickerViewController alloc] initWithSlotTitle:[NSString stringWithFormat:@"%@ Date / Time", settings_nicebar_slot_name(slot)]
                                                           selectedFormat:selectedFormat
                                                                 onSelect:^(NSString *format) {
            [weakSelf nicebarSetTimeFormat:format forSlot:slot];
        }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)refreshNiceBarWeatherForce:(BOOL)force
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!settings_nicebar_has_weather_slots(d)) return;

    NSString *cached = [d stringForKey:kSettingsNiceBarLiteWeatherCache] ?: @"";
    if (force && cached.length == 0) {
        settings_nicebar_store_weather_result(d, nil, nil, @"Weather...", NO);
        [self.tableView reloadData];
    }

    __weak typeof(self) weakSelf = self;
    settings_nicebar_refresh_weather_if_needed(force, ^(BOOL ok, NSString *text) {
        dispatch_async(dispatch_get_main_queue(), ^{
            (void)ok;
            (void)text;
            [weakSelf.tableView reloadData];
        });
    });
}

- (void)nicebarSetWeatherLanguage:(NSString *)language forSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSString *resolved = [language isEqualToString:@"zh"] ? @"zh" : @"en";
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setInteger:NiceBarLiteContentWeather forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
    [d setObject:resolved forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, slot)];
    settings_nicebar_update_weather_slot_texts(d);
    [d synchronize];
    settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotWeatherLanguagePrefix, slot));
    [self.tableView reloadData];
    [self refreshNiceBarWeatherForce:YES];
}

- (void)presentNiceBarWeatherLanguagePickerForSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ Weather", settings_nicebar_slot_name(slot)]
                                                                   message:@"Choose display language"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"English" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self nicebarSetWeatherLanguage:@"en" forSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"中文" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self nicebarSetWeatherLanguage:@"zh" forSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIView *anchor = self.tableView;
    sheet.popoverPresentationController.sourceView = anchor;
    sheet.popoverPresentationController.sourceRect = anchor.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)runGravityLiteAction:(NSString *)action
{
    if (!settings_device_supported()) return;
    BOOL restore = [action isEqualToString:@"gravitylite-restore"];
    BOOL explosion = [action isEqualToString:@"gravitylite-explosion"];
    if (!restore && !explosion) return;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if (g_settings_actions_running) {
            log_user("[GRAVITY] Action blocked: Apply Tweaks is still running.\n");
            return;
        }
        if (!settings_ensure_kexploit()) {
            log_user("[GRAVITY] Action failed: kernel primitives were not acquired.\n");
            return;
        }

        bool ok = false;
        @synchronized (settings_rc_lock()) {
            if (!g_springboard_rc_ready &&
                !settings_ensure_springboard_remote_call_locked()) {
                log_user("[GRAVITY] SpringBoard RemoteCall is not ready.\n");
                return;
            }
            ok = restore
                ? gravitylite_stop_in_session()
                : gravitylite_explosion_in_session(settings_gravitylite_config_from_defaults(d).explosionForce);
        }

        if (restore) {
            __sync_lock_test_and_set(&g_gravitylite_background_armed, 0);
            settings_stop_gravity_motion();
            settings_mark_tweak_applied(kSettingsGravityLiteEnabled, NO);
            log_user("%s Gravity Lite restore %s.\n",
                     ok ? "[OK]" : "[WARN]",
                     ok ? "completed" : "found no active state");
        } else {
            log_user("%s Gravity Lite explosion %s.\n",
                     ok ? "[OK]" : "[WARN]",
                     ok ? "sent" : "found no active state");
        }
        settings_notify_package_queue_changed_async();
    });
}

- (void)presentNiceBarSystemPickerForSlot:(NSInteger)slot
{
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger selectedItem = [d integerForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot)];
    NSString *selectedLanguage = [d stringForKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, slot)] ?: @"en";
    __weak typeof(self) weakSelf = self;
    _NiceBarSystemItemPickerViewController *picker =
        [[_NiceBarSystemItemPickerViewController alloc] initWithSlotTitle:[NSString stringWithFormat:@"%@ System Item", settings_nicebar_slot_name(slot)]
                                                             selectedItem:selectedItem
                                                         selectedLanguage:selectedLanguage
                                                                  onSelect:^(NSInteger item, NSString *language) {
            [d setInteger:NiceBarLiteContentSystem forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotKindPrefix, slot)];
            [d setInteger:item forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot)];
            [d setObject:[language isEqualToString:@"zh"] ? @"zh" : @"en"
                forKey:settings_nicebar_key(kSettingsNiceBarLiteSlotSystemLanguagePrefix, slot)];
            [d synchronize];
            settings_schedule_live_apply_for_key(settings_nicebar_key(kSettingsNiceBarLiteSlotSystemPrefix, slot));
            [weakSelf.tableView reloadData];
        }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)nicebarSlotButtonTapped:(UIButton *)sender
{
    NSInteger slot = sender.tag;
    if (slot < 0 || slot >= NiceBarLiteSlotCount) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:settings_nicebar_slot_name(slot)
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Off" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self nicebarSetKind:NiceBarLiteContentOff forSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Custom Text" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self nicebarSetKind:NiceBarLiteContentCustomText forSlot:slot];
        [self presentNiceBarTextEditorForSlot:slot action:@"nicebar-text"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"System Item" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarSystemPickerForSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Date / Time" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarDateTimePickerForSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Weather" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
        [self presentNiceBarWeatherLanguagePickerForSlot:slot];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (!self.detailMode) {
        switch ((RootSection)indexPath.section) {
            case RootSectionWarning:
                return;
            case RootSectionChangelog: {
                NSInteger entryCount = (NSInteger)settings_changelog_entries().count;
                if (indexPath.row >= entryCount) {
                    [self openReleasesPage];
                }
                return;
            }
            case RootSectionActions:
                indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:SectionActions];
                break;
            case RootSectionTweakBundles:
            case RootSectionSystemBundles: {
                NSArray<NSDictionary *> *bundles = (RootSection)indexPath.section == RootSectionTweakBundles
                    ? self.tweakBundleRows : self.systemBundleRows;
                NSDictionary *bundle = bundles[indexPath.row];
                NSInteger underlying = [bundle[@"section"] integerValue];
                NSString *pushTitle = bundle[@"title"];
                SettingsViewController *detail = [[SettingsViewController alloc] initWithUnderlyingSection:underlying
                                                                                              bundleTitle:pushTitle];
                [self.navigationController pushViewController:detail animated:YES];
                return;
            }
            case RootSectionAppIcon:
                [self selectAppIconAtRow:indexPath.row inTableView:tableView];
                return;
            case RootSectionDocs: {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                DocsViewController *docs = [[DocsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
                [self.navigationController pushViewController:docs animated:YES];
                return;
            }
            case RootSectionAbout:
                if (indexPath.row == 1) {
                    [self openViewLog];
                } else if (indexPath.row == 2) {
                    [self openShareLog];
                }
                return;
            case RootSectionExperimental: {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
                if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
                    UISwitch *sw = (UISwitch *)cell.accessoryView;
                    [sw setOn:!sw.isOn animated:YES];
                    [self experimentalSwitchChanged:sw];
                }
                return;
            }
            case RootSectionCount:
                return;
        }
    } else {
        indexPath = [NSIndexPath indexPathForRow:indexPath.row inSection:self.underlyingSection];
    }

    if (!settings_device_supported() &&
        indexPath.section != SectionWarning &&
        indexPath.section != SectionOTA &&
        indexPath.section != SectionThemer &&
        indexPath.section != SectionSnowBoardLite) {
        printf("[SETTINGS] tap blocked: %s\n", settings_unsupported_message().UTF8String);
        return;
    }

    if (indexPath.section == SectionActions) {
        if (indexPath.row == 0) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Clean Up?"
                                 message:@"This is a terminal cleanup for the current app-side KRW session. It stops live SpringBoard tweak sessions, parks the KRW socket state, closes Cyanide's local KRW file descriptors, and clears the in-app exploit cache. The next Run will try launchd KRW recovery first; if that is unavailable, it will run the full chain again."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Clean Up"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                settings_queue_terminal_kexploit_cleanup("manual action");
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 1) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Respring?"
                                 message:@"Are you sure you want to respring? SpringBoard will restart."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            __weak typeof(self) weakSelf = self;
            [ac addAction:[UIAlertAction actionWithTitle:@"Respring"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    if (__sync_lock_test_and_set(&g_settings_actions_running, 1)) {
                        printf("[SETTINGS] respring blocked: actions already running\n");
                        return;
                    }

                    __sync_lock_test_and_set(&g_settings_respring_cleanup_running, 1);
                    settings_notify_cleanup_state_changed();
                    @try {
                        settings_prepare_for_respring_sync();
                    } @finally {
                        __sync_lock_release(&g_settings_actions_running);
                        __sync_lock_release(&g_settings_respring_cleanup_running);
                        settings_notify_cleanup_state_changed();
                    }

                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf = weakSelf;
                        if (!strongSelf) return;
                        settings_show_respring_overlay(strongSelf);
                    });
                });
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 2) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Reset All Packages?"
                                 message:@"This uninstalls every package and clears the pending queue. The next chain run will start fresh from a clean slate. SpringBoard patches already live in this session stay until you respring or reboot.\n\nThis does not touch your Run options, Powercuff level, SBCustomizer grid, or other per-tweak settings — only install state."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Reset"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                NSUInteger uninstalled = 0;
                for (Package *p in [PackageCatalog allPackages]) {
                    if (p.isInstalled || p.isQueuedForApply) {
                        [p applyCommittedState:NO];
                        uninstalled++;
                    }
                }
                NSInteger cleared = [[PackageQueue sharedQueue] pendingCount];
                [[PackageQueue sharedQueue] clear];
                log_user("[INSTALLER] Reset: uninstalled %lu package(s), cleared %ld queued change(s).\n",
                         (unsigned long)uninstalled, (long)cleared);
                [self.tableView reloadData];
            }]];
            settings_present_controller(ac, self);
        } else if (indexPath.row == 3) {
            [[UpdateChecker shared] checkForUpdatesManuallyFrom:self];
        } else if (indexPath.row == 4) {
            if (!g_springboard_rc_ready) {
                log_user("[KILLALL] Needs an active SpringBoard session. Hit Run first.\n");
                return;
            }
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Kill Background Apps?"
                                 message:@"This asks SpringBoard to terminate every running app except Cyanide, like swiping them all out of the App Switcher.\n\nApps with unsaved work may lose it. SpringBoard and the lock-screen process are skipped."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Kill Apps"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_) {
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    @synchronized (settings_rc_lock()) {
                        if (settings_cleanup_in_progress() || !g_springboard_rc_ready) {
                            log_user("[KILLALL] Aborted: session not ready.\n");
                            return;
                        }
                        int killed = 0;
                        bool ok = killallapps_apply_in_session(&killed);
                        if (ok) {
                            log_user("[KILLALL] Killed %d background app(s).\n", killed);
                        } else {
                            log_user("[KILLALL] Failed: SpringBoard enumeration error (see log).\n");
                        }
                    }
                });
            }]];
            settings_present_controller(ac, self);
        }
    }

    if (indexPath.section == SectionOTA) {
        settings_run_ota_action(indexPath.row == 0);
        return;
    }

    if (indexPath.section == SectionNanoRegistry) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];

        if ([action isEqualToString:@"nano-load"]) {
            if (!settings_nano_load_override_enabled()) {
                log_user("[NANO] Load Current Override requires parked KRW recovery; button is disabled until recovery is available.\n");
                return;
            }
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                if (!settings_ensure_kexploit_recovery_only()) {
                    log_user("[NANO] Failed: parked KRW recovery was not acquired.\n");
                } else {
                    settings_nano_load_from_plist_into_defaults(YES);
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                  withRowAnimation:UITableViewRowAnimationNone];
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kSettingsActionsDidCompleteNotification
                                      object:nil];
                });
            });
        } else if ([action isEqualToString:@"nano-preset-newer"]) {
            settings_nano_set_defaults_values(kNanoPresetNewerMaxPairing,
                                              kNanoPresetNewerMinPairing,
                                              kNanoPresetNewerMinPairingChipID,
                                              kNanoPresetNewerMinQuickSwitch);
            log_user("[NANO] Loaded pairing range 99/23/10/6: max=%ld min=%ld minChip=%ld minQuick=%ld. Hit Apply to write.\n",
                     (long)kNanoPresetNewerMaxPairing,
                     (long)kNanoPresetNewerMinPairing,
                     (long)kNanoPresetNewerMinPairingChipID,
                     (long)kNanoPresetNewerMinQuickSwitch);
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        } else if ([action isEqualToString:@"nano-apply"]) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Apply Pairing Override?"
                                 message:@"Saves these watchOS pairing settings on this iPhone. Respring or reboot afterwards before trying to pair."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                settings_run_nano_apply_action();
            }]];
            settings_present_controller(ac, self);
        } else if ([action isEqualToString:@"nano-probe"]) {
            settings_run_nano_probe_action();
        } else if ([action isEqualToString:@"nano-steer"]) {
            settings_run_nano_steer_action();
        } else if ([action isEqualToString:@"nano-seed"]) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Seed Compatibility Index?"
                                 message:@"Adds this phone's product type to the local NanoRegistry compatibility-index MobileAsset and saves a .cyanide.bak backup beside the original file."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Seed" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                settings_run_nano_seed_action();
            }]];
            settings_present_controller(ac, self);
        } else if ([action isEqualToString:@"nano-clear"]) {
            UIAlertController *ac = [UIAlertController
                alertControllerWithTitle:@"Remove Pairing Override?"
                                 message:@"Removes the saved Watch Pairing Override without touching the rest of your watch data. Respring or reboot afterwards."
                          preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [ac addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
                settings_run_nano_clear_action();
            }]];
            settings_present_controller(ac, self);
        }
        return;
    }

    if (indexPath.section == SectionTypeBanner) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"typebanner-test"]) {
            static volatile int sTbTestInFlight = 0;
            if (__sync_lock_test_and_set(&sTbTestInFlight, 1)) {
                log_user("[TYPEBANNER] Test already running — wait for the previous one to finish before tapping again.\n");
                return;
            }
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @try {
                    if (g_settings_actions_running) {
                        log_user("[TYPEBANNER] Test aborted: Apply Tweaks is still running.\n");
                        return;
                    }
                    if (!settings_ensure_kexploit()) {
                        log_user("[TYPEBANNER] Test failed: kernel primitives not acquired. Run kexploit (Apply Tweaks) first.\n");
                        return;
                    }

                    // Pause the live loop while the test runs so the one-shot
                    // diagnostics do not race the periodic banner updater.
                    BOOL liveLoopWasRunning = g_typebanner_live_running != 0;
                    if (liveLoopWasRunning) {
                        g_typebanner_live_stop_requested = 1;
                        int waitMs = 0;
                        while (g_typebanner_live_running && waitMs < 30000) {
                            usleep(100000);
                            waitMs += 100;
                        }
                        if (g_typebanner_live_running) {
                            log_user("[TYPEBANNER] Test aborted: live loop did not yield in 30s.\n");
                            return;
                        }
                    }

                    log_user("[TYPEBANNER] Test: polling imagent for typing indicators…\n");
                    NSString *detected = nil;
                    @synchronized (settings_rc_lock()) {
                        RemoteCallSession *daemonSession = [[RemoteCallSession alloc] initWithProcess:@"imagent"
                                                                                   useMigFilterBypass:NO
                                                                              firstExceptionTimeoutMS:TYPEBANNER_RC_MOBILESMS_FIRST_EXCEPTION_TIMEOUT_MS
                                                                                    originalThreadOnly:YES];
                        if (!daemonSession) {
                            RemoteCallInitFailure failure = remote_call_last_init_failure();
                            uint32_t pid = remote_call_last_init_failure_pid();
                            if (failure == RemoteCallInitFailureProcessMissing) {
                                log_user("[TYPEBANNER] imagent is not running.\n");
                            } else if (failure == RemoteCallInitFailureFirstExceptionTimeout && pid != 0) {
                                log_user("[TYPEBANNER] imagent pid=%u did not answer the original-thread bootstrap this tick.\n",
                                         pid);
                            } else if (pid != 0) {
                                log_user("[TYPEBANNER] imagent RemoteCall init failed: %s (pid=%u)\n",
                                         remote_call_init_failure_description(failure), pid);
                            } else {
                                log_user("[TYPEBANNER] imagent RemoteCall init failed: %s\n",
                                         remote_call_init_failure_description(failure));
                            }
                        } else {
                            @try {
                                detected = typebanner_poll_in_imagent_remote_session(daemonSession);
                            } @catch (NSException *e) {
                                log_user("[TYPEBANNER] imagent poll threw: %s\n", e.reason.UTF8String);
                            }
                            if (detected.length == 0) {
                                log_user("[TYPEBANNER] No daemon typing indicator detected on this poll.\n");
                            }
                            [daemonSession destroyRemoteCall];
                        }
                    }

                    if (detected.length > 0) {
                        log_user("[TYPEBANNER] Detected typing: %s. Showing banner.\n",
                                 detected.UTF8String);
                    } else {
                        log_user("[TYPEBANNER] Showing a one-shot demo banner so you can confirm the SpringBoard render path.\n");
                    }

                    @synchronized (settings_rc_lock()) {
                        RemoteCallSession *springboardSession = [[RemoteCallSession alloc] initWithProcess:@"SpringBoard"
                                                                                         useMigFilterBypass:NO
                                                                                    firstExceptionTimeoutMS:TYPEBANNER_RC_FIRST_EXCEPTION_TIMEOUT_MS];
                        if (!springboardSession) {
                            log_user("[TYPEBANNER] SpringBoard not reachable; cannot show banner.\n");
                        } else {
                            bool ok = false;
                            @try {
                                NSString *label = detected.length > 0 ? detected : @"TypeBanner demo";
                                ok = typebanner_show_in_springboard_remote_session(springboardSession, label);
                            } @catch (NSException *e) {
                                log_user("[TYPEBANNER] SpringBoard show threw: %s\n", e.reason.UTF8String);
                            }
                            log_user("[TYPEBANNER] show=%d. Banner auto-hides in 5s.\n", ok);
                            sleep(5);
                            @try { typebanner_hide_in_springboard_remote_session(springboardSession); } @catch (NSException *e) {}
                            [springboardSession destroyRemoteCall];
                        }
                    }

                    if (liveLoopWasRunning) {
                        log_user("[TYPEBANNER] Resuming live loop.\n");
                        g_typebanner_live_stop_requested = 0;
                        settings_start_typebanner_live_loop();
                    }
                } @finally {
                    __sync_lock_release(&sTbTestInFlight);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                                          withRowAnimation:UITableViewRowAnimationNone];
                    });
                }
            });
        }
        return;
    }

    if (indexPath.section == SectionNiceBarLite) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"nicebar-traffic-history"]) {
            NiceBarTrafficHistoryViewController *vc = [[NiceBarTrafficHistoryViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
            return;
        }
        if ([action isEqualToString:@"nicebar-apply"]) {
            if (!g_springboard_rc_ready) {
                log_user("[NICEBAR] Needs an active SpringBoard session. Hit Run first.\n");
                return;
            }
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setBool:YES forKey:kSettingsNiceBarLiteEnabled];
            [d synchronize];
            log_user("[NICEBAR] Manual apply requested.\n");
            settings_log_nicebar_config(d, "manual config");
            [self refreshNiceBarWeatherForce:YES];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                uint64_t beginUS = settings_now_us();
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    uint64_t applyStartUS = settings_now_us();
                    bool ok = settings_apply_nicebarlite_from_defaults_locked(d);
                    uint64_t endUS = settings_now_us();
                    settings_mark_tweak_applied(kSettingsNiceBarLiteEnabled, ok);
                    log_user("%s NiceBar Lite applied now.\n", ok ? "[OK]" : "[WARN]");
                    log_user("[NICEBAR] Manual apply result=%d apply=%llums total=%llums\n",
                             ok ? 1 : 0,
                             (unsigned long long)((endUS >= applyStartUS) ? ((endUS - applyStartUS) / 1000ULL) : 0ULL),
                             (unsigned long long)((endUS >= beginUS) ? ((endUS - beginUS) / 1000ULL) : 0ULL));
                    settings_notify_package_queue_changed_async();
                }
                settings_start_nicebarlite_live_loop();
            });
            return;
        }
        if ([action hasPrefix:@"nicebar-"]) {
            [self presentNiceBarTextEditorForSlot:[row[@"slot"] integerValue] action:action];
        }
        return;
    }

    if (indexPath.section == SectionAppSwitcherGrid) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"appswitchergrid-restore"]) {
            if (!g_springboard_rc_ready) {
                log_user("[ASG] Restore needs an active SpringBoard session. Hit Run first, or respring to restore stock.\n");
                return;
            }
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setBool:NO forKey:kSettingsAppSwitcherGridEnabled];
            [d synchronize];
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @synchronized (settings_rc_lock()) {
                    if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;
                    bool ok = appswitchergrid_stop_in_session();
                    settings_mark_tweak_applied(kSettingsAppSwitcherGridEnabled, NO);
                    log_user("%s App Switcher Grid restore %s.\n",
                             ok ? "[OK]" : "[WARN]",
                             ok ? "completed" : "did not find an active patch; respring restores stock");
                }
                settings_notify_package_queue_changed_async();
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.tableView reloadData];
                });
            });
        }
        return;
    }

    if (indexPath.section == SectionGravityLite) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        [self runGravityLiteAction:row[@"action"]];
        return;
    }

    if (indexPath.section == SectionThemer) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"themer-select-ios6"]) {
            [self selectBuiltInIOS6Theme];
        } else if ([action isEqualToString:@"themer-import"]) {
            [self presentThemerImporter];
        } else if ([action isEqualToString:@"themer-guide"]) {
            [self presentThemerFormatGuide];
        } else if ([action isEqualToString:@"themer-clear"]) {
            [self clearSelectedTheme];
        }
        return;
    }

    if (indexPath.section == SectionSnowBoardLite) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        NSString *kind = row[@"kind"];
        if ([kind isEqualToString:@"sbl-theme"]) {
            [self selectSnowBoardLiteThemeID:row[@"id"]];
            return;
        }
        if ([kind isEqualToString:@"sbl-online-entry"]) {
            [self presentSnowBoardLiteOnlineDownloads];
            return;
        }
        if (![kind isEqualToString:@"button"] &&
            ![kind isEqualToString:@"sbl-action"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"sbl-import"]) {
            [self presentSnowBoardLiteImporter];
        } else if ([action isEqualToString:@"sbl-select-ios6"]) {
            [self selectSnowBoardLiteBuiltinIOS6Theme];
        } else if ([action isEqualToString:@"sbl-import-url"]) {
            [self promptSnowBoardLiteThemeURL];
        } else if ([action isEqualToString:@"sbl-online"]) {
            [self presentSnowBoardLiteOnlineDownloads];
        } else if ([action isEqualToString:@"sbl-guide"]) {
            [self presentSnowBoardLiteFormatGuide];
        } else if ([action isEqualToString:@"sbl-clear"]) {
            [self clearSnowBoardLiteSelectedTheme];
        } else if ([action isEqualToString:@"sbl-remove"]) {
            [self presentSnowBoardLiteRemoveThemePicker];
        }
        return;
    }

    if (indexPath.section == SectionLiveWP) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if (![row[@"kind"] isEqualToString:@"button"]) return;
        NSString *action = row[@"action"];
        if ([action isEqualToString:@"livewp-select-video"]) {
            [self showLiveWPVideoPicker];
        } else if ([action isEqualToString:@"livewp-online-video"]) {
            [self showLiveWPOnlineDownloader];
        }
        return;
    }

    if (indexPath.section == SectionSBC) {
        NSDictionary *row = [self rowsForSection:indexPath.section][indexPath.row];
        if ([row[@"kind"] isEqualToString:@"button"]) {
            settings_reset_sbc_defaults();
            // In detail mode, SBC sits at table-view section 0.
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationNone];
        }
    }
}

@end
