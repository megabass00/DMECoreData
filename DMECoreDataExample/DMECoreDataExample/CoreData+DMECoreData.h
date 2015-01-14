//
//  DMECoreData.h
//  DMECoreDataExample
//
//  Created by David Getapp on 13/1/15.
//
//

#ifdef __OBJC__

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

#ifndef NS_BLOCKS_AVAILABLE
#warning DMECoreData requires blocks
#endif

#import "CoreDataStack.h"
#import "GETAPIEngine.h"
#import "GETSyncEngine.h"

#import "NSManagedObjectContext+ModelOperations.h"
#import "NSFetchedResultsController+Fetch.h"
#import "NSManagedObject+Files.h"
#import "NSManagedObject+Serialize.h"
#import "NSManagedObject+Translation.h"
#import "NSManagedObject+Unique.h"
#import "NSPredicate+Fields.h"

#endif