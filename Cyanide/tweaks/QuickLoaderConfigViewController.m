#import "QuickLoaderConfigViewController.h"
#import "QuickLoader.h"
#import "../SettingsViewController.h"

static bool quickloader_valid_identifier(const char *name);

@interface QuickLoaderConfigViewController ()
@property (nonatomic, copy) NSString *rawScript;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *values;
@property (nonatomic, copy, nullable) NSString *repoURL;
@property (nonatomic, copy, nullable) NSString *tweakID;
@property (nonatomic, strong) NSArray<NSDictionary *> *params;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@end

@implementation QuickLoaderConfigViewController

- (instancetype)initWithRawScript:(NSString *)rawScript
                      displayName:(NSString *)displayName
                           values:(NSMutableDictionary<NSString *, NSString *> *)values
                          repoURL:(nullable NSString *)repoURL
                         tweakID:(nullable NSString *)tweakID
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _rawScript = [rawScript copy];
        _displayName = [displayName copy];
        _values = values ?: [NSMutableDictionary dictionary];
        _repoURL = [repoURL copy];
        _tweakID = [tweakID copy];
        _params = [self parseParamsFromScript:rawScript];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.title = @"Configure Tweak";
    [self setupNavigation];
    [self setupScrollView];
    [self buildLayout];
}

- (void)setupNavigation
{
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark"]
        style:UIBarButtonItemStylePlain
        target:self action:@selector(didTapCancel)];

    UIBarButtonItem *saveItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Save & Apply"
        style:UIBarButtonItemStyleDone
        target:self action:@selector(didTapSave)];
    saveItem.tintColor = self.view.tintColor;
    self.navigationItem.rightBarButtonItem = saveItem;
}

- (void)setupScrollView
{
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];

    _stackView = [[UIStackView alloc] init];
    _stackView.translatesAutoresizingMaskIntoConstraints = NO;
    _stackView.axis = UILayoutConstraintAxisVertical;
    _stackView.spacing = 16;
    _stackView.alignment = UIStackViewAlignmentFill;
    [_scrollView addSubview:_stackView];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *content = _scrollView.contentLayoutGuide;
    UILayoutGuide *frame = _scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [_stackView.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [_stackView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_stackView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_stackView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [_stackView.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-32],
    ]];
}

#pragma mark - Param parsing

- (NSArray<NSDictionary *> *)parseParamsFromScript:(NSString *)script
{
    NSMutableArray *result = [NSMutableArray array];
    NSArray *lines = [script componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if (![line containsString:@"@param:"]) continue;
        NSArray *parts = [line componentsSeparatedByString:@"|"];
        if (parts.count < 4) continue;
        NSArray *typeParts = [parts[0] componentsSeparatedByString:@"@param:"];
        if (typeParts.count < 2) continue;
        NSString *type = [typeParts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *varName = [parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *label = [parts[2] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *defValue = [parts[3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!quickloader_valid_identifier([varName UTF8String])) continue;
        NSMutableDictionary *param = [NSMutableDictionary dictionaryWithDictionary:@{
            @"type": type, @"varName": varName, @"label": label, @"default": defValue
        }];
        if (parts.count >= 5 && ([type isEqualToString:@"slider"] || [type isEqualToString:@"number"])) {
            NSString *rangeStr = [parts[4] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSArray *rangeParts = [rangeStr componentsSeparatedByString:@"-"];
            if (rangeParts.count == 2) {
                param[@"min"] = rangeParts[0];
                param[@"max"] = rangeParts[1];
            }
        }
        [result addObject:param];
    }
    return result;
}

#pragma mark - Layout

- (void)buildLayout
{
    [self addHeaderCard];
    if (self.params.count > 0) {
        [self addSectionTitle:@"Parameters"];
        for (NSDictionary *param in self.params) {
            [self addParamCard:param];
        }
    }
    [self addApplyButton];
}

- (void)addHeaderCard
{
    UIView *card = [self cardContainer];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.systemYellowColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = self.displayName;
    nameLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    nameLabel.textColor = UIColor.labelColor;

    UILabel *sourceLabel = [[UILabel alloc] init];
    sourceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    sourceLabel.text = self.repoURL.length > 0 ? @"From source repo" : @"Local script";
    sourceLabel.font = [UIFont systemFontOfSize:14.0];
    sourceLabel.textColor = UIColor.secondaryLabelColor;

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = UIColor.systemGreenColor;
    dot.layer.cornerRadius = 5;
    dot.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.text = @"Not active — configure below";
    statusLabel.font = [UIFont systemFontOfSize:13.0];
    statusLabel.textColor = UIColor.secondaryLabelColor;

    [card addSubview:icon];
    [card addSubview:nameLabel];
    [card addSubview:sourceLabel];
    [card addSubview:dot];
    [card addSubview:statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:nameLabel.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:28],
        [icon.heightAnchor constraintEqualToConstant:28],

        [nameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [nameLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [nameLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [sourceLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:2],
        [sourceLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [sourceLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [dot.topAnchor constraintEqualToAnchor:sourceLabel.bottomAnchor constant:10],
        [dot.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [dot.widthAnchor constraintEqualToConstant:10],
        [dot.heightAnchor constraintEqualToConstant:10],
        [dot.centerYAnchor constraintEqualToAnchor:statusLabel.centerYAnchor],

        [statusLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:6],
        [statusLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [statusLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];

    [self.stackView addArrangedSubview:card];
}

- (void)addSectionTitle:(NSString *)title
{
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    label.textColor = UIColor.secondaryLabelColor;
    label.textAlignment = NSTextAlignmentNatural;
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.stackView addArrangedSubview:label];
}

- (void)addParamCard:(NSDictionary *)param
{
    NSString *type = param[@"type"];
    NSString *varName = param[@"varName"];
    NSString *label = param[@"label"];
    NSString *defValue = param[@"default"] ?: @"";
    CGFloat min = [param[@"min"] floatValue];
    CGFloat max = [param[@"max"] floatValue];

    UIView *card = [self cardContainer];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = label;
    titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    titleLabel.textColor = UIColor.labelColor;

    [card addSubview:titleLabel];

    if ([type isEqualToString:@"switch"]) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.translatesAutoresizingMaskIntoConstraints = NO;
        sw.on = [self.values[varName] isEqualToString:@"true"] ?: [defValue isEqualToString:@"true"];
        UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            self.values[varName] = sw.isOn ? @"true" : @"false";
        }];
        [sw addAction:action forControlEvents:UIControlEventValueChanged];

        [card addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-12],
            [titleLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
            [sw.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
            [sw.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        ]];
    }
    else if ([type isEqualToString:@"color"]) {
        UIColor *currentColor = [self colorFromHex:self.values[varName] ?: defValue ?: @"#FF0000"];

        UITextField *hexField = [[UITextField alloc] init];
        hexField.translatesAutoresizingMaskIntoConstraints = NO;
        hexField.text = [self.values[varName] length] > 0 ? self.values[varName] : defValue;
        hexField.font = [UIFont systemFontOfSize:15.0];
        hexField.textColor = UIColor.labelColor;
        hexField.borderStyle = UITextBorderStyleRoundedRect;
        hexField.keyboardType = UIKeyboardTypeASCIICapable;
        hexField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        hexField.placeholder = @"#FF0000";

        UIColorWell *colorWell = [[UIColorWell alloc] init];
        colorWell.translatesAutoresizingMaskIntoConstraints = NO;
        colorWell.selectedColor = currentColor;

        __weak typeof(self) weakSelf = self;
        UIAction *wellAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            weakSelf.values[varName] = [self hexFromColor:colorWell.selectedColor];
            hexField.text = weakSelf.values[varName];
        }];
        [colorWell addAction:wellAction forControlEvents:UIControlEventValueChanged];

        UIAction *fieldAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            NSString *val = hexField.text;
            if (val.length > 0) {
                if (![val hasPrefix:@"#"]) val = [@"#" stringByAppendingString:val];
                weakSelf.values[varName] = val;
                colorWell.selectedColor = [self colorFromHex:val];
            }
        }];
        [hexField addAction:fieldAction forControlEvents:UIControlEventEditingDidEnd];
        [hexField addAction:fieldAction forControlEvents:UIControlEventEditingDidEndOnExit];

        UIView *colorPreview = [[UIView alloc] init];
        colorPreview.translatesAutoresizingMaskIntoConstraints = NO;
        colorPreview.backgroundColor = currentColor;
        colorPreview.layer.cornerRadius = 4;
        colorPreview.layer.cornerCurve = kCACornerCurveContinuous;
        colorPreview.layer.borderWidth = 1;
        colorPreview.layer.borderColor = UIColor.separatorColor.CGColor;

        [card addSubview:colorWell];
        [card addSubview:colorPreview];
        [card addSubview:hexField];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

            [colorWell.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [colorWell.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:10],
            [colorWell.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
            [colorWell.widthAnchor constraintEqualToConstant:32],
            [colorWell.heightAnchor constraintEqualToConstant:32],

            [colorPreview.centerXAnchor constraintEqualToAnchor:colorWell.centerXAnchor],
            [colorPreview.centerYAnchor constraintEqualToAnchor:colorWell.centerYAnchor],
            [colorPreview.widthAnchor constraintEqualToConstant:24],
            [colorPreview.heightAnchor constraintEqualToConstant:24],

            [hexField.leadingAnchor constraintEqualToAnchor:colorWell.trailingAnchor constant:12],
            [hexField.centerYAnchor constraintEqualToAnchor:colorWell.centerYAnchor],
            [hexField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [hexField.heightAnchor constraintEqualToConstant:34],
        ]];
        [card sendSubviewToBack:colorPreview];
    }
    else if ([type isEqualToString:@"slider"]) {
        CGFloat currentVal = [self.values[varName] floatValue] ?: [defValue floatValue];
        if (max <= min) max = min + 1;

        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = min;
        slider.maximumValue = max;
        slider.value = currentVal;

        UILabel *valLabel = [[UILabel alloc] init];
        valLabel.translatesAutoresizingMaskIntoConstraints = NO;
        valLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
        valLabel.textColor = UIColor.secondaryLabelColor;
        valLabel.textAlignment = NSTextAlignmentCenter;
        valLabel.text = [NSString stringWithFormat:@"%.1f", currentVal];
        [valLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [card addSubview:slider];
        [card addSubview:valLabel];

        UIAction *updateAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            valLabel.text = [NSString stringWithFormat:@"%.1f", slider.value];
        }];
        [slider addAction:updateAction forControlEvents:UIControlEventValueChanged];

        UIAction *saveAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            self.values[varName] = [NSString stringWithFormat:@"%.1f", slider.value];
        }];
        [slider addAction:saveAction forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

            [slider.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [slider.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [slider.trailingAnchor constraintEqualToAnchor:valLabel.leadingAnchor constant:-8],

            [valLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [valLabel.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
            [valLabel.widthAnchor constraintEqualToConstant:48],

            [slider.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        ]];
    }
    else if ([type isEqualToString:@"number"]) {
        CGFloat currentVal = [self.values[varName] floatValue] ?: [defValue floatValue];
        if (max <= min) max = min + 10;

        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = min;
        slider.maximumValue = max;
        slider.value = currentVal;
        slider.continuous = YES;

        UITextField *numField = [[UITextField alloc] init];
        numField.translatesAutoresizingMaskIntoConstraints = NO;
        numField.text = [NSString stringWithFormat:@"%.0f", currentVal];
        numField.font = [UIFont systemFontOfSize:15.0];
        numField.textColor = UIColor.labelColor;
        numField.textAlignment = NSTextAlignmentCenter;
        numField.borderStyle = UITextBorderStyleRoundedRect;
        numField.keyboardType = UIKeyboardTypeNumberPad;
        [numField setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [numField setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        [card addSubview:slider];
        [card addSubview:numField];

        UIAction *sliderUpdate = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            numField.text = [NSString stringWithFormat:@"%.0f", slider.value];
        }];
        [slider addAction:sliderUpdate forControlEvents:UIControlEventValueChanged];

        UIAction *sliderSave = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            self.values[varName] = [NSString stringWithFormat:@"%.0f", slider.value];
        }];
        [slider addAction:sliderSave forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

        UIAction *fieldAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            float val = [numField.text floatValue];
            val = MAX(min, MIN(max, val));
            self.values[varName] = [NSString stringWithFormat:@"%.0f", val];
            slider.value = val;
            numField.text = [NSString stringWithFormat:@"%.0f", val];
        }];
        [numField addAction:fieldAction forControlEvents:UIControlEventEditingDidEnd];
        [numField addAction:fieldAction forControlEvents:UIControlEventEditingDidEndOnExit];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

            [slider.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [slider.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [slider.trailingAnchor constraintEqualToAnchor:numField.leadingAnchor constant:-8],

            [numField.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [numField.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
            [numField.widthAnchor constraintEqualToConstant:52],
            [numField.heightAnchor constraintEqualToConstant:34],

            [slider.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        ]];
    }
    else if ([type isEqualToString:@"text"]) {
        UITextField *tf = [[UITextField alloc] init];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.text = [self.values[varName] length] > 0 ? self.values[varName] : defValue;
        tf.font = [UIFont systemFontOfSize:15.0];
        tf.textColor = UIColor.labelColor;
        tf.borderStyle = UITextBorderStyleRoundedRect;
        tf.placeholder = defValue ?: @"Enter value";

        __weak typeof(self) weakSelf = self;
        UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull a) {
            weakSelf.values[varName] = tf.text;
        }];
        [tf addAction:action forControlEvents:UIControlEventEditingDidEnd];
        [tf addAction:action forControlEvents:UIControlEventEditingDidEndOnExit];

        [card addSubview:tf];
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

            [tf.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [tf.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
            [tf.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [tf.heightAnchor constraintEqualToConstant:36],
            [tf.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        ]];
    }

    [self.stackView addArrangedSubview:card];
}

- (void)addApplyButton
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;

    UIButtonConfiguration *cfg = [UIButtonConfiguration filledButtonConfiguration];
    cfg.title = @"Activate & Apply";
    cfg.buttonSize = UIButtonConfigurationSizeLarge;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    cfg.baseForegroundColor = UIColor.whiteColor;
    cfg.baseBackgroundColor = self.view.tintColor;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(16, 24, 16, 24);
    button.configuration = cfg;

    [button addTarget:self action:@selector(didTapSave) forControlEvents:UIControlEventTouchUpInside];

    UIView *container = [[UIView alloc] init];
    [container addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [button.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [button.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
        [button.heightAnchor constraintEqualToConstant:52],
    ]];

    [self.stackView addArrangedSubview:container];
}

#pragma mark - Actions

- (void)didTapCancel
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)didTapSave
{
    [self.view endEditing:YES];

    if (self.repoURL && self.tweakID) {
        quickloader_save_repo_tweak(self.repoURL, self.tweakID, self.displayName, self.rawScript, self.values);
    } else {
        quickloader_save_repo_tweak(@"", @"", self.displayName, self.rawScript, self.values);
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:YES forKey:kSettingsQuickLoaderEnabled];
    [d synchronize];

    if (quickloader_is_driven_by_repo_tweak() || !self.repoURL) {
        quickloader_refresh_active_repo_tweak();
    }

    quickloader_apply_in_session();

    [[NSNotificationCenter defaultCenter] postNotificationName:@"PackageQueueDidChangeNotification" object:nil];

    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Color helpers

- (UIColor *)colorFromHex:(NSString *)hex
{
    if (![hex isKindOfClass:NSString.class]) return UIColor.blackColor;
    NSString *clean = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (clean.length == 0) return UIColor.blackColor;
    unsigned val = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&val];
    return [UIColor colorWithRed:((val & 0xFF0000) >> 16)/255.0
                           green:((val & 0xFF00) >> 8)/255.0
                            blue:(val & 0xFF)/255.0 alpha:1.0];
}

- (NSString *)hexFromColor:(UIColor *)color
{
    if (![color isKindOfClass:UIColor.class]) return @"#000000";
    const CGFloat *c = CGColorGetComponents(color.CGColor);
    if (CGColorGetNumberOfComponents(color.CGColor) == 4) {
        return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
                lroundf(c[0] * 255), lroundf(c[1] * 255), lroundf(c[2] * 255)];
    }
    return @"#000000";
}

#pragma mark - Helpers

- (UIView *)cardContainer
{
    UIView *v = [[UIView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    v.layer.cornerRadius = 14;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.borderWidth = 0.5;
    v.layer.borderColor = UIColor.separatorColor.CGColor;
    return v;
}

static bool quickloader_valid_identifier(const char *name) {
    if (!name || !*name) return false;
    if (!isalpha((unsigned char)*name) && *name != '_') return false;
    for (const char *p = name + 1; *p; p++) {
        if (!isalnum((unsigned char)*p) && *p != '_') return false;
    }
    return true;
}

@end
