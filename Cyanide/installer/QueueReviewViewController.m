//
//  QueueReviewViewController.m
//  Cyanide
//

#import "QueueReviewViewController.h"
#import "PackageQueue.h"
#import "PackageCatalog.h"
#import "InstallProgressViewController.h"
#import "../LogTextView.h"

typedef NS_ENUM(NSInteger, QueueReviewSection) {
    QueueReviewSectionInstall = 0,
    QueueReviewSectionUninstall,
    QueueReviewSectionReApply,   // packages already installed that will re-run on confirm
    QueueReviewSectionCount,
};

@interface QueueReviewViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *confirmButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation QueueReviewViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Queue";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    UIView *footer = [self buildFooter];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];

    self.emptyLabel = [[UILabel alloc] init];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"No pending changes.\nQueue packages from the Installer tab.";
    self.emptyLabel.font = [UIFont systemFontOfSize:16.0];
    self.emptyLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    [self.view addSubview:self.emptyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor   constraintEqualToAnchor:footer.topAnchor],

        [footer.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor  constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueChanged:)
                                                 name:PackageQueueDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshUI];
}

- (UIView *)buildFooter
{
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.confirmButton setTitle:@"Confirm" forState:UIControlStateNormal];
    [self.confirmButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.confirmButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.confirmButton.backgroundColor = self.view.tintColor;
    self.confirmButton.layer.cornerRadius = 12.0;
    self.confirmButton.layer.masksToBounds = YES;
    [self.confirmButton addTarget:self action:@selector(didTapConfirm) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.confirmButton];

    self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.clearButton setTitle:@"Clear Queue" forState:UIControlStateNormal];
    [self.clearButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    self.clearButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    [self.clearButton addTarget:self action:@selector(didTapClear) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:self.clearButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.confirmButton.topAnchor      constraintEqualToAnchor:container.topAnchor constant:8.0],
        [self.confirmButton.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:16.0],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
        [self.confirmButton.heightAnchor   constraintEqualToConstant:50.0],

        [self.clearButton.topAnchor        constraintEqualToAnchor:self.confirmButton.bottomAnchor constant:2.0],
        [self.clearButton.centerXAnchor    constraintEqualToAnchor:container.centerXAnchor],
        [self.clearButton.bottomAnchor     constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
    ]];
    return container;
}

- (void)refreshUI
{
    [self.tableView reloadData];
    NSInteger count = [PackageQueue sharedQueue].pendingCount;
    self.emptyLabel.hidden = (count > 0);
    self.tableView.hidden = (count == 0);
    self.confirmButton.enabled = (count > 0);
    self.confirmButton.alpha = (count > 0) ? 1.0 : 0.4;
    self.clearButton.enabled = (count > 0);
    self.clearButton.alpha = (count > 0) ? 1.0 : 0.4;

    if (count == 1) {
        [self.confirmButton setTitle:@"Confirm 1 Change" forState:UIControlStateNormal];
    } else if (count > 1) {
        [self.confirmButton setTitle:[NSString stringWithFormat:@"Confirm %ld Changes", (long)count] forState:UIControlStateNormal];
    } else {
        [self.confirmButton setTitle:@"Confirm" forState:UIControlStateNormal];
    }
}

- (void)queueChanged:(NSNotification *)note
{
    [self refreshUI];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return QueueReviewSectionCount;
}

- (NSArray<Package *> *)reApplyPackages
{
    PackageQueue *q = [PackageQueue sharedQueue];
    NSMutableArray<Package *> *out = [NSMutableArray array];
    for (Package *p in [PackageCatalog allPackages]) {
        if (!p.isInstalled) continue;
        if ([q intentForPackage:p] == PackageQueueIntentUninstall) continue;
        [out addObject:p];
    }
    return out;
}

- (NSArray<Package *> *)packagesForSection:(NSInteger)section
{
    PackageQueue *q = [PackageQueue sharedQueue];
    switch ((QueueReviewSection)section) {
        case QueueReviewSectionInstall:   return q.queuedInstalls;
        case QueueReviewSectionUninstall: return q.queuedUninstalls;
        case QueueReviewSectionReApply:   return [self reApplyPackages];
        case QueueReviewSectionCount:     return @[];
    }
    return @[];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[self packagesForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSArray<Package *> *list = [self packagesForSection:section];
    if (list.count == 0) return nil;
    BOOL allOTA = YES;
    for (Package *pkg in list) {
        if (pkg.kind != PackageInstallKindOTA) {
            allOTA = NO;
            break;
        }
    }
    NSString *label;
    switch ((QueueReviewSection)section) {
        case QueueReviewSectionInstall:   label = allOTA ? @"Disable" : @"Install";    break;
        case QueueReviewSectionUninstall: label = allOTA ? @"Enable" : @"Uninstall";   break;
        case QueueReviewSectionReApply:   label = @"Will Re-Apply";    break;
        default:                          return nil;
    }
    return [NSString stringWithFormat:@"%@  ·  %ld", label, (long)list.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ((QueueReviewSection)section != QueueReviewSectionReApply) return nil;
    if ([self reApplyPackages].count == 0) return nil;
    return @"These are already installed, not newly queued changes. Confirming re-runs the chain so installed RemoteCall-backed tweaks come back after a force-quit. To stop one from running, uninstall it from the Installer tab, or use Reset All Packages in Settings → Quick Actions.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *sectionPackages = [self packagesForSection:indexPath.section];
    
    // ==================== prevent out-of-bounds ====================
    if (indexPath.row >= sectionPackages.count || sectionPackages.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"QueueRow"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle 
                                          reuseIdentifier:@"QueueRow"];
        }
        cell.textLabel.text = @"（unknown）";
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    // ================================================
    
    Package *pkg = sectionPackages[indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"QueueRow"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle 
                                      reuseIdentifier:@"QueueRow"];
    }
    cell.textLabel.text = pkg.name;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];

    QueueReviewSection s = (QueueReviewSection)indexPath.section;
    switch (s) {
        case QueueReviewSectionInstall:
            switch (pkg.kind) {
                case PackageInstallKindOTA:
                    cell.detailTextLabel.text = @"Pending OTA disable";
                    cell.detailTextLabel.textColor = UIColor.systemOrangeColor;
                    break;
                case PackageInstallKindNanoRegistry:
                    cell.detailTextLabel.text = @"Pending override apply";
                    cell.detailTextLabel.textColor = self.view.tintColor;
                    break;
                default:
                    cell.detailTextLabel.text = @"Pending install";
                    cell.detailTextLabel.textColor = UIColor.systemGreenColor;
                    break;
            }
            break;
        case QueueReviewSectionUninstall:
            switch (pkg.kind) {
                case PackageInstallKindOTA:
                    cell.detailTextLabel.text = @"Pending OTA enable";
                    cell.detailTextLabel.textColor = UIColor.systemGreenColor;
                    break;
                case PackageInstallKindNanoRegistry:
                    cell.detailTextLabel.text = @"Pending override remove";
                    cell.detailTextLabel.textColor = UIColor.systemRedColor;
                    break;
                default:
                    cell.detailTextLabel.text = @"Pending removal";
                    cell.detailTextLabel.textColor = UIColor.systemRedColor;
                    break;
            }
            break;
        case QueueReviewSectionReApply:
            cell.detailTextLabel.text = @"Installed; will re-apply";
            cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            break;
        default:
            cell.detailTextLabel.text = nil;
            break;
    }
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.imageView.image = [UIImage systemImageNamed:pkg.symbolName];
    cell.imageView.tintColor = (s == QueueReviewSectionReApply)
        ? UIColor.tertiaryLabelColor
        : self.view.tintColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Swipe-to-remove only applies to the pending queue rows. "Will Re-Apply"
    // is informational — to drop one, the user uninstalls it from the
    // Installer tab or runs Reset All Packages.
    QueueReviewSection s = (QueueReviewSection)indexPath.section;
    if (s != QueueReviewSectionInstall && s != QueueReviewSectionUninstall) return nil;

    Package *pkg = [self packagesForSection:indexPath.section][indexPath.row];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"Remove"
                                                                       handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        [[PackageQueue sharedQueue] removePackage:pkg];
        completionHandler(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

#pragma mark - Actions

- (void)didTapConfirm
{
    if ([PackageQueue sharedQueue].pendingCount == 0) return;
    NSInteger count = [PackageQueue sharedQueue].pendingCount;

    InstallProgressViewController *vc = [[InstallProgressViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationAutomatic;
    [self presentViewController:nav animated:YES completion:^{
        log_user("[INSTALLER] ── Applying %ld queued change(s) ──\n", (long)count);
        [[PackageQueue sharedQueue] commit];
    }];
}

- (void)didTapClear
{
    if ([PackageQueue sharedQueue].pendingCount == 0) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Clear Queue?"
                                                                message:@"Discard all pending install / uninstall changes."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
        [[PackageQueue sharedQueue] clear];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
