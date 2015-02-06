//
//  GETAPPSyncEngine.m
//  iWine
//
//  Created by David Getapp on 04/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "DMECoreData.h"

NSString * const SyncEngineInitialCompleteKey = @"SyncEngineInitialSyncCompleted";
NSString * const SyncEngineSyncCompletedNotificationName = @"SyncEngineSyncCompleted";
NSString * const SyncEngineSyncErrorNotificationName = @"SyncEngineSyncError";
NSString * const SyncEngineErrorDomain = @"SyncEngineErrorDomain";

typedef void (^RecieveObjectsCompletionBlock)();
typedef void (^SendObjectsCompletionBlock)();
typedef void (^DownloadCompletionBlock)();

@interface DMESyncEngine (){
    NSPredicate *idPredicateTemplate;
    NSPredicate *syncStatusPredicateTemplate;
    NSPredicate *syncStatusNotPredicateTemplate;
    DownloadCompletionBlock downloadCompletionAuxBlock;
}

@property (nonatomic, strong) NSManagedObjectContext *context;

@property (nonatomic, strong) __block NSMutableArray *registeredClassesToSync;
@property (nonatomic, strong) __block NSMutableArray *classesToSync;
@property (nonatomic, strong) __block NSMutableArray *registeredClassesWithFiles;
@property (nonatomic, strong) __block NSMutableArray *registeredClassesWithOptionalFiles;

@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) __block NSMutableDictionary *JSONRecords;
@property (nonatomic, strong) __block NSMutableDictionary *savedEntities;
@property (nonatomic, strong) __block NSMutableArray *filesToDownload;
@property (nonatomic, strong) __block NSOperationQueue *downloadQueue;
@property (nonatomic) __block NSInteger downloadedFiles;
@property (nonatomic) __block CGFloat progressTotal;
@property (nonatomic) __block CGFloat progressCurrent;
@property (nonatomic) __block CGFloat progressSubprocessTotal;
@property (nonatomic) __block CGFloat progressSubprocessCurrent;

@property (nonatomic, strong) SyncStartBlock startBlock;
@property (nonatomic, strong) SyncCompletionBlock completionBlock;
@property (nonatomic, strong) ErrorBlock errorBlock;
@property (nonatomic, strong) ProgressBlock progressBlock;
@property (nonatomic, strong) MessageBlock messageBlock;

@property (nonatomic, strong) NSDate *startDate;

@end

@implementation DMESyncEngine

+ (instancetype)sharedEngine {
    static DMESyncEngine *sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEngine = [[DMESyncEngine alloc] init];
        sharedEngine.downloadFiles = NO;
        sharedEngine.downloadOptionalFiles = NO;
        sharedEngine.autoSyncDelay = 180;
        sharedEngine.logLevel = SyncLogLevelVerbose;
    });
    
    return sharedEngine;
}

#pragma mark - General

//Anade una clase al array para ser sincronizada
- (void)registerNSManagedObjectClassToSync:(Class)aClass {
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
- (void)registerNSManagedObjectClassToSyncWithFiles:(Class)aClass {
    
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
- (void)registerNSManagedObjectClassToSyncWithOptionalFiles:(Class)aClass {
    
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
- (BOOL)initialSyncComplete {
    return [[NSUserDefaults standardUserDefaults] boolForKey:SyncEngineInitialCompleteKey];
}

- (void)blockSync
{
    [self willChangeValueForKey:@"syncInProgress"];
    _syncInProgress = YES;
    [self didChangeValueForKey:@"syncInProgress"];
}

- (void)unblockSync
{
    [self willChangeValueForKey:@"syncInProgress"];
    _syncInProgress = NO;
    [self didChangeValueForKey:@"syncInProgress"];
}

//Guarda la primera sincronizacion
- (void)setInitialSyncCompleted {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SyncEngineInitialCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setInitialSyncIncompleted {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SyncEngineInitialCompleteKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSError *)createErrorWithCode:(SyncErrorCode)aCode andDescription:(NSString *)aDescription andFailureReason:(NSString *)aReason andRecoverySuggestion:(NSString *)aSuggestion
{
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: aDescription,
                               NSLocalizedFailureReasonErrorKey: aReason,
                               NSLocalizedRecoverySuggestionErrorKey: aSuggestion};
    return [NSError errorWithDomain:SyncEngineErrorDomain code:aCode userInfo:userInfo];
}

- (void)checkStartConditionsNeedInstall:(BOOL)needInstall completionBlock:(void (^)())completionBlock
{
    self.context = [DMECoreDataStack sharedInstance].backgroundContext;
    
    [self.context performBlock:^{
        if(!self.initialSyncComplete && needInstall){
            //Si no esta instalado
            NSError *error = [self createErrorWithCode:SyncErrorCodeInstalation
                                        andDescription:NSLocalizedString(@"No se ha iniciado una instalación inicial", nil)
                                      andFailureReason:NSLocalizedString(@"El método requiere de una instalación inicial", nil)
                                 andRecoverySuggestion:NSLocalizedString(@"Realice primero una instalación inicial", nil)];
            [self errorBlock:error fatal:YES];
            [self executeSyncErrorOperations];
        }
        else{
            if (!self.syncInProgress) {
                if([AFNetworkReachabilityManager sharedManager].reachable){
                    if(completionBlock){
                        completionBlock();
                    }
                }
                else{
                    //Si no tiene internet
                    NSError *error = [self createErrorWithCode:SyncErrorCodeConnection
                                                andDescription:NSLocalizedString(@"No tiene conexión a internet", nil)
                                              andFailureReason:NSLocalizedString(@"Ha fallado al conectar con el servidor", nil)
                                         andRecoverySuggestion:NSLocalizedString(@"Compruebe su conexión", nil)];
                    [self errorBlock:error fatal:YES];
                    [self executeSyncErrorOperations];
                }
            }
        }
    }];
}

#pragma mark - Start Sync

//Comienza la sincronizacion

- (void)startSync:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
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

//Repite la sincronizacion periodicamente
- (void)autoSync:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock{
    [self checkStartConditionsNeedInstall:YES completionBlock:^{
        //Si tenemos wifi sincronizamos de forma automática
        [self startSync:startBlock withCompletionBlock:completionBlock withProgressBlock:progressBlock withMessageBlock:messageBlock withErrorBlock:errorBlock];
    }];
    
    [self performBlock:^{
        [self autoSync:startBlock withCompletionBlock:completionBlock withProgressBlock:progressBlock withMessageBlock:messageBlock withErrorBlock:errorBlock];
    } afterDelay:self.autoSyncDelay];
}

//Enviar datos
- (void)pushDataToServer:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
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

//Recibir datos
- (void)fetchDataFromServer:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
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

//Download files
- (void)downloadFiles:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock
{
    [self checkStartConditionsNeedInstall:YES completionBlock:^{
        //Inicializamos la sincronizacion
        self.startBlock = startBlock;
        self.completionBlock = completionBlock;
        self.progressBlock = progressBlock;
        self.messageBlock = messageBlock;
        self.errorBlock = errorBlock;
        
        [self executeSyncStartOperations:^{
            [self progressBlockTotal:self.downloadFiles ? 1 : 0 inMainProcess:YES];
            
            ///Enviamos los datos
            [self downloadFiles:^{
                [self executeSyncCompletedOperations];
            }];
        }];
    }];
}


#pragma mark - Start/End Sync Operations

//Comienzo de la sincronizacion
-(void)executeSyncStartOperations:(void (^)())completionBlock {
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
    
    [self willChangeValueForKey:@"syncInProgress"];
    _syncInProgress = YES;
    [self didChangeValueForKey:@"syncInProgress"];
    
    [[DMECoreDataStack sharedInstance] saveWithCompletionBlock:^(BOOL didSave, NSError *error) {
        if(!error){
            if(self.startBlock){
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.startBlock();
                });
            }
            
            [self.context performBlock:^{
                completionBlock();
            }];
        }
        else{
            [self logError:@"Error when save main context: %@",error];
        }
    }];
}

//Final de la sincronizacion
- (void)executeSyncCompletedOperations {
    [self cleanEngine];
    
    [self messageBlock:NSLocalizedString(@"Proceso terminado", nil) important:YES];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setInitialSyncCompleted];
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineSyncCompletedNotificationName object:nil];
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = NO;
        [self didChangeValueForKey:@"syncInProgress"];
        
        //Llamamos al bloque de completar
        if(self.completionBlock){
            self.completionBlock();
        }
    });
}

//Error en la sincronizacion
- (void)executeSyncErrorOperations {
    [self cleanEngine];
    
    [self messageBlock:NSLocalizedString(@"Terminando proceso tras un error...", nil) important:YES];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SyncEngineSyncErrorNotificationName object:nil];
        [self willChangeValueForKey:@"syncInProgress"];
        _syncInProgress = NO;
        [self didChangeValueForKey:@"syncInProgress"];
    });
}

#pragma mark - Core Data

//Crea un objeto Core Data a partir de un registro JSON
- (NSManagedObject *)newManagedObjectWithClassName:(NSString *)className forRecord:(NSDictionary *)record {

    //Creamos el nuevo objeto
    NSManagedObject *newManagedObject = [NSEntityDescription insertNewObjectForEntityForName:className inManagedObjectContext:self.context];
    [newManagedObject setValue:[[record objectForKey:className] objectForKey:@"id"] forKey:@"id"];  //Nos aseguramos de que tenga id
    
    //Recorremos las relaciones
    for (NSString* key in record) {
        //Si es el objeto principal lo creamos
        if([className isEqualToString:key]){
            [[record objectForKey:className] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                [self setValue:obj forKey:key forManagedObject:newManagedObject];
            }];
            [newManagedObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
        }
        else if([[record objectForKey:key] isKindOfClass:[NSDictionary class]]){ //Si es otro objeto comprobamos si existe y si no lo creamos
            //Creamos la relacion con el objeto principal
            [self updateRelation:className ofManagedObject:newManagedObject withClassName:key withRecord:[record objectForKey:key]];
        }
        else if([[record objectForKey:key] isKindOfClass:[NSArray class]]){
            for(NSDictionary *relationObject in [record objectForKey:key]){
                //Creamos la relacion con el objeto principal
                [self updateRelation:className ofManagedObject:newManagedObject withClassName:key withRecord:relationObject];
            }
        }
    }
    
    if(![self.savedEntities objectForKey:className]){
        [self.savedEntities setObject:[NSMutableDictionary dictionary] forKey:className];
    }
    
    [[self.savedEntities objectForKey:className] setObject:newManagedObject forKey:[[record objectForKey:className] objectForKey:@"id"]];
    [self logDebug:@"   Saved %@ with id: %@", className, [[record objectForKey:className] objectForKey:@"id"]];
    return newManagedObject;
}

//Actualiza un objeto Core Data a partir de un registro JSON
- (NSManagedObject *)updateManagedObject:(NSManagedObject *)managedObject withClassName:(NSString *)className withRecord:(NSDictionary *)record {
    //Recorremos las relaciones
    for (NSString* key in record) {
        //Si es el objeto principal lo actualizamos
        if([className isEqualToString:key]){
            [[record objectForKey:className] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                [self setValue:obj forKey:key forManagedObject:managedObject];
            }];
        }
        else if([[record objectForKey:key] isKindOfClass:[NSDictionary class]]){ //Si es otro objeto comprobamos actualizamos la relacion
            //Creamos la relacion con el objeto principal
            [self updateRelation:className ofManagedObject:managedObject withClassName:key withRecord:[record objectForKey:key]];
        }
        else if([[record objectForKey:key] isKindOfClass:[NSArray class]]){ //Relación con varios objetos
            
            if(self.initialSyncComplete){
                //Vaciamos la relacion multiple
                [self truncateRelation:className ofManagedObject:managedObject withClassName:key];
                
                //Volvemos a crearla
                for(NSDictionary *relationObject in [record objectForKey:key]){
                    //Creamos la relacion con el objeto principal
                    [self updateRelation:className ofManagedObject:managedObject withClassName:key withRecord:relationObject];
                }
            }
        }
    }
    [self logDebug:@"   Updated %@ with id: %@", className, [[record objectForKey:className] objectForKey:@"id"]];
    return managedObject;
}

//Vacia una relacion
-(void) truncateRelation:(NSString *)relation ofManagedObject:(NSManagedObject *)managedObject withClassName:(NSString *)className {
    //Obtenemos el nombre de la relacion
    NSString *relationName = [self nameFromClassName:&className relation:relation];
    
    //Comprobamos si la relacion es a uno o a varios
    NSEntityDescription *entityDescription = [managedObject entity];
    NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
    
    NSString *inverseRelationName = [[[[relationsDictionary allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        NSRelationshipDescription *relationship = (NSRelationshipDescription *)evaluatedObject;
        return [[[relationship inverseRelationship] name] isEqualToString:relationName] && [[[relationship destinationEntity] name] isEqualToString:className];
    }]] firstObject] name];
    
    //Comprobamos si la relacion es a uno o a varios
    if([relationsDictionary objectForKey:inverseRelationName]){
        if([managedObject valueForKey:inverseRelationName]){
            [managedObject setValue:nil forKey:inverseRelationName];
        }
    }
}

//Actualiza las relaciones de un objeto Core Data a partir del JSON
- (NSManagedObject *) updateRelation:(NSString *)relation ofManagedObject:(NSManagedObject *)managedObject withClassName:(NSString *)className withRecord:(NSDictionary *)record {
    NSManagedObject *newRelationManagedObject = nil;
    
    if(![[record objectForKey:@"id"] isKindOfClass:[NSNull class]]){
        //Obtenemos el nombre de la relacion
        NSString *relationName = [self nameFromClassName:&className relation:relation];
        
        if(self.initialSyncComplete){
            newRelationManagedObject = [self managedObjectForClass:className withId:[record objectForKey:@"id"]];
        }
        else{
            newRelationManagedObject = [[self.savedEntities objectForKey:className] objectForKey:[record objectForKey:@"id"]];
        }
        
        if(!newRelationManagedObject){
            newRelationManagedObject = [self newManagedObjectWithClassName:className forRecord:[NSDictionary dictionaryWithObject:record forKey:className]];
        }
        else{
            newRelationManagedObject = [self updateManagedObject:newRelationManagedObject withClassName:className withRecord:[NSDictionary dictionaryWithObject:record forKey:className]];
        }
        
        //Comprobamos si la relacion es a uno o a varios
        NSEntityDescription *entityDescription = [newRelationManagedObject entity];
        NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
        
        //Comprobamos si la relacion es a uno o a varios
        if([relationsDictionary objectForKey:relationName]){
            if([[relationsDictionary objectForKey:relationName] isToMany]){
                //Comprobamos si la inversa es tambiena  varios
                if([[[relationsDictionary objectForKey:relationName] inverseRelationship] isToMany]){
                    SEL selector = NSSelectorFromString([NSString stringWithFormat:@"add%@Object:", className]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [managedObject performSelector:selector withObject:[newRelationManagedObject objectInContext:managedObject.managedObjectContext]];
#pragma clang diagnostic pop
                }
                else{
                    //Obtenemos la relacion inversa
                    relationName = [[[relationsDictionary objectForKey:relationName] inverseRelationship] name];
                    
                    [managedObject setValue:[newRelationManagedObject objectInContext:managedObject.managedObjectContext] forKey:relationName];
                }
            }
            else{
                [newRelationManagedObject setValue:[managedObject objectInContext:newRelationManagedObject.managedObjectContext] forKey:relationName];
            }
            [self logDebug:@"   Updated relation %@ with id: %@", relationName, [record objectForKey:@"id"]];
        }
    }
    else{
        //Obtenemos el nombre de la relacion
        NSString *relationName = [self nameFromClassName:&className relation:relation];
        
        //Comprobamos si la relacion es a uno o a varios
        NSEntityDescription *entityDescription = [managedObject entity];
        NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
        
        NSString *inverseRelationName = [[[[relationsDictionary allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            NSRelationshipDescription *relationship = (NSRelationshipDescription *)evaluatedObject;
            return [[[relationship inverseRelationship] name] isEqualToString:relationName] && [[[relationship destinationEntity] name] isEqualToString:className];
        }]] firstObject] name];
        
        //Comprobamos si la relacion es a uno o a varios
        if([relationsDictionary objectForKey:inverseRelationName]){
            if(![[relationsDictionary objectForKey:inverseRelationName] isToMany]){
                if([managedObject valueForKey:inverseRelationName]){
                    [managedObject setValue:nil forKey:inverseRelationName];
                }
            }
        }
    }
    
    return newRelationManagedObject;
}

-(NSString *)nameFromClassName:(NSString **)className relation:(NSString *)relation{
    //Obtenemos el nombre de la relacion
    NSString *relationName;
    NSArray *classNameParts = [*className componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_"]];
    if([classNameParts count]>1){
        *className = [classNameParts objectAtIndex:0];
        relationName = [[[[[classNameParts objectAtIndex:0] substringToIndex:1] lowercaseString] stringByAppendingString:[[classNameParts objectAtIndex:0] substringFromIndex:1]] stringByAppendingString:[classNameParts objectAtIndex:1]];
    }
    else{
        relationName = [[[relation substringToIndex:1] lowercaseString] stringByAppendingString:[relation substringFromIndex:1]];
    }
    return relationName;
}

//Introduce un valor en una propiedad de un objeto Core Data
- (void)setValue:(id)value forKey:(NSString *)key forManagedObject:(NSManagedObject *)managedObject {
    //Si el objeto tiene esa propiedad
    if([managedObject respondsToSelector:NSSelectorFromString(key)] && ![managedObject isFault]){
        //Si es nulo lo convertimos en nil
        if([value isKindOfClass:[NSNull class]]){
            value = nil;
        }
        
        //Según el tipo asignamos el valor
        if ([[[managedObject.entity.propertiesByName objectForKey:key] attributeValueClassName] isEqualToString:@"NSDate"]) {    //Si es una fecha
            if([value length] == 10){
                value = [value stringByAppendingString:@" 00:00:00"];
            }
            NSDate *date = [self dateUsingStringFromAPI:value];
            [managedObject setValue:date forKey:key];
        } else if ([[[managedObject.entity.propertiesByName objectForKey:key] attributeValueClassName] isEqualToString:@"NSNumber"]) {    //Si es un numero
            if([value isKindOfClass:[NSString class]]){
                [managedObject setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:key];
                
            }else{
                [managedObject setValue:[NSNumber numberWithDouble:[value doubleValue]] forKey:key];
            }
        } else {    //Si es una cadena
            [managedObject setValue:value forKey:key];
        }
    }
}

- (NSPredicate *)idPredicateTemplate {
    if (idPredicateTemplate == nil) {
        idPredicateTemplate = [NSPredicate predicateWithFormat:@"id = $ID"];
    }
    return idPredicateTemplate;
}

- (NSPredicate *)syncStatusPredicateTemplate {
    if (syncStatusPredicateTemplate == nil) {
        syncStatusPredicateTemplate = [NSPredicate predicateWithFormat:@"syncStatus = $SYNC_STATUS"];
    }
    return syncStatusPredicateTemplate;
}

- (NSPredicate *)syncStatusNotPredicateTemplate {
    if (syncStatusNotPredicateTemplate == nil) {
        syncStatusNotPredicateTemplate = [NSPredicate predicateWithFormat:@"syncStatus != $SYNC_STATUS"];
    }
    return syncStatusNotPredicateTemplate;
}

//Obtiene todos los objetos Core Data que tengan un estado de sincronizacion determinado
- (NSArray *)managedObjectsForClass:(NSString *)className withSyncStatus:(ObjectSyncStatus)syncStatus {
    __block NSArray *results = nil;
    NSManagedObjectContext *managedObjectContext = self.context;
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    [fetchRequest setPredicate:[[self syncStatusPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:syncStatus]}]];
    
    [self.context performBlockAndWait:^{
        NSError *error = nil;
        results = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    
    return results;
}

//Obtiene todos los objetos Core Data que NO tengan un estado de sincronizacion determinado
- (NSArray *)managedObjectsForClass:(NSString *)className withPredicate:(NSPredicate *)predicate {
    NSManagedObjectContext *managedObjectContext = self.context;
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    if(predicate != nil){
        [fetchRequest setPredicate:predicate];
    }
    
    __block NSArray *objects = nil;
    [self.context performBlockAndWait:^{
        NSError *error = nil;
        objects = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    
    return objects;
}

- (NSArray *)managedObjectsForClass:(NSString *)className {
    return [self managedObjectsForClass:className withPredicate:nil];
}

//Obtiene el objeto Core Data con un id
- (NSManagedObject *)managedObjectForClass:(NSString *)className withId:(NSString *)aId {
    NSManagedObjectContext *managedObjectContext = self.context;
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    [fetchRequest setFetchLimit:1];
    [fetchRequest setPredicate:[[self idPredicateTemplate] predicateWithSubstitutionVariables:@{@"ID": aId}]];
    
    __block NSManagedObject *object = nil;
    [self.context performBlockAndWait:^{
        NSError *error = nil;
        object = [[managedObjectContext executeFetchRequest:fetchRequest error:&error] lastObject];
    }];
    
    return object;
}

//Obtiene los objetos Core Data de un tipo que esten en el array de ids
- (NSArray *)managedObjectsForClass:(NSString *)className sortedByKey:(NSString *)key usingArrayOfIds:(NSArray *)idArray inArrayOfIds:(BOOL)inIds {
    __block NSArray *results = nil;
    NSManagedObjectContext *managedObjectContext = self.context;
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:className];
    NSPredicate *predicate;
    //TODO Optimizar a fuego
    if (inIds) {
        predicate = [NSPredicate predicateWithFormat:@"id IN %@", idArray];
    } else {
        predicate = [NSPredicate predicateWithFormat:@"NOT (id IN %@)", idArray];
    }
    NSPredicate *syncPredicate = [[self syncStatusNotPredicateTemplate] predicateWithSubstitutionVariables:@{@"SYNC_STATUS": [NSNumber numberWithInteger:ObjectNotSync]}];
    NSPredicate *andPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:syncPredicate, predicate, nil]];
    
    [fetchRequest setPredicate:andPredicate];
    [fetchRequest setReturnsObjectsAsFaults:YES];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES selector:@selector(localizedStandardCompare:)]]];
    
    [self.context performBlockAndWait:^{
        NSError *error = nil;
        results = [managedObjectContext executeFetchRequest:fetchRequest error:&error];
    }];
    
    return results;
}

- (void)saveContext:(void (^)(BOOL result))success
{
    [self.context performBlockAndWait:^{
        BOOL result = YES;
        
        if(self.context.hasChanges){
            // Execute the sync completion operations as this is now the final step of the sync process
            NSError *error = nil;
            
            if (![self.context save:&error]){
                NSLog(@"Unresolved error %@", error);
                //NSLog(@"Unresolved error %@", [error userInfo]);
                //NSLog(@"Unresolved error %@", [error localizedDescription]);
                
                NSError *error = [self createErrorWithCode:SyncErrorCodeSaveContext
                                            andDescription:NSLocalizedString(@"No se han podido guardar los datos", nil)
                                          andFailureReason:NSLocalizedString(@"Ha fallado al guardar el contexto", nil)
                                     andRecoverySuggestion:NSLocalizedString(@"Compruebe la integridad de los datos", nil)];
                [self errorBlock:error fatal:YES];
                [self executeSyncErrorOperations];
                
                result = NO;
            }
        }
        
        if(result){
            [[DMECoreDataStack sharedInstance] saveWithCompletionBlock:^(BOOL didSave, NSError *error) {
                if(!error){
                    success(YES);
                }
                else{
                    [self logError:@"Error when save main context: %@", error];
                    success(NO);
                }
            }];
        }
        else{
            success(NO);
        }
        
        
    }];
}

#pragma mark - JSON Data Management

//Devuelve los valores descargados para una clase
- (NSArray *)JSONArrayForClassWithName:(NSString *)className{
    return [self JSONArrayForClassWithName:className modifiedAfter:nil];
}

//Devuelve los valores descargados para una clase modificados a partir de una fecha o que no esten en la base de datos
- (NSArray *)JSONArrayForClassWithName:(NSString *)className modifiedAfter:(NSDate *)aDate {
    if(aDate){
        NSArray *objects = [[self managedObjectsForClass:className] valueForKey:@"id"];
        //TODO: Optimizar a fuego
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"NOT(%K.id IN %@) OR %K.modified > %@", className, objects, className, [aDate description]];
        return [[self.JSONRecords objectForKey:className] filteredArrayUsingPredicate:pred];
    }
    else{
        return [self.JSONRecords objectForKey:className];
    }
}

//Devuelve los valores descargados para una clase ordenados por un campo
- (NSArray *)JSONDataRecordsForClass:(NSString *)className sortedByKey:(NSString *)key {
    return [self JSONDataRecordsForClass:className sortedByKey:key modifiedAfter:nil];
}

//Devuelve los valores descargados para una clase ordenados por un campo y modificados a partir de una fecha
- (NSArray *)JSONDataRecordsForClass:(NSString *)className sortedByKey:(NSString *)key modifiedAfter:(NSDate *)aDate {
    NSArray *JSONArray = [self JSONArrayForClassWithName:className modifiedAfter:aDate];
    NSArray *result = [JSONArray sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        if([[[(NSDictionary*)a objectForKey:className] objectForKey:key] isKindOfClass:[NSString class]]){
            NSString *first = [[(NSDictionary*)a objectForKey:className] objectForKey:key];
            NSString *second = [[(NSDictionary*)b objectForKey:className] objectForKey:key];
            
            return [first localizedStandardCompare:second];
        }
        else{
            NSInteger first = [[[(NSDictionary*)a objectForKey:className] objectForKey:key] integerValue];
            NSInteger second = [[[(NSDictionary*)b objectForKey:className] objectForKey:key] integerValue];
            if (first > second)
                return NSOrderedDescending;
            if (first < second)
                return NSOrderedAscending;
            return NSOrderedSame;
        }
    }];
    return result;
}

#pragma mark - Syncronize Steps

#pragma mark Receive Data

//Descarga los datos de sincronizacion
-(void)downloadSyncEntitiesForSync:(RecieveObjectsCompletionBlock)completionBlock {
    [self.context performBlock:^{
        [self messageBlock:NSLocalizedString(@"Descargando información de sincronización...", nil) important:YES];
        
        [[DMEAPIEngine sharedInstance] fetchEntitiesForSync:^(NSArray *objects, NSError *error) {
            [self progressBlockIncrementInMainProcess:YES];
            
            [self.context performBlock:^{
                if(!error){
                    self.classesToSync = [NSMutableArray array];
                    
                    for (NSString *className in self.registeredClassesToSync) {
                        if([objects containsObject:className]){
                            [self.classesToSync addObject:className];
                        }
                    }
                    
                    [self messageBlock:NSLocalizedString(@"Información de sincronización descargada", nil) important:YES];
                    
                    [self saveContext:^(BOOL result) {
                        if(result){
                            [self downloadJSONForRegisteredObjects:completionBlock];
                        }
                    }];
                }
                else{
                    NSError *errorSync = nil;
                    
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
                        errorSync = [self createErrorWithCode:SyncErrorCodeDownloadSyncInfo
                                               andDescription:NSLocalizedString(@"Error al descargar la información de la sincronización", nil)
                                             andFailureReason:NSLocalizedString(@"Ha fallado el servicio web de sincronización", nil)
                                        andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web y su conexión", nil)];
                    }
                    
                    [self errorBlock:errorSync fatal:YES];
                    
                    [self executeSyncErrorOperations];
                }
            }];
        }];
    }];
}

//Descarga los datos de las clases registradas
- (void)downloadJSONForRegisteredObjects:(RecieveObjectsCompletionBlock)completionBlock {
    [self.context performBlock:^{
        self.savedEntities = [NSMutableDictionary dictionary];
        
        __block NSError *errorSync = nil;
        
        // Create a dispatch group
        __block dispatch_group_t group = dispatch_group_create();
        
        [self messageBlock:NSLocalizedString(@"Descargando información...", nil) important:YES];
        
        [self progressBlockTotal:self.classesToSync.count inMainProcess:NO];
        
        for (NSString *className in self.classesToSync) {
            // Enter the group for each request we create
            dispatch_group_enter(group);
            
            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Descargando información de %@...", nil), [self logClassName:className]] important:NO];
            
            //Obtenemos los objetos de la clase
            [[DMEAPIEngine sharedInstance] fetchObjectsForClass:className withParameters:nil onCompletion:^(NSArray *objects, NSError *error) {
                [self progressBlockIncrementInMainProcess:NO];
                
                [self.context performBlock:^{
                    if(!error){
                        [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Información de %@ descargada", nil), [self logClassName:className]] important:NO];
                        
                        if (objects.count > 0) {
                            //Escribimos el resultado en memoria
                            [self.JSONRecords setObject:[objects objectAtIndex:0] forKey:className];
                        }
                    }
                    else{
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
                                                   andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se han podido descargar los datos de %@", nil), className]
                                                 andFailureReason:NSLocalizedString(@"Ha fallado alguno de los servicios web", nil)
                                            andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web y su conexión", nil)];
                        }
                    }
                    
                    // Leave the group as soon as the request succeeded
                    dispatch_group_leave(group);
                }];
            }];
        }
        
        // Here we wait for all the requests to finish
        dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self progressBlockIncrementInMainProcess:YES];
            [self.context performBlock:^{
                if(!errorSync){
                    // Do whatever you need to do when all requests are finished
                    [self messageBlock:NSLocalizedString(@"Descargada toda la información", nil) important:YES];
                    
                    [self processJSONDataRecordsIntoCoreData:completionBlock];
                }
                else{
                    [self errorBlock:errorSync fatal:YES];
                    
                    [self executeSyncErrorOperations];
                }
            }];
        });
    }];
}

- (void)processJSONDataRecordsIntoCoreData:(RecieveObjectsCompletionBlock)completionBlock {
    [self.context performBlock:^{
        NSMutableDictionary *JSONData = [NSMutableDictionary dictionary];
        
        // Calculamos el progreso
        NSInteger total = 0;
        for (NSString *className in self.classesToSync) {
            
            if (![self initialSyncComplete]){
                // If this is the initial sync then the logic is pretty simple, you will fetch the JSON data from disk
                // for the class of the current iteration and create new NSManagedObjects for each record
                [JSONData setObject:[self JSONArrayForClassWithName:className] forKey:className];
            }
            else{
                // Otherwise you need to do some more logic to determine if the record is new or has been updated.
                // First get the downloaded records from the JSON response, verify there is at least one object in
                // the data, and then fetch all records stored in Core Data whose objectId matches those from the JSON response.
                [JSONData setObject:[self JSONDataRecordsForClass:className sortedByKey:@"id"] forKey:className];
            }
            total += [(NSArray *)[JSONData objectForKey:className] count];
        }
        
        [self progressBlockTotal:total inMainProcess:NO];
        
        // Iterate over all registered classes to sync
        for (NSString *className in self.classesToSync) {
            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Guardando información de %@ (%@ objetos)...", nil), [self logClassName:className], [NSNumber numberWithInteger:[[JSONData objectForKey:className] count]]] important:NO];
            
            if (![self initialSyncComplete]) { // import all downloaded data to Core Data for initial sync
                for (NSDictionary *record in [JSONData objectForKey:className]) {
                    NSManagedObject *managedObject = [[self.savedEntities objectForKey:className] objectForKey:[[record objectForKey:className] objectForKey:@"id"]];
                    if(!managedObject){
                        [self newManagedObjectWithClassName:className forRecord:record];
                    }
                    else{
                        [self updateManagedObject:managedObject withClassName:className withRecord:record];
                    }
                    
                    [self progressBlockIncrementInMainProcess:NO];
                }
            }
            else {
                NSArray *storedManagedObjects = [self managedObjectsForClass:className withPredicate:[NSPredicate predicateWithFormat:@"id != nil"]];
                
                NSEnumerator *JSONEnumerator = [[JSONData objectForKey:className] objectEnumerator];
                NSEnumerator *fetchResultsEnumerator = [storedManagedObjects objectEnumerator];
                
                NSDictionary *record = [JSONEnumerator nextObject];
                NSManagedObject *storedManagedObject = [fetchResultsEnumerator nextObject];
                
                while (record) {
                    NSString *id = nil;
                    
                    if([[record objectForKey:className] isKindOfClass:[NSDictionary class]]){
                        id = [[record objectForKey:className] valueForKey:@"id"];
                    }
                    
                    if(id && ![id isEqualToString:@""]){
                        if([id isEqualToString:[storedManagedObject valueForKey:@"id"]]){
                            if([[self dateUsingStringFromAPI:[[record objectForKey:className] valueForKey:@"modified"]] compare:[storedManagedObject valueForKey:@"modified"]] == NSOrderedDescending){
                                [self updateManagedObject:storedManagedObject withClassName:className withRecord:record];
                            }
                            
                            //Avanzamos ambos cursores
                            record = [JSONEnumerator nextObject];
                            storedManagedObject = [fetchResultsEnumerator nextObject];
                            
                            [self progressBlockIncrementInMainProcess:NO];
                        }
                        else{
                            if([self managedObjectForClass:className withId:id]){
                                storedManagedObject = [fetchResultsEnumerator nextObject];
                            }
                            else{
                                [self newManagedObjectWithClassName:className forRecord:record];
                                record = [JSONEnumerator nextObject];
                                
                                [self progressBlockIncrementInMainProcess:NO];
                            }
                        }
                    }
                    else{
                        NSError *errorSync = [self createErrorWithCode:SyncErrorCodeNoId
                                                        andDescription:[NSString stringWithFormat:NSLocalizedString(@"La información descargada de %@ no tiene ID", nil), [self logClassName:className]]
                                                      andFailureReason:NSLocalizedString(@"La entidad descargada no tiene ID", nil)
                                                 andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                        [self errorBlock:errorSync fatal:YES];
                        [self executeSyncErrorOperations];
                        
                        return;
                    }
                }
            }
            
            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Información de %@ guardada", nil), [self logClassName:className]] important:NO];
        }
        
        self.savedEntities = [NSMutableDictionary dictionary];
        
        [self messageBlock:NSLocalizedString(@"Toda la información ha sido guardada", nil) important:YES];
        [self progressBlockIncrementInMainProcess:YES];
        
        [self processJSONDataRecordsForDeletion:completionBlock];
    }];
}

- (void)processJSONDataRecordsForDeletion:(RecieveObjectsCompletionBlock)completionBlock {
    NSManagedObjectContext *managedObjectContext = self.context;
    
    // Iterate over all registered classes to sync
    if(self.initialSyncComplete){
        [self progressBlockTotal:self.classesToSync.count inMainProcess:NO];
        
        for (NSString *className in self.classesToSync) {
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
            }
            
            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Limpiando información de %@ (%@ objetos)...", nil), [self logClassName:className], [NSNumber numberWithInteger:[storedRecords count]]] important:NO];
            
            // Schedule the NSManagedObject for deletion
            for (NSManagedObject *managedObject in storedRecords) {
                [self logDebug:@"   Deleted %@", className];
                [self.context performBlockAndWait:^{
                    [managedObjectContext deleteObject:managedObject];
                }];
            }
            
            [self progressBlockIncrementInMainProcess:NO];
            
            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Información de %@ limpiada", nil), [self logClassName:className]] important:NO];
        }
        
        [self messageBlock:NSLocalizedString(@"Se ha finalizado la limpieza de datos", nil) important:YES];
        [self progressBlockIncrementInMainProcess:YES];
    }
    
    self.JSONRecords = [NSMutableDictionary dictionary];
    
    [self messageBlock:NSLocalizedString(@"Guardando los datos...", nil) important:YES];
    
    [self saveContext:^(BOOL result) {
        if(result){
            //Send syncstate remove order
            if(self.classesToSync.count > 0 && self.initialSyncComplete){
                [[DMEAPIEngine sharedInstance] pushEntitiesSynchronized:self.startDate onCompletion:^(NSDictionary *object, NSError *error) {
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
                        }
                    }];
                }];
            }
            
            [self messageBlock:NSLocalizedString(@"Se han guardado los datos", nil) important:YES];
            
            if(completionBlock){
                completionBlock();
            }
        }
    }];
}

#pragma mark Send Data

//Envia los objetos creados localmente al servidor
- (void)postLocalObjectsToServer:(SendObjectsCompletionBlock)completionBlock {
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

- (void)postLocalObjectsToServerOfClassWithId:(NSInteger)index completionBlock:(void (^)())completionBlock {
    if(index >= self.registeredClassesToSync.count){
        if(completionBlock){
            completionBlock();
        }
    }
    else{
        if(self.initialSyncComplete && self.registeredClassesToSync.count > 0){
            [self progressBlockIncrementInMainProcess:NO];
            
            NSString *className = [self.registeredClassesToSync objectAtIndex:index];
            
            // Fetch all objects from Core Data whose syncStatus is equal to SDObjectCreated
            NSArray *objectsToCreate = [self managedObjectsForClass:className withSyncStatus:ObjectCreated];
            
            if(objectsToCreate.count > 0){
                // Create a dispatch group
                __block dispatch_group_t groupGeneral = dispatch_group_create();
                
                // Iterate over all fetched objects who syncStatus is equal to SDObjectCreated
                for (NSManagedObject *objectToCreate in objectsToCreate) {
                    // Get the JSON representation of the NSManagedObject
                    NSDictionary *jsonString = [objectToCreate JSONToObjectOnServer];
                    NSDictionary *filesURL = [objectToCreate filesURLToObjectOnServer];
                    
                    if(jsonString && jsonString.count > 0){
                        // Enter the group for each request we create
                        dispatch_group_enter(groupGeneral);
                        
                        [[DMEAPIEngine sharedInstance] pushObjectForClass:className parameters:jsonString files:filesURL onCompletion:^(NSDictionary *object, NSError *error) {
                            [self.context performBlock:^{
                                if(!error){
                                    if(object.count > 0){
                                        for (NSString* key in object) {
                                            if([[object objectForKey:key] isKindOfClass:[NSArray class]]){
                                                
                                                //Obtenemos el nombre de la relacion
                                                NSString *className2 = (NSString *)[className copy];
                                                NSString *relationName = [self nameFromClassName:&className2 relation:key];
                                                
                                                //Obtenemos los objetos de la relacion
                                                NSArray *objectsToUpdate = [(NSSet *)[objectToCreate valueForKey:relationName] allObjects];
                                                
                                                if(objectsToUpdate.count == [(NSArray *)[object objectForKey:key] count]){
                                                    //Volvemos a crear los objetos
                                                    NSInteger i = 0;
                                                    for (NSDictionary *record in [object objectForKey:key]) {
                                                        if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"created"]){
                                                            NSManagedObject *relationObject = [objectsToUpdate objectAtIndex:i];
                                                            
                                                            NSDate *createdDate = [self dateUsingStringFromAPI:[record valueForKey:@"created"]];
                                                            NSDate *modifiedDate = [self dateUsingStringFromAPI:[record valueForKey:@"modified"]];
                                                            [relationObject setValue:createdDate forKey:@"created"];
                                                            [relationObject setValue:modifiedDate forKey:@"modified"];
                                                            [relationObject setValue:[record valueForKey:@"id"] forKey:@"id"];
                                                            [relationObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                        }
                                                        i++;
                                                    }
                                                }
                                                
                                                
                                            }
                                            else if ([[object objectForKey:key] isKindOfClass:[NSDictionary class]]){
                                                if([key isEqualToString:className]){
                                                    NSDictionary *record = [object objectForKey:key];
                                                    
                                                    if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"created"] && [record valueForKey:@"modified"]){
                                                        [self updateManagedObject:objectToCreate withClassName:className withRecord:@{className: record}];
                                                        [objectToCreate setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                    }
                                                }
                                            }
                                        }
                                        
                                        [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Se ha creado el %@ con id %@", nil), [self logClassName:[[objectToCreate entity] name]], [objectToCreate valueForKey:@"id"]] important:NO];
                                        
                                        [self saveContext:^(BOOL result) {
                                            dispatch_group_leave(groupGeneral);
                                        }];
                                    }
                                    else{
                                        NSError *error = [self createErrorWithCode:SyncErrorCodeCreateInfo
                                                                    andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido enviar el %@ al servidor", nil), [self logClassName:className]]
                                                                  andFailureReason:NSLocalizedString(@"Ha fallado la respuesta del servicio web", nil)
                                                             andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                        [self errorBlock:error fatal:NO];
                                        
                                        dispatch_group_leave(groupGeneral);
                                    }
                                }
                                else{
                                    NSError *error = [self createErrorWithCode:SyncErrorCodeCreateInfo
                                                                andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido enviar el %@ al servidor", nil), [self logClassName:className]]
                                                              andFailureReason:NSLocalizedString(@"Ha fallado la respuesta del servicio web", nil)
                                                         andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                    [self errorBlock:error fatal:NO];
                                    
                                    dispatch_group_leave(groupGeneral);
                                }
                            }];
                        }];
                    }
                }
                
                dispatch_group_notify(groupGeneral, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    [self.context performBlock:^{
                        [self postLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                    }];
                });
            }
            else{
                [self postLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
            }
        }
        else{
            [self postLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
        }
    }
}

//Envia los objetos actualizados localmente al servidor
- (void)updateLocalObjectsToServer:(SendObjectsCompletionBlock)completionBlock {
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


- (void)updateLocalObjectsToServerOfClassWithId:(NSInteger)index completionBlock:(void (^)())completionBlock {
    if(index >= self.registeredClassesToSync.count){
        if(completionBlock){
            completionBlock();
        }
    }
    else{
        if(self.initialSyncComplete && self.registeredClassesToSync.count > 0){
            [self progressBlockIncrementInMainProcess:NO];
            
            NSString *className = [self.registeredClassesToSync objectAtIndex:index];
            
            // Fetch all objects from Core Data whose syncStatus is equal to SDObjectCreated
            NSArray *objectsToModified = [self managedObjectsForClass:className withSyncStatus:ObjectModified];
            
            if(objectsToModified.count > 0){
                // Create a dispatch group
                __block dispatch_group_t groupGeneral = dispatch_group_create();
                
                // Iterate over all fetched objects who syncStatus is equal to SDObjectCreated
                for (NSManagedObject *objectToModified in objectsToModified) {
                    // Get the JSON representation of the NSManagedObject
                    NSDictionary *jsonString = [objectToModified JSONToObjectOnServer];
                    NSDictionary *filesURL = [objectToModified filesURLToObjectOnServer];
                    
                    if(jsonString && jsonString.count > 0){
                        // Enter the group for each request we create
                        dispatch_group_enter(groupGeneral);
                        
                        [[DMEAPIEngine sharedInstance] updateObjectForClass:className withId:[objectToModified valueForKey:@"id"] parameters:jsonString files:filesURL onCompletion:^(NSDictionary *object, NSError *error) {
                            [self.context performBlock:^{
                                if(!error){
                                    if(object.count > 0){
                                        for (NSString* key in object) {
                                            if([[object objectForKey:key] isKindOfClass:[NSArray class]]){
                                                for (NSDictionary *record in [object objectForKey:key]) {
                                                    if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"created"]){
                                                        NSManagedObject *relationObject = [self updateRelation:className ofManagedObject:objectToModified withClassName:key withRecord:record];
                                                        [relationObject setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                    }
                                                }
                                            }
                                            else if ([[object objectForKey:key] isKindOfClass:[NSDictionary class]]){
                                                if([key isEqualToString:className]){
                                                    NSDictionary *record = [object objectForKey:key];
                                                    
                                                    if(record.count > 0 && [record valueForKey:@"id"] && [record valueForKey:@"modified"]){
                                                        [self updateManagedObject:objectToModified withClassName:className withRecord:@{className: record}];
                                                        [objectToModified setValue:[NSNumber numberWithInt:ObjectSynced] forKey:@"syncStatus"];
                                                    }
                                                }
                                            }
                                        }
                                        
                                        [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Se ha modificado el %@ con id %@", nil), [self logClassName:[[objectToModified entity] name]], [objectToModified valueForKey:@"id"]] important:NO];
                                        
                                        [self saveContext:^(BOOL result) {
                                            dispatch_group_leave(groupGeneral);
                                        }];
                                    }
                                    else{
                                        NSError *error = [self createErrorWithCode:SyncErrorCodeModifyInfo
                                                                    andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido actualizar el %@ al servidor", nil), [self logClassName:className]]
                                                                  andFailureReason:NSLocalizedString(@"Ha fallado la respuesta del servicio web", nil)
                                                             andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                        [self errorBlock:error fatal:NO];
                                        
                                        dispatch_group_leave(groupGeneral);
                                    }
                                }
                                else{
                                    NSError *error = [self createErrorWithCode:SyncErrorCodeModifyInfo
                                                                andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido actualizar el %@ al servidor", nil), [self logClassName:className]]
                                                              andFailureReason:NSLocalizedString(@"Ha fallado la respuesta del servicio web", nil)
                                                         andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                    [self errorBlock:error fatal:NO];
                                    
                                    dispatch_group_leave(groupGeneral);
                                }
                            }];
                        }];
                    }
                }
                
                dispatch_group_notify(groupGeneral, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    [self.context performBlock:^{
                        [self updateLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
                    }];
                });
            }
            else{
                [self updateLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
            }
        }
        else{
            [self updateLocalObjectsToServerOfClassWithId:index+1 completionBlock:completionBlock];
        }
    }
}

//Elimina del servidor los objetos eliminados localmente
- (void)deleteObjectsOnServer:(SendObjectsCompletionBlock)completionBlock {
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

- (void)deleteObjectsOnServerOfClassWithId:(NSInteger)index completionBlock:(void (^)())completionBlock {
    if(index >= self.registeredClassesToSync.count){
        if(completionBlock){
            completionBlock();
        }
    }
    else{
        if(self.initialSyncComplete && self.registeredClassesToSync.count > 0){
            [self progressBlockIncrementInMainProcess:NO];
            
            NSString *className = [self.registeredClassesToSync objectAtIndex:index];
            
            // Fetch all objects from Core Data whose syncStatus is equal to SDObjectCreated
            NSArray *objectsToDelete = [self managedObjectsForClass:className withSyncStatus:ObjectDeleted];
            
            if(objectsToDelete.count > 0){
                // Create a dispatch group
                __block dispatch_group_t groupGeneral = dispatch_group_create();
                
                // Iterate over all fetched objects who syncStatus is equal to SDObjectCreated
                for (NSManagedObject *objectToDelete in objectsToDelete) {
                    NSString *objectId = [objectToDelete valueForKey:@"id"];
                    if(objectId && ![objectId isEqualToString:@""]){
                        // Enter the group for each request we create
                        dispatch_group_enter(groupGeneral);
                        
                        [[DMEAPIEngine sharedInstance] deleteObjectForClass:className withId:[objectToDelete valueForKey:@"id"] onCompletion:^(NSDictionary *object, NSError *error) {
                            [self.context performBlock:^{
                                if(!error && object.count > 0 && [[object objectForKey:className] valueForKey:@"id"]){
                                    //Delete object in Core Data
                                    [self.context deleteObject:objectToDelete];
                                    
                                    [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Se ha eliminado el %@ con id %@", nil), [self logClassName:[[objectToDelete entity] name]], [objectToDelete valueForKey:@"id"]] important:NO];
                                    
                                    [self saveContext:^(BOOL result) {
                                        dispatch_group_leave(groupGeneral);
                                    }];
                                }
                                else{
                                    NSError *error = [self createErrorWithCode:SyncErrorCodeDeleteInfo
                                                                andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido eliminar el %@ al servidor", nil), [self logClassName:className]]
                                                              andFailureReason:NSLocalizedString(@"Ha fallado el borrado de datos en el servidor", nil)
                                                         andRecoverySuggestion:NSLocalizedString(@"Compruebe los servicios web", nil)];
                                    [self errorBlock:error fatal:NO];
                                    
                                    dispatch_group_leave(groupGeneral);
                                }
                            }];
                        }];
                    }
                }
                
                dispatch_group_notify(groupGeneral, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                    [self.context performBlock:^{
                        [self deleteObjectsOnServerOfClassWithId:index+1 completionBlock:completionBlock];
                    }];
                });
            }
            else{
                [self deleteObjectsOnServerOfClassWithId:index+1 completionBlock:completionBlock];
            }
        }
        else{
            [self deleteObjectsOnServerOfClassWithId:index+1 completionBlock:completionBlock];
        }
    }
}

#pragma mark Download files

//Comienza la descarga de ficheros
- (void)downloadFiles:(DownloadCompletionBlock)completionBlock
{
    [self.context performBlock:^{
        //Comprobamos que hay que hacer
        if(!self.downloadFiles){
            
            [self messageBlock:NSLocalizedString(@"La descarga de ficheros esta desactivada", nil) important:YES];
            
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
    [self.context reset];
    self.context = nil;
    self.JSONRecords = [NSMutableDictionary dictionary];
    self.savedEntities = [NSMutableDictionary dictionary];
    self.dateFormatter = nil;
    self.classesToSync = nil;
    self.downloadQueue = nil;
    self.filesToDownload = nil;
    self.downloadedFiles = 0;
    self.progressCurrent = 0;
    self.progressTotal = 0;
    self.startDate = nil;
    
    //self.currentQueue = nil;
    idPredicateTemplate = nil;
    syncStatusNotPredicateTemplate = nil;
    syncStatusPredicateTemplate = nil;
}

#pragma mark - Downloaded File Management

//Comprueba si faltan ficheros por descargar y los añade a la lista
- (void)checkFilesToDownload
{
    NSManagedObjectContext *managedObjectContext = self.context;
    
    // Iterate over all registered classes to sync
    for (NSString *className in self.registeredClassesToSync) {
        if(([self.registeredClassesWithFiles containsObject:className] && self.downloadFiles) || ([self.registeredClassesWithOptionalFiles containsObject:className] && self.downloadOptionalFiles)){
            NSEntityDescription *classDescription = [NSEntityDescription entityForName:className inManagedObjectContext:managedObjectContext];
            NSArray *properties = [classDescription properties];
            for (NSPropertyDescription *property in properties) {
                if([property.name length] > 2 && [[property.name substringToIndex:3] isEqualToString:@"url"]){
                    NSArray *objects = [self managedObjectsForClass:className];
                    for (NSManagedObject *object in objects) {
                        if([object valueForKey:property.name] && ![(NSString *)[object valueForKey:property.name] isEqualToString:@""] && ![self fileExistWithName:[object valueForKey:property.name] ofClass:className]){
                            //Añadimos la url para ser descargada
                            [self.filesToDownload addObject:[NSDictionary dictionaryWithObjectsAndKeys:className, @"classname", [object valueForKey:property.name], @"url", nil]];
                        }
                    }
                }
            }
        }
    }
}

//Descarga todos los ficheros de la cola
- (void)downloadFilesToDownload:(DownloadCompletionBlock)completionBlock
{
    self.downloadQueue = [[NSOperationQueue alloc] init];
    self.downloadQueue.name = @"Download Files Queue";
    self.downloadQueue.MaxConcurrentOperationCount = MaxConcurrentDownload;
    
    //Thumbnails
    [DMEThumbnailer sharedInstance].sizes = thumbnailSize();
    
    for (NSDictionary *file in self.filesToDownload) {
        //Eliminamos el valor anterior si no es la primera sincronizacion
        if(self.initialSyncComplete){
            [self removeFileWithName:[file objectForKey:@"url"] ofClass:[file objectForKey:@"classname"]];
        }
    }
    
    [self progressBlockTotal:self.filesToDownload.count inMainProcess:NO];
    
    for (NSDictionary *file in self.filesToDownload) {
        // Add an operation as a block to a queue
        [self.downloadQueue addOperationWithBlock: ^ {
            BOOL downloaded = YES;
            if(![self fileExistWithName:[file objectForKey:@"url"] ofClass:[file objectForKey:@"classname"]]){
                downloaded = [self downloadFileWithName:[file objectForKey:@"url"] ofClass: [file objectForKey:@"classname"]];
                [self thumbnailFileWithName:[file objectForKey:@"url"] ofClass: [file objectForKey:@"classname"]];
            }
            
            //Descargamos el fichero
            self.downloadedFiles++;
            
            [self progressBlockIncrementInMainProcess:NO];
            
            if(downloaded){
                [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Descargado fichero (%@/%@): %@", nil), [NSNumber numberWithInteger:self.downloadedFiles], [NSNumber numberWithInteger:self.filesToDownload.count], [file objectForKey:@"url"]] important:NO];
            }
            else{
                
            }
            
        }];
    }
    
    downloadCompletionAuxBlock = completionBlock;
    [self.downloadQueue addObserver:self forKeyPath:@"operations" options:0 context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == self.downloadQueue && [keyPath isEqualToString:@"operations"]) {
        if ([self.downloadQueue.operations count] == 0) {
            // Do whatever you need to do when all requests are finished
            [self messageBlock:NSLocalizedString(@"Se han descargado todos los ficheros", nil) important:YES];
            [self progressBlockIncrementInMainProcess:YES];
            
            [self.context performBlock:^{
                if(downloadCompletionAuxBlock){
                    downloadCompletionAuxBlock();
                    downloadCompletionAuxBlock = nil;
                }
            }];
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
}


//Descarga un fichero
-(BOOL)downloadFileWithName:(NSString *)aName ofClass:(NSString *)aClass
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    
    //Creamos la URL remota y local
    NSString *className = [NSString stringWithFormat:@"%@%@", [[aClass substringToIndex:1] lowercaseString], [aClass substringFromIndex:1]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@/%@", URLUploads, className, aName]];
    NSString *urlDirectorio = [NSString stringWithFormat:@"%@/%@", pathCache(), className];
    NSString *tmpName = [[NSUUID new] UUIDString];
    NSString *urlTmp = [NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), tmpName];
    NSString *urlLocal = [NSString stringWithFormat:@"%@/%@", urlDirectorio, aName];
    
    NSError *error = nil;
    BOOL resultado = YES;
    
    if(url){
        NSData *imgData = [NSData dataWithContentsOfURL:url options:0 error:&error];
        
        if(!error){
            if(filemgr){
                [filemgr createFileAtPath: urlTmp contents:imgData attributes:nil];
                
                //Cambiamos al directorio de cache
                if([filemgr changeCurrentDirectoryPath: urlDirectorio] == NO){
                    [filemgr createDirectoryAtPath: urlDirectorio withIntermediateDirectories: YES attributes: nil error: NULL];
                }
                
                if ([filemgr changeCurrentDirectoryPath: urlDirectorio] == YES)
                {
                    if(!imgData){
                        NSError *error = [self createErrorWithCode:SyncErrorCodeDownloadFile
                                                    andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido descargar el fichero: %@", nil), url]
                                                  andFailureReason:NSLocalizedString(@"No se ha descargado el contenido del fichero", nil)
                                             andRecoverySuggestion:NSLocalizedString(@"Compruebe la conexión o el fichero", nil)];
                        [self errorBlock:error fatal:NO];
                        
                        resultado = NO;
                    }
                    else {
                        [filemgr moveItemAtPath:urlTmp toPath:urlLocal error:&error];
                        if(error){
                            NSError *error = [self createErrorWithCode:SyncErrorCodeMoveFile
                                                        andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido mover el fichero: %@", nil), url]
                                                      andFailureReason:NSLocalizedString(@"No se ha podido mover el fichero a su ubicación definitiva", nil)
                                                 andRecoverySuggestion:NSLocalizedString(@"Compruebe el sistema de ficheros", nil)];
                            [self errorBlock:error fatal:NO];
                            
                            resultado = NO;
                        }
                    }
                }
                else{
                    NSError *error = [self createErrorWithCode:SyncErrorCodeOpenDirectory
                                                andDescription:NSLocalizedString(@"No se ha podido abrir el directorio", nil)
                                              andFailureReason:NSLocalizedString(@"No se ha podido acceder al directorio de destino", nil)
                                         andRecoverySuggestion:NSLocalizedString(@"Compruebe el sistema de ficheros", nil)];
                    [self errorBlock:error fatal:NO];
                    
                    resultado = NO;
                }
            }
            else{
                NSError *error = [self createErrorWithCode:SyncErrorCodeOpenFile
                                            andDescription:NSLocalizedString(@"No se ha podido abrir el fichero", nil)
                                          andFailureReason:NSLocalizedString(@"No se ha podido acceder al fichero de destino", nil)
                                     andRecoverySuggestion:NSLocalizedString(@"Compruebe el sistema de ficheros", nil)];
                [self errorBlock:error fatal:NO];
                
                resultado = NO;
            }
        }
        else{
            NSError *error = [self createErrorWithCode:SyncErrorCodeDownloadFile
                                        andDescription:[NSString stringWithFormat:NSLocalizedString(@"No se ha podido descargar el fichero: %@", nil), url]
                                      andFailureReason:NSLocalizedString(@"No se ha descargado el contenido del fichero", nil)
                                 andRecoverySuggestion:NSLocalizedString(@"Compruebe la conexión o el fichero", nil)];
            [self errorBlock:error fatal:NO];
            
            resultado = NO;
        }
    }
    else{
        NSError *error = [self createErrorWithCode:SyncErrorCodeURLContainIllegalCharacters
                                    andDescription:NSLocalizedString(@"La URL puede contener caracteres ilegales", nil)
                                  andFailureReason:NSLocalizedString(@"No se admiten espacios y carácteres especiales en la URL", nil)
                             andRecoverySuggestion:NSLocalizedString(@"Compruebe el nombre del fichero", nil)];
        [self errorBlock:error fatal:NO];
        
        resultado = NO;
    }
    
    return resultado;
}

//Comprueba si un fichero existe
-(BOOL)fileExistWithName: (NSString *) aName ofClass: (NSString *) aClass
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *className = [NSString stringWithFormat:@"%@%@", [[aClass substringToIndex:1] lowercaseString], [aClass substringFromIndex:1]];
    NSString *urlLocal = [NSString stringWithFormat:@"%@/%@/%@", pathCache(), className, aName];
    return [filemgr fileExistsAtPath:urlLocal];
}

//Elimina un fichero
-(BOOL)removeFileWithName: (NSString *) aName ofClass: (NSString *) aClass
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
            [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Eliminado fichero: %@", nil), urlLocal] important:NO];
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
                [self messageBlock:[NSString stringWithFormat:NSLocalizedString(@"Cache de %@ limpiada", nil), [self logClassName:className]] important:NO];
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
    [self logInfo:message];
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
    
    if(self.progressBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(self.progressCurrent, self.progressTotal);
        });
    }
}

-(void)progressBlockIncrementInMainProcess:(BOOL)main
{
    CGFloat current = 0;
    if(main){
        self.progressCurrent += 1;
        self.progressSubprocessCurrent = 0;
        
        current = self.progressCurrent;
    }
    else{
        self.progressSubprocessCurrent += 1;
        
        current = self.progressCurrent+(((1/self.progressTotal)/self.progressSubprocessTotal)*self.progressSubprocessCurrent);
    }
    
    if(self.progressBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressBlock(current, self.progressTotal);
        });
    }
}

-(void)errorBlock:(NSError *)error fatal:(BOOL)fatal
{
    [self logError:error.localizedDescription];
    if(self.errorBlock){
        dispatch_async(dispatch_get_main_queue(), ^{
            self.errorBlock(error, fatal);
        });
    }
}

#pragma mark - Date Utils

//Inicializa el formateador de fechas
- (void)initializeDateFormatter {
    if (!self.dateFormatter) {
        self.dateFormatter = [[NSDateFormatter alloc] init];
        [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        [self.dateFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    }
}

//Convierte la fecha de MySQL a NSDate
- (NSDate *)dateUsingStringFromAPI:(NSString *)dateString {
    [self initializeDateFormatter];
    
    return [self.dateFormatter dateFromString:dateString];
}

//Convierte la fecha de NSDate a MySQL
- (NSString *)dateStringForAPIUsingDate:(NSDate *)date {
    [self initializeDateFormatter];
    NSString *dateString = [self.dateFormatter stringFromDate:date];
    // remove Z
    dateString = [dateString substringWithRange:NSMakeRange(0, [dateString length]-1)];
    // add milliseconds and put Z back on
    dateString = [dateString stringByAppendingFormat:@".000Z"];
    
    return dateString;
}


#pragma mark - Log Utils

-(NSString *)logClassName:(NSString *)className {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    return [NSClassFromString(className) performSelector:@selector(localizedEntityName)];
#pragma clang diagnostic pop
}

-(void)logError:(NSString *)aMessage, ... {
    va_list args;
    va_start(args, aMessage);
    if(self.logLevel == SyncLogLevelVerbose){
        NSString *mes = [[NSString alloc] initWithFormat:aMessage arguments:args];
        DDLogError(@"%@", mes);
    }
    va_end(args);
}

-(void)logInfo:(NSString *)aMessage, ... {
    va_list args;
    va_start(args, aMessage);
    if(self.logLevel == SyncLogLevelVerbose){
        NSString *mes = [[NSString alloc] initWithFormat:aMessage arguments:args];
        DDLogInfo(@"%@", mes);
    }
    va_end(args);
}

-(void)logDebug:(NSString *)aMessage, ... {
    va_list args;
    va_start(args, aMessage);
    if(self.logLevel == SyncLogLevelVerbose){
        NSString *mes = [[NSString alloc] initWithFormat:aMessage arguments:args];
        DDLogDebug(@"%@", mes);
    }
    va_end(args);
}

@end
