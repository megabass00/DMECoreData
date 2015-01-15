//
//  DMECoreData.h
//  DMECoreDataExample
//
//  Created by David Getapp on 13/1/15.
//
//

#ifdef __OBJC__

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <CommonCrypto/CommonDigest.h>

#ifndef NS_BLOCKS_AVAILABLE
#warning DMECoreData requires blocks
#endif

#import <CocoaLumberjack/CocoaLumberjack.h>

#import "AFNetworkActivityLogger.h"
#import "AFNetworkActivityIndicatorManager.h"

#import "DMECoreDataStack.h"

#import "NSString+Hashes.h"
#import "NSString+Inflections.h"
#import "NSObject+PWObject.h"
#import "NSFetchedResultsController+Fetch.h"
#import "NSManagedObject+Fetch.h"
#import "NSManagedObject+Files.h"
#import "NSManagedObject+Serialize.h"
#import "NSManagedObject+Translation.h"
#import "NSManagedObject+Unique.h"
#import "NSPredicate+Fields.h"

#import "DMEAPIEngine.h"
#import "DMEThumbnailer.h"
#import "DMESyncEngine.h"

extern NSInteger const TimeoutInterval;
extern NSInteger const MaxConcurrentDownload;
extern NSString *const URLUploads;
extern NSString *const ModelName;
extern NSString *const SecuritySalt;
extern NSInteger const ddLogLevel;
extern NSString *const URLAPI;
extern NSDictionary* thumbnailSize();
extern NSString* pathCache();

#endif
