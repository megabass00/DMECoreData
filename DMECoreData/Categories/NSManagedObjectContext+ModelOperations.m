//
//  NSManagedObjectContext+ModelOperations.m
//  Ramondin
//
//  Created by David Getapp on 5/12/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import "DMECoreData.h"

@implementation NSManagedObjectContext (ModelOperations)

-(NSFetchedResultsController *) allObjectsFromEntity:(NSString *)aEntity
{
    return [self objectsFromEntity:aEntity orderBy:@"id" orderAscending:YES filterBy:nil];
}

-(NSFetchedResultsController *) allObjectsFromEntity:(NSString *)aEntity orderBy:(NSString *)orderField orderAscending:(BOOL)ascending
{
    return [self objectsFromEntity:aEntity orderBy:orderField orderAscending:ascending filterBy:nil];
}

-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity filterBy:(NSPredicate *)aPredicate
{
    return [self objectsFromEntity:aEntity orderBy:@"id" orderAscending:YES filterBy:aPredicate];
}

-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate
{
    return [self objectsFromEntity:aEntity orderBy:orderField orderAscending:ascending filterBy:aPredicate sectionNameKeyPath:nil];
}

-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate
{
    return [self objectsFromEntity:aEntity orderBy:sortDescriptors filterBy:aPredicate sectionNameKeyPath:nil];
}

-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key
{
    NSArray *order = nil;
    
    NSAttributeDescription *propertyDesc = [[NSEntityDescription entityForName:aEntity inManagedObjectContext:self].propertiesByName objectForKey:orderField];
    if([propertyDesc isKindOfClass:[NSAttributeDescription class]] && [[propertyDesc attributeValueClassName] isEqualToString: @"NSString"]){
        order = @[[NSSortDescriptor sortDescriptorWithKey:orderField ascending:ascending selector:@selector(caseInsensitiveCompare:)]];
    }
    else{
        order = @[[NSSortDescriptor sortDescriptorWithKey:orderField ascending:ascending]];
    }
    
    return [self objectsFromEntity:aEntity orderBy:order filterBy:aPredicate sectionNameKeyPath:key];
}

-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key
{
    __block NSFetchedResultsController *res = nil;
    
    [self performBlockAndWait:^{
        //Crear un request
        NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName: [NSClassFromString(aEntity) entityName]];
        req.sortDescriptors = sortDescriptors;
        
        //Predicado
        NSPredicate *syncPredicate = [NSPredicate predicateWithFormat:@"syncStatus != %@",[NSNumber numberWithInt:ObjectDeleted]];
        
        if(aPredicate){
            NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, aPredicate, nil]];
            req.predicate = predicate;
        }
        else{
            req.predicate = syncPredicate;
        }
        
        //Crear un fetched results
        res = [[NSFetchedResultsController alloc] initWithFetchRequest:req managedObjectContext:self sectionNameKeyPath:key cacheName:nil];
    }];
    return res;
}

-(NSFetchedResultsController *) objectFromEntity:(NSString *)aEntity widthId:(NSString *)aId
{
    //Predicado
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"self.id == %@",aId];
    
    //Crear un fetched results
    return [self objectFromEntity:aEntity filterBy:predicate];
}

-(NSFetchedResultsController *) objectFromEntity:(NSString *)aEntity filterBy:(NSPredicate *)aPredicate
{
    __block NSFetchedResultsController *res = nil;
    
    [self performBlockAndWait:^{
        //Crear un request
        NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName: [NSClassFromString(aEntity) entityName]];
        req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES]];
        
        //Predicado
        NSPredicate *syncPredicate = [NSPredicate predicateWithFormat:@"syncStatus != %@",[NSNumber numberWithInt:ObjectDeleted]];
        NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, aPredicate, nil]];
        req.predicate=predicate;
        
        //Crear un fetched results
        res = [[NSFetchedResultsController alloc] initWithFetchRequest:req managedObjectContext:self sectionNameKeyPath:nil cacheName:nil];
    }];
    return res;
}

@end
