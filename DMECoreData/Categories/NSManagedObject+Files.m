//
//  NSManagedObject+Files.m
//  iWine
//
//  Created by David Getapp on 28/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import "DMECoreData.h"

@implementation NSManagedObject (Files)

-(BOOL)fileExistWithName: (NSString *) aName
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *className = [NSString stringWithFormat:@"%@%@", [[self.entity.name substringToIndex:1] lowercaseString], [self.entity.name substringFromIndex:1]];
    NSString *urlLocal = [NSString stringWithFormat:@"%@/%@/%@", pathCache(), className, aName];
    return [filemgr fileExistsAtPath:urlLocal];
}

-(BOOL)deleteFileWithName:(NSString *) aName
{
    if(aName && ![aName isEqualToString:@""] && [self fileExistWithName:aName]){
        NSFileManager *filemgr = [NSFileManager defaultManager];
        NSString *className = [NSString stringWithFormat:@"%@%@", [[self.entity.name substringToIndex:1] lowercaseString], [self.entity.name substringFromIndex:1]];
        NSString *urlLocal = [NSString stringWithFormat:@"%@/%@/%@", pathCache(), className, aName];
        NSError *error;
        [filemgr removeItemAtPath:urlLocal error:&error];
        if (error) {
            return NO;
        }
        else{
            [[DMEThumbnailer sharedInstance] removeThumbnails:aName];
            
            return YES;
        }
    }
    else{
        return NO;
    }
}

@end
