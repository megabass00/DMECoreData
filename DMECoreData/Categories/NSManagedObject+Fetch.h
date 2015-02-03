//
//  NSManagedObject+Fetch.h
//  Pods
//
//  Created by David Getapp on 15/1/15.
//
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (Fetch)

#pragma mark - FetchResultController

+(NSFetchedResultsController *) fetchAllObjects;
+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending;
+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSArray *)sortDescriptors;

+(NSFetchedResultsController *) fetchObjectsFilterBy:(NSPredicate *)aPredicate;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key;

+(NSFetchedResultsController *) fetchObjectWithId:(NSString *)aId;
+(NSFetchedResultsController *) fetchObjectFilterBy:(NSPredicate *)aPredicate;

#pragma mark - FetchResultController with context

+(NSFetchedResultsController *) fetchAllObjectsInContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending inContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSArray *)sortDescriptors inContext:(NSManagedObjectContext *)aContext;

+(NSFetchedResultsController *) fetchObjectsFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext;

+(NSFetchedResultsController *) fetchObjectWithId:(NSString *)aId inContext:(NSManagedObjectContext *)aContext;
+(NSFetchedResultsController *) fetchObjectFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;

#pragma mark - Fetch Objects

+(NSArray *) allObjects;
+(NSArray *) allObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending;
+(NSArray *) allObjectsOrderBy:(NSArray *)sortDescriptors;

+(NSArray *) objectsFilterBy:(NSPredicate *)aPredicate;
+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate;
+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate;
+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key;
+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key;

+(instancetype) objectWithId:(NSString *)aId;
+(instancetype) objectFilterBy:(NSPredicate *)aPredicate;

#pragma mark - Fetch Objects with context

+(NSArray *) allObjectsInContext:(NSManagedObjectContext *)aContext;
+(NSArray *) allObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending inContext:(NSManagedObjectContext *)aContext;
+(NSArray *) allObjectsOrderBy:(NSArray *)sortDescriptors inContext:(NSManagedObjectContext *)aContext;

+(NSArray *) objectsFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;
+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;
+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;
+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext;
+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext;

+(instancetype) objectWithId:(NSString *)aId inContext:(NSManagedObjectContext *)aContext;
+(instancetype) objectFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;

#pragma mark - Count

+(NSInteger) countAllObjects;
+(NSInteger) countObjectsFilterBy:(NSPredicate *)aPredicate;

#pragma mark - Count with context

+(NSInteger) countAllObjectsInContext:(NSManagedObjectContext *)aContext;
+(NSInteger) countObjectsFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext;

#pragma mark - Other

+(NSString *) entityNameChildClass;

+(instancetype) objectWithID:(NSManagedObjectID *)aId;
+(instancetype) objectWithID:(NSManagedObjectID *)aId inContext:(NSManagedObjectContext *)aContext;

@end
