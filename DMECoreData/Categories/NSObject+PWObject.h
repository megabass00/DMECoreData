//
//  NSObject+PWObject.h
//  iWine
//
//  Created by David Getapp on 15/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (PWObject)

- (void)performBlock:(void (^)(void))block afterDelay:(NSTimeInterval)delay;

@end