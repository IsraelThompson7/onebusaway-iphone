/**
 * Copyright (C) 2009 bdferris <bdferris@onebusaway.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *         http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "OBAContactUsViewController.h"
#import "UITableViewController+oba_Additions.h"

#define kEmailRow 0
#define kTwitterRow 1
#define kFacebookRow 2

#define kRowCount 3 //including Facebook which is optional

static NSString *kOBADefaultContactEmail = @"contact@onebusaway.org";
static NSString *kOBADefaultTwitterURL = @"http://twitter.com/onebusaway";

@implementation OBAContactUsViewController


- (id)init {
    if (self = [super initWithStyle:UITableViewStylePlain]) {
        self.title = NSLocalizedString(@"Contact Us", @"Contact us tab title");
        self.appDelegate = APP_DELEGATE;
    }
    return self;
}


#pragma mark UIViewController

- (void) viewDidLoad
{
    [super viewDidLoad];
    [self hideEmptySeparators];
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = [UIColor whiteColor];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [TestFlight passCheckpoint:[NSString stringWithFormat:@"View: %@", [self class]]];
}

#pragma mark Table view methods

// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    OBARegionV2 *region = _appDelegate.modelDao.region;
    if (region.facebookUrl && ![region.facebookUrl isEqualToString:@""]) {
        return kRowCount;
    }
    
    //if no facebook URL 1 less row
    return (kRowCount-1);
}


// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell * cell = [UITableViewCell getOrCreateCellForTableView:tableView];
    cell.imageView.image = nil;

    cell.textLabel.font = [UIFont systemFontOfSize:18];
    
    switch( indexPath.row) {
        case kEmailRow:
            cell.textLabel.text = NSLocalizedString(@"Email", @"Email title");
            break;
        case kTwitterRow:
            cell.textLabel.text = NSLocalizedString(@"Twitter", @"Twitter title");
            break;
        case kFacebookRow:
            cell.textLabel.text = NSLocalizedString(@"Facebook", @"Facebook title");
            break;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    OBARegionV2 *region = _appDelegate.modelDao.region;
    switch( indexPath.row) {
        case kEmailRow:
            {
                [TestFlight passCheckpoint:@"Clicked Email Link"];
                NSString *contactEmail = kOBADefaultContactEmail;
                if (region) {
                    contactEmail = region.contactEmail;
                }
                contactEmail = [NSString stringWithFormat:@"mailto:%@",contactEmail];
                [[UIApplication sharedApplication] openURL: [NSURL URLWithString: contactEmail]];
            }
            break;
        case kTwitterRow:
            {
                [TestFlight passCheckpoint:@"Clicked Twitter Link"];
                NSString *twitterUrl = kOBADefaultTwitterURL;
                if (region) {
                    twitterUrl = region.twitterUrl;
                }
                NSString *twitterName = [[twitterUrl componentsSeparatedByString:@"/"] lastObject];
                if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitter://"]]) {
                    [TestFlight passCheckpoint:@"Loaded Twitter via App"];
                    NSString *url = [NSString stringWithFormat:@"twitter://user?screen_name=%@",twitterName ];
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
                } else {
                    [TestFlight passCheckpoint:@"Loaded Twitter via Web"];
                    NSString *url = [NSString stringWithFormat:@"http://twitter.com/%@", twitterName];
                    [[UIApplication sharedApplication] openURL: [NSURL URLWithString: url]];
                }
            }
            break;
        case kFacebookRow:
            if (region.facebookUrl) {
                [TestFlight passCheckpoint:@"Clicked Facebook Link"];
                NSString *facebookUrl = region.facebookUrl;
                NSString *facebookPage = [[facebookUrl componentsSeparatedByString:@"/"] lastObject];

                if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"fb://"]]) {
                    [TestFlight passCheckpoint:@"Loaded Facebook via App"];
                    NSString *url = [NSString stringWithFormat:@"fb://profile/%@",facebookPage ];
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString: url]];
                } else {
                    [TestFlight passCheckpoint:@"Loaded Facebook via Web"];
                    NSString *url = [NSString stringWithFormat:@"http://facebook.com/%@", facebookPage];
                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString: url]];
                }
            }
            break;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    

}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{        
    return 0.0;
}

#pragma mark OBANavigationTargetAware

- (OBANavigationTarget*) navigationTarget {
    return [OBANavigationTarget target:OBANavigationTargetTypeContactUs];
}

@end

