//
//  CoreDataStack.m
//
//  Created by Fernando Rodríguez Romero on 1/24/13.
//  Copyright (c) 2013 Agbo. All rights reserved.
//

#import "DMECoreData.h"

@interface CoreDataStack ()
@property (strong, nonatomic, readonly) NSManagedObjectContext *privateContext;
@property (strong, nonatomic, readonly) NSManagedObjectModel *model;
@property (strong, nonatomic, readonly) NSPersistentStoreCoordinator *storeCoordinator;
@property (strong, nonatomic) NSURL *modelURL;
@property (strong, nonatomic) NSURL *dbURL;
@property (strong, nonatomic) NSMutableDictionary *threadsContexts;

@end

@implementation CoreDataStack


#pragma mark -  Properties
// When using a readonly property with a custom getter, auto-synthesize
// is disabled.
// See http://www.cocoaosx.com/2012/12/04/auto-synthesize-property-reglas-excepciones/
// (in Spanish)
@synthesize model=_model;
@synthesize storeCoordinator=_storeCoordinator;
@synthesize context=_context;
@synthesize backgroundContext=_backgroundContext;
@synthesize privateContext=_privateContext;

-(NSManagedObjectContext *)privateContext{
    //Creamos un solo contexto para guardar en el disco
    if (_privateContext == nil){
        _privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _privateContext.persistentStoreCoordinator = self.storeCoordinator;
        _privateContext.undoManager = nil;
        _privateContext.retainsRegisteredObjects = NO;
        [_privateContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    }
    
    return _privateContext;
}


-(NSManagedObjectContext *)context{
    //Creamos un solo contexto para el hilo actual
    if (_context == nil){
        _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        _context.parentContext = [self privateContext];
        _context.undoManager = nil;
        _privateContext.retainsRegisteredObjects = NO;
        [_context setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    }
    
    return _context;
}

-(NSManagedObjectContext *)backgroundContext{
    //Creamos un solo contexto para el hilo en segundo plano
    if (_backgroundContext == nil){
        
        //Creamos de nuevo el contexto background
        _backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _backgroundContext.parentContext = [self context];
        _backgroundContext.undoManager = nil;
        _privateContext.retainsRegisteredObjects = NO;
        [_backgroundContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    }
    
    return _backgroundContext;
}

-(NSPersistentStoreCoordinator *) storeCoordinator{
    if (_storeCoordinator == nil) {
        _storeCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
        
        //NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES};
        
        NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption : @YES,
                                  NSInferMappingModelAutomaticallyOption : @YES,
                                  NSSQLitePragmasOption : @{ @"journal_mode" : @"WAL", @"synchronous": @"NORMAL" }};
        
        
        NSError *err = nil;
        if (![_storeCoordinator addPersistentStoreWithType:NSSQLiteStoreType
                                             configuration:nil
                                                       URL:self.dbURL
                                                   options:options
                                                     error:&err ]) {
            // Something went really wrong...
            // Send a notification and return nil
            NSNotification *note = [NSNotification
                                    notificationWithName:[CoreDataStack persistentStoreCoordinatorErrorNotificationName]
                                    object:self
                                    userInfo:@{@"error" : err}];
            [[NSNotificationCenter defaultCenter] postNotification:note];
            NSLog(@"Error while adding a Store: %@", err);
            return nil;
            
        }
    }
    return _storeCoordinator;
}

-(NSManagedObjectModel *) model{
    
    if (_model == nil) {
        _model = [[NSManagedObjectModel alloc] initWithContentsOfURL:self.modelURL];
    }
    return _model;
}


#pragma mark - Class Methods
+(NSString *) persistentStoreCoordinatorErrorNotificationName{
    return @"persistentStoreCoordinatorErrorNotificationName";
}

// Returns the URL to the application's Documents directory.
+ (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

+(CoreDataStack *) coreDataStackWithModelName:(NSString *)aModelName
                             databaseFilename:(NSString*) aDBName{
    
    NSURL *url = nil;
    
    if (aDBName) {
        url = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:aDBName];
    }else{
        url = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:aModelName];
    }
    
    return [self coreDataStackWithModelName:aModelName
                                databaseURL:url];
}

+(CoreDataStack *) coreDataStackWithModelName:(NSString *)aModelName{
    
    return [self coreDataStackWithModelName:aModelName
                           databaseFilename:nil];
}

+(CoreDataStack *) coreDataStackWithModelName:(NSString *)aModelName
                                  databaseURL:(NSURL*) aDBURL{
    return [[self alloc] initWithModelName: aModelName databaseURL:aDBURL];
    
}

#pragma mark - Init

-(id) initWithModelName:(NSString *)aModelName databaseURL:(NSURL*) aDBURL{
    
    if (self = [super init]) {
        self.modelURL = [[NSBundle mainBundle] URLForResource:aModelName
                                                withExtension:@"momd"];
        self.dbURL = aDBURL;
        self.threadsContexts = [NSMutableDictionary dictionary];
        [self context];
    }
    
    return self;
}



#pragma mark - Others

-(void) zapAllData{
    NSError *err = nil;
    for (NSPersistentStore *store in self.storeCoordinator.persistentStores) {
        
        if(![self.storeCoordinator removePersistentStore:store
                                                   error:&err]){
            NSLog(@"Error while removing store %@ from store coordinator %@", store, self.storeCoordinator);
        }
    }
    if (![[NSFileManager defaultManager] removeItemAtURL:self.dbURL
                                                   error:&err]) {
        NSLog(@"Error removing %@: %@", self.dbURL, err);
    }
    
    
    // The Core Data stack does not like you removing the file under it. If you want to delete the file
    // you should tear down the stack, delete the file and then reconstruct the stack.
    // Part of the problem is that the stack keeps a cache of the data that is in the file. When you
    // remove the file you don't have a way to clear that cache and you are then putting
    // Core Data into an unknown and unstable state.
    
    
    _backgroundContext = nil;
    _context = nil;
    _privateContext = nil;
    _storeCoordinator = nil;
    [self privateContext];
    [self context]; // this will rebuild the stack
    [self backgroundContext]; // this will rebuild the stack
    
}

-(void)resetStack {
    [_backgroundContext performBlockAndWait:^{
        [_backgroundContext reset];
    }];
    
    [_context performBlockAndWait:^{
        [_context reset];
    }];
    
    _backgroundContext = nil;
    _context = nil;
    _storeCoordinator = nil;
    _model = nil;
    
    [self model];
    [self storeCoordinator];
    [self context]; // this will rebuild the stack
    [self backgroundContext]; // this will rebuild the stack
}


-(void) saveWithErrorBlock: (void(^)(NSError *error))errorBlock{
    
    //Guardamos el contexto principal de la interfaz
    [self.context performBlockAndWait:^{
        NSError *err = nil;
        
        // If a context is nil, saving it should also be considered an
        // error, as being nil might be the result of a previous error
        // while creating the db.
        if (!_context) {
            err = [NSError errorWithDomain:@"CoreDataStack"
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey :
                                                 @"Attempted to save a nil NSManagedObjectContext. This CoreDataStack has no context - probably there was an earlier error trying to access the CoreData database file."}];
            errorBlock(err);
            
        }else if (self.context.hasChanges) {
            //DDLogInfo(@"---- Saving main context... ----");
            if (![self.context save:&err]) {
                errorBlock(err);
            }
            //DDLogInfo(@"---- Main context saved ----");
        }
    }];
    
    
    //Guardamos el contexto que escribe en disco
    [_privateContext performBlock:^{
        NSError *err = nil;
        
        if (!_privateContext) {
            err = [NSError errorWithDomain:@"CoreDataStack"
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey :
                                                 @"Attempted to save a nil NSManagedObjectContext. This CoreDataStack has no private context - probably there was an earlier error trying to access the CoreData database file."}];
            errorBlock(err);
            
        }else if (self.privateContext.hasChanges) {
            //DDLogInfo(@"---- Writing into disk... ----");
            if (![self.privateContext save:&err]) {
                errorBlock(err);
            }
            
            //DDLogInfo(@"---- Context saved into disk ----");
        }
    }];
    
}

@end
