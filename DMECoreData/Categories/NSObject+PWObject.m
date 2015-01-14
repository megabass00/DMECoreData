//
//  NSObject+PWObject.m
//  iWine
//
//  Created by David Getapp on 15/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import "DMECoreData.h"

@implementation NSObject (PWObject)

- (void)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay
{
	int64_t delta = (int64_t)(1.0e9 * delay);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delta), dispatch_get_main_queue(), block);
}

@end
