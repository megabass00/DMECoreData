//
//  GETAPPSyncEngine.h
//  iWine
//
//  Created by David Getapp on 04/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "DMECoreDataStack.h"

typedef NS_ENUM(NSUInteger, ObjectSyncStatus) {
    ObjectSynced = 0,
    ObjectCreated = 1,
    ObjectDeleted = 2,
    ObjectModified = 3,
    ObjectNotSync = 4
};

typedef NS_ENUM(NSUInteger, SyncLogLevel) {
    SyncLogLevelDisabled = 0,
    SyncLogLevelVerbose = 1
};

typedef NS_ENUM(NSUInteger, SyncErrorCode) {
    SyncErrorCodeInstalation = 0,
    SyncErrorCodeConnection = 1,
    SyncErrorCodeSaveContext = 2,
    SyncErrorCodeNewVersion = 3,
    SyncErrorCodeIntegration = 4,
    SyncErrorCodeDownloadSyncInfo = 5,
    SyncErrorCodeDownloadInfo = 6,
    SyncErrorCodeNoId = 7,
    SyncErrorCodeCleanSyncInfo = 8,
    SyncErrorCodeCreateInfo = 9,
    SyncErrorCodeModifyInfo = 10,
    SyncErrorCodeDeleteInfo = 11,
    SyncErrorCodeDownloadFile = 12,
    SyncErrorCodeMoveFile = 13,
    SyncErrorCodeOpenDirectory = 14,
    SyncErrorCodeOpenFile = 15,
    SyncErrorCodeURLContainIllegalCharacters = 16,
    SyncErrorCodeCleanCache = 17,
    SyncErrorCodeCleanThumbsCache = 18,
    SyncErrorCodeJSON = 19,
};

typedef void (^SyncStartBlock)();
typedef void (^SyncCompletionBlock)();
typedef void (^ErrorBlock)(NSError *error, BOOL fatal);
typedef void (^ProgressBlock)(CGFloat current, CGFloat total);
typedef void (^MessageBlock)(NSString *message, BOOL important);

@interface DMESyncEngine : NSObject

@property (atomic, readonly) BOOL syncInProgress;   //Indica si la sincronización esta ya en curso
@property (atomic) BOOL syncBlocked;   //Indica si la sincronización esta bloqueada
@property (atomic) BOOL autoSyncActive; //Indica si la sincronización automática está activada
@property (assign, nonatomic) NSInteger autoSyncDelay;
@property (assign, nonatomic) BOOL downloadFiles;
@property (assign, nonatomic) BOOL downloadOptionalFiles;
@property (assign, nonatomic) SyncLogLevel logLevel;

+(instancetype)sharedEngine;

#pragma mark - Start Methods

//Sincronizacion puntual
-(void)startSync:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock;

//Sincronizacion periodica
-(void)autoSync:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock;

//Enviar datos
-(void)pushDataToServer:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock;

//Recibir datos
-(void)fetchDataFromServer:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock;

//Download files
-(void)downloadFiles:(SyncStartBlock)startBlock withCompletionBlock:(SyncCompletionBlock)completionBlock withProgressBlock:(ProgressBlock)progressBlock withMessageBlock:(MessageBlock)messageBlock withErrorBlock:(ErrorBlock)errorBlock;

#pragma mark - Other

//Registra una clase para ser sincronizada con el servidor
-(void)registerNSManagedObjectClassToSync:(Class)aClass;
-(void)registerNSManagedObjectClassToSyncWithFiles:(Class)aClass;
-(void)registerNSManagedObjectClassToSyncWithOptionalFiles:(Class)aClass;

//Indica si ya se ha sincronizado inicialmente
-(BOOL)initialSyncComplete;
-(void)setInitialSyncIncompleted;
-(void)cancelAutoSync;
-(void)blockSync;
-(void)unblockSync;
-(void)clearCache;

@end
