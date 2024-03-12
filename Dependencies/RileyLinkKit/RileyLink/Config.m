//
//  Config.m
//  RileyLink
//
//  Created by Pete Schwamb on 6/27/15.
//  Copyright (c) 2015 Pete Schwamb. All rights reserved.
//

@import CoreData;
#import "Config.h"
#import <UIKit/UIKit.h>

@implementation Config

+ (Config *)sharedInstance
{
    // structure used to test whether the block has completed or not
    static dispatch_once_t p = 0;
    
    // initialize sharedObject as nil (first call only)
    __strong static Config * _sharedObject = nil;
    
    // executes a block object once and only once for the lifetime of an application
    dispatch_once(&p, ^{
        _sharedObject = [[self alloc] init];
    });
    
    // returns the same object each time
    return _sharedObject;
}

- (instancetype)init {
    if (self = [super init]) {
        _defaults = [NSUserDefaults standardUserDefaults];
    }
    
    return self;
}


- (void) setNightscoutURL:(NSURL *)nightscoutURL {
    [_defaults setValue:nightscoutURL.absoluteString forKey:@"nightscoutURL"];
}

- (NSURL*) nightscoutURL {
    return [NSURL URLWithString:[_defaults stringForKey:@"nightscoutURL"]];
}

- (void) setNightscoutAPISecret:(NSString *)nightscoutAPISecret {
    [_defaults setValue:nightscoutAPISecret forKey:@"nightscoutAPISecret"];
}

- (NSString*) nightscoutAPISecret {
    return [_defaults stringForKey:@"nightscoutAPISecret"];
}

- (NSSet*) autoConnectIds {
    NSSet *set = [[NSUserDefaults standardUserDefaults] objectForKey:@"autoConnectIds"];
    if (!set) {
        set = [NSSet set];
    }
    return set;
}

- (void) setAutoConnectIds:(NSSet *)autoConnectIds {
    [[NSUserDefaults standardUserDefaults] setObject:[autoConnectIds allObjects] forKey:@"autoConnectIds"];
}

- (BOOL) uploadEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"uploadEnabled"];
}

- (void) setUploadEnabled:(BOOL)uploadEnabled {
    [[NSUserDefaults standardUserDefaults] setBool:uploadEnabled forKey:@"uploadEnabled"];
}

- (BOOL) fetchCGMEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"fetchCGMEnabled"];
}

- (void) setFetchCGMEnabled:(BOOL)fetchCGMEnabled {
    [[NSUserDefaults standardUserDefaults] setBool:fetchCGMEnabled forKey:@"fetchCGMEnabled"];
}


@end
