//
//  NSManagedObject+Manipulate.h
//  Pods
//
//  Created by David Getapp on 16/1/15.
//
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (Manipulate)

#pragma mark - Create

+(instancetype) createEntity;
+(instancetype) createEntityInContext:(NSManagedObjectContext *)aContext;

#pragma mark - Delete

-(void) deleteEntity;
-(void) deleteEntityInContext:(NSManagedObjectContext *)aContext;

#pragma mark - Truncate

+(BOOL) truncateAll;
+(BOOL) truncateAllInContext:(NSManagedObjectContext *)aContext;

@end
