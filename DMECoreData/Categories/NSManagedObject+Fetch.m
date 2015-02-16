//
//  NSManagedObject+Fetch.m
//  Pods
//
//  Created by David Getapp on 15/1/15.
//
//

#import "DMECoreData.h"

@implementation NSManagedObject (Fetch)

#pragma mark - FetchResultController

+(NSFetchedResultsController *) fetchAllObjects
{
    return [self fetchAllObjectsInContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending
{
    return [self fetchAllObjectsOrderBy:orderField orderAscending:ascending inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSArray *)sortDescriptors
{
    return [self fetchAllObjectsOrderBy:sortDescriptors inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectsFilterBy:(NSPredicate *)aPredicate
{
    return [self fetchObjectsFilterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate
{
    return [self fetchObjectsOrderBy:orderField orderAscending:ascending filterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate
{
    return [self fetchObjectsOrderBy:sortDescriptors filterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key
{
    return [self fetchObjectsOrderBy:orderField orderAscending:ascending filterBy:aPredicate sectionNameKeyPath:key inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key
{
    return [self fetchObjectsOrderBy:sortDescriptors filterBy:aPredicate sectionNameKeyPath:key inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectWithId:(NSString *)aId
{
    return [self fetchObjectWithId:aId inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSFetchedResultsController *) fetchObjectFilterBy:(NSPredicate *)aPredicate
{
    return [self fetchObjectFilterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}


#pragma mark - FetchResultController with context

+(NSFetchedResultsController *) fetchAllObjectsInContext:(NSManagedObjectContext *)aContext
{
    return [self fetchAllObjectsOrderBy:@[] inContext:aContext];
}

+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending inContext:(NSManagedObjectContext *)aContext
{
    return [self fetchAllObjectsOrderBy:@[[[NSSortDescriptor alloc] initWithKey:orderField ascending:ascending]] inContext:aContext];
}

+(NSFetchedResultsController *) fetchAllObjectsOrderBy:(NSArray *)sortDescriptors inContext:(NSManagedObjectContext *)aContext
{
    return [self fetchObjectsOrderBy:sortDescriptors filterBy:nil sectionNameKeyPath:nil inContext:aContext];
}

+(NSFetchedResultsController *) fetchObjectsFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [self fetchObjectsOrderBy:nil filterBy:aPredicate inContext:aContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [self fetchObjectsOrderBy:@[[[NSSortDescriptor alloc] initWithKey:orderField ascending:ascending]] filterBy:aPredicate inContext:aContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [self fetchObjectsOrderBy:sortDescriptors filterBy:aPredicate sectionNameKeyPath:nil inContext:aContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext
{
    return [self fetchObjectsOrderBy:@[[[NSSortDescriptor alloc] initWithKey:orderField ascending:ascending]] filterBy:aPredicate sectionNameKeyPath:key inContext:aContext];
}

+(NSFetchedResultsController *) fetchObjectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext
{
    NSFetchedResultsController *res = nil;
    
    //Crear un request
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:[self entityNameChildClass]];
    if(sortDescriptors){
        req.sortDescriptors = sortDescriptors;
    }
    else{
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES]];
    }
    
    //Predicado
    NSPredicate *syncPredicate = [NSPredicate predicateWithFormat:@"syncStatus != %@",[NSNumber numberWithInt:ObjectDeleted]];
    if(aPredicate){
        NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, aPredicate, nil]];
        req.predicate=predicate;
    }
    else{
        req.predicate = syncPredicate;
    }
    
    //Crear un fetched results
    res = [[NSFetchedResultsController alloc] initWithFetchRequest:req managedObjectContext:aContext sectionNameKeyPath:key cacheName:nil];
    
    return res;
}

+(NSFetchedResultsController *) fetchObjectWithId:(NSString *)aId inContext:(NSManagedObjectContext *)aContext
{
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"id = %@", aId];
    return [self fetchObjectFilterBy:pred inContext:aContext];
}

+(NSFetchedResultsController *) fetchObjectFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    NSFetchedResultsController *res = nil;
    
    //Crear un request
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:[self entityNameChildClass]];
    req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES]];
    
    //Predicado
    NSPredicate *syncPredicate = [NSPredicate predicateWithFormat:@"syncStatus != %@",[NSNumber numberWithInt:ObjectDeleted]];
    if(aPredicate){
        NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, aPredicate, nil]];
        req.predicate=predicate;
    }
    else{
        req.predicate = syncPredicate;
    }
    req.fetchLimit = 1;
    
    //Crear un fetched results
    res = [[NSFetchedResultsController alloc] initWithFetchRequest:req managedObjectContext:aContext sectionNameKeyPath:nil cacheName:nil];
    
    return res;
}

#pragma mark - Fetch Objects

+(NSArray *) allObjects {
    return [self allObjectsInContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) allObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending {
    return [self allObjectsOrderBy:orderField orderAscending:ascending inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) allObjectsOrderBy:(NSArray *)sortDescriptors {
    return [self allObjectsOrderBy:sortDescriptors inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) objectsFilterBy:(NSPredicate *)aPredicate {
    return [self objectsFilterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate {
    return [self objectsOrderBy:orderField orderAscending:ascending filterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate {
    return [self objectsOrderBy:sortDescriptors filterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key {
    return [self objectsOrderBy:orderField orderAscending:ascending filterBy:aPredicate sectionNameKeyPath:key inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key {
    return [self objectsOrderBy:sortDescriptors filterBy:aPredicate sectionNameKeyPath:key inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(instancetype) objectWithId:(NSString *)aId {
    return [self objectWithId:aId inContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(instancetype) objectFilterBy:(NSPredicate *)aPredicate {
    return [self objectFilterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}


#pragma mark - Fetch Objects with context

+(NSArray *) allObjectsInContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchAllObjectsInContext:aContext] fetchAll];
}

+(NSArray *) allObjectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchAllObjectsOrderBy:orderField orderAscending:ascending inContext:aContext] fetchAll];
}

+(NSArray *) allObjectsOrderBy:(NSArray *)sortDescriptors inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchAllObjectsOrderBy:sortDescriptors inContext:aContext] fetchAll];
}

+(NSArray *) objectsFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectsFilterBy:aPredicate inContext:aContext] fetchAll];
}

+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectsOrderBy:orderField orderAscending:ascending filterBy:aPredicate inContext:aContext] fetchAll];
}

+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectsOrderBy:sortDescriptors filterBy:aPredicate inContext:aContext] fetchAll];
}

+(NSArray *) objectsOrderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectsOrderBy:orderField orderAscending:ascending filterBy:aPredicate sectionNameKeyPath:key inContext:aContext] fetchAll];
}

+(NSArray *) objectsOrderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectsOrderBy:sortDescriptors filterBy:aPredicate sectionNameKeyPath:key inContext:aContext] fetchAll];
}

+(instancetype) objectWithId:(NSString *)aId inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectWithId:aId inContext:aContext] fetchFirst];
}

+(instancetype) objectFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    return [[self fetchObjectFilterBy:aPredicate inContext:aContext] fetchFirst];
}

#pragma mark - Count

+(NSInteger) countAllObjects
{
    return [self countAllObjectsInContext:[DMECoreDataStack sharedInstance].mainContext];
}

+(NSInteger) countObjectsFilterBy:(NSPredicate *)aPredicate
{
    return [self countObjectsFilterBy:aPredicate inContext:[DMECoreDataStack sharedInstance].mainContext];
}

#pragma mark - Count with context

+(NSInteger) countAllObjectsInContext:(NSManagedObjectContext *)aContext
{
    return [self countObjectsFilterBy:nil inContext:aContext];
}

+(NSInteger) countObjectsFilterBy:(NSPredicate *)aPredicate inContext:(NSManagedObjectContext *)aContext
{
    //Crear un request
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:[self entityNameChildClass]];
    
    //Predicado
    NSPredicate *syncPredicate = [NSPredicate predicateWithFormat:@"syncStatus != %@",[NSNumber numberWithInt:ObjectDeleted]];
    if(aPredicate){
        NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, aPredicate, nil]];
        req.predicate=predicate;
    }
    else{
        req.predicate = syncPredicate;
    }
    
    NSError *err;
    NSUInteger count = [aContext countForFetchRequest:req error:&err];
    if(count == NSNotFound) {
        NSLog(@"Se ha producido un error al contar los objetos");
        return 0;
    }
    else{
        return count;
    }
}

#pragma mark - Other

+(NSString *) entityNameChildClass
{
    NSString *entityName;
    
    if ([self respondsToSelector:@selector(entityName)])
    {
        entityName = [self performSelector:@selector(entityName)];
    }
    
    if ([entityName length] == 0) {
        entityName = NSStringFromClass(self);
    }
    
    return entityName;
}

-(instancetype) objectInMainContext{
    return [self objectInContext:[DMECoreDataStack sharedInstance].mainContext];
}

-(instancetype) objectInContext:(NSManagedObjectContext *)aContext{
    return [aContext objectWithID:self.objectID];
}

@end
