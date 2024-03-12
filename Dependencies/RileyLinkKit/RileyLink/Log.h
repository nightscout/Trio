//
//  Log.h
//  GlucoseLink
//
//  Created by Pete Schwamb on 2/22/15.
//  Copyright (c) 2015 Pete Schwamb. All rights reserved.
//

#ifndef RILEYLINK_Log_h
#define RILEYLINK_Log_h

//#define LOG_TO_NS 1

#define NSLog(args...) _Log(@"DEBUG ", __FILE__,__LINE__,__PRETTY_FUNCTION__,args);
@interface Log : NSObject

+ (NSArray*) popLogEntries;

void _Log(NSString *prefix, const char *file, int lineNumber, const char *funcName, NSString *format,...);
@end

void logMemUsage(void);

#endif
