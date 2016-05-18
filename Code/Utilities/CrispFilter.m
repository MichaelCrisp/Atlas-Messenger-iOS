//
//  CrispFilter.m
//  Atlas Messenger
//
//  Created by Mike Manley on 3/30/16.
//  Copyright © 2016 Layer, Inc. All rights reserved.
//
#import <Atlas/Atlas.h>
#import "CrispFilter.h"

@interface CrispFilter()
@property (nonatomic) NSURL *monitoredConversationIdentifier;
@property (nonatomic) ATLMLayerClient *layerClient;
@property (nonatomic) NSDate *silencedUntil;
@property (nonatomic) NSString *confirmText;
@property (nonatomic) NSString *confirmImage;
@property (nonatomic) NSString *confirmVideo;
@property (nonatomic) NSString *confirmLocation;

//- (LYRMessage*) messageFromRemoteNotification:(NSDictionary*) remoteNotification;

@end

@implementation CrispFilter

- (id) initWithApiKey: (NSString*) apiKey policy: (NSString*) policy
{
    self = [super init];
    if(self) {
        self->_serverUrl = @"http://live1.dc1.rmf.crispthinking.com/";
        self->_apiKey = apiKey;
        self->_policy = policy;
        self->_contentType = policy;
        self->_silencedUntil = nil;
        self->_confirmText = nil;
        self->_confirmImage = nil;
        self->_confirmVideo = nil;
        self->_confirmLocation = nil;
    }
    return self;
}

- (id) initWithApiKey:(NSString *)apiKey policy:(NSString *)policy serverUrl: (NSString*)serverUrl
{
    self = [super init];
    if(self) {
        self->_serverUrl = serverUrl;
        self->_apiKey = apiKey;
        self->_policy = policy;
        self->_contentType = policy;
        self->_confirmText = nil;
        self->_confirmImage = nil;
        self->_confirmLocation = nil;
    }
    return self;
}

- (id) initWithApiKey:(NSString *)apiKey policy:(NSString *)policy contentType: (NSString*) contentType serverUrl: (NSString*)serverUrl
{
    self = [super init];
    if(self) {
        self->_serverUrl = serverUrl;
        self->_apiKey = apiKey;
        self->_policy = policy;
        self->_contentType = contentType;
        self->_confirmText = nil;
        self->_confirmImage = nil;
        self->_confirmLocation = nil;
    }
    return self;
}

- (NSString*) submitUGCText:(NSString *) text From:(NSString *)author FromName:(NSString *) authorName To:(NSString *) recipient
{
    NSString *contentId = [[NSUUID UUID] UUIDString];
    return [self submitUGCText:text From:author FromName:authorName To:recipient Policy:self.policy ContentType:self.contentType ContentId: contentId];
}

- (NSString*) submitUGCText:(NSString *) text From:(NSString *)author FromName:(NSString *) authorName To:(NSString *) recipient Policy: (NSString*) policy ContentType:(NSString*) contentType ContentId: (NSString*) contentId
{
    if  (self.isSilenced)
        return nil;
    
    NSError *error = nil;
    
    NSMutableDictionary* parameters = [[NSMutableDictionary alloc] init];
    [parameters setObject:self.apiKey forKey:@"ApiKey"];
    if(policy != nil) { [parameters setObject:policy forKey:@"Policy"]; }
    [parameters setObject:contentType forKey:@"ContentType"];
    [parameters setObject:contentId forKey:@"ContentId"];
    [parameters setObject:author forKey:@"Author"];
    [parameters setObject:recipient forKey:@"Recipient"];
    [parameters setObject:text forKey:@"Text"];
    if(authorName != nil) { [parameters setObject:authorName forKey:@"AuthorDisplayName"]; }

    /*
    NSDictionary *parameters = @{ @"ApiKey": self.apiKey,
                                  @"Policy": policy,
                                  @"ContentType": contentType,
                                  @"ContentId": contentId,
                                  @"Author": author,
                                  @"AuthodDisplayName", authorName,
                                  @"Recipient" : recipient,
                                  @"Text": text };
     */
    
    NSString *fullUrl = [NSString stringWithFormat: @"%@/Rmf/v2/SubmitUGCText", self.serverUrl];
    NSData *json = [NSJSONSerialization dataWithJSONObject:parameters options:NSJSONWritingPrettyPrinted error:&error];
    
    NSMutableURLRequest *request  = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: fullUrl]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody: json];
    
    //NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    
    NSURLResponse * resp = nil;
    NSData *response = [NSURLConnection sendSynchronousRequest: request returningResponse: &resp error: &error];
    
    
    NSDictionary *rmfResponse = [NSJSONSerialization JSONObjectWithData: response options: 0 error: &error];
    NSString* filtered = rmfResponse[@"FilteredText"];
    if(filtered == nil)
    {
        filtered = text;
    }
    return filtered;
}

- (NSString*) submitChat:(NSString *) text From:(NSString *)author FromName: authorName To:(NSString *) recipient
{
    NSError *error = nil;
    
    NSString *fullUrl = [NSString stringWithFormat: @"%@Rmf/v2/SubmitChat?apikey=%@&policy=%@&author=%@&authorname=%@&recipient=%@&text=%@",self.serverUrl, self.apiKey, self.policy, author, authorName, recipient, text];
    // quick cheat encoding
    fullUrl = [fullUrl stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSURLRequest *request  = [NSURLRequest requestWithURL: [NSURL URLWithString: fullUrl]];
    NSURLResponse * resp = nil;
    NSData *response = [NSURLConnection sendSynchronousRequest: request returningResponse: &resp error: &error];
    
    NSDictionary *rmfResponse = [NSJSONSerialization JSONObjectWithData: response options: 0 error: &error];
    return rmfResponse[@"Filtered"];
}

-(void) registerWithCrisp: (ATLMLayerClient*) layerClient user: (LYRIdentity*) user
{
    NSSet  *participants = [NSSet setWithObject: user.userID];
    NSDictionary *options =
    @{ LYRConversationOptionsMetadataKey:
           @{ @"conversationName" : @"CrispAlerts" }
    };
    NSError *error;
    // Look for an existing conversation with just this user as participant - if it exists use it
    LYRConversation *conversation = [layerClient existingConversationForParticipants:participants];
    
    if(!conversation) {
        // Otherwise we create a new one
        conversation = [layerClient newConversationWithParticipants: participants options: options error: &error ];
        // Send a message to the conversation to ensure its setup fully
        LYRMessagePart *messagePart = [LYRMessagePart messagePartWithText:@"Alerts"];
        LYRMessage* message = [layerClient newMessageWithParts:@[ messagePart ] options:nil error:&error];
        [conversation sendMessage:message error:&error];
    }
    
    self.monitoredConversationIdentifier = conversation.identifier;
    self.layerClient = layerClient;
    NSString *conversationId = [conversation.identifier lastPathComponent];
    NSString *appId = [layerClient.appID lastPathComponent];
    NSString *messages_url = [NSString stringWithFormat:@"https://api.layer.com/apps/%@/conversations/%@/messages", appId, conversationId];
    [self submitUGCText:messages_url From:user.userID FromName:user.displayName To: @"Crisp_Notification_System"];
}

- (LYRMessage*) messageFromRemoteNotification:(NSDictionary*) remoteNotification
{
    NSURL *messageIdentifier = [NSURL URLWithString:[remoteNotification valueForKeyPath:@"layer.message_identifier"]];
    return [self.layerClient messageForIdentifier:messageIdentifier];
}

- (void) processCrispPolicyMessagePart:(LYRMessagePart*) part
{
    NSString *text = [[NSString alloc] initWithData:part.data encoding:NSUTF8StringEncoding];
    self->_policy = text;
}

- (void) processCrispAlertMessagePart:(LYRMessagePart*) part
{
    NSString *text = [[NSString alloc] initWithData:part.data encoding:NSUTF8StringEncoding];
    
    /*
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Crisp Alerts"
                                                        message:text
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                            otherButtonTitles:@"OK", nil];
    [alertView show];
     */
    // iOS 8 preferred method :(
    //Can't use here because we don't have access to call presentViewController
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Crisp Alert" message:text preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK action")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alertController addAction:okAction];
    
    UIApplication* application = [UIApplication sharedApplication];
    dispatch_async(dispatch_get_main_queue(), ^{
        [application.keyWindow.rootViewController presentViewController: alertController animated:YES completion:nil];
    });
}

- (void) processCrispSilenceMessagePart:(LYRMessagePart*) part
{
    NSString *text = [[NSString alloc] initWithData:part.data encoding:NSUTF8StringEncoding];
    int minutes = [text intValue];
    
    self.silencedUntil = [[[NSDate alloc] init] dateByAddingTimeInterval:(minutes*60)];
}

- (void) processCrispConfirmMessagePart:(LYRMessagePart*) part
{
    NSString *text = [[NSString alloc] initWithData:part.data encoding:NSUTF8StringEncoding];

    if ([part.MIMEType isEqualToString: @"crisp/confirmText"]) {
        _confirmText = text;
    } else if([part.MIMEType isEqualToString: @"crisp/confirmImage"]) {
        _confirmImage = text;
    } else if([part.MIMEType isEqualToString: @"crisp/confirmVideo"]) {
        _confirmVideo = text;
    } else if([part.MIMEType isEqualToString: @"crisp/confirmLocation"]) {
        _confirmLocation = text;
    }
}

- (BOOL) isSilenced
{
    if(self.silencedUntil == nil) return false;
    
    NSDate* now = [[NSDate alloc] init];
    if([now compare: self.silencedUntil] == NSOrderedAscending)
    {
        return true;
    }
    return false;
}

- (void) displaySilencedAlert
{
    if(self.silencedUntil == nil) return;
    
    NSString *localDate = [NSDateFormatter localizedStringFromDate:self.silencedUntil dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *text = [NSString stringWithFormat: @"You have been silenced until %@", localDate];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Crisp Alert" message:text preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK action")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alertController addAction:okAction];
    
    UIApplication* application = [UIApplication sharedApplication];
    [application.keyWindow.rootViewController presentViewController: alertController animated:YES completion:nil];
}

- (NSString*) confirmTextForMediaType:(ATLMediaAttachmentType) mediaType
{
    switch(mediaType)
    {
        case ATLMediaAttachmentTypeText:
            return _confirmText;
        case ATLMediaAttachmentTypeLocation:
            return _confirmLocation;
        case ATLMediaAttachmentTypeImage:
            return _confirmImage;
        case ATLMediaAttachmentTypeVideo:
            return _confirmVideo;
        default:
            return _confirmText;
    }
}

-(BOOL) confirmSend
{
    // TODO - Check if we want to confirm send and pick up text from there
    NSString *text = [NSString stringWithFormat: @"Do you really want to send?"];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Crisp Alert" message:text preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK action")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel action")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alertController addAction:okAction];
    [alertController addAction:cancelAction];
    
    UIApplication* application = [UIApplication sharedApplication];
    [application.keyWindow.rootViewController presentViewController: alertController animated:YES completion:nil];
    
    return false;
}

- (LYRAnnouncement *)announcementForIdentifier:(NSURL*)announcementIdentifier
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRAnnouncement class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"identifier" predicateOperator:LYRPredicateOperatorIsEqualTo value:announcementIdentifier];
    NSError *error = nil;
    LYRAnnouncement *announcement = [[self.layerClient executeQuery: query error:&error] firstObject];
    return announcement;
}

- (LYRMessage *)messageForIdentifier:(NSURL*)messageIdentifier
{
    LYRQuery *query = [LYRQuery queryWithQueryableClass:[LYRMessage class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"identifier" predicateOperator:LYRPredicateOperatorIsEqualTo value:messageIdentifier];
    NSError *error = nil;
    LYRAnnouncement *message = [[self.layerClient executeQuery: query error:&error] firstObject];
    return message;
}


- (LYRAnnouncement *)announcementFromRemoteNotification:(NSDictionary *)remoteNotification
{
    NSURL *announcementIdentifier = [NSURL URLWithString:[remoteNotification valueForKeyPath:@"layer.announcement_identifier"]];
    if(announcementIdentifier == nil) return nil;
    return [self announcementForIdentifier:announcementIdentifier];
}

- (void) onNotification: (NSDictionary*)notification
{
    NSLog(@"Processing Notification");
    NSURL* annoucementIdentifier = [NSURL URLWithString:[notification valueForKeyPath:@"layer.announcement_identifier"]];
    if(annoucementIdentifier != nil)
    {
        [self.layerClient waitForCreationOfObjectWithIdentifier:annoucementIdentifier timeout:3.0F completion:
         ^(id  _Nullable object, NSError * _Nullable error) {
             if(object)
             {
                 [self onMessageNotification: (LYRMessage*)object];
             }
         }];
    }
    // Check for matching conversation so we don't do potential expensive operations for every conversation.
    NSURL *conversationIdentifier = [NSURL URLWithString:[notification valueForKeyPath:@"layer.conversation_identifier"]];
    if(![conversationIdentifier isEqual:self.monitoredConversationIdentifier]) return;
    
    // Get the message identifier and wait for the creation of that object
    NSURL *messageIdentifier = [NSURL URLWithString:[notification valueForKeyPath:@"layer.message_identifier"]];
    if(messageIdentifier != nil) {
        [self.layerClient waitForCreationOfObjectWithIdentifier:messageIdentifier timeout:3.0F completion:
         ^(id  _Nullable object, NSError * _Nullable error) {
             if(object)
             {
                 [self onMessageNotification: (LYRMessage*)object];
             }
         }];
    }
}

- (void) onMessageNotification: (LYRMessage*) message
{
    if(message == nil) return;
    if([message.sender.displayName isEqual:@"Crisp System"])
    {
        for(LYRMessagePart* messagePart in message.parts)
        {
            if ([messagePart.MIMEType isEqualToString: @"crisp/policy"])
            {
                [self processCrispPolicyMessagePart: messagePart];
            } else if ([messagePart.MIMEType isEqualToString:@"crisp/alert"]) {
                [self processCrispAlertMessagePart: messagePart];
            } else if ([messagePart.MIMEType isEqualToString:@"crisp/silence"]) {
                [self processCrispSilenceMessagePart: messagePart];
            } else if ([messagePart.MIMEType hasPrefix: @"crisp/confirm"]) {
                [self processCrispConfirmMessagePart: messagePart];
            }
        }
    }
}

/*
- (void) onConversationNotification: (LYRConversation*) conversation notification: (NSDictionary*)notification;
{
    if(self.monitoredConversationIdentifier != nil && [self.monitoredConversationIdentifier isEqual:conversation.identifier])
    {
        LYRMessage *message = [self messageFromRemoteNotification: notification];
        if([message.sender.displayName isEqual:@"Crisp System"])
        {
            for(LYRMessagePart* messagePart in message.parts)
            {
                if ([messagePart.MIMEType isEqualToString: @"crisp/policy"])
                {
                    [self processCrispPolicyMessagePart: messagePart];
                } else if ([messagePart.MIMEType isEqualToString:@"crisp/alert"]) {
                    [self processCrispAlertMessagePart: messagePart];
                }
            }
        }
    }
}
*/

@end
