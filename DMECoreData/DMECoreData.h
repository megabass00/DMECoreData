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
#import "NSManagedObject+Manipulate.h"
#import "NSManagedObject+Files.h"
#import "NSManagedObject+Serialize.h"
#import "NSManagedObject+Translation.h"
#import "NSManagedObject+Unique.h"
#import "NSPredicate+Fields.h"

#import "DMEAPIEngine.h"
#import "DMEThumbnailer.h"
#import "DMESyncEngine.h"

extern NSInteger const TimeoutInterval;         //Timeout de las peticiones al API
extern NSInteger const MaxConcurrentDownload;   //Numero máximo de descargas simultaneas de ficheros
extern NSString *const URLUploads;              //URL de las descargas de ficheros
extern NSString *const ModelName;               //Nombre del modelo
extern NSString *const SecuritySalt;            //Salt de seguridad
extern NSInteger const ddLogLevel;              //Nivel de log
extern NSString *const URLAPI;                  //URL del API
extern BOOL const ValidateUniqueId;             //Indica si se validan los ids como unicos
extern NSDictionary* thumbnailSize();           //Tamaños de thumbnails
extern NSString* pathCache();                   //Directorio de cache

#endif
