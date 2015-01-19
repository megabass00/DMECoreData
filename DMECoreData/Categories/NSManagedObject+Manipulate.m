//
//  NSManagedObject+Manipulate.m
//  Pods
//
//  Created by David Getapp on 16/1/15.
//
//

#import "DMECoreData.h"

@implementation NSManagedObject (Manipulate)

#pragma mark - Create

+(instancetype) createEntity
{
    return [self createEntityInContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(instancetype) createEntityInContext:(NSManagedObjectContext *)aContext
{
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wundeclared-selector"
    SEL selector = @selector(insertInManagedObjectContext:);
    #pragma clang diagnostic pop
    
    if ([self respondsToSelector:selector] && aContext != nil)
    {
        id entity = [self performSelector:selector withObject:aContext];
        return entity;
    }
    else
    {
        return [[self alloc] initWithEntity:[NSEntityDescription entityForName:[self entityNameChildClass] inManagedObjectContext:aContext] insertIntoManagedObjectContext:aContext];
    }
}

#pragma mark - Delete

-(void) deleteEntity
{
    [self deleteEntityInContext:[DMECoreDataStack sharedInstance].mainContext];
}

-(void) deleteEntityInContext:(NSManagedObjectContext *)aContext
{
    [aContext deleteObject:self];
}

#pragma mark - Truncate

+(BOOL) truncateAll
{
    return [self truncateAllInContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(BOOL) truncateAllInContext:(NSManagedObjectContext *)aContext
{
    NSArray *objectsToDelete = [self allObjectsInContext:aContext];
    for (NSManagedObject *objectToDelete in objectsToDelete)
    {
        [aContext deleteObject:objectToDelete];
    }
    return YES;
}

@end
