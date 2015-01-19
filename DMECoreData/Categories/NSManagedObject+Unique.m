//
//  NSManagedObject+Unique.m
//  Ramondin
//
//  Created by David Getapp on 9/1/15.
//  Copyright (c) 2015 get-app. All rights reserved.
//

#import "DMECoreData.h"

@implementation NSManagedObject (Unique)

-(BOOL)validateId:(id *)ioValue error:(NSError * __autoreleasing *)outError {
    if([self respondsToSelector:@selector(id)]){
        NSString *id = [self valueForKey:@"id"];
        
        if (!id || [id isEqualToString:@""]) {
            return YES;
        }
        else{
            __block BOOL exists = NO;
            [self.managedObjectContext performBlockAndWait:^{
                exists = [self.class countObjectsFilterBy:[NSPredicate predicateWithFormat:@"id = %@", id] inContext:self.managedObjectContext] > 1;
            }];
            
            if(exists){
                if (outError != NULL) {
                    NSDictionary *userInfoDict = @{ NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Id %@ of entity %@ is not unique", nil), id, self.entity.name] };
                    NSError *error = [[NSError alloc] initWithDomain:@"com.damarte.coredata" code:1 userInfo:userInfoDict];
                    *outError = error;
                }
                return NO;
            }
            else{
                return YES;
            }
        }
    }
    else{
        return YES;
    }
    
}

@end
