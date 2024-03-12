//
//  Config.h
//  RileyLink
//
//  Created by Pete Schwamb on 6/27/15.
//  Copyright (c) 2015 Pete Schwamb. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Config : NSObject {
  NSUserDefaults *_defaults;
}

+ (nonnull Config *)sharedInstance;

@property (nonatomic, nullable, strong) NSURL *nightscoutURL;
@property (nonatomic, nullable, strong) NSString *nightscoutAPISecret;
@property (nonatomic, nullable, strong) NSSet *autoConnectIds;
@property (nonatomic, assign) BOOL uploadEnabled;
@property (nonatomic, assign) BOOL fetchCGMEnabled;

@end
