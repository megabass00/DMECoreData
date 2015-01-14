//
//  NSFetchedResultsController+Fetch.m
//  iWine
//
//  Created by David Getapp on 21/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import "CoreData+DMECoreData.h"
#import "NSFetchedResultsController+Fetch.h"

@implementation NSFetchedResultsController (Fetch)

- (NSArray *)fetchAll
{
    __block NSArray *result = @[];
    [self.managedObjectContext performBlockAndWait:^{
        NSError *error;
        [self performFetch:&error];
        
        if(!error){
            result = self.fetchedObjects.copy;
        }
    }];
    
    return result;
}

- (NSManagedObject *)fetchFirst
{
    __block NSManagedObject *result = nil;
    [self.managedObjectContext performBlockAndWait:^{
        NSError *error;
        [self performFetch:&error];
        
        if(!error && self.fetchedObjects.count > 0){
            result = (NSManagedObject *)[self.fetchedObjects objectAtIndex:0];
        }
    }];
    
    return result;
}

@end
