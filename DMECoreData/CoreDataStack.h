//
//  CoreDataStack.h
//
//  Created by Fernando Rodríguez Romero on 1/24/13.
//  Copyright (c) 2013 Agbo. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NSManagedObjectContext;

@interface CoreDataStack : NSObject

@property (strong, nonatomic, readonly) NSManagedObjectContext *context;
@property (strong, nonatomic, readonly) NSManagedObjectContext *backgroundContext;

+(NSString *) persistentStoreCoordinatorErrorNotificationName;

+(CoreDataStack *) coreDataStackWithModelName:(NSString *)aModelName
                               databaseFilename:(NSString*) aDBName;

+(CoreDataStack *) coreDataStackWithModelName:(NSString *)aModelName;

+(CoreDataStack *) coreDataStackWithModelName:(NSString *)aModelName
                                    databaseURL:(NSURL*) aDBURL;

-(id) initWithModelName:(NSString *)aModelName
            databaseURL:(NSURL*) aDBURL;

-(void) zapAllData;

-(void)resetStack;

-(void) saveWithErrorBlock: (void(^)(NSError *error))errorBlock;

@end
