//
//  Log.m
//  GlucoseLink
//
//  Created by Pete Schwamb on 2/22/15.
//  Copyright (c) 2015 Pete Schwamb. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "mach/mach.h" 
#import "Log.h"

NSMutableArray *logEntries = nil;

@implementation Log

vm_size_t usedMemory(void) {
  struct task_basic_info info;
  mach_msg_type_number_t size = sizeof(info);
  kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
  return (kerr == KERN_SUCCESS) ? info.resident_size : 0; // size in bytes
}

vm_size_t freeMemory(void) {
  mach_port_t host_port = mach_host_self();
  mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
  vm_size_t pagesize;
  vm_statistics_data_t vm_stat;
  
  host_page_size(host_port, &pagesize);
  (void) host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size);
  return vm_stat.free_count * pagesize;
}

void logMemUsage(void) {
  // compute memory usage and log if different by >= 100k
  static long prevMemUsage = 0;
  long curMemUsage = usedMemory();
  long memUsageDiff = curMemUsage - prevMemUsage;
  
  if (memUsageDiff > 100000 || memUsageDiff < -100000) {
    prevMemUsage = curMemUsage;
    NSLog(@"Memory used %7.1f (%+5.0f), free %7.1f kb", curMemUsage/1000.0f, memUsageDiff/1000.0f, freeMemory()/1000.0f);
  }
}

+ (NSArray*) popLogEntries {
  NSArray *rval = logEntries;
  logEntries = [NSMutableArray array];
  if (rval == nil) {
    rval = [NSMutableArray array];
  }
  return rval;
}

void append(NSString *msg){
  if (logEntries == nil) {
    logEntries = [NSMutableArray array];
  }
#ifdef LOG_TO_NS
  [logEntries addObject:msg];
#endif
  // get path to Documents/somefile.txt
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *documentsDirectory = paths[0];
  NSString *path = [documentsDirectory stringByAppendingPathComponent:@"logfile.txt"];
  // create if needed
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]){
    fprintf(stderr,"Creating file at %s",path.UTF8String);
    [[NSData data] writeToFile:path atomically:YES];
  }
  // append
  NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
  [handle truncateFileAtOffset:[handle seekToEndOfFile]];
  [handle writeData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
  [handle closeFile];
}

void _Log(NSString *prefix, const char *file, int lineNumber, const char *funcName, NSString *format,...) {
  
  static NSDateFormatter *dateFormat = nil;
  if (nil == dateFormat) {
    dateFormat = [[NSDateFormatter alloc] init]; // NOT NSDateFormatter *dateFormat = ...
    dateFormat.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
  }
  
  va_list ap;
  va_start (ap, format);
  format = [format stringByAppendingString:@"\n"];
  NSDate *time = [NSDate date];
  NSString *msg = [[NSString alloc] initWithFormat:[NSString stringWithFormat:@"%@: %@", [dateFormat stringFromDate:time], format] arguments:ap];
  va_end (ap);
  fprintf(stderr,"%s", msg.UTF8String);
  append(msg);
}
@end