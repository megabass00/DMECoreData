//
//  CoreDataStack.m
//
//  Created by Fernando Rodríguez Romero on 1/24/13.
//  Copyright (c) 2013 Agbo. All rights reserved.
//

#import "DMECoreData.h"

@interface DMECoreDataStack ()

//@property (strong, nonatomic, readonly) NSManagedObjectContext *privateContext;
@property (strong, nonatomic, readonly) NSManagedObjectModel *model;
@property (strong, nonatomic, readonly) NSPersistentStoreCoordinator *storeCoordinator;
@property (strong, nonatomic) NSURL *modelURL;
@property (strong, nonatomic) NSURL *dbURL;
@property (strong, nonatomic) NSMutableDictionary *threadsContexts;
@property (nonatomic) __block BOOL *saving;

@end

@implementation DMECoreDataStack

static DMECoreDataStack *sharedInstance = nil;

#pragma mark - Singleton

+(instancetype)sharedInstance
{
    if(sharedInstance){
        return sharedInstance;
    }
    else{
        NSLog(@"Debes inicializar el CoreDataStack antes de usarlo");
    }
}

#pragma mark - Init Methods

+(instancetype)coreDataStackWithModelName:(NSString *)aModelName databaseFilename:(NSString*) aDBName
{
    if(sharedInstance == nil){
        NSURL *url = nil;
        
        if (aDBName) {
            url = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:aDBName];
        }
        else{
            url = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:aModelName];
        }
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sharedInstance = [DMECoreDataStack coreDataStackWithModelName:aModelName databaseURL:url];
        });
        
        return sharedInstance;
    }
    else{
        NSLog(@"El CoreDataStack ya ha sido inicializado con anterioridad");
        
        return nil;
    }
}

+(instancetype)coreDataStackWithModelName:(NSString *)aModelName
{
    return [DMECoreDataStack coreDataStackWithModelName:aModelName databaseFilename:nil];
}

+(instancetype)coreDataStackWithModelName:(NSString *)aModelName databaseURL:(NSURL*) aDBURL
{
    if(sharedInstance == nil){
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sharedInstance = [[DMECoreDataStack alloc] initWithModelName:aModelName databaseURL:aDBURL];
            sharedInstance.saving = NO;
        });
        
        return sharedInstance;
    }
    else{
        NSLog(@"El CoreDataStack ya ha sido inicializado con anterioridad");
        
        return nil;
    }
}

#pragma mark -  Properties
// When using a readonly property with a custom getter, auto-synthesize
// is disabled.
// See http://www.cocoaosx.com/2012/12/04/auto-synthesize-property-reglas-excepciones/
// (in Spanish)
@synthesize model=_model;
@synthesize storeCoordinator=_storeCoordinator;
@synthesize mainContext=_mainContext;
//@synthesize privateContext=_privateContext;

/*-(NSManagedObjectContext *)privateContext{
    //Creamos un solo contexto para guardar en el disco
    if (_privateContext == nil){
        _privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _privateContext.persistentStoreCoordinator = self.storeCoordinator;
        [_privateContext setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
    }
    
    return _privateContext;
}*/


-(NSManagedObjectContext *)mainContext
{
    //Creamos un solo contexto para el hilo actual
    if (_mainContext == nil){
        _mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        //_mainContext.parentContext = [self privateContext];
        _mainContext.persistentStoreCoordinator = self.storeCoordinator;
        _mainContext.undoManager = nil;
        [_mainContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    }
    
    return _mainContext;
}

-(NSManagedObjectContext *)backgroundContext
{
    //Creamos de nuevo el contexto background
    NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    backgroundContext.parentContext = [self mainContext];
    backgroundContext.undoManager = nil;
    backgroundContext.retainsRegisteredObjects = NO;
    [backgroundContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    
    return backgroundContext;
}

-(NSPersistentStoreCoordinator *)storeCoordinator
{
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
                                    notificationWithName:[DMECoreDataStack persistentStoreCoordinatorErrorNotificationName]
                                    object:self
                                    userInfo:@{@"error" : err}];
            [[NSNotificationCenter defaultCenter] postNotification:note];
            NSLog(@"Error while adding a Store: %@", err);
            return nil;
            
        }
    }
    return _storeCoordinator;
}

-(NSManagedObjectModel *)model
{
    
    if (_model == nil) {
        _model = [[NSManagedObjectModel alloc] initWithContentsOfURL:self.modelURL];
    }
    return _model;
}


#pragma mark - Class Methods

+(NSString *) persistentStoreCoordinatorErrorNotificationName
{
    return @"persistentStoreCoordinatorErrorNotificationName";
}

// Returns the URL to the application's Documents directory.
+(NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

#pragma mark - Init

-(id)initWithModelName:(NSString *)aModelName databaseURL:(NSURL*) aDBURL
{
    if (self = [super init]) {
        self.modelURL = [[NSBundle mainBundle] URLForResource:aModelName
                                                withExtension:@"momd"];
        self.dbURL = aDBURL;
        self.threadsContexts = [NSMutableDictionary dictionary];
    }
    
    return self;
}

#pragma mark - Others

-(void)zapAllData
{
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
    _mainContext = nil;
    //_privateContext = nil;
    _storeCoordinator = nil;
    //[self privateContext];
    [self mainContext]; // this will rebuild the stack
}

-(void)saveWithCompletionBlock:(void(^)(BOOL didSave, NSError *error))completionBlock
{
    if(!self.saving){
        //Guardamos el contexto principal de la interfaz
        [self.mainContext performBlockAndWait:^{
            self.saving = YES;
            NSError *err = nil;
            BOOL success = NO;
            
            if (!_mainContext) {
                err = [NSError errorWithDomain:@"com.damarte.coredata" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Attempted to save a nil NSManagedObjectContext. This CoreDataStack has no context - probably there was an earlier error trying to access the CoreData database file."}];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(success, err);
                });
                
                self.saving = NO;
            }
            else if (self.mainContext.hasChanges) {
                success = [self.mainContext save:&err];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(success, err);
                });
                
                self.saving = NO;
                
                /*if (success && !err) {
                 //Guardamos el contexto que escribe en disco
                 [self.privateContext performBlockAndWait:^{
                 if (!_privateContext) {
                 err = [NSError errorWithDomain:@"com.damarte.coredata"
                 code:1
                 userInfo:@{NSLocalizedDescriptionKey: @"Attempted to save a nil NSManagedObjectContext. This CoreDataStack has no private context - probably there was an earlier error trying to access the CoreData database file."}];
                 completionBlock(success, err);
                 }
                 else if (self.privateContext.hasChanges) {
                 success = [self.privateContext save:&err];
                 completionBlock(success, err);
                 }
                 else{
                 completionBlock(NO, err);
                 }
                 }];
                 }
                 else{
                 completionBlock(NO, err);
                 }*/
            }
            else{
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionBlock(NO, nil);
                });
                
                self.saving = NO;
            }
        }];
    }
    else{
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(NO, nil);
        });
    }
}

@end
