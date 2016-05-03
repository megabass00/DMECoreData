//
//  GETAPPSyncEngine.m
//  iWine
//
//  Created by David Getapp on 04/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "DMECoreData.h"
#import <AFNetworking.h>

NSString * const SyncEngineInitialCompleteKey = @"SyncEngineInitialSyncCompleted";
NSString * const SyncEngineSyncCompletedNotificationName = @"SyncEngineSyncCompleted";
NSString * const SyncEngineSyncErrorNotificationName = @"SyncEngineSyncError";
NSString * const SyncEngineErrorDomain = @"SyncEngineErrorDomain";

typedef void (^RecieveObjectsCompletionBlock)();
typedef void (^SendObjectsCompletionBlock)();
typedef void (^DownloadCompletionBlock)();

@interface DMESyncEngine(){
    NSPredicate *idPredicateTemplate;
    NSPredicate *syncStatusPredicateTemplate;
    NSPredicate *syncStatusNotPredicateTemplate;
    DownloadCompletionBlock downloadCompletionAuxBlock;
    NSMutableDictionary *savedEntities;
    NSTimer *autoSyncTimer;
}

@property (nonatomic, strong) NSManagedObjectContext *context;

@property (nonatomic, strong) __block NSMutableArray *registeredClassesToSync;
@property (nonatomic, strong) __block NSMutableArray *classesToSync;
@property (nonatomic, strong) __block NSMutableArray *registeredClassesWithFiles;
@property (nonatomic, strong) __block NSMutableArray *registeredClassesWithOptionalFiles;

@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSMutableDictionary *JSONRecords;
@property (nonatomic, strong) __block NSMutableArray *filesToDownload;
@property (nonatomic, strong) __block NSOperationQueue *downloadQueue;
@property (nonatomic) __block NSInteger downloadedFiles;
@property (nonatomic) __block CGFloat progressTotal;
@property (nonatomic) __block CGFloat progressCurrent;
@property (nonatomic) __block CGFloat progressSubprocessTotal;
@property (nonatomic) __block CGFloat progressSubprocessCurrent;

@property (nonatomic, copy) SyncStartBlock startBlock;
@property (nonatomic, copy) SyncCompletionBlock completionBlock;
@property (nonatomic, copy) ErrorBlock errorBlock;
@property (nonatomic, copy) ProgressBlock progressBlock;
@property (nonatomic, copy) MessageBlock messageBlock;

@property (nonatomic, copy) SyncStartBlock autoSyncStartBlock;
@property (nonatomic, copy) SyncCompletionBlock autoSyncCompletionBlock;
@property (nonatomic, copy) ErrorBlock autoSyncErrorBlock;
@property (nonatomic, copy) ProgressBlock autoSyncProgressBlock;
@property (nonatomic, copy) MessageBlock autoSyncMessageBlock;

@property (nonatomic, strong) NSDate *startDate;

@end

@implementation DMESyncEngine

+(instancetype)sharedEngine
{
    static DMESyncEngine *sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEngine = [[DMESyncEngine alloc] init];
        sharedEngine.downloadFiles = NO;
        sharedEngine.downloadOptionalFiles = NO;
        sharedEngine.autoSyncDelay = 180;
        sharedEngine.logLevel = SyncLogLevelVerbose;
        sharedEngine.syncBlocked = NO;
        sharedEngine.autoSyncActive = NO;
    });
    
    return sharedEngine;
}

#pragma mark - General

//Anade una clase al array para ser sincronizada
-(void)registerNSManagedObjectClassToSync:(Class)aClass
{
    if (!self.registeredClassesToSync) {
        self.registeredClassesToSync = [NSMutableArray array];
    }
    
    if ([aClass isSubclassOfClass:[NSManagedObject class]]) {
        if (![self.registeredClassesToSync containsObject:NSStringFromClass(aClass)]) {
            [self.registeredClassesToSync addObject:NSStringFromClass(aClass)];
        } else {
            [self logError:@"Unable to register %@ as it is already registered", NSStringFromClass(aClass)];
        }
    } else {
        [self logError:@"Unable to register %@ as it is not a subclass of NSManagedObject", NSStringFromClass(aClass)];
    }
}

//Anade una clase al array para ser sincronizada y descargar su multimedia
-(void)registerNSManagedObjectClassToSyncWithFiles:(Class)aClass
{
    
    if (!self.registeredClassesWithFiles) {
        self.registeredClassesWithFiles = [NSMutableArray array];
    }
    
    if ([aClass isSubclassOfClass:[NSManagedObject class]]) {
        if (![self.registeredClassesWithFiles containsObject:NSStringFromClass(aClass)]) {
            [self.registeredClassesWithFiles addObject:NSStringFromClass(aClass)];
        } else {
            [self logError:@"Unable to register %@ as it is already registered", NSStringFromClass(aClass)];
        }
    } else {
        [self logError:@"Unable to register %@ as it is not a subclass of NSManagedObject", NSStringFromClass(aClass)];
    }
    
    [self registerNSManagedObjectClassToSync:aClass];
}

//Anade una clase al array para ser sincronizada y descargar su multimedia opcional
-(void)registerNSManagedObjectClassToSyncWithOptionalFiles:(Class)aClass
{
    if (!self.registeredClassesWithOptionalFiles) {
        self.registeredClassesWithOptionalFiles = [NSMutableArray array];
    }
    
    if ([aClass isSubclassOfClass:[NSManagedObject class]]) {
        if (![self.registeredClassesWithOptionalFiles containsObject:NSStringFromClass(aClass)]) {
            [self.registeredClassesWithOptionalFiles addObject:NSStringFromClass(aClass)];
        } else {
            [self logError:@"Unable to register %@ as it is already registered", NSStringFromClass(aClass)];
        }
    } else {
        [self logError:@"Unable to register %@ as it is not a subclass of NSManagedObject", NSStringFromClass(aClass)];
    }
    
    [self registerNSManagedObjectClassToSync:aClass];
}

//Indica si ya se ha sincronizado la primera vez
-(BOOL)initialSyncComplete
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:SyncEngineInitialCompleteKey];
}

-(void)cancelAutoSync
{
    if(self.autoSyncActive){
        if(autoSyncTimer){
            [autoSyncTimer invalidate];
            autoSyncTimer = nil;
        }
        
        self.autoSyncActive = NO;
    }
}

-(void)blockSync
{
    if(!_syncBlocked){
        if(autoSyncTimer){
            [autoSyncTimer invalidate];
            autoSyncTimer = nil;
        }
        self.syncBlocked = YES;
        
        [self willChangeValueForKey:@"syncBlocked"];
        _syncBlocked = YES;
        [self didChangeValueForKey:@"syncBlocked"];
    }
}

-(void)unblockSync
{
    if(_syncBlocked){
        if(self.autoSyncActive){
            autoSyncTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoSyncDelay target:self selector:@selector(autoSyncRepeat:) userInfo:nil repeats:YES];
        }
        
        [self willChangeValueForKey:@"syncBlocked"];
        _syncBlocked = NO;
        [self didChangeValueForKey:@"syncBlocked"];
    }
}

//Guarda la primera sincronizacion
-(void)setInitialSyncCompleted {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SyncEngineInitialCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(void)setInitialSyncIncompleted {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SyncEngineInitialCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(NSError *)createErrorWithCode:(SyncErrorCode)aCode andDescription:(NSString *)aDescription andFailureReason:(NSString *)aReason andRecoverySuggestion:(NSString *)aSuggestion
{
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: aDescription,
                               NSLocalizedFailureReasonErrorKey: aReason,
                               NSLocalizedRecoverySuggestionErrorKey: aSuggestion};
    return [NSError errorWithDomain:SyncEngineErrorDomain code:aCode userInfo:userInfo];
}

-(void)checkStartConditionsNeedInstall:(BOOL)needInstall completionBlock:(void (^)())completionBlock
{
    if(self.initialSyncComplete || !needInstall){
        if(!_syncInProgress && !_syncBlocked) {
            if([AFNetworkReachabilityManager sharedManager].reachable){
                if(completionBlock){
                    self.context = [DMECoreDataStack sharedInstance].backgroundContext;
                    
                    [self.context performBlock:^{
                        completionBlock();
                    }];
                }
            }
        }
    }
}

#pragma mark - Start Sync

//Comienza la sincronizacion

-(void)startSync:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
    @autoreleasepool {
        [self checkStartConditionsNeedInstall:NO completionBlock:^{
            
            //Inicializamos la sincronizacion
            self.startBlock = startBlock;
            self.completionBlock = completionBlock;
            self.progressBlock = progressBlock;
            self.messageBlock = messageBlock;
            self.errorBlock = errorBlock;
            
            [self executeSyncStartOperations:^{
                NSInteger steps = 0;
                if(self.initialSyncComplete){
                    steps = 4 + 3;
                }
                else{
                    steps = 2;
                }
                
                if(self.downloadFiles){
                    steps += 1;
                }
                
                [self progressBlockTotal:steps inMainProcess:YES];
                
                //Si ya se ha instalado
                if(self.initialSyncComplete){
                    //Recibimos los datos
                    [self downloadSyncEntitiesForSync:^{
                        //Enviamos los datos
                        [self postLocalObjectsToServer:^{
                            //Descargamos los ficheros
                            [self downloadFiles:^{
                                [self executeSyncCompletedOperations];
                            }];
                        }];
                    }];
                }
                else{
                    //Si es la instalacion
                    self.classesToSync = self.registeredClassesToSync;
                    [[NSThread currentThread] setName:@"Install"];
                    [self downloadJSONForRegisteredObjects:^{
                        [self executeSyncCompletedOperations];
                    }];
                }
            }];
        }];
    }
}

//Repite la sincronizacion periodicamente
-(void)autoSync:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
    if(!autoSyncTimer && !self.autoSyncActive && self.autoSyncDelay > 0){
        self.autoSyncCompletionBlock = completionBlock;
        self.autoSyncStartBlock = startBlock;
        self.autoSyncMessageBlock = messageBlock;
        self.autoSyncProgressBlock = progressBlock;
        self.autoSyncErrorBlock = errorBlock;
        self.autoSyncActive = YES;
        
        [self startSync:self.autoSyncStartBlock withCompletionBlock:self.autoSyncCompletionBlock withProgressBlock:self.autoSyncProgressBlock withMessageBlock:self.autoSyncMessageBlock withErrorBlock:self.autoSyncErrorBlock];
    }
}

-(void)autoSyncRepeat:(NSTimer *)timer
{
    [self startSync:self.autoSyncStartBlock withCompletionBlock:self.autoSyncCompletionBlock withProgressBlock:self.autoSyncProgressBlock withMessageBlock:self.autoSyncMessageBlock withErrorBlock:self.autoSyncErrorBlock];
}

//Enviar datos
- (void)pushDataToServer:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
    @autoreleasepool {
        [self checkStartConditionsNeedInstall:YES completionBlock:^{
            
            //Inicializamos la sincronizacion
            self.startBlock = startBlock;
            self.completionBlock = completionBlock;
            self.progressBlock = progressBlock;
            self.messageBlock = messageBlock;
            self.errorBlock = errorBlock;
            
            [self executeSyncStartOperations:^{
                [self progressBlockTotal:3 inMainProcess:YES];
                
                ///Enviamos los datos
                [self postLocalObjectsToServer:^{
                    [self executeSyncCompletedOperations];
                }];
            }];
        }];
    }
}

//Recibir datos
- (void)fetchDataFromServer:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
    @autoreleasepool {
        [self checkStartConditionsNeedInstall:YES completionBlock:^{
            
            //Inicializamos la sincronizacion
            self.startBlock = startBlock;
            self.completionBlock = completionBlock;
            self.progressBlock = progressBlock;
            self.messageBlock = messageBlock;
            self.errorBlock = errorBlock;
            
            [self executeSyncStartOperations:^{
                [self progressBlockTotal:4 inMainProcess:YES];
                
                ///Enviamos los datos
                [self downloadSyncEntitiesForSync:^{
                    [self executeSyncCompletedOperations];
                }];
            }];
        }];
    }
}

//Download files
- (void)downloadFiles:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
    @autoreleasepool {
        [self checkStartConditionsNeedInstall:YES completionBlock:^{
            
            //Inicializamos la sincronizacion
            self.startBlock = startBlock;
            self.completionBlock = completionBlock;
            self.progressBlock = progressBlock;
            self.messageBlock = messageBlock;
            self.errorBlock = errorBlock;
            
            [self executeSyncStartOperations:^{
                [self progressBlockTotal:1 inMainProcess:YES];
                
                ///Enviamos los datos
                [self downloadFiles:^{
                    [self executeSyncCompletedOperations];
                }];
            }];
        }];
    }
}


#pragma mark - Start/End Sync Operations

//Comienzo de la sincronizacion
-(void)executeSyncStartOperations:(void (^)())completionBlock
{
    @autoreleasepool {
        if(self.initialSyncComplete){
            [[NSThread currentThread] setName:@"Sync"];
            
            [self messageBlock:NSLocalizedString(@"Comenzando el proceso...", nil) important:YES];
        }
        else{
            [[NSThread currentThread] setName:@"Install"];
            
            [self messageBlock:NSLocalizedString(@"Comenzando la instalación...", nil) important:YES];
        }
        
        self.filesToDownload = [NSMutableArray array];
        self.JSONRecords = [NSMutableDictionary dictionary];
        self.downloadedFiles = 0;
        self.progressCurrent = 0;
        self.progressTotal = 0;
        self.progressSubprocessCurrent = 0;
        self.progressSubprocessTotal = 0;
        self.startDate = [NSDate date];
        
        if(autoSyncTimer && self.autoSyncActive){
            [autoSyncTimer invalidate];
            autoSyncTimer = nil;
        }
        
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = YES;
        [self didChangeValueForKey:@"syncInProgress"];

        [self saveContext:^(BOOL result) {
            if(result){
                if(self.startBlock){
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self.startBlock();
                    });
                }
                
                [self.context performBlock:^{
                    completionBlock();
                }];
            }
        }];
    }
}

//Final de la sincronizacion
-(void)executeSyncCompletedOperations
{
    @autoreleasepool {
        [self cleanEngine];
        
        [self messageBlock:NSLocalizedString(@"Proceso terminado", nil) important:YES];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setInitialSyncCompleted];
            [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineSyncCompletedNotificationName object:nil];
            [self willChangeValueForKey:@"syncInProgress"];
            _syncInProgress = NO;
            [self didChangeValueForKey:@"syncInProgress"];
            
            if(self.autoSyncActive){
                autoSyncTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoSyncDelay target:self selector:@selector(autoSyncRepeat:) userInfo:nil repeats:YES];
            }
            
            //Llamamos al bloque de completar
            if(self.completionBlock){
                self.completionBlock();
            }
        });
    }
}

//Error en la sincronizacion
-(void)executeSyncErrorOperations
{
    @autoreleasepool {
        [self cleanEngine];
        
        [self messageBlock:NSLocalizedString(@"Terminando proceso tras un error...", nil) important:YES];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineSyncErrorNotificationName object:nil];
            
            [self willChangeValueForKey:@"syncInProgress"];
            _syncInProgress = NO;
            [self didChangeValueForKey:@"syncInProgress"];
            
            if(self.autoSyncActive){
                autoSyncTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoSyncDelay target:self selector:@selector(autoSyncRepeat:) userInfo:nil repeats:YES];
            }
        });
    }
}

#pragma mark - Core Data

//Crea un objeto Core Data a partir de un registro JSON
-(NSManagedObject *)newManagedObjectWithClassName:(NSString *)className forRecord:(NSDictionary *)record
{
    @autoreleasepool {
        //Creamos el nuevo objeto
        NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:className inManagedObjectContext:self.context];
        [newManagedObject setValue:[[record objectForKey:className] objectForKey:@"id"] forKey:@"id"];  //Nos aseguramos de que tenga id
        
        //Recorremos las relaciones
        for (NSString* key in record) {
            @autoreleasepool {
                //Si es el objeto principal lo creamos
                if([className isEqualToString:key]){
                    for(id key in [record objectForKey:className]){
                        @autoreleasepool {
                            [self setValue:[[record objectForKey:className] objectForKey:key] forKey:key forManagedObject:[newManagedObject objectInContext:self.context]];
                        }
                    }
                    [newManagedObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                }
                else if([[record objectForKey:key] isKindOfClass:[NSDictionary class]]){ //Si es otro objeto comprobamos si existe y si no lo creamos
                    //Creamos la relacion con el objeto principal
                    [self updateRelation:className ofManagedObject:newManagedObject withClassName:key withRecord:[record objectForKey:key]];
                }
                else if([[record objectForKey:key] isKindOfClass:[NSArray class]]){
                    for(NSDictionary *relationObject in [record objectForKey:key]){
                        @autoreleasepool {
                            //Creamos la relacion con el objeto principal
                            [self updateRelation:className ofManagedObject:newManagedObject withClassName:key withRecord:relationObject];
                        }
                    }
                }
            }
        }
        
        if(!self.initialSyncComplete){
            if(![savedEntities objectForKey:className]){
                [savedEntities setObject:[NSMutableDictionary dictionary] forKey:className];
            }
            
            [[savedEntities objectForKey:className] setObject:newManagedObject forKey:[[record objectForKey:className] objectForKey:@"id"]];
        }
        
        [self logDebug:@"   Saved %@ with id: %@", className, [[record objectForKey:className] objectForKey:@"id"]];
        
        return newManagedObject;
    }
}

//Actualiza un objeto Core Data a partir de un registro JSON
-(NSManagedObject *)updateManagedObject:(NSManagedObject *)managedObject withClassName:(NSString *)className withRecord:(NSDictionary *)record
{
    @autoreleasepool {
        //Recorremos las relaciones
        for (NSString* key in record) {
            @autoreleasepool {
                //Si es el objeto principal lo actualizamos
                if([className isEqualToString:key]){
                    for(id key in [record objectForKey:className]){
                        @autoreleasepool {
                            [self setValue:[[record objectForKey:className] objectForKey:key] forKey:key forManagedObject:[managedObject objectInContext:self.context]];
                        }
                    }
                    [managedObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                }
                else if([[record objectForKey:key] isKindOfClass:[NSDictionary class]]){ //Si es otro objeto comprobamos actualizamos la relacion
                    //Creamos la relacion con el objeto principal
                    [self updateRelation:className ofManagedObject:[managedObject objectInContext:self.context] withClassName:key withRecord:[record objectForKey:key]];
                }
                else if([[record objectForKey:key] isKindOfClass:[NSArray class]]){ //Relación con varios objetos
                    //Vaciamos la relacion multiple
                    [self truncateRelation:className ofManagedObject:[managedObject objectInContext:self.context] withClassName:key];
                    
                    if([[record objectForKey:key] count] > 0){
                        //Volvemos a crearla
                        for(NSDictionary *relationObject in [record objectForKey:key]){
                            @autoreleasepool {
                                //Creamos la relacion con el objeto principal
                                [self updateRelation:className ofManagedObject:[managedObject objectInContext:self.context] withClassName:key withRecord:relationObject];
                            }
                        }
                    }
                }
            }
        }
        [self logDebug:@"   Updated %@ with id: %@", className, [[record objectForKey:className] objectForKey:@"id"]];
        
        return managedObject;
    }
}

//Vacia una relacion
-(void)truncateRelation:(NSString *)relation ofManagedObject:(NSManagedObject *)managedObject withClassName:(NSString *)className
{
    @autoreleasepool {
        //Obtenemos el nombre de la relacion
        NSDictionary *values = [self nameFromClassName:className relation:relation];
        NSString *relationName = [values objectForKey:@"relationName"];
        NSString *newClassName = [values objectForKey:@"className"];
        
        if([relation isEqualToString:newClassName]){
            [managedObject setValue:nil forKey:relationName];
        }
        else{
            //Comprobamos si la relacion es a uno o a varios
            NSEntityDescription *entityDescription = [[managedObject objectInContext:self.context] entity];
            NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
            
            NSString *inverseRelationName;
            for(NSRelationshipDescription *relationship in [relationsDictionary allValues]) {
                if([[[relationship inverseRelationship] name] isEqualToString:relationName] && [[[relationship destinationEntity] name] isEqualToString:newClassName]){
                    inverseRelationName = [relationship name];
                    break;
                }
            }
            
            //Comprobamos que exista la relación
            NSRelationshipDescription *relationDescription = [relationsDictionary objectForKey:inverseRelationName];
            if(relationDescription && [[managedObject objectInContext:self.context] valueForKey:inverseRelationName]){
                
                //Si son traducciones las eliminamos
                if(relationDescription.isToMany && [inverseRelationName containsString:@"Translation"]){
                    //Eliminamos los objetos de la relación
                    for (NSManagedObject *relationObject in [[managedObject objectInContext:self.context] valueForKey:inverseRelationName]) {
                        @autoreleasepool {
                            [self.context deleteObject:relationObject];
                        }
                    }
                }
                
                //Eliminamos la relacion
                [managedObject setValue:nil forKey:inverseRelationName];
            }
            
            relationsDictionary = nil;
            entityDescription = nil;
            relationDescription = nil;
            inverseRelationName = nil;
        }
        
        values = nil;
        relationName = nil;
        newClassName = nil;
        
    }
}

//Actualiza las relaciones de un objeto Core Data a partir del JSON
-(NSManagedObject *)updateRelation:(NSString *)relation ofManagedObject:(NSManagedObject *)managedObject withClassName:(NSString *)className withRecord:(NSDictionary *)record
{
    @autoreleasepool {
        NSManagedObject *newRelationManagedObject = nil;
        
        //Obtenemos el nombre de la relacion
        NSDictionary *values = [self nameFromClassName:className relation:relation];
        NSString *relationName = [values objectForKey:@"relationName"];
        NSString *newClassName = [values objectForKey:@"className"];
        
        if(![[record objectForKey:@"id"] isKindOfClass:[NSNull class]]){
            if(self.initialSyncComplete){
                newRelationManagedObject = [[self managedObjectForClass:newClassName withId:[record objectForKey:@"id"]] objectInContext:self.context];
            }
            else{
                newRelationManagedObject = [[[savedEntities objectForKey:newClassName] objectForKey:[record objectForKey:@"id"]] objectInContext:self.context];
            }
            
            if(!newRelationManagedObject){
                newRelationManagedObject = [[self newManagedObjectWithClassName:newClassName forRecord:[NSDictionary dictionaryWithObject:record forKey:newClassName]] objectInContext:self.context];
            }
            
            //Comprobamos si la relacion es a uno o a varios
            NSEntityDescription *entityDescription = [newRelationManagedObject entity];
            NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
            
            //Comprobamos si la relacion es a uno o a varios
            if([relationsDictionary objectForKey:relationName]){
                if([[relationsDictionary objectForKey:relationName] isToMany]){
                    //Comprobamos si la inversa es tambien a varios
                    if([[[relationsDictionary objectForKey:relationName] inverseRelationship] isToMany]){
                        /*SEL selector = NSSelectorFromString([NSString stringWithFormat:@"add%@Object:", newClassName]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [[managedObject objectInContext:self.context] performSelector:selector withObject:newRelationManagedObject];
#pragma clang diagnostic pop*/
                        SEL selector = NSSelectorFromString([NSString stringWithFormat:@"add%@Object:", [className stringByReplacingOccurrencesOfString:@"_" withString:@""]]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [[managedObject objectInContext:self.context] performSelector:selector withObject:[newRelationManagedObject objectInContext:self.context]];
#pragma clang diagnostic pop
                    }
                    else{
                        //Obtenemos la relacion inversa
                        relationName = [[[relationsDictionary objectForKey:relationName] inverseRelationship] name];
                        
                        [[managedObject objectInContext:self.context] setValue:newRelationManagedObject forKey:relationName];
                    }
                }
                else{
                    [newRelationManagedObject setValue:[managedObject objectInContext:self.context] forKey:relationName];
                }
                [self logDebug:@"   Updated relation %@ with id: %@", relationName, [record objectForKey:@"id"]];
            }
            
            entityDescription = nil;
            relationsDictionary = nil;
        }
        else{
            //Comprobamos si la relacion es a uno o a varios
            NSEntityDescription *entityDescription = [managedObject entity];
            NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
            
            NSString *inverseRelationName;
            for(NSRelationshipDescription *relationship in [relationsDictionary allValues]) {
                if([[[relationship inverseRelationship] name] isEqualToString:relationName] && [[[relationship destinationEntity] name] isEqualToString:newClassName]){
                    inverseRelationName = [relationship name];
                    break;
                }
            }
            
            //Comprobamos si la relacion es a uno o a varios
            if([relationsDictionary objectForKey:inverseRelationName]){
                if(![[relationsDictionary objectForKey:inverseRelationName] isToMany]){
                    if([[managedObject objectInContext:self.context] valueForKey:inverseRelationName]){
                        [[managedObject objectInContext:self.context] setValue:nil forKey:inverseRelationName];
                    }
                }
            }
            
            entityDescription = nil;
            relationsDictionary = nil;
            inverseRelationName = nil;
        }
        
        values = nil;
        relationName = nil;
        newClassName = nil;
        
        return newRelationManagedObject;
    }
}

-(NSDictionary *)nameFromClassName:(NSString *)className relation:(NSString *)relation
{
    //Obtenemos el nombre de la relacion
    @autoreleasepool {
        NSString *relationName;
        NSString *classNameFinal;
        NSArray *classNameParts = [className componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_"]];
        if([classNameParts count]>1){
            classNameFinal = [classNameParts objectAtIndex:0];
            relationName = [[[[[classNameParts objectAtIndex:0] substringToIndex:1] lowercaseString] stringByAppendingString:[[classNameParts objectAtIndex:0] substringFromIndex:1]] stringByAppendingString:[classNameParts objectAtIndex:1]];
        }
        else{
            classNameFinal = className;
            relationName = [[[relation substringToIndex:1] lowercaseString] stringByAppendingString:[relation substringFromIndex:1]];
        }
        
        classNameParts = nil;
        
        return @{@"relationName": relationName, @"className": classNameFinal};
    }
}

//Introduce un valor en una propiedad de un objeto Core Data
-(void)setValue:(id)value forKey:(NSString *)key forManagedObject:(NSManagedObject *)managedObject
{
    @autoreleasepool {
        //Si es nulo lo convertimos en nil
        if([value isKindOfClass:[NSNull class]]){
            value = nil;
        }
        
        id currentValue = [managedObject performSelector:NSSelectorFromString(key)];
        
        //Según el tipo asignamos el valor
        if ([[[managedObject.entity.propertiesByName objectForKey:key] attributeValueClassName] isEqualToString:@"NSDate"]) {    //Si es una fecha
            @autoreleasepool {
                if([value length] == 10){
                    value = [value stringByAppendingString:@" 00:00:00"];
                }
                
                NSDate *dateValue = [self dateUsingStringFromAPI:value];
                if(![currentValue isEqualToDate:dateValue]){
                    [managedObject setValue:[dateValue copy] forKey:key];
                }
                dateValue = nil;
            }
        } else if ([[[managedObject.entity.propertiesByName objectForKey:key] attributeValueClassName] isEqualToString:@"NSNumber"]) {    //Si es un numero
            if([[[value class] description] isEqualToString:@"__NSCFBoolean"]){
                if(currentValue != value){
                    [managedObject setValue:value forKey:key];
                }
            }
            else{
                if(currentValue == nil || ([currentValue doubleValue] != [value doubleValue])){
                    [managedObject setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:key];
                }
            }
        } else {    //Si es una cadena
            if(currentValue == nil || ![currentValue isEqualToString:value]){
                [managedObject setValue:[value copy] forKey:key];
            }
        }
        
        currentValue = nil;
    }
}

-(NSPredicate *)idPredicateTemplate
{
    if (idPredicateTemplate == nil) {
        idPredicateTemplate = [NSPredicate predicateWithFormat:@"id = $ID"];
    }
    return idPredicateTemplate;
}

-(NSPredicate *)syncStatusPredicateTemplate
{
    if (syncStatusPredicateTemplate == nil) {
        syncStatusPredicateTemplate = [NSPredicate predicateWithFormat:@"syncStatus = $SYNC_STATUS"];
    }
    return syncStatusPredicateTemplate;
}

-(NSPredicate *)syncStatusNotPredicateTemplate
{
    if (syncStatusNotPredicateTemplate == nil) {
        syncStatusNotPredicateTemplate = [NSPredicate predicateWithFormat:@"syncStatus != $SYNC_STATUS"];
    }
    return syncStatusNotPredicateTemplate;
}

//Obtiene todos los objetos Core Data que tengan un estado de sincronizacion determinado
-(NSArray *)managedObjectsForClass:(NSString *)className withSyncStatus:(ObjectSyncStatus)syncStatus
{
    @autoreleasepool {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES selector:@selector(localizedStandardCompare:)]]];
        [fetchRequest setPredicate:[[self syncStatusPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:syncStatus]}]];
        
        __block NSArray *results = @[];
        [self.context performBlockAndWait:^{
            NSError *error = nil;
            results = [self.context executeFetchRequest:fetchRequest error:&error];
        }];
        
        fetchRequest = nil;
        
        return results;
    }
}

//Obtiene todos los objetos Core Data que NO tengan un estado de sincronizacion determinado
-(NSArray *)managedObjectsForClass:(NSString *)className withPredicate:(NSPredicate *)predicate
{
    @autoreleasepool {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES selector:@selector(localizedStandardCompare:)]]];
        if(predicate != nil){
            [fetchRequest setPredicate:predicate];
        }
        
        __block NSArray *objects = @[];
        [self.context performBlockAndWait:^{
            NSError *error = nil;
            objects = [self.context executeFetchRequest:fetchRequest error:&error];
        }];
        
        fetchRequest = nil;
        
        return objects;
    }
}

-(NSArray *)managedObjectsForClass:(NSString *)className
{
    return [self managedObjectsForClass:className withPredicate:nil];
}

//Comprueba si existe un objeto
-(BOOL)existsManagedObjectForClass:(NSString *)className withId:(NSString *)aId
{
    @autoreleasepool {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
        [fetchRequest setFetchLimit:1];
        [fetchRequest setPredicate:[[self idPredicateTemplate] predicateWithSubstitutionVariables:@{@"ID": aId}]];
        
        __block NSUInteger count = nil;
        [self.context performBlockAndWait:^{
            NSError *error = nil;
            count = [self.context countForFetchRequest:fetchRequest error:&error];
        }];
        
        fetchRequest = nil;
        
        return count > 0;
    }
}

//Obtiene el objeto Core Data con un id
-(NSManagedObject *)managedObjectForClass:(NSString *)className withId:(NSString *)aId
{
    @autoreleasepool {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
        [fetchRequest setFetchLimit:1];
        [fetchRequest setPredicate:[[self idPredicateTemplate] predicateWithSubstitutionVariables:@{@"ID": aId}]];
        
        __block NSManagedObject *object = nil;
        [self.context performBlockAndWait:^{
            NSError *error = nil;
            object = [[self.context executeFetchRequest:fetchRequest error:&error] lastObject];
        }];
        
        fetchRequest = nil;
        
        return object;
    }
}

//Obtiene los objetos Core Data de un tipo que esten en el array de ids
-(NSArray *)managedObjectsForClass:(NSString *)className sortedByKey:(NSString *)key usingArrayOfIds:(NSArray *)idArray inArrayOfIds:(BOOL)inIds
{
    @autoreleasepool {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
        NSPredicate *predicate;
        //TODO Optimizar a fuego
        if (inIds) {
            predicate = [NSPredicate predicateWithFormat:@"id IN %@", [NSSet setWithArray:idArray]];
        } else {
            predicate = [NSPredicate predicateWithFormat:@"NOT (id IN %@)", [NSSet setWithArray:idArray]];
        }
        NSPredicate *createdPredicate = [[self syncStatusNotPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:ObjectCreated]}];
        NSPredicate *syncPredicate = [[self syncStatusNotPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:ObjectNotSync]}];
        NSPredicate *andPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, createdPredicate, predicate, nil]];
        
        [fetchRequest setPredicate:andPredicate];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES selector:@selector(localizedStandardCompare:)]]];
        
        __block NSArray *results = @[];
        [self.context performBlockAndWait:^{
            NSError *error = nil;
            results = [self.context executeFetchRequest:fetchRequest error:&error];
        }];
        
        predicate = nil;
        syncPredicate = nil;
        andPredicate = nil;
        fetchRequest = nil;
        
        return results;
    }
}

-(NSDate *)lastModifiedDateForClass:(NSString *)className
{
    @autoreleasepool {
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
        [fetchRequest setFetchLimit:1];
        [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"modified != nil"]];
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"modified" ascending:NO]]];
        
        __block NSManagedObject *object = nil;
        [self.context performBlockAndWait:^{
            NSError *error = nil;
            object = [[self.context executeFetchRequest:fetchRequest error:&error] lastObject];
        }];
        
        fetchRequest = nil;
        
        return (NSDate *)[object valueForKey:@"modified"];
    }
}

-(void)saveContext:(void (^)(BOOL result))success
{
    [self.context performBlockAndWait:^{
        @autoreleasepool {
            BOOL result = YES;
            
            if(self.context.hasChanges){
                // Execute the sync completion operations as this is now the final step of the sync process
                NSError *error = nil;
                
                result = [self.context save:&error];
                
                if (!result){
                    NSLog(@"Unresolved error %@", error);
                    //NSLog(@"Unresolved error %@", [error userInfo]);
                    //NSLog(@"Unresolved error %@", [error localizedDescription]);
                    
                    NSError *errorFinal = [self createErrorWithCode:SyncErrorCodeSaveContext
                                                     andDescription:NSLocalizedString(@"No se han podido guardar los datos, pongase en contacto con el administrador", nil)
                                                   andFailureReason:[error description]
                                              andRecoverySuggestion:NSLocalizedString(@"Compruebe la integridad de los datos", nil)];
                    
                    [self errorBlock:errorFinal fatal:YES];
                    [self executeSyncErrorOperations];
                    errorFinal = nil;
                    
                    return;
                }
            }
            
            if(result){
                [[DMECoreDataStack sharedInstance] saveWithCompletionBlock:^(BOOL didSave, NSError *error) {
                    if(!error){
                        success(YES);
                    }
                    else{
                        [self logError:@"Error when save main context: %@", error];
                        
                        [self errorBlock:error fatal:YES];
                        [self executeSyncErrorOperations];
                        error = nil;
                        
                        return;
                    }
                }];
            }
        }
    }];
}

#pragma mark - JSON Data Management

//Devuelve los valores descargados para una clase
-(NSArray *)JSONArrayForClassWithName:(NSString *)className
{
    return (NSArray *)[self.JSONRecords objectForKey:className];
}

//Devuelve los valores descargados para una clase modificados a partir de una fecha o que no esten en la base de datos
-(NSArray *)JSONArrayForClassWithName:(NSString *)className modifiedAfter:(NSDate *)aDate
{
    @autoreleasepool {
        NSArray *returnValue;
        
        if(aDate){
            NSSet *actualIds = [NSSet setWithArray:[[self managedObjectsForClass:className] valueForKey:@"id"]];
            
            NSMutableArray *filtered = [NSMutableArray array];
            
            NSArray *JSONRecords = [self.JSONRecords objectForKey:className];
            [JSONRecords enumerateObjectsWithOptions:nil usingBlock:
             ^(id obj, NSUInteger idx, BOOL* stop){
                 if(([[self dateUsingStringFromAPI:obj[className][@"modified"]] compare:aDate] == NSOrderedDescending) || ![actualIds member:obj[className][@"id"]]) {
                     [filtered addObject:obj];
                 }
             }];
            
            JSONRecords = nil;
            actualIds = nil;
            returnValue = [NSArray arrayWithArray:filtered];
            [filtered removeAllObjects];
            filtered = nil;
        }
        else{
            returnValue = (NSArray *)[self.JSONRecords objectForKey:className];
        }
        
        return returnValue;
    }
}

//Devuelve los valores descargados para una clase ordenados por un campo
-(NSArray *)JSONDataRecordsForClass:(NSString *)className sortedByKey:(NSString *)key
{
    return [self JSONDataRecordsForClass:className sortedByKey:key modifiedAfter:nil];
}

//Devuelve los valores descargados para una clase ordenados por un campo y modificados a partir de una fecha
-(NSArray *)JSONDataRecordsForClass:(NSString *)className sortedByKey:(NSString *)key modifiedAfter:(NSDate *)aDate
{
    NSArray *JSONArray = [self JSONArrayForClassWithName:className modifiedAfter:aDate];
    NSArray *result = [JSONArray sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        @autoreleasepool {
            if([[[(NSDictionary*)a objectForKey:className] objectForKey:key] isKindOfClass:[NSString class]]){
                @autoreleasepool {
                    NSString *first = [[(NSDictionary*)a objectForKey:className] objectForKey:key];
                    NSString *second = [[(NSDictionary*)b objectForKey:className] objectForKey:key];
                    
                    return [first localizedStandardCompare:second];
                }
            }
            else{
                @autoreleasepool {
                    NSInteger first = [[[(NSDictionary*)a objectForKey:className] objectForKey:key] integerValue];
                    NSInteger second = [[[(NSDictionary*)b objectForKey:className] objectForKey:key] integerValue];
                    if (first > second){
                        return NSOrderedDescending;
                    }
                    if (first < second){
                        return NSOrderedAscending;
                    }
                    return NSOrderedSame;
                }
            }
        }
    }];
    
    JSONArray = nil;
    
    return result;
}

#pragma mark - Syncronize Steps

#pragma mark Receive Data

//Descarga los datos de sincronizacion
-(void)downloadSyncEntitiesForSync:(RecieveObjectsCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        @autoreleasepool {
            [self messageBlock:NSLocalizedString(@"Descargando información de sincronización...", nil) important:YES];
            
            __block DMEAPIEngine *api = [[DMEAPIEngine alloc] init];
            
            [api fetchEntitiesForSync:^(NSArray *objects, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [api invalidateSessionCancelingTasks:YES];
                    api = nil;
                });
                
                [self progressBlockIncrementInMainProcess:YES];
                
                [self.context performBlock:^{
                    if(!error){
                        self.classesToSync = [NSMutableArray array];
                        
                        for (NSDictionary *entity in objects) {
                            @autoreleasepool {
                                NSString *className = [entity valueForKey:@"entity"];
                                BOOL delete = [[entity valueForKey:@"delete"] boolValue];
                                BOOL push = [[entity valueForKey:@"push"] boolValue];
                                
                                //Añadimos la entidad para sincronizar
                                if([self.registeredClassesToSync containsObject:className] && ![self.classesToSync containsObject:className]){
                                    [self.classesToSync addObject:className];
                                }
                                
                                //Si esta marcada para borrar, truncamos todas las sincronizadas
                                if(delete){
                                    for (NSManagedObject *object in [self managedObjectsForClass:className withSyncStatus:ObjectSynced]) {
                                        @autoreleasepool {
                                            if([object respondsToSelector:NSSelectorFromString(@"deletable")] && (BOOL)[object performSelector:NSSelectorFromString(@"deletable")] == YES){
                                                [self.context deleteObject:object];
                                            }
                                        }
                                    }
                                }
                                
                                //Si esta marcada para enviar, marcamos como modificadas
                                if(push){
                                    for (NSManagedObject *object in [self managedObjectsForClass:className withSyncStatus:ObjectSynced]) {
                                        @autoreleasepool {
                                            if([object respondsToSelector:NSSelectorFromString(@"modifiable")] && (BOOL)[object performSelector:NSSelectorFromString(@"modifiable")] == YES){
                                                [object setValue:[NSNumber numberWithInt:ObjectModified] forKey:@"syncStatus"];
                                            }
                                        }
                                    }
                                }
                                
                            }
                        }
                        
                        //Ordenamos las entidades del sync states en el mismo orden que el sincronizador
                        NSArray *referenceArray = self.registeredClassesToSync;
                        NSArray *jumbledArray = self.classesToSync;
                        
                        NSMutableOrderedSet *setToOrder = [[NSMutableOrderedSet alloc] initWithArray:jumbledArray];
                        
                        NSUInteger insertIndex = 0;
                        
                        for (NSString *refString in referenceArray) {
                            NSUInteger presentIndex = [setToOrder indexOfObject:refString]; // one lookup, presumably cheap
                            
                            if (presentIndex != NSNotFound) {
                                [setToOrder moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:presentIndex] toIndex:insertIndex];
                                insertIndex++;
                            }
                        }
                        
                        self.classesToSync = [setToOrder array];
                        
                        [self messageBlock:NSLocalizedString(@"Información de sincronización descargada", nil) important:YES];
                        
                        [self downloadJSONForRegisteredObjects:completionBlock];
                    }
                    else{
                        NSError *errorSync = nil;
                        
                        if([error.userInfo objectForKey:@"NSLocalizedDescription"] && [(NSString *)[error.userInfo objectForKey:@"NSLocalizedDescription"] rangeOfString:@"403"].location != NSNotFound){
                            errorSync = [self createErrorWithCode:SyncErrorCodeNewVersion
                                                   andDescription:NSLocalizedString(@"Nueva versión de la aplicación", nil)
                                                 andFailureReason:NSLocalizedString(@"Hay una nueva versión disponible, debe actualizar la aplicación para continuar utilizandola", nil)
                                            andRecoverySuggestion:NSLocalizedString(@"Actualice la aplicación", nil)];
                            
                            [self errorBlock:errorSync fatal:YES];
                            [self executeSyncErrorOperations];
                        }
                        else if ([error.userInfo objectForKey:@"NSLocalizedDescription"] && [(NSString *)[error.userInfo objectForKey:@"NSLocalizedDescription"] rangeOfString:@"405"].location != NSNotFound){
                            errorSync = [self createErrorWithCode:SyncErrorCodeIntegration
                                                   andDescription:NSLocalizedString(@"Integración en curso", nil)
                                                 andFailureReason:NSLocalizedString(@"Se está realizando una integración, intentelo de nuevo más tarde.", nil)
                                            andRecoverySuggestion:NSLocalizedString(@"Intentelo de nuevo más tarde", nil)];
                            
                            [self errorBlock:errorSync fatal:YES];
                            [self executeSyncErrorOperations];
                        }
                        else{
                            errorSync = [self createErrorWithCode:SyncErrorCodeDownloadSyncInfo
                                                   andDescription:NSLocalizedString(@"Error al descargar la información de la sincronización", nil)
                                                 andFailureReason:NSLocalizedString(@"Ha fallado el servicio web de sincronización", nil)
                                            andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web y su conexión", nil)];
                            
                            if(self.initialSyncComplete){
                                [self errorBlock:errorSync fatal:NO];
                                
                                if(completionBlock){
                                    completionBlock();
                                }
                            }
                            else{
                                [self errorBlock:errorSync fatal:YES];
                                [self executeSyncErrorOperations];
                            }
                        }

                        errorSync = nil;
                    }
                }];
            }];
        }
    }];
}

//Descarga los datos de las clases registradas
-(void)downloadJSONForRegisteredObjects:(RecieveObjectsCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        @autoreleasepool {
            savedEntities = [NSMutableDictionary dictionary];
            
            __block DMEAPIEngine *api = [[DMEAPIEngine alloc] init];
            
            __block NSError *errorSync = nil;
            
            savedEntities = [NSMutableDictionary dictionary];
            
            self.downloadQueue = [[NSOperationQueue alloc] init];
            self.downloadQueue.name = @"Download JSON Queue";
            self.downloadQueue.MaxConcurrentOperationCount = MaxConcurrentDownloadJSON;
            
            NSMutableArray *requestArray = [NSMutableArray array];
            downloadCompletionAuxBlock = completionBlock;
            
            [self progressBlockTotal:self.classesToSync.count inMainProcess:NO];
            
            for (NSString *className in self.classesToSync) {
                @autoreleasepool {
                    [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Descargando información de %@...", nil), [self logClassName:className]] important:NO];
                    
                    //Creamos la operacion de descarga
                    AFHTTPRequestOperation *op = [[DMEAPIEngine sharedInstance] operationFetchObjectsForClass:className withParameters:nil onCompletion:^(NSArray *objects, NSError *error) {
                        @autoreleasepool {
                            [self progressBlockIncrementInMainProcess:NO];
                            
                            [self.context performBlock:^{
                                if(!error){
                                    @autoreleasepool {
                                        //Escribimos el resultado en memoria
                                        [self.JSONRecords setObject:objects forKey:className];
                                    }
                                }
                                else{
                                    @autoreleasepool {
                                        if([error.userInfo objectForKey:@"NSLocalizedDescription"] && [(NSString *)[error.userInfo objectForKey:@"NSLocalizedDescription"] rangeOfString:@"403"].location != NSNotFound){
                                            errorSync = [self createErrorWithCode:SyncErrorCodeNewVersion
                                                                   andDescription:NSLocalizedString(@"Nueva versión de la aplicación", nil)
                                                                 andFailureReason:NSLocalizedString(@"Hay una nueva versión disponible, debe actualizar la aplicación para continuar utilizandola", nil)
                                                            andRecoverySuggestion:NSLocalizedString(@"Actualice la aplicación", nil)];
                                        }
                                        else if ([error.userInfo objectForKey:@"NSLocalizedDescription"] && [(NSString *)[error.userInfo objectForKey:@"NSLocalizedDescription"] rangeOfString:@"405"].location != NSNotFound){
                                            errorSync = [self createErrorWithCode:SyncErrorCodeIntegration
                                                                   andDescription:NSLocalizedString(@"Integración en curso", nil)
                                                                 andFailureReason:NSLocalizedString(@"Se está realizando una integración, intentelo de nuevo más tarde.", nil)
                                                            andRecoverySuggestion:NSLocalizedString(@"Intentelo de nuevo más tarde", nil)];
                                        }
                                        else{
                                            errorSync = [self createErrorWithCode:SyncErrorCodeDownloadInfo
                                                                   andDescription:NSLocalizedString(@"Ha fallado alguno de los servicios web, intentelo de nuevo más tarde", nil)
                                                                 andFailureReason:[NSString stringWithFormat:NSLocalizedString(@"No se han podido descargar los datos de %@", nil), className]
                                                            andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web y su conexión", nil)];
                                        }
                                    }
                                }
                            }];
                        }
                    }];

                    [requestArray addObject:op];
                }
            }
            
            NSArray *batches = [AFURLConnectionOperation batchOfRequestOperations:requestArray progressBlock:^(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations) {} completionBlock:^(NSArray *operations) {
                [self.context performBlock:^{
                    @autoreleasepool {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [api invalidateSessionCancelingTasks:YES];
                            api = nil;
                        });
                        
                        [self progressBlockIncrementInMainProcess:YES];
                        
                        if(!errorSync){
                            @autoreleasepool {
                                // Do whatever you need to do when all requests are finished
                                [self messageBlock:NSLocalizedString(@"Descargada toda la información, procesando los datos", nil) important:YES];
                            
                                [self processJSONDataRecordsIntoCoreData:completionBlock];
                            }
                        }
                        else{
                            if(self.initialSyncComplete){
                                [self errorBlock:errorSync fatal:NO];
                                
                                if(completionBlock){
                                    completionBlock();
                                }
                            }
                            else{
                                [self errorBlock:errorSync fatal:YES];
                                [self executeSyncErrorOperations];
                            }
                            
                            errorSync = nil;
                        }
                    }
                }];
            }];
            
            if(batches.count > 0){
                [self.downloadQueue addOperations:batches waitUntilFinished:NO];
            }
            else{
                if(downloadCompletionAuxBlock){
                    downloadCompletionAuxBlock();
                    downloadCompletionAuxBlock = nil;
                }
            }
        }
    }];
}

-(void)processJSONDataRecordsIntoCoreData:(RecieveObjectsCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        @autoreleasepool {
            NSMutableDictionary *JSONData = [NSMutableDictionary dictionary];
            
            // Calculamos el progreso
            NSInteger total = 0;
            for (NSString *className in self.classesToSync) {
                @autoreleasepool {
                    if (![self initialSyncComplete]){
                        // If this is the initial sync then the logic is pretty simple, you will fetch the JSON data from disk
                        // for the class of the current iteration and create new NSManagedObjects for each record
                        [JSONData setObject:[self JSONArrayForClassWithName:className] forKey:className];
                    }
                    else{
                        // Otherwise you need to do some more logic to determine if the record is new or has been updated.
                        // First get the downloaded records from the JSON response, verify there is at least one object in
                        // the data, and then fetch all records stored in Core Data whose objectId matches those from the JSON response.
                        [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Procesando información de %@...", nil), [self logClassName:className]] important:NO];
                        [JSONData setObject:[self JSONDataRecordsForClass:className sortedByKey:@"id" modifiedAfter:[self lastModifiedDateForClass:className]] forKey:className];
                    }
                    total += [(NSArray *)[JSONData objectForKey:className] count];
                }
            }
            
            [self progressBlockTotal:total inMainProcess:NO];
            
            // Iterate over all registered classes to sync
            for (NSString *className in self.classesToSync) {
                @autoreleasepool {
                    if([JSONData objectForKey:className] && [[JSONData objectForKey:className] count] > 0){
                        [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Guardando información de %@ (%@ objetos)...", nil), [self logClassName:className], [NSNumber numberWithInteger:[[JSONData objectForKey:className] count]]] important:NO];
                        
                        if (![self initialSyncComplete]) { // import all downloaded data to Core Data for initial sync
                            for (NSDictionary *record in [JSONData objectForKey:className]) {
                                @autoreleasepool {
                                    NSManagedObject *managedObject = [[savedEntities objectForKey:className] objectForKey:[[record objectForKey:className] objectForKey:@"id"]];
                                    if(!managedObject){
                                        [self newManagedObjectWithClassName:className forRecord:record];
                                    }
                                    else{
                                        [self updateManagedObject:managedObject withClassName:className withRecord:record];
                                        managedObject = nil;
                                    }
                                    
                                    [self progressBlockIncrementInMainProcess:NO];
                                }
                            }
                        }
                        else {
                            if([[JSONData valueForKey:className] count] > 0){
                                NSArray *storedManagedObjects = [self managedObjectsForClass:className withPredicate:[NSPredicate predicateWithFormat:@"id IN %@", [[[JSONData valueForKey:className] valueForKey:className] valueForKey:@"id"]]];
                                
                                NSEnumerator *JSONEnumerator = [[JSONData objectForKey:className] objectEnumerator];
                                NSEnumerator *fetchResultsEnumerator = [storedManagedObjects objectEnumerator];
                                
                                NSDictionary *record = [JSONEnumerator nextObject];
                                NSManagedObject *storedManagedObject = [[fetchResultsEnumerator nextObject] objectInContext:self.context];
                                
                                while (record) {
                                    @autoreleasepool {
                                        NSString *id = nil;
                                        
                                        if([[record objectForKey:className] isKindOfClass:[NSDictionary class]]){
                                            id = [[record objectForKey:className] valueForKey:@"id"];
                                        }
                                        
                                        if(id && ![id isEqualToString:@""]){
                                            if([id isEqualToString:[storedManagedObject valueForKey:@"id"]]){
                                                [self updateManagedObject:storedManagedObject withClassName:className withRecord:record];
                                                
                                                //Avanzamos ambos cursores
                                                record = [JSONEnumerator nextObject];
                                                storedManagedObject = [[fetchResultsEnumerator nextObject] objectInContext:self.context];
                                                
                                                [self progressBlockIncrementInMainProcess:NO];
                                            }
                                            else{
                                                if([self existsManagedObjectForClass:className withId:id]){
                                                    if(!storedManagedObject){
                                                        storedManagedObject = [self managedObjectForClass:className withId:id];
                                                    }
                                                    [self updateManagedObject:storedManagedObject withClassName:className withRecord:record];
                                                    
                                                    storedManagedObject = [[fetchResultsEnumerator nextObject] objectInContext:self.context];
                                                }
                                                else{
                                                    [self newManagedObjectWithClassName:className forRecord:record];
                                                }
                                                
                                                record = [JSONEnumerator nextObject];
                                                
                                                [self progressBlockIncrementInMainProcess:NO];
                                            }
                                        }
                                        else{
                                            NSError *errorSync = [self createErrorWithCode:SyncErrorCodeNoId
                                                                            andDescription:[NSString stringWithFormat:NSLocalizedString(@"La información descargada de %@ no tiene ID", nil), [self logClassName:className]]
                                                                          andFailureReason:NSLocalizedString(@"La entidad descargada no tiene ID", nil)
                                                                     andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                            
                                            if(self.initialSyncComplete){
                                                [self errorBlock:errorSync fatal:NO];
                                                
                                                if(completionBlock){
                                                    completionBlock();
                                                }
                                            }
                                            else{
                                                [self errorBlock:errorSync fatal:YES];
                                                [self executeSyncErrorOperations];
                                            }
                                            
                                            errorSync = nil;
                                            
                                            return;
                                        }
                                    }
                                }
                                
                                storedManagedObjects = nil;
                                JSONEnumerator = nil;
                                fetchResultsEnumerator = nil;
                                record = nil;
                                storedManagedObject = nil;
                            }
                        }
                        
                        [JSONData removeObjectForKey:className];
                    }
                }
            }
            [savedEntities removeAllObjects];
            savedEntities = nil;
            [JSONData removeAllObjects];
            JSONData = nil;
            
            [self messageBlock:NSLocalizedString(@"Toda la información ha sido guardada", nil) important:YES];
            [self progressBlockIncrementInMainProcess:YES];
            
            [self processJSONDataRecordsForDeletion:completionBlock];
        }
    }];
}

-(void)processJSONDataRecordsForDeletion:(RecieveObjectsCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        @autoreleasepool {
            // Iterate over all registered classes to sync
            if(self.initialSyncComplete){
                [self progressBlockTotal:self.classesToSync.count inMainProcess:NO];
                
                for (NSString *className in self.classesToSync) {
                    @autoreleasepool {
                        // Retrieve the JSON response records from disk
                        NSArray *JSONRecords = [self JSONDataRecordsForClass:className sortedByKey:@"id"];
                        NSArray *storedRecords;
                        if ([JSONRecords count] > 0) {
                            // If there are any records fetch all locally stored records that are NOT in the list of downloaded records
                            storedRecords = [self managedObjectsForClass:className sortedByKey:@"id" usingArrayOfIds:[[JSONRecords valueForKey:className] valueForKey:@"id"] inArrayOfIds:NO];
                        }
                        else{
                            NSPredicate *createdPredicate = [[self syncStatusNotPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:ObjectCreated]}];
                            NSPredicate *notSyncPredicate = [[self syncStatusNotPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:ObjectNotSync]}];
                            NSPredicate *andPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:createdPredicate, notSyncPredicate, nil]];
                            storedRecords = [self managedObjectsForClass:className withPredicate:andPredicate];
                            
                            createdPredicate = nil;
                            notSyncPredicate = nil;
                            andPredicate = nil;
                        }
                        
                        if([storedRecords count] > 0){
                            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Limpiando información de %@ (%@ objetos)...", nil), [self logClassName:className], [NSNumber numberWithInteger:[storedRecords count]]] important:NO];
                            
                            // Schedule the NSManagedObject for deletion
                            for (NSManagedObject *managedObject in storedRecords) {
                                @autoreleasepool {
                                    [self logDebug:@"   Deleted %@", className];
                                    [self.context performBlockAndWait:^{
                                        [self.context deleteObject:managedObject];
                                    }];
                                }
                            }
                            
                            [self progressBlockIncrementInMainProcess:NO];
                        }
                        
                        JSONRecords = nil;
                        storedRecords = nil;
                    }
                }
                
                [self messageBlock:NSLocalizedString(@"Se ha finalizado la limpieza de datos", nil) important:YES];
                [self progressBlockIncrementInMainProcess:YES];
            }
            [self.JSONRecords removeAllObjects];
            self.JSONRecords = nil;
            
            [self messageBlock:NSLocalizedString(@"Guardando los datos...", nil) important:YES];
            
            [self saveContext:^(BOOL result) {
                @autoreleasepool {
                    if(result){
                        //Send syncstate remove order
                        if(self.classesToSync.count > 0 && self.initialSyncComplete){
                            __block DMEAPIEngine *api = [[DMEAPIEngine alloc] init];
                            [api pushEntitiesSynchronized:self.startDate onCompletion:^(NSDictionary *object, NSError *error) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [api invalidateSessionCancelingTasks:YES];
                                    api = nil;
                                });
                                
                                [self.context performBlock:^{
                                    if(!error){
                                        [self messageBlock:NSLocalizedString(@"Se ha limpiado la información de sincronización", nil) important:YES];
                                    }
                                    else{
                                        NSError *errorSync = [self createErrorWithCode:SyncErrorCodeCleanSyncInfo
                                                                        andDescription:NSLocalizedString(@"No se ha podido limpiar la información de sincronización", nil)
                                                                      andFailureReason:NSLocalizedString(@"Ha fallado alguno de los servicios web", nil)
                                                                 andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web y su conexión", nil)];
                                        
                                        [self errorBlock:errorSync fatal:NO];
                                        
                                        errorSync = nil;
                                    }
                                }];
                            }];
                        }
                        
                        [self messageBlock:NSLocalizedString(@"Se han guardado los datos", nil) important:YES];
                    }
                    
                    if(completionBlock){
                        completionBlock();
                    }
                }
            }];
        }
    }];
}

#pragma mark Send Data

//Envia los objetos creados localmente al servidor
-(void)postLocalObjectsToServer:(SendObjectsCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        if(self.initialSyncComplete){
            [self messageBlock:NSLocalizedString(@"Enviando datos al servidor...", nil) important:YES];
            
            [self progressBlockTotal:self.registeredClassesToSync.count inMainProcess:NO];
            
            //Recursive call
            [self postLocalObjectsToServerOfClassWithId:0 completionBlock:^{
                [self progressBlockIncrementInMainProcess:YES];
                [self updateLocalObjectsToServer:completionBlock];
            }];
        }
        else{
            [self progressBlockIncrementInMainProcess:YES];
            [self updateLocalObjectsToServer:completionBlock];
        }
    }];
}

-(void)postLocalObjectsToServerOfClassWithId:(NSInteger)index completionBlock:(void (^)())completionBlock
{
    @autoreleasepool {
        if(index >= self.registeredClassesToSync.count){
            if(completionBlock){
                completionBlock();
            }
        }
        else{
            if(self.initialSyncComplete && self.registeredClassesToSync.count > 0){
                [self progressBlockIncrementInMainProcess:NO];
                
                NSString *className = [self.registeredClassesToSync objectAtIndex:index];
                NSArray *objectsToCreate = [self managedObjectsForClass:className withSyncStatus:ObjectCreated];
                
                if(objectsToCreate.count > 0){
                    // Create a dispatch group
                    __block dispatch_group_t groupGeneral = dispatch_group_create();
                    dispatch_semaphore_t sem;
                    
                    DMEAPIEngine *api = [[DMEAPIEngine alloc] init];
                    
                    for (NSManagedObject *objectToCreate in objectsToCreate) {
                        @autoreleasepool {
                            if(!objectToCreate.isDeleted){
                                // Get the JSON representation of the NSManagedObject
                                NSDictionary *jsonString = [objectToCreate JSONToObjectOnServer];
                                NSDictionary *filesURL = [objectToCreate filesURLToObjectOnServer];
                                
                                if(jsonString && jsonString.count > 0){
                                    // Enter the group for each request we create
                                    dispatch_group_enter(groupGeneral);
                                    
                                    sem = dispatch_semaphore_create(0);
                                    
                                    [api pushObjectForClass:className parameters:jsonString files:filesURL onCompletion:^(NSDictionary *object, NSError *error) {
                                        dispatch_semaphore_signal(sem);
                                        
                                        [self.context performBlock:^{
                                            if(!error && object){
                                                if(object.count > 0){
                                                    for (NSString* key in object) {
                                                        @autoreleasepool {
                                                            if([[object objectForKey:key] isKindOfClass:[NSArray class]]){
                                                                //Obtenemos el nombre de la relacion
                                                                NSString *relationName = [[self nameFromClassName:className relation:key] objectForKey:@"relationName"];
                                                                
                                                                //Obtenemos los objetos de la relacion
                                                                NSArray *objectsToUpdate = [(NSSet *)[[objectToCreate objectInContext:self.context] valueForKey:relationName] allObjects];
                                                                
                                                                if(objectsToUpdate.count == [(NSArray *)[object objectForKey:key] count]){
                                                                    //Volvemos a crear los objetos
                                                                    NSInteger i = 0;
                                                                    for (NSDictionary *record in [object objectForKey:key]) {
                                                                        if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"created"]){
                                                                            NSManagedObject *relationObject = [objectsToUpdate objectAtIndex:i];
                                                                            
                                                                            [relationObject setValue:[self dateUsingStringFromAPI:[record valueForKey:@"created"]] forKey:@"created"];
                                                                            [relationObject setValue:[self dateUsingStringFromAPI:[record valueForKey:@"modified"]] forKey:@"modified"];
                                                                            [relationObject setValue:[record valueForKey:@"id"] forKey:@"id"];
                                                                            [relationObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                                        }
                                                                        i++;
                                                                    }
                                                                }
                                                                
                                                                relationName = nil;
                                                                objectsToUpdate = nil;
                                                            }
                                                            else if ([[object objectForKey:key] isKindOfClass:[NSDictionary class]]){
                                                                if([key isEqualToString:className]){
                                                                    NSDictionary *record = [object objectForKey:key];
                                                                    
                                                                    if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"created"] && [record valueForKey:@"modified"]){
                                                                        [self updateManagedObject:[objectToCreate objectInContext:self.context] withClassName:className withRecord:@{className: record}];
                                                                        [[objectToCreate objectInContext:self.context] setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                                    }
                                                                    
                                                                    record = nil;
                                                                }
                                                            }
                                                        }
                                                    }
                                                    
                                                    [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Se ha creado el %@ con id %@", nil), [self logClassName:[[[objectToCreate objectInContext:self.context] entity] name]], [[objectToCreate objectInContext:self.context] valueForKey:@"id"]] important:NO];
                                                    
                                                    [self saveContext:^(BOOL result) {
                                                        dispatch_group_leave(groupGeneral);
                                                    }];
                                                }
                                                else{
                                                    //Delete object in Core Data
                                                    [self.context deleteObject:[objectToCreate objectInContext:self.context]];
                                                    
                                                    [self saveContext:^(BOOL result) {
                                                        dispatch_group_leave(groupGeneral);
                                                    }];
                                                }
                                            }
                                            else{
                                                NSError *errorPost = [self createErrorWithCode:SyncErrorCodeCreateInfo
                                                                                andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido enviar el %@ al servidor", nil), [self logClassName:className]]
                                                                              andFailureReason:[[error.localizedDescription ?: @"" stringByAppendingString:@" "] stringByAppendingString:error.debugDescription ?: @""]
                                                                         andRecoverySuggestion:error.localizedRecoverySuggestion ?:@""];
                                                [self errorBlock:errorPost fatal:NO];
                                                errorPost = nil;
                                                
                                                dispatch_group_leave(groupGeneral);
                                            }
                                        }];
                                    }];
                                    
                                    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                                }
                                
                                jsonString = nil;
                                filesURL = nil;
                            }
                        }
                    }
                    
                    dispatch_group_notify(groupGeneral, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        [self.context performBlock:^{
                            [self postLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                        }];
                    });
                }
                else{
                    [self.context performBlock:^{
                        [self postLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                    }];
                }
                
                objectsToCreate = nil;
                className = nil;
            }
            else{
                [self.context performBlock:^{
                    [self postLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                }];
            }
        }
    }
}

//Envia los objetos actualizados localmente al servidor
-(void)updateLocalObjectsToServer:(SendObjectsCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        if(self.initialSyncComplete){
            [self messageBlock:NSLocalizedString(@"Modificando datos en el servidor...", nil) important:YES];
            
            [self progressBlockTotal:self.registeredClassesToSync.count inMainProcess:NO];
            
            //Recursive call
            [self updateLocalObjectsToServerOfClassWithId:0 completionBlock:^{
                [self progressBlockIncrementInMainProcess:YES];
                [self deleteObjectsOnServer:completionBlock];
            }];
        }
        else{
            [self progressBlockIncrementInMainProcess:YES];
            [self deleteObjectsOnServer:completionBlock];
        }
    }];
}


-(void)updateLocalObjectsToServerOfClassWithId:(NSInteger)index completionBlock:(void (^)())completionBlock
{
    @autoreleasepool {
        if(index >= self.registeredClassesToSync.count){
            if(completionBlock){
                completionBlock();
            }
        }
        else{
            if(self.initialSyncComplete && self.registeredClassesToSync.count > 0){
                [self progressBlockIncrementInMainProcess:NO];
                
                NSString *className = [self.registeredClassesToSync objectAtIndex:index];
                NSArray *objectsToModified = [self managedObjectsForClass:className withSyncStatus:ObjectModified];
                
                if(objectsToModified.count > 0){
                    // Create a dispatch group
                    __block dispatch_group_t groupGeneral = dispatch_group_create();
                    dispatch_semaphore_t sem;
                    
                    DMEAPIEngine *api = [[DMEAPIEngine alloc] init];
                    
                    for (NSManagedObject *objectToModified in objectsToModified) {
                        @autoreleasepool {
                            if(!objectToModified.isDeleted){
                                NSString *objectId = [objectToModified valueForKey:@"id"];
                                
                                if(objectId && ![objectId isEqualToString:@""] && !objectToModified.isDeleted){
                                    // Get the JSON representation of the NSManagedObject
                                    NSDictionary *jsonString = [objectToModified JSONToObjectOnServer];
                                    NSDictionary *filesURL = [objectToModified filesURLToObjectOnServer];
                                    
                                    if(jsonString && jsonString.count > 0){
                                        // Enter the group for each request we create
                                        dispatch_group_enter(groupGeneral);
                                        
                                        sem = dispatch_semaphore_create(0);
                                        
                                        [api updateObjectForClass:className withId:[objectToModified valueForKey:@"id"] parameters:jsonString files:filesURL onCompletion:^(NSDictionary *object, NSError *error) {
                                            dispatch_semaphore_signal(sem);
                                            
                                            [self.context performBlock:^{
                                                if(!error && object){
                                                    if(object.count > 0){
                                                        for (NSString* key in object) {
                                                            @autoreleasepool {
                                                                if([[object objectForKey:key] isKindOfClass:[NSArray class]]){
                                                                    for (NSDictionary *record in [object objectForKey:key]) {
                                                                        if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"created"]){
                                                                            NSManagedObject *relationObject = [self updateRelation:className ofManagedObject:[objectToModified objectInContext:self.context] withClassName:key withRecord:record];
                                                                            [relationObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                                        }
                                                                    }
                                                                }
                                                                else if ([[object objectForKey:key] isKindOfClass:[NSDictionary class]]){
                                                                    if([key isEqualToString:className]){
                                                                        NSDictionary *record = [object objectForKey:key];
                                                                        
                                                                        if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"modified"]){
                                                                            [self updateManagedObject:[objectToModified objectInContext:self.context] withClassName:className withRecord:@{className: record}];
                                                                            [[objectToModified objectInContext:self.context] setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                                        }
                                                                        
                                                                        record = nil;
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        
                                                        [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Se ha modificado el %@ con id %@", nil), [self logClassName:[[[objectToModified objectInContext:self.context] entity] name]], [[objectToModified objectInContext:self.context] valueForKey:@"id"]] important:NO];
                                                        
                                                        [self saveContext:^(BOOL result) {
                                                            dispatch_group_leave(groupGeneral);
                                                        }];
                                                    }
                                                    else{
                                                        NSError *errorUpdate = [self createErrorWithCode:SyncErrorCodeModifyInfo
                                                                                          andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido actualizar el %@ al servidor", nil), [self logClassName:className]]
                                                                                        andFailureReason:NSLocalizedString(@"Ha fallado la respuesta del servicio web", nil)
                                                                                   andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                                        [self errorBlock:errorUpdate fatal:NO];
                                                        
                                                        errorUpdate = nil;
                                                        
                                                        dispatch_group_leave(groupGeneral);
                                                    }
                                                }
                                                else{
                                                    NSError *errorUpdate = [self createErrorWithCode:SyncErrorCodeModifyInfo
                                                                                      andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido actualizar el %@ al servidor", nil), [self logClassName:className]]
                                                                                    andFailureReason:[[error.localizedDescription ?: @"" stringByAppendingString:@" "] stringByAppendingString:error.debugDescription ?: @""]
                                                                               andRecoverySuggestion:error.localizedRecoverySuggestion ?:@""];
                                                    [self errorBlock:errorUpdate fatal:NO];
                                                    
                                                    errorUpdate = nil;
                                                    
                                                    dispatch_group_leave(groupGeneral);
                                                }
                                            }];
                                        }];
                                        
                                        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                                    }
                                    
                                    jsonString = nil;
                                    filesURL = nil;
                                }
                            }
                        }
                    }
                    
                    dispatch_group_notify(groupGeneral, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        [self.context performBlock:^{
                            [self updateLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                        }];
                    });
                }
                else{
                    [self.context performBlock:^{
                        [self updateLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                    }];
                }
                
                objectsToModified = nil;
                className = nil;
            }
            else{
                [self.context performBlock:^{
                    [self updateLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                }];
            }
        }
    }
}

//Elimina del servidor los objetos eliminados localmente
-(void)deleteObjectsOnServer:(SendObjectsCompletionBlock)completionBlock {
    [self.context performBlock:^{
        if(self.initialSyncComplete){
            [self messageBlock:NSLocalizedString(@"Eliminando datos en el servidor...", nil) important:YES];
            
            [self progressBlockTotal:self.registeredClassesToSync.count inMainProcess:NO];
            
            //Recursive call
            [self deleteObjectsOnServerOfClassWithId:0 completionBlock:^{
                [self progressBlockIncrementInMainProcess:YES];
                if(completionBlock){
                    completionBlock();
                }
            }];
        }
        else{
            [self progressBlockIncrementInMainProcess:YES];
            if(completionBlock){
                completionBlock();
            }
        }
    }];
}

-(void)deleteObjectsOnServerOfClassWithId:(NSInteger)index completionBlock:(void (^)())completionBlock {
    @autoreleasepool {
        if(index >= self.registeredClassesToSync.count){
            if(completionBlock){
                completionBlock();
            }
        }
        else{
            if(self.initialSyncComplete && self.registeredClassesToSync.count > 0){
                [self progressBlockIncrementInMainProcess:NO];
                
                NSString *className = [self.registeredClassesToSync objectAtIndex:index];
                NSArray *objectsToDelete = [self managedObjectsForClass:className withSyncStatus:ObjectDeleted];
                
                if(objectsToDelete.count > 0){
                    // Create a dispatch group
                    __block dispatch_group_t groupGeneral = dispatch_group_create();
                    dispatch_semaphore_t sem;
                    
                    DMEAPIEngine *api = [[DMEAPIEngine alloc] init];
                    
                    for (NSManagedObject *objectToDelete in objectsToDelete) {
                        @autoreleasepool {
                            if(!objectToDelete.isDeleted){
                                NSString *objectId = [objectToDelete valueForKey:@"id"];
                                
                                if(objectId && ![objectId isEqualToString:@""] && !objectToDelete.isDeleted){
                                    // Enter the group for each request we create
                                    dispatch_group_enter(groupGeneral);
                                    
                                    sem = dispatch_semaphore_create(0);
                                    
                                    [api deleteObjectForClass:className withId:[objectToDelete valueForKey:@"id"] onCompletion:^(NSDictionary *object, NSError *error) {
                                        dispatch_semaphore_signal(sem);
                                        
                                        [self.context performBlock:^{
                                            if(!error && object){
                                                if(object.count > 0 && [[object objectForKey:className] valueForKey:@"id"]){
                                                    //Delete object in Core Data
                                                    [self.context deleteObject:[objectToDelete objectInContext:self.context]];
                                                    
                                                    [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Se ha eliminado el %@ con id %@", nil), [self logClassName:[[[objectToDelete objectInContext:self.context] entity] name]], [[objectToDelete objectInContext:self.context] valueForKey:@"id"]] important:NO];
                                                    
                                                    [self saveContext:^(BOOL result) {
                                                        dispatch_group_leave(groupGeneral);
                                                    }];
                                                }
                                                else{
                                                    NSError *errorDelete = [self createErrorWithCode:SyncErrorCodeDeleteInfo
                                                                                      andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido eliminar el %@ al servidor", nil), [self logClassName:className]]
                                                                                    andFailureReason:NSLocalizedString(@"Ha fallado el borrado de datos en el servidor", nil)
                                                                               andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                                    [self errorBlock:errorDelete fatal:NO];
                                                    
                                                    errorDelete = nil;
                                                    
                                                    dispatch_group_leave(groupGeneral);
                                                }
                                                
                                            }
                                            else{
                                                NSError *errorDelete = [self createErrorWithCode:SyncErrorCodeDeleteInfo
                                                                                  andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido eliminar el %@ al servidor", nil), [self logClassName:className]]
                                                                                andFailureReason:[[error.localizedDescription ?: @"" stringByAppendingString:@" "] stringByAppendingString:error.debugDescription ?: @""]
                                                                           andRecoverySuggestion:error.localizedRecoverySuggestion ?:@""];
                                                [self errorBlock:errorDelete fatal:NO];
                                                
                                                errorDelete = nil;
                                                
                                                dispatch_group_leave(groupGeneral);
                                            }
                                        }];
                                    }];
                                    
                                    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                                }
                                
                                objectId = nil;
                            }
                        }
                    }
                    
                    dispatch_group_notify(groupGeneral, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                        [self.context performBlock:^{
                            [self deleteObjectsOnServerOfClassWithId:index+1 completionBlock:completionBlock];
                        }];
                    });
                }
                else{
                    [self.context performBlock:^{
                        [self deleteObjectsOnServerOfClassWithId:index+1 completionBlock:completionBlock];
                    }];
                }
                
                objectsToDelete = nil;
                className = nil;
            }
            else{
                [self.context performBlock:^{
                    [self deleteObjectsOnServerOfClassWithId:index+1 completionBlock:completionBlock];
                }];
            }
        }
    }
}

#pragma mark Download files

//Comienza la descarga de ficheros
-(void)downloadFiles:(DownloadCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        //Comprobamos que hay que hacer
        if(!self.downloadFiles){
            [self messageBlock:NSLocalizedString(@"La descarga de ficheros esta desactivada", nil) important:YES];
            [self progressBlockIncrementInMainProcess:YES];
            
            if(completionBlock){
                completionBlock();
            }
        }
        else{
            [self messageBlock:NSLocalizedString(@"Buscando ficheros por descargar...", nil) important:YES];
            
            //Check exiting files
            [self checkFilesToDownload];
            
            // Download files
            if(self.filesToDownload.count){
                [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Hay %@ ficheros por descargar", nil), [NSNumber numberWithInteger:self.filesToDownload.count]] important:YES];
                
                [self downloadFilesToDownload:completionBlock];
            }
            else{
                [self messageBlock:NSLocalizedString(@"No hay ficheros para descargar", nil) important:YES];
                [self progressBlockIncrementInMainProcess:YES];
                
                if(completionBlock){
                    completionBlock();
                }
            }
        }
    }];
}

#pragma mark - Clean Service

-(void)cleanEngine
{
    @autoreleasepool {
        [self.JSONRecords removeAllObjects];
        [self.filesToDownload removeAllObjects];
        [savedEntities removeAllObjects];
        
        [self.context reset];
        self.context = nil;
        self.JSONRecords = [NSMutableDictionary dictionary];
        self.dateFormatter = nil;
        self.downloadQueue = nil;
        self.filesToDownload = nil;
        self.downloadedFiles = 0;
        self.progressCurrent = 0;
        self.progressTotal = 0;
        self.startDate = nil;
        
        savedEntities = nil;
        idPredicateTemplate = nil;
        syncStatusNotPredicateTemplate = nil;
        syncStatusPredicateTemplate = nil;
    }
}

#pragma mark - Downloaded File Management

//Comprueba si faltan ficheros por descargar y los añade a la lista
-(void)checkFilesToDownload
{
    NSManagedObjectContext *managedObjectContext = self.context;
    NSMutableArray *filesToDownloadURLs = [NSMutableArray array];
    
    // Iterate over all registered classes to sync
    for (NSString *className in self.registeredClassesToSync) {
        @autoreleasepool {
            if(([self.registeredClassesWithFiles containsObject:className] && self.downloadFiles) || ([self.registeredClassesWithOptionalFiles containsObject:className] && self.downloadOptionalFiles)){
                NSEntityDescription *classDescription = [NSEntityDescription entityForName:className inManagedObjectContext:managedObjectContext];
                if(classDescription){
                    NSArray *properties = [classDescription properties];
                    for (NSPropertyDescription *property in properties) {
                        @autoreleasepool {
                            if([property.name length] > 2 && [[property.name substringToIndex:3] isEqualToString:@"url"]){
                                NSArray *objects = [self managedObjectsForClass:className];
                                for (NSManagedObject *object in objects) {
                                    @autoreleasepool {
                                        if([object valueForKey:property.name] && ![(NSString *)[object valueForKey:property.name] isEqualToString:@""] && ![self fileExistWithName:[object valueForKey:property.name] ofClass:className] && ![filesToDownloadURLs containsObject:[[className stringByAppendingString:@"/"] stringByAppendingString:[object valueForKey:property.name]]]){
                                            //Añadimos la url para ser descargada
                                            [self.filesToDownload addObject:[NSDictionary dictionaryWithObjectsAndKeys:className, @"classname", [object valueForKey:property.name], @"url", nil]];
                                            [filesToDownloadURLs addObject:[[className stringByAppendingString:@"/"] stringByAppendingString:[object valueForKey:property.name]]];
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    filesToDownloadURLs = nil;
    managedObjectContext = nil;
}

//Descarga todos los ficheros de la cola
-(void)downloadFilesToDownload:(DownloadCompletionBlock)completionBlock
{
    self.downloadQueue = [[NSOperationQueue alloc] init];
    self.downloadQueue.name = @"Download Files Queue";
    self.downloadQueue.MaxConcurrentOperationCount = MaxConcurrentDownload;
    
    NSMutableArray *requestArray = [NSMutableArray array];
    downloadCompletionAuxBlock = completionBlock;
    
    //Thumbnails
    [DMEThumbnailer sharedInstance].sizes = thumbnailSize();
    
    for (NSDictionary *file in self.filesToDownload) {
        @autoreleasepool {
            //Eliminamos el valor anterior si no es la primera sincronizacion
            if(self.initialSyncComplete){
                [self removeFileWithName:[file objectForKey:@"url"] ofClass:[file objectForKey:@"classname"]];
            }
        }
    }
    
    [self progressBlockTotal:self.filesToDownload.count inMainProcess:NO];
    
    for (NSDictionary *file in self.filesToDownload) {
        @autoreleasepool {
            // Add an operation as a block to a queue
            NSFileManager *filemgr = [NSFileManager defaultManager];
            
            //Creamos la URL remota y local
            NSString *className = [NSString stringWithFormat:@"%@%@", [[[file objectForKey:@"classname"] substringToIndex:1] lowercaseString], [[file objectForKey:@"classname"] substringFromIndex:1]];
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@/%@", URLUploads, className, [file objectForKey:@"url"]]];
            NSString *urlDirectorio = [NSString stringWithFormat:@"%@/%@", pathCache(), className];
            NSString *tmpName = [[NSUUID new] UUIDString];
            NSString *urlTmp = [NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), tmpName];
            NSString *urlLocal = [NSString stringWithFormat:@"%@/%@", urlDirectorio, [file objectForKey:@"url"]];
            
            //Cambiamos al directorio de cache
            if([filemgr changeCurrentDirectoryPath:urlDirectorio] == NO){
                [filemgr createDirectoryAtPath:urlDirectorio withIntermediateDirectories:YES attributes: nil error: NULL];
            }
            
            //Creamos la operacion de descarga
            AFHTTPRequestOperation *op = [[AFHTTPRequestOperation alloc] initWithRequest:[NSURLRequest requestWithURL:url]];
            op.outputStream = [NSOutputStream outputStreamToFileAtPath:urlLocal append:NO];
            op.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"application/pdf", @"application/x-bzpdf", @"application/x-gzpdf", @"image/jpeg", @"image/png", @"image/tiff", @"image/tiff-fx", @"video/mp4", @"video/quicktime", nil];

            op.queuePriority = NSOperationQueuePriorityHigh;
            
            [op setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead){}];
            
            [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
                
                self.downloadedFiles++;
                
                [self progressBlockIncrementInMainProcess:NO];
                
                NSError *error;
                if(![operation.responseSerializer validateResponse:operation.response data:operation.responseData error:&error] || error){
                    error = [self createErrorWithCode:SyncErrorCodeDeleteInfo
                                       andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido descargar el fichero: %@/%@", nil), [file objectForKey:@"classname"], [file objectForKey:@"url"]]
                                     andFailureReason:NSLocalizedString(@"Ha fallado la descarga del fichero", nil)
                                andRecoverySuggestion:NSLocalizedString(@"Compruebe los ficheros", nil)];
                    
                    [self errorBlock:error fatal:NO];
                    
                    [self removeFileWithName:[file objectForKey:@"url"] ofClass:className];
                }
                else{
                    [self thumbnailFileWithName:[file objectForKey:@"url"] ofClass:[file objectForKey:@"classname"]];
                    
                    [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Descargado fichero (%@/%@): %@/%@", nil), [NSNumber numberWithInteger:self.downloadedFiles], [NSNumber numberWithInteger:self.filesToDownload.count], [file objectForKey:@"classname"], [file objectForKey:@"url"]] important:NO];
                }
                
                responseObject = nil;
                error = nil;
                
            } failure:^(AFHTTPRequestOperation * _Nonnull operation, NSError * _Nonnull error) {
                self.downloadedFiles++;
                
                
                [self progressBlockIncrementInMainProcess:NO];
                
                
                error = [self createErrorWithCode:SyncErrorCodeDeleteInfo
                                   andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido descargar el fichero: %@/%@", nil), [file objectForKey:@"classname"], [file objectForKey:@"url"]]
                                 andFailureReason:NSLocalizedString(@"Ha fallado la descarga del fichero", nil)
                            andRecoverySuggestion:NSLocalizedString(@"Compruebe los ficheros", nil)];
                
                
                [self errorBlock:error fatal:NO];
                
                [self removeFileWithName:[file objectForKey:@"url"] ofClass:className];
                
                error = nil;
            }];
            
            [requestArray addObject:op];
        }
    }
    
    NSArray *batches = [AFURLConnectionOperation batchOfRequestOperations:requestArray progressBlock:^(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations) {} completionBlock:^(NSArray *operations) {
        
        [self messageBlock:NSLocalizedString(@"Se han descargado todos los ficheros", nil) important:YES];
        [self progressBlockIncrementInMainProcess:YES];
        
        [self.context performBlock:^{
            if(downloadCompletionAuxBlock){
                downloadCompletionAuxBlock();
                downloadCompletionAuxBlock = nil;
            }
        }];
    }];
    
    if(batches.count > 0){
        [self.downloadQueue addOperations:batches waitUntilFinished:NO];
    }
    else{
        if(downloadCompletionAuxBlock){
            downloadCompletionAuxBlock();
            downloadCompletionAuxBlock = nil;
        }
    }
}

-(void)thumbnailFileWithName:(NSString *)aName ofClass:(NSString *)aClass
{
    NSString *className = [NSString stringWithFormat:@"%@%@", [[aClass substringToIndex:1] lowercaseString], [aClass substringFromIndex:1]];
    NSString *urlDirectorio = [NSString stringWithFormat:@"%@/%@", pathCache(), className];
    NSString *urlLocal = [NSString stringWithFormat:@"%@/%@", urlDirectorio, aName];
    
    NSString *file = urlLocal;
    CFStringRef fileExtension = (__bridge CFStringRef) [file pathExtension];
    CFStringRef fileUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    
    if (UTTypeConformsTo(fileUTI, kUTTypeImage)){
        [[DMEThumbnailer sharedInstance] generateImageThumbnails:urlLocal afterGenerate:nil completionBlock:nil];
    }
    else if (UTTypeConformsTo(fileUTI, kUTTypeMovie)){
        [[DMEThumbnailer sharedInstance] generateVideoThumbnails:urlLocal afterGenerate:^(UIImage **thumb) {
            //Overlay play
            UIImage *backgroundImage = *thumb;
            UIImage *watermarkImage = [UIImage imageNamed:@"VideoWatermark"];
            CGSize watermarkSize = watermarkImage.size;
            watermarkSize = [[DMEThumbnailer sharedInstance] adjustSizeRetina:watermarkSize];
            UIGraphicsBeginImageContext(backgroundImage.size);
            [backgroundImage drawInRect:CGRectMake(0, 0, backgroundImage.size.width, backgroundImage.size.height)];
            [watermarkImage drawInRect:CGRectMake((backgroundImage.size.width - watermarkSize.width) / 2, (backgroundImage.size.height - watermarkSize.height) / 2, watermarkSize.width, watermarkSize.height)];
            *thumb = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        } completionBlock:nil];
    }
    else if (UTTypeConformsTo(fileUTI, kUTTypePDF)){
        [[DMEThumbnailer sharedInstance] generatePDFThumbnails:urlLocal afterGenerate:nil completionBlock:nil];
    }
    
    CFRelease(fileUTI);
    file = nil;
    urlLocal = nil;
    urlDirectorio = nil;
    className = nil;
}

//Comprueba si un fichero existe
-(BOOL)fileExistWithName:(NSString *)aName ofClass:(NSString *)aClass
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *className = [NSString stringWithFormat:@"%@%@", [[aClass substringToIndex:1] lowercaseString], [aClass substringFromIndex:1]];
    NSString *urlLocal = [NSString stringWithFormat:@"%@/%@/%@", pathCache(), className, aName];
    return [filemgr fileExistsAtPath:urlLocal];
}

//Elimina un fichero
-(BOOL)removeFileWithName:(NSString *)aName ofClass:(NSString *)aClass
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    BOOL resultado = YES;
    
    //Multimedia
    NSString *className = [NSString stringWithFormat:@"%@%@", [[aClass substringToIndex:1] lowercaseString], [aClass substringFromIndex:1]];
    NSString *urlLocal = [NSString stringWithFormat:@"%@/%@/%@", pathCache(), className, aName];
    if ([filemgr isDeletableFileAtPath: urlLocal]) {
        NSError *error = nil;
        [filemgr removeItemAtPath: urlLocal error: &error];
        if(error){
            resultado = NO;
        }
        else{
            [self logDebug:[NSString stringWithFormat:NSLocalizedString(@"Eliminado fichero: %@", nil), urlLocal]];
        }
    }
    else{
        resultado = NO;
    }
    
    return resultado;
}

//Elimina la cache de archivos
-(void)clearCache
{
    [self messageBlock:NSLocalizedString(@"Limpiando cache...", nil) important:YES];
    
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSError *error;
    BOOL isDir = YES;
    
    //Borramos la cache de cada entidad
    for (NSString *aClass in self.registeredClassesToSync) {
        @autoreleasepool {
            NSString *className = [NSString stringWithFormat:@"%@%@", [[aClass substringToIndex:1] lowercaseString], [aClass substringFromIndex:1]];
            NSString *urlLocal = [NSString stringWithFormat:@"%@/%@", pathCache(), className];
            isDir = YES;
            if ([filemgr fileExistsAtPath:urlLocal isDirectory:&isDir] && [filemgr isDeletableFileAtPath: urlLocal]) {
                [filemgr removeItemAtPath: urlLocal error:&error];
                if(error){
                    NSError *error = [self createErrorWithCode:SyncErrorCodeCleanCache
                                                andDescription:NSLocalizedString(@"No se ha podido limpiar la cache", nil)
                                              andFailureReason:NSLocalizedString(@"Ocurrio un error al eliminar ficheros de la cache", nil)
                                         andRecoverySuggestion:NSLocalizedString(@"Compruebe el sistema de ficheros", nil)];
                    [self errorBlock:error fatal:NO];
                }
                else{
                    [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Cache de %@ limpiada", nil), [self logClassName:aClass]] important:NO];
                }
            }
        }
    }
    
    [self messageBlock:NSLocalizedString(@"Se ha terminado de limpiar la cache", nil) important:YES];
    
    [self messageBlock:NSLocalizedString(@"Limpiando cache de miniaturas", nil) important:YES];
    
    //Borramos los thumbs
    NSString *urlLocal = [NSString stringWithFormat:@"%@/Thumbs", pathCache()];
    if ([filemgr fileExistsAtPath:urlLocal isDirectory:&isDir] && [filemgr isDeletableFileAtPath: urlLocal]) {
        [filemgr removeItemAtPath: urlLocal error:&error];
        if(error){
            NSError *error = [self createErrorWithCode:SyncErrorCodeCleanThumbsCache
                                        andDescription:NSLocalizedString(@"No se ha podido limpiar la cache de miniaturas", nil)
                                      andFailureReason:NSLocalizedString(@"Ocurrio un error al eliminar ficheros de la cache", nil)
                                 andRecoverySuggestion:NSLocalizedString(@"Compruebe el sistema de ficheros", nil)];
            [self errorBlock:error fatal:NO];
        }
        else{
            [self messageBlock:NSLocalizedString(@"Se ha terminado de limpiar la cache de miniaturas", nil) important:YES];
        }
    }
}

#pragma mark - Block Utils

-(void)messageBlock:(NSString *)message important:(BOOL)important
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logInfo:message];
    });
    if(self.messageBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.messageBlock(message, important);
        });
    }
}

-(void)progressBlockTotal:(NSInteger)total inMainProcess:(BOOL)main
{
    if(main){
        self.progressCurrent = 0;
        self.progressTotal = total;
    }
    else{
        self.progressSubprocessTotal = total;
    }
    self.progressSubprocessCurrent = 0;
    
    CGFloat current = self.progressCurrent;
    CGFloat totalAux = (CGFloat)self.progressTotal;
    
    if(self.progressBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(current, totalAux);
        });
    }
}

-(void)progressBlockIncrementInMainProcess:(BOOL)main
{
    CGFloat current = 0;
    CGFloat total = self.progressTotal;
    if(main){
        self.progressCurrent += 1;
        self.progressSubprocessCurrent = 0;
        
        current = self.progressCurrent;
    }
    else{
        self.progressSubprocessCurrent += 1;
        
        current = self.progressCurrent+(self.progressSubprocessCurrent/self.progressSubprocessTotal);
    }
    
    if(self.progressBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(current, total);
        });
    }
}

-(void)errorBlock:(NSError *)error fatal:(BOOL)fatal
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self logError:error.localizedDescription];
    });
    if(self.errorBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.errorBlock(error, fatal);
        });
    }
}

#pragma mark - Date Utils

//Inicializa el formateador de fechas
-(void)initializeDateFormatter
{
    if (!self.dateFormatter) {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        [self.dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    }
}

//Convierte la fecha de MySQL a NSDate
-(NSDate *)dateUsingStringFromAPI:(NSString *)dateString
{
    [self initializeDateFormatter];
    
    return [self.dateFormatter dateFromString:dateString];
}

//Convierte la fecha de NSDate a MySQL
-(NSString *)dateStringForAPIUsingDate:(NSDate *)date
{
    [self initializeDateFormatter];
    NSString *dateString = [self.dateFormatter stringFromDate:date];
    // remove Z
    dateString = [dateString substringWithRange:NSMakeRange(0, [dateString length]-1)];
    // add milliseconds and put Z back on
    dateString = [dateString stringByAppendingFormat:@".000Z"];
    
    return dateString;
}


#pragma mark - Log Utils

-(NSString *)logClassName:(NSString *)className
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    return [NSClassFromString(className) performSelector:@selector(localizedEntityName)];
#pragma clang diagnostic pop
}

-(void)logError:(NSString *)aMessage, ...
{
    va_list args;
    va_start(args, aMessage);
    if(self.logLevel == SyncLogLevelVerbose){
        NSLog(@"%@", [[NSString alloc] initWithFormat:aMessage arguments:args]);
    }
    va_end(args);
}

-(void)logInfo:(NSString *)aMessage, ...
{
    va_list args;
    va_start(args, aMessage);
    if(self.logLevel == SyncLogLevelVerbose){
        NSLog(@"%@", [[NSString alloc] initWithFormat:aMessage arguments:args]);
    }
    va_end(args);
}

-(void)logDebug:(NSString *)aMessage, ...
{
    va_list args;
    va_start(args, aMessage);
    if(self.logLevel == SyncLogLevelVerbose){
        NSLog(@"%@", [[NSString alloc] initWithFormat:aMessage arguments:args]);
    }
    va_end(args);
}

@end
