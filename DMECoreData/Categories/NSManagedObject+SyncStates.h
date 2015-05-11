//
//  NSManagedObject+SyncStates.h
//  Pods
//
//  Created by David Getapp on 5/5/15.
//
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (SyncStates)

-(BOOL)deletable;

-(BOOL)modifiable;

@end
