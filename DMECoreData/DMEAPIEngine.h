//
//  GETAPPiWineAPIEngine.h
//  iWine
//
//  Created by David Getapp on 04/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "AFHTTPSessionManager.h"
#import <AFNetworking.h>

typedef void (^FetchEntitiesCompletionBlock)(NSArray *objects, NSError *error);
typedef void (^FetchObjectsCompletionBlock)(NSDictionary *objects, NSError *error);
typedef void (^OperationObjectCompletionBlock)(NSDictionary *object, NSError *error);
typedef void (^LoginCompletionBlock)(NSDictionary *result, NSError *error);

@interface DMEAPIEngine : AFHTTPSessionManager

+ (instancetype)sharedInstance;
- (instancetype)init;
- (instancetype)initWithBaseURL:(NSURL *)url sessionConfiguration:(NSURLSessionConfiguration *)configuration;
- (instancetype)initWithBaseURL:(NSURL *)url;

//Devuelve una operacion para todos los objetos de una clase actualizados o borrados despues de una fecha
- (AFHTTPRequestOperation *)operationFetchObjectsForClass:(NSString *)className updatedAfterDate:(NSDate *)updatedDate withParameters:(NSDictionary *)parameters onCompletion:(FetchObjectsCompletionBlock)completionBlock;

//Devuelve todas las entidades a sincronizar
- (void)fetchEntitiesForSync:(FetchEntitiesCompletionBlock)completionBlock;

//Devuelve todas las entidades a sincronizar
- (void)pushEntitiesSynchronized:(NSDate *)startDate onCompletion:(OperationObjectCompletionBlock)completionBlock;

//Envia un objeto al servidor
- (void)pushObjectForClass:(NSString *)className parameters:(NSDictionary *)parameters files:(NSDictionary *)files onCompletion:(OperationObjectCompletionBlock)completionBlock;

//Actualiza un objeto en el servidor
- (void)updateObjectForClass:(NSString *)className withId:(NSString *)objectId parameters:(NSDictionary *)parameters files:(NSDictionary *)files onCompletion:(OperationObjectCompletionBlock)completionBlock;

//Elimina un objeto en el servidor
- (void)deleteObjectForClass:(NSString *)className withId:(NSString *)objectId onCompletion:(OperationObjectCompletionBlock)completionBlock;

//Hash
-(NSString *)generateHashWithParameters:(NSArray *)parameters;

-(NSString *)tableNameForClassName:(NSString *)className;

@end
