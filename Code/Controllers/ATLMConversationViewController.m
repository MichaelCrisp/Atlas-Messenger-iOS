//
//  ATLMConversationViewController.m
//  Atlas Messenger
//
//  Created by Kevin Coleman on 9/10/14.
//  Copyright (c) 2014 Layer, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "ATLMConversationViewController.h"
#import "ATLMConversationDetailViewController.h"
#import "ATLMMediaViewController.h"
#import "ATLMUtilities.h"
#import "ATLMParticipantTableViewController.h"
#import "ATLMSplitViewController.h"
#import "LYRIdentity+ATLParticipant.h"



static NSDateFormatter *ATLMShortTimeFormatter()
{
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.timeStyle = NSDateFormatterShortStyle;
    }
    return dateFormatter;
}

static NSDateFormatter *ATLMDayOfWeekDateFormatter()
{
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"EEEE"; // Tuesday
    }
    return dateFormatter;
}

static NSDateFormatter *ATLMRelativeDateFormatter()
{
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.doesRelativeDateFormatting = YES;
    }
    return dateFormatter;
}

static NSDateFormatter *ATLMThisYearDateFormatter()
{
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"E, MMM dd,"; // Sat, Nov 29,
    }
    return dateFormatter;
}

static NSDateFormatter *ATLMDefaultDateFormatter()
{
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"MMM dd, yyyy,"; // Nov 29, 2013,
    }
    return dateFormatter;
}

typedef NS_ENUM(NSInteger, ATLMDateProximity) {
    ATLMDateProximityToday,
    ATLMDateProximityYesterday,
    ATLMDateProximityWeek,
    ATLMDateProximityYear,
    ATLMDateProximityOther,
};

static ATLMDateProximity ATLMProximityToDate(NSDate *date)
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    NSCalendarUnit calendarUnits = NSEraCalendarUnit | NSYearCalendarUnit | NSWeekOfMonthCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit;
#pragma GCC diagnostic pop
    NSDateComponents *dateComponents = [calendar components:calendarUnits fromDate:date];
    NSDateComponents *todayComponents = [calendar components:calendarUnits fromDate:now];
    if (dateComponents.day == todayComponents.day &&
        dateComponents.month == todayComponents.month &&
        dateComponents.year == todayComponents.year &&
        dateComponents.era == todayComponents.era) {
        return ATLMDateProximityToday;
    }

    NSDateComponents *componentsToYesterday = [NSDateComponents new];
    componentsToYesterday.day = -1;
    NSDate *yesterday = [calendar dateByAddingComponents:componentsToYesterday toDate:now options:0];
    NSDateComponents *yesterdayComponents = [calendar components:calendarUnits fromDate:yesterday];
    if (dateComponents.day == yesterdayComponents.day &&
        dateComponents.month == yesterdayComponents.month &&
        dateComponents.year == yesterdayComponents.year &&
        dateComponents.era == yesterdayComponents.era) {
        return ATLMDateProximityYesterday;
    }

    if (dateComponents.weekOfMonth == todayComponents.weekOfMonth &&
        dateComponents.month == todayComponents.month &&
        dateComponents.year == todayComponents.year &&
        dateComponents.era == todayComponents.era) {
        return ATLMDateProximityWeek;
    }

    if (dateComponents.year == todayComponents.year &&
        dateComponents.era == todayComponents.era) {
        return ATLMDateProximityYear;
    }

    return ATLMDateProximityOther;
}

// Horrible Hack to give us access to defaultMessagesForMediaAttachments from super class
@interface ATLConversationViewController (Private)
- (NSOrderedSet *)defaultMessagesForMediaAttachments:(NSArray *)mediaAttachments;
@end

@interface ATLMConversationViewController () <ATLMConversationDetailViewControllerDelegate, ATLParticipantTableViewControllerDelegate>

@end

@implementation ATLMConversationViewController

NSString *const ATLMConversationViewControllerAccessibilityLabel = @"Conversation View Controller";
NSString *const ATLMDetailsButtonAccessibilityLabel = @"Details Button";
NSString *const ATLMDetailsButtonLabel = @"Details";

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.accessibilityLabel = ATLMConversationViewControllerAccessibilityLabel;
    self.dataSource = self;
    self.delegate = self;
   
    if (self.conversation) {
        [self addDetailsButton];
    }
    
    [self configureUserInterfaceAttributes];
    [self registerNotificationObservers];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self configureTitle];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!self.view.isFirstResponder) {
        [self.view becomeFirstResponder];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (![self isMovingFromParentViewController]) {
        [self.view resignFirstResponder];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Accessors

- (void)setConversation:(LYRConversation *)conversation
{
    [super setConversation:conversation];
    [self configureTitle];
}

#pragma mark - ATLConversationViewControllerDelegate

/**
 Atlas - Informs the delegate of a successful message send. Atlas Messenger adds a `Details` button to the navigation bar if this is the first message sent within a new conversation.
 */
- (void)conversationViewController:(ATLConversationViewController *)viewController didSendMessage:(LYRMessage *)message
{
    [self addDetailsButton];
}

/**
 Atlas - Informs the delegate that a message failed to send. Atlas messeneger display an alert view to inform the user of the failure.
 */
- (void)conversationViewController:(ATLConversationViewController *)viewController didFailSendingMessage:(LYRMessage *)message error:(NSError *)error;
{
    NSLog(@"Message Send Failed with Error: %@", error);
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Messaging Error"
                                                        message:error.localizedDescription
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}

/**
 Atlas - Informs the delegate that a message was selected. Atlas messenger presents an `ATLImageViewController` if the message contains an image.
 */
- (void)conversationViewController:(ATLConversationViewController *)viewController didSelectMessage:(LYRMessage *)message
{
    LYRMessagePart *messagePart = ATLMessagePartForMIMEType(message, ATLMIMETypeImageJPEG);
    if (messagePart) {
        [self presentMediaViewControllerWithMessage:message];
        return;
    }
    messagePart = ATLMessagePartForMIMEType(message, ATLMIMETypeImagePNG);
    if (messagePart) {
        [self presentMediaViewControllerWithMessage:message];
        return;
    }
    messagePart = ATLMessagePartForMIMEType(message, ATLMIMETypeImageGIF);
    if (messagePart) {
        [self presentMediaViewControllerWithMessage:message];
        return;
    }
    messagePart = ATLMessagePartForMIMEType(message, ATLMIMETypeVideoMP4);
    if (messagePart) {
        [self presentMediaViewControllerWithMessage:message];
        return;
    }
}

- (void)presentMediaViewControllerWithMessage:(LYRMessage *)message
{
    ATLMMediaViewController *imageViewController = [[ATLMMediaViewController alloc] initWithMessage:message];
    UINavigationController *controller = [[UINavigationController alloc] initWithRootViewController:imageViewController];
    [self.navigationController presentViewController:controller animated:YES completion:nil];
}

#pragma mark - ATLConversationViewControllerDataSource

/**
 Atlas - Returns an object conforming to the `ATLParticipant` protocol whose `userID` property matches the supplied identity.
 */
- (id<ATLParticipant>)conversationViewController:(ATLConversationViewController *)conversationViewController participantForIdentity:(nonnull LYRIdentity *)identity
{
    return identity;
}

/**
 Atlas - Returns an `NSAttributedString` object for a given date. The format of this string can be configured to whatever format an application wishes to display.
 */
- (NSAttributedString *)conversationViewController:(ATLConversationViewController *)conversationViewController attributedStringForDisplayOfDate:(NSDate *)date
{
    NSDateFormatter *dateFormatter;
    ATLMDateProximity dateProximity = ATLMProximityToDate(date);
    switch (dateProximity) {
        case ATLMDateProximityToday:
        case ATLMDateProximityYesterday:
            dateFormatter = ATLMRelativeDateFormatter();
            break;
        case ATLMDateProximityWeek:
            dateFormatter = ATLMDayOfWeekDateFormatter();
            break;
        case ATLMDateProximityYear:
            dateFormatter = ATLMThisYearDateFormatter();
            break;
        case ATLMDateProximityOther:
            dateFormatter = ATLMDefaultDateFormatter();
            break;
    }

    NSString *dateString = [dateFormatter stringFromDate:date];
    NSString *timeString = [ATLMShortTimeFormatter() stringFromDate:date];
    
    NSMutableAttributedString *dateAttributedString = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ %@", dateString, timeString]];
    [dateAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor grayColor] range:NSMakeRange(0, dateAttributedString.length)];
    [dateAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11] range:NSMakeRange(0, dateAttributedString.length)];
    [dateAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:11] range:NSMakeRange(0, dateString.length)];
    return dateAttributedString;
}

/**
 Atlas - Returns an `NSAttributedString` object for given recipient state. The state string will only be displayed below the latest message that was sent by the currently authenticated user.
 */
- (NSAttributedString *)conversationViewController:(ATLConversationViewController *)conversationViewController attributedStringForDisplayOfRecipientStatus:(NSDictionary *)recipientStatus
{
    NSMutableDictionary *mutableRecipientStatus = [recipientStatus mutableCopy];
    if ([mutableRecipientStatus valueForKey:self.applicationController.layerClient.authenticatedUser.userID]) {
        [mutableRecipientStatus removeObjectForKey:self.applicationController.layerClient.authenticatedUser.userID];
    }
    
    NSString *statusString = [NSString new];
    if (mutableRecipientStatus.count > 1) {
        __block NSUInteger readCount = 0;
        __block BOOL delivered = NO;
        __block BOOL sent = NO;
        __block BOOL pending = NO;
        [mutableRecipientStatus enumerateKeysAndObjectsUsingBlock:^(NSString *userID, NSNumber *statusNumber, BOOL *stop) {
            LYRRecipientStatus status = statusNumber.integerValue;
            switch (status) {
                case LYRRecipientStatusInvalid:
                    break;
                case LYRRecipientStatusPending:
                    pending = YES;
                    break;
                case LYRRecipientStatusSent:
                    sent = YES;
                    break;
                case LYRRecipientStatusDelivered:
                    delivered = YES;
                    break;
                case LYRRecipientStatusRead:
                    readCount += 1;
                    break;
            }
        }];
        if (readCount) {
            NSString *participantString = readCount > 1 ? @"Participants" : @"Participant";
            statusString = [NSString stringWithFormat:@"Read by %lu %@", (unsigned long)readCount, participantString];
        } else if (pending) {
            statusString = @"Pending";
        }else if (delivered) {
            statusString = @"Delivered";
        } else if (sent) {
            statusString = @"Sent";
        }
    } else {
        __block NSString *blockStatusString = [NSString new];
        [mutableRecipientStatus enumerateKeysAndObjectsUsingBlock:^(NSString *userID, NSNumber *statusNumber, BOOL *stop) {
            if ([userID isEqualToString:self.applicationController.layerClient.authenticatedUser.userID]) return;
            LYRRecipientStatus status = statusNumber.integerValue;
            switch (status) {
                case LYRRecipientStatusInvalid:
                    blockStatusString = @"Not Sent";
                    break;
                case LYRRecipientStatusPending:
                    blockStatusString = @"Pending";
                    break;
                case LYRRecipientStatusSent:
                    blockStatusString = @"Sent";
                    break;
                case LYRRecipientStatusDelivered:
                    blockStatusString = @"Delivered";
                    break;
                case LYRRecipientStatusRead:
                    blockStatusString = @"Read";
                    break;
            }
        }];
        statusString = blockStatusString;
    }
    return [[NSAttributedString alloc] initWithString:statusString attributes:@{NSFontAttributeName : [UIFont boldSystemFontOfSize:11]}];
}

#pragma mark - ATLAddressBarControllerDelegate

/**
 Atlas - Informs the delegate that the user tapped the `addContacts` icon in the `ATLAddressBarViewController`. Atlas Messenger presents an `ATLParticipantPickerController`.
 */
- (void)addressBarViewController:(ATLAddressBarViewController *)addressBarViewController didTapAddContactsButton:(UIButton *)addContactsButton
{
    NSSet *selectedParticipantIDs = [addressBarViewController.selectedParticipants valueForKey:@"userID"];
    if (!selectedParticipantIDs) {
        selectedParticipantIDs = [NSSet new];
    }
    
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRIdentity class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"userID" predicateOperator:LYRPredicateOperatorIsNotIn value:selectedParticipantIDs];
    NSError *error;
    NSOrderedSet *identities = [self.layerClient executeQuery:query error:&error];
    if (error) {
            ATLMAlertWithError(error);
    }
    
    ATLMParticipantTableViewController  *controller = [ATLMParticipantTableViewController participantTableViewControllerWithParticipants:identities.set sortType:ATLParticipantPickerSortTypeFirstName];
    controller.blockedParticipantIdentifiers = [self.layerClient.policies valueForKey:@"sentByUserID"];
    controller.delegate = self;
    controller.allowsMultipleSelection = NO;
    
    UINavigationController *navigationController =[[UINavigationController alloc] initWithRootViewController:controller];
    [self.navigationController presentViewController:navigationController animated:YES completion:nil];
}

/**
 Atlas - Informs the delegate that the user is searching for participants. Atlas Messengers queries for participants whose `fullName` property contains the given search string.
 */
- (void)addressBarViewController:(ATLAddressBarViewController *)addressBarViewController searchForParticipantsMatchingText:(NSString *)searchText completion:(void (^)(NSArray *participants))completion
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRIdentity class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"displayName" predicateOperator:LYRPredicateOperatorLike value:[searchText stringByAppendingString:@"%"]];
    [self.layerClient executeQuery:query completion:^(NSOrderedSet<id<ATLParticipant>> * _Nullable resultSet, NSError * _Nullable error) {
        if (resultSet) {
            completion(resultSet.array);
        } else {
            completion([NSArray array]);
        }
    }];
}

/**
 Atlas - Informs the delegate that the user tapped on the `ATLAddressBarViewController` while it was disabled. Atlas Messenger presents an `ATLConversationDetailViewController` in response.
 */
- (void)addressBarViewControllerDidSelectWhileDisabled:(ATLAddressBarViewController *)addressBarViewController
{
    [self detailsButtonTapped];
}

#pragma mark - ATLParticipantTableViewControllerDelegate

/**
 Atlas - Informs the delegate that the user selected an participant. Atlas Messenger in turn, informs the `ATLAddressBarViewController` of the selection.
 */
- (void)participantTableViewController:(ATLParticipantTableViewController *)participantTableViewController didSelectParticipant:(id<ATLParticipant>)participant
{
    [self.addressBarController selectParticipant:participant];
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

/**
 Atlas - Informs the delegate that the user is searching for participants. Atlas Messengers queries for participants whose `fullName` property contains the give search string.
 */
- (void)participantTableViewController:(ATLParticipantTableViewController *)participantTableViewController didSearchWithString:(NSString *)searchText completion:(void (^)(NSSet *))completion
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRIdentity class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"displayName" predicateOperator:LYRPredicateOperatorLike value:searchText];
    [self.layerClient executeQuery:query completion:^(NSOrderedSet<id<ATLParticipant>> * _Nullable resultSet, NSError * _Nullable error) {
        if (resultSet) {
            completion(resultSet.set);
        } else {
            completion([NSSet set]);
        }
    }];
}

#pragma mark - LSConversationDetailViewControllerDelegate

/**
 Atlas - Informs the delegate that the user has tapped the `Share My Current Location` button. Atlas Messenger sends a message into the current conversation with the current location.
 */
- (void)conversationDetailViewControllerDidSelectShareLocation:(ATLMConversationDetailViewController *)conversationDetailViewController
{
    [self sendLocationMessage];
    [self.navigationController popViewControllerAnimated:YES];
}

/**
 Atlas - Informs the delegate that the conversation has changed. Atlas Messenger updates its conversation and the current view controller's title in response.
 */
- (void)conversationDetailViewController:(ATLMConversationDetailViewController *)conversationDetailViewController didChangeConversation:(LYRConversation *)conversation
{
    self.conversation = conversation;
    [self configureTitle];
}

#pragma mark - Details Button Actions

- (void)addDetailsButton
{
    if (self.navigationItem.rightBarButtonItem) return;

    UIBarButtonItem *detailsButtonItem = [[UIBarButtonItem alloc] initWithTitle:ATLMDetailsButtonLabel
                                                                          style:UIBarButtonItemStylePlain
                                                                         target:self
                                                                         action:@selector(detailsButtonTapped)];
    detailsButtonItem.accessibilityLabel = ATLMDetailsButtonAccessibilityLabel;
    self.navigationItem.rightBarButtonItem = detailsButtonItem;
}

- (void)detailsButtonTapped
{
    ATLMConversationDetailViewController *detailViewController = [ATLMConversationDetailViewController conversationDetailViewControllerWithConversation:self.conversation];
    detailViewController.detailDelegate = self;
    detailViewController.applicationController = self.applicationController;
    [self.navigationController pushViewController:detailViewController animated:YES];
}

#pragma mark - Notification Handlers

- (void)conversationMetadataDidChange:(NSNotification *)notification
{
    if (!self.conversation) return;
    if (!notification.object) return;
    if (![notification.object isEqual:self.conversation]) return;

    [self configureTitle];
}

#pragma mark - Helpers

- (void)configureTitle
{
    if ([self.conversation.metadata valueForKey:ATLMConversationMetadataNameKey]) {
        NSString *conversationTitle = [self.conversation.metadata valueForKey:ATLMConversationMetadataNameKey];
        if (conversationTitle.length) {
            self.title = conversationTitle;
        } else {
            self.title = [self defaultTitle];
        }    } else {
        self.title = [self defaultTitle];
    }
}

- (NSString *)defaultTitle
{
    if (!self.conversation) {
        return @"New Message";
    }
    
    NSMutableSet *otherParticipants = [self.conversation.participants mutableCopy];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"userID != %@", self.layerClient.authenticatedUser.userID];
    [otherParticipants filterUsingPredicate:predicate];
    
    if (otherParticipants.count == 0) {
        return @"Personal";
    } else if (otherParticipants.count == 1) {
        LYRIdentity *otherIdentity = [otherParticipants anyObject];
        id<ATLParticipant> participant = [self conversationViewController:self participantForIdentity:otherIdentity];
        return participant ? participant.firstName : @"Message";
    } else if (otherParticipants.count > 1) {
        NSUInteger participantCount = 0;
        id<ATLParticipant> knownParticipant;
        for (LYRIdentity *identity in otherParticipants) {
            id<ATLParticipant> participant = [self conversationViewController:self participantForIdentity:identity];
            if (participant) {
                participantCount += 1;
                knownParticipant = participant;
            }
        }
        if (participantCount == 1) {
            return knownParticipant.firstName;
        } else if (participantCount > 1) {
            return @"Group";
        }
    }
    return @"Message";
}

#pragma mark - Link Tap Handler

- (void)userDidTapLink:(NSNotification *)notification
{
    [[UIApplication sharedApplication] openURL:notification.object];
}

- (void)configureUserInterfaceAttributes
{
    [[ATLIncomingMessageCollectionViewCell appearance] setBubbleViewColor:ATLLightGrayColor()];
    [[ATLIncomingMessageCollectionViewCell appearance] setMessageTextColor:[UIColor blackColor]];
    [[ATLIncomingMessageCollectionViewCell appearance] setMessageLinkTextColor:ATLBlueColor()];
    
    [[ATLOutgoingMessageCollectionViewCell appearance] setBubbleViewColor:ATLBlueColor()];
    [[ATLOutgoingMessageCollectionViewCell appearance] setMessageTextColor:[UIColor whiteColor]];
    [[ATLOutgoingMessageCollectionViewCell appearance] setMessageLinkTextColor:[UIColor whiteColor]];
}

- (void)registerNotificationObservers
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDidTapLink:) name:ATLUserDidTapLinkNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(conversationMetadataDidChange:) name:ATLMConversationMetadataDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
}

#pragma mark - Device Orientation

- (void)deviceOrientationDidChange:(NSNotification *)notification
{
    [self.collectionView.collectionViewLayout invalidateLayout];
}

- (void)messageInputToolbarDidType:(ATLMessageInputToolbar *)messageInputToolbar
{
    if (!self.conversation) return;
    if (![self.applicationController.crispFilter isSilenced])
    {
        [self.conversation sendTypingIndicator:LYRTypingDidBegin];
    }
}

- (NSString *)filterText:(NSString *)text
{
    NSString *senderName =  self.layerClient.authenticatedUser.displayName;
    NSString *senderId = self.layerClient.authenticatedUser.userID;
    NSString *recipient = self.conversation.identifier.absoluteString;
    
    return [self.applicationController.crispFilter submitUGCText:text From:senderId FromName:senderName To:recipient];
}

// Override mediaAttachments so we can provide filtering
- (NSOrderedSet <LYRMessage*> *)conversationViewController:(ATLConversationViewController *)viewController messagesForMediaAttachments:(NSArray <ATLMediaAttachment*> *)mediaAttachments;
{
    // Check if we are silenced and return an nil messaage if so - will cause ATLConversationViewController
    // to abort sending.
    if ([self.applicationController.crispFilter isSilenced])
    {
        [self.applicationController.crispFilter displaySilencedAlert];
        return [NSOrderedSet orderedSet];
    }
    
    // Do filtering on the media attachments
    NSMutableArray *filteredMediaAttachments = [[NSMutableArray alloc] initWithCapacity:mediaAttachments.count];
    for(int i = 0; i < mediaAttachments.count; i++)
    {
        ATLMediaAttachment *attachment = mediaAttachments[i];
        if(attachment.mediaType == ATLMediaAttachmentTypeText)
        {
            NSString *filtered = [self filterText: attachment.textRepresentation];
            if (![filtered isEqualToString: attachment.textRepresentation])
            {
                attachment = [ATLMediaAttachment mediaAttachmentWithText: filtered];
            }
        }
        [filteredMediaAttachments addObject: attachment];
    }
    // Pass filtered media attachments on to the defaultMessagesForMediaAttachments method
    return [super defaultMessagesForMediaAttachments:filteredMediaAttachments];
}

@end
