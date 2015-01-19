//
//  CoreDataStack.h
//
//  Created by Fernando Rodríguez Romero on 1/24/13.
//  Copyright (c) 2013 Agbo. All rights reserved.
//

#import <Foundation/Foundation.h>

@class NSManagedObjectContext;

@interface DMECoreDataStack : NSObject

@property (strong, nonatomic, readonly) NSManagedObjectContext *mainContext;
@property (strong, nonatomic, readonly) NSManagedObjectContext *backgroundContext;

+(instancetype)sharedInstance;

+(NSString *) persistentStoreCoordinatorErrorNotificationName;

+(instancetype) coreDataStackWithModelName:(NSString *)aModelName databaseFilename:(NSString*) aDBName;

+(instancetype) coreDataStackWithModelName:(NSString *)aModelName;

+(instancetype) coreDataStackWithModelName:(NSString *)aModelName databaseURL:(NSURL*) aDBURL;

-(id) initWithModelName:(NSString *)aModelName databaseURL:(NSURL*) aDBURL;

-(void) zapAllData;

-(void) saveWithCompletionBlock:(void(^)(BOOL didSave, NSError *error))completionBlock;

@end