//
//  GETAPPiWineAPIEngine.m
//  iWine
//
//  Created by David Getapp on 04/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "DMECoreData.h"

@implementation DMEAPIEngine

+ (instancetype)sharedInstance
{
    static DMEAPIEngine *_sharedInstance = nil;
    if(URLAPI && ![URLAPI isEqualToString:@""]){
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            // Initialize the session
            _sharedInstance = [[DMEAPIEngine alloc] initWithBaseURL:[NSURL URLWithString:URLAPI]];
        });
    }
    else{
        NSLog(@"No se ha definido una URL para el API, defina la constante URLAPI.");
    }
    
    return _sharedInstance;
}

- (instancetype)init
{
    self = [self initWithBaseURL:[NSURL URLWithString:URLAPI]];
    
    if (!self) return nil;
    
    return self;
}

- (instancetype)initWithBaseURL:(NSURL *)url sessionConfiguration:(NSURLSessionConfiguration *)configuration
{
    self = [super initWithBaseURL:url sessionConfiguration:configuration];
    if (!self) return nil;
    
    // Network activity indicator manager setup
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    
    [self.requestSerializer setTimeoutInterval:TimeoutInterval];
    
    return self;
}

- (instancetype)initWithBaseURL:(NSURL *)url
{
    // Session configuration setup
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfiguration.HTTPAdditionalHeaders = @{
                                                   @"api-key"       : @"55e76dc4bbae25b066cb",
                                                   @"User-Agent"    : @"Sync iOS Client"
                                                   };
    
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:0 * 1024 * 1024     // 10MB. memory cache
                                                      diskCapacity:0 * 1024 * 1024     // 50MB. on disk cache
                                                          diskPath:nil];

    [[NSURLCache sharedURLCache] setMemoryCapacity:0];
    [[NSURLCache sharedURLCache] setDiskCapacity:0];
    sessionConfiguration.URLCache = cache;
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    sessionConfiguration.timeoutIntervalForRequest = TimeoutInterval;
    sessionConfiguration.timeoutIntervalForResource = TimeoutInterval;
    
    self = [super initWithBaseURL:url sessionConfiguration:sessionConfiguration];
    if (!self) return nil;
    
    return self;
}

#pragma mark - Login

-(NSString *)generateHashWithParameters:(NSArray *)parameters
{
    NSMutableString *hash = [NSMutableString string];
    [hash appendString:SecuritySalt];
    for (NSString *parameter in parameters) {
        [hash appendString:parameter];
    }
    
    return [hash sha512];
}

#pragma mark - Sincronizacion

- (AFHTTPRequestOperation *)operationFetchObjectsForClass:(NSString *)className updatedAfterDate:(NSDate *)updatedDate withParameters:(NSDictionary *)parameters onCompletion:(FetchObjectsCompletionBlock)completionBlock
{
    if(!parameters){
        parameters = @{};
    }
    NSString *name = [self tableNameForClassName:className];
    NSString *path = [NSString stringWithFormat:@"%@.json", name];
    
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *hash = [self generateHashWithParameters:@[name, uuid, version]];
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *basicParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:version, @"version", uuid, @"uuid", hash, @"hash", ios, @"ios", nil];
    if(updatedDate){
        NSDateFormatter *gmtDateFormatter = [[NSDateFormatter alloc] init];
        gmtDateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
        gmtDateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        
        [basicParameters setValue:[gmtDateFormatter stringFromDate:updatedDate] forKey:@"last_modified"];
    }
    [basicParameters addEntriesFromDictionary:parameters];
    
    NSURL *url = [self.baseURL URLByAppendingPathComponent:path];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableArray *queryItems = [NSMutableArray array];
    for (NSString *key in basicParameters) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:basicParameters[key]]];
    }
    components.queryItems = queryItems;
    
    AFHTTPRequestOperation *op = [[AFHTTPRequestOperation alloc] initWithRequest:[NSURLRequest requestWithURL:components.URL cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:TimeoutInterval]];
    
    op.queuePriority = NSOperationQueuePriorityHigh;
    
    NSURL *tmpDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileURL = [[tmpDirURL URLByAppendingPathComponent:className] URLByAppendingPathExtension:@"json"];
    
    op.outputStream = [NSOutputStream outputStreamWithURL:fileURL append:NO];
    op.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript", nil];
    
    [op setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead){}];
    
    [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSError *error;
        if(![operation.responseSerializer validateResponse:operation.response data:operation.responseData error:&error] || error){
            NSMutableDictionary *mutableUserInfo = [@{
                                                      NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringFromTable(@"Request failed: unacceptable content-type: %@", @"AFNetworking", nil), [operation.response MIMEType]],
                                                      NSURLErrorFailingURLErrorKey:[operation.response URL],
                                                      AFNetworkingOperationFailingURLResponseErrorKey: operation.response,
                                                      } mutableCopy];
            if (operation.responseData) {
                mutableUserInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] = operation.responseData;
            }
            
            error = [NSError errorWithDomain:AFURLResponseSerializationErrorDomain code:NSURLErrorCannotDecodeContentData userInfo:mutableUserInfo];
            completionBlock(nil, error);
        }
        else{
            completionBlock(responseObject, nil);
        }
        
        responseObject = nil;
        error = nil;
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        completionBlock(nil, error);
    }];
    
    return op;
}

- (void)fetchEntitiesForSync:(FetchEntitiesCompletionBlock)completionBlock
{
    NSString *path = @"sync_states.json";
    
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *hash = [self generateHashWithParameters:@[@"sync_states", uuid, version]];
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *basicParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:version, @"version", uuid, @"uuid", hash, @"hash", ios, @"ios", nil];
    
    [self GET:path parameters:basicParameters success:^(NSURLSessionDataTask *task, id responseObject) {
        completionBlock([((NSDictionary *)responseObject) objectForKey:@"sync_states"], nil);
        responseObject = nil;
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        completionBlock(nil, error);
    }];
}

- (void)pushEntitiesSynchronized:(NSDate *)startDate onCompletion:(OperationObjectCompletionBlock)completionBlock
{
    NSString *path = @"sync_states.json";
    
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *hash = [self generateHashWithParameters:@[@"sync_states", uuid, version]];
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *basicParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:version, @"version", uuid, @"uuid", hash, @"hash", ios, @"ios", nil];
    
    if(startDate){
        NSDateFormatter *gmtDateFormatter = [[NSDateFormatter alloc] init];
        gmtDateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
        gmtDateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        
        [basicParameters addEntriesFromDictionary:@{@"last_sync_date": [gmtDateFormatter stringFromDate:startDate]}];
    }
    
    [self POST:path parameters:basicParameters success:^(NSURLSessionDataTask *task, id responseObject) {
        if(![[(NSDictionary *)responseObject objectForKey:@"result"] isKindOfClass:[NSString class]]){
            completionBlock([(NSDictionary *)responseObject objectForKey:@"result"], nil);
            responseObject = nil;
        }
        else{
            completionBlock(nil, [NSError errorWithDomain:NSLocalizedString(@"Se ha producido un error", nil) code:6666 userInfo:@{}]);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        completionBlock(nil, error);
    }];
}

- (void)pushObjectForClass:(NSString *)className parameters:(NSDictionary *)parameters files:(NSDictionary *)files onCompletion:(OperationObjectCompletionBlock)completionBlock
{
    NSString *name = [self tableNameForClassName:className];
    NSString *path = [NSString stringWithFormat:@"%@.json", name];
    
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *hash = [self generateHashWithParameters:@[name, uuid, version]];
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *basicParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:version, @"version", uuid, @"uuid", hash, @"hash", ios, @"ios", nil];
    [basicParameters addEntriesFromDictionary:parameters];
    
    [self POST:path parameters:basicParameters constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        for (NSString* key in files) {
            NSDictionary *fileFields = [files objectForKey:key];
            NSData *fileData = [fileFields objectForKey:@"data"];
            NSString *fileName = [fileFields objectForKey:@"name"];
            NSString *fileMime = [fileFields objectForKey:@"mime"];
            NSString *fileKey = [NSString stringWithFormat:@"data[%@][%@]", className, key];
            [formData appendPartWithFileData:fileData name:fileKey fileName:fileName mimeType:fileMime];
        }
    } success:^(NSURLSessionDataTask *task, id responseObject) {
        if(![[(NSDictionary *)responseObject objectForKey:@"result"] isKindOfClass:[NSString class]]){
            completionBlock([(NSDictionary *)responseObject objectForKey:@"result"], nil);
            responseObject = nil;
        }
        else{
            completionBlock(nil, [NSError errorWithDomain:NSLocalizedString(@"Se ha producido un error de validación", nil) code:6666 userInfo:@{}]);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        
        if([error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"]){
            NSString *html = [[NSString alloc] initWithData:[error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"] encoding:NSUTF8StringEncoding];
            NSLog(@"HTML: %@", html);
        }
        completionBlock(nil, error);
    }];
}

- (void)updateObjectForClass:(NSString *)className withId:(NSString *)objectId parameters:(NSDictionary *)parameters files:(NSDictionary *)files onCompletion:(OperationObjectCompletionBlock)completionBlock
{
    NSString *name = [self tableNameForClassName:className];
    NSString *path = [NSString stringWithFormat:@"%@/edit/%@.json", name, objectId];
    
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *hash = [self generateHashWithParameters:@[name, uuid, version]];
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *basicParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:version, @"version", uuid, @"uuid", hash, @"hash", ios, @"ios", nil];
    [basicParameters addEntriesFromDictionary:parameters];
    
    [self POST:path parameters:basicParameters constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        for (NSString* key in files) {
            NSDictionary *fileFields = [files objectForKey:key];
            NSData *fileData = [fileFields objectForKey:@"data"];
            NSString *fileName = [fileFields objectForKey:@"name"];
            NSString *fileMime = [fileFields objectForKey:@"mime"];
            NSString *fileKey = [NSString stringWithFormat:@"data[%@][%@]", className, key];
            [formData appendPartWithFileData:fileData name:fileKey fileName:fileName mimeType:fileMime];
        }
    } success:^(NSURLSessionDataTask *task, id responseObject) {
        if(![[(NSDictionary *)responseObject objectForKey:@"result"] isKindOfClass:[NSString class]]){
            completionBlock([(NSDictionary *)responseObject objectForKey:@"result"], nil);
            responseObject = nil;
        }
        else{
            completionBlock(nil, [NSError errorWithDomain:NSLocalizedString(@"Se ha producido un error de validación", nil) code:6666 userInfo:@{}]);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        if([error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"]){
            NSString *html = [[NSString alloc] initWithData:[error.userInfo objectForKey:@"com.alamofire.serialization.response.error.data"] encoding:NSUTF8StringEncoding];
            NSLog(@"HTML: %@", html);
        }
        completionBlock(nil, error);
    }];
}

- (void)deleteObjectForClass:(NSString *)className withId:(NSString *)objectId onCompletion:(OperationObjectCompletionBlock)completionBlock
{
    NSString *name = [self tableNameForClassName:className];
    NSString *path = [NSString stringWithFormat:@"%@/delete/%@.json", name, objectId];
    
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *hash = [self generateHashWithParameters:@[name, uuid, version]];
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    NSMutableDictionary *basicParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:version, @"version", uuid, @"uuid", hash, @"hash", ios, @"ios", nil];
    
    [self DELETE:path parameters:basicParameters success:^(NSURLSessionDataTask *task, id responseObject) {
        if(![[(NSDictionary *)responseObject objectForKey:@"result"] isKindOfClass:[NSString class]]){
            completionBlock([(NSDictionary *)responseObject objectForKey:@"result"], nil);
            responseObject = nil;
        }
        else{
            completionBlock(nil, [NSError errorWithDomain:NSLocalizedString(@"Se ha producido un error al borrar", nil) code:6686 userInfo:@{}]);
        }
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        completionBlock(nil, error);
    }];
}

-(NSString *)tableNameForClassName:(NSString *)className
{
    return [[className pluralize] underscore];
}

-(void)dealloc
{
    NSLog(@"Liberada el API");
}

@end
