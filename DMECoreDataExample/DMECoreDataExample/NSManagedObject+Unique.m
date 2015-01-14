//
//  NSManagedObject+Unique.m
//  Ramondin
//
//  Created by David Getapp on 9/1/15.
//  Copyright (c) 2015 get-app. All rights reserved.
//

#import "CoreData+DMECoreData.h"
#import "NSManagedObject+Unique.h"

@implementation NSManagedObject (Unique)

-(BOOL)validateId:(id *)ioValue error:(NSError * __autoreleasing *)outError {
    NSString *id = [self valueForKey:@"id"];
    
    if (!id || [id isEqualToString:@""]) {
        return YES;
    }
    else{
        if([[self.managedObjectContext objectsFromEntity:self.entity.name filterBy:[NSPredicate predicateWithFormat:@"id = %@", id]] fetchAll].count > 1){
            if (outError != NULL) {
                NSDictionary *userInfoDict = @{ NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Id %@ of entity %@ is not unique", nil), id, self.entity.name] };
                NSError *error = [[NSError alloc] initWithDomain:@"CoreData"
                                                            code:1
                                                        userInfo:userInfoDict];
                *outError = error;
            }
            return NO;
        }
        else{
            return YES;
        }
    }
}

@end
