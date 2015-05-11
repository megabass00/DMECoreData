//
//  NSManagedObject+SyncStates.m
//  Pods
//
//  Created by David Getapp on 5/5/15.
//
//

#import "NSManagedObject+SyncStates.h"

@implementation NSManagedObject (SyncStates)

-(BOOL)deletable
{
    return NO;
}

-(BOOL)modifiable
{
    return NO;
}

@end
