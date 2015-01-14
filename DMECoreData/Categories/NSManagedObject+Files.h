//
//  NSManagedObject+Files.h
//  iWine
//
//  Created by David Getapp on 28/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (Files)

-(BOOL)fileExistWithName: (NSString *) aName;

-(BOOL)deleteFileWithName:(NSString *) aName;

@end
