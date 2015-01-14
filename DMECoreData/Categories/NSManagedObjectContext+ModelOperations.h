//
//  NSManagedObjectContext+ModelOperations.h
//  Ramondin
//
//  Created by David Getapp on 5/12/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObjectContext (ModelOperations)

-(NSFetchedResultsController *) allObjectsFromEntity:(NSString *)aEntity;
-(NSFetchedResultsController *) allObjectsFromEntity:(NSString *)aEntity orderBy:(NSString *)orderField orderAscending:(BOOL)ascending;
-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity filterBy:(NSPredicate *)aPredicate;
-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate;
-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate;
-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSString *)orderField orderAscending:(BOOL)ascending filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key;
-(NSFetchedResultsController *) objectsFromEntity:(NSString *)aEntity orderBy:(NSArray *)sortDescriptors filterBy:(NSPredicate *)aPredicate sectionNameKeyPath:(NSString *)key;
-(NSFetchedResultsController *) objectFromEntity:(NSString *)aEntity widthId:(NSString *)aId;
-(NSFetchedResultsController *) objectFromEntity:(NSString *)aEntity filterBy:(NSPredicate *)aPredicate;

@end
