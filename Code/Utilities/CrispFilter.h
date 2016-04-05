//
//  CrispFilter.h
//  Atlas Messenger
//
//  Created by Mike Manley on 3/30/16.
//  Copyright © 2016 Layer, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ATLMLayerClient.h"

@interface CrispFilter : NSObject

@property (nonatomic, readonly) NSString *serverUrl;
@property (nonatomic, readonly) NSString *apiKey;
@property (nonatomic) NSString *policy;
@property (nonatomic) NSString *contentType;

- (id) initWithApiKey: (NSString *) apiKey policy: (NSString *) policy;
- (id) initWithApiKey: (NSString *) apiKey policy: (NSString *) policy serverUrl: (NSString*) serverUrl;
- (id) initWithApiKey: (NSString *) apiKey policy: (NSString *) policy contentType: (NSString*) contentType serverUrl: (NSString*) serverUrl;


- (NSString*) submitChat:(NSString *) text From:(NSString *) author FromName: authorName To:(NSString *) recipient;
- (NSString*) submitUGCText:(NSString *) text From:(NSString *)author FromName:(NSString *) authorName To:(NSString *) recipient;
- (NSString*) submitUGCText:(NSString *) text From:(NSString *)author FromName:(NSString *) authorName To:(NSString *) recipient Policy: (NSString*) policy ContentType:(NSString*) contentType ContentId: (NSString*) contentId;
- (void) registerWithCrisp: (ATLMLayerClient*) layerClient user: (LYRIdentity*) user;
- (void) onNotification: (NSDictionary*)notification;
- (void) onMessageNotification: (LYRMessage*) message;

@end
