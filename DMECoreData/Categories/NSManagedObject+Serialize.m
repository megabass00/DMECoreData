//
//  NSManagedObject+Serialize.m
//  iWine
//
//  Created by David Getapp on 22/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import "DMECoreData.h"

@implementation NSManagedObject (Serialize)

- (NSDictionary *)JSONToObjectOnServer {
    @throw [NSException exceptionWithName:@"JSONStringToObjectOnServer Not Overridden" reason:@"Must override JSONStringToObjectOnServer on NSManagedObject class" userInfo:nil];
    return nil;
}

- (NSDictionary *)filesURLToObjectOnServer {
    return @{};
}

@end
