//
//  GETAPPiWineAPIEngine.h
//  iWine
//
//  Created by David Getapp on 04/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "AFHTTPSessionManager.h"

typedef void (^FetchObjectsCompletionBlock)(NSArray *objects, NSError *error);
typedef void (^OperationObjectCompletionBlock)(NSDictionary *object, NSError *error);
typedef void (^LoginCompletionBlock)(NSDictionary *result, NSError *error);

@interface DMEAPIEngine : AFHTTPSessionManager

+ (instancetype)sharedInstance;
- (instancetype)init;
- (instancetype)initWithBaseURL:(NSURL *)url sessionConfiguration:(NSURLSessionConfiguration *)configuration;
- (instancetype)initWithBaseURL:(NSURL *)url;

//Devuelve todos los objetos de una clase
- (void)fetchObjectsForClass:(NSString *)className withParameters:(NSDictionary *)parameters onCompletion:(FetchObjectsCompletionBlock)completionBlock;

//Devuelve todas las entidades a sincronizar
- (void)fetchEntitiesForSync:(FetchObjectsCompletionBlock)completionBlock;

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
