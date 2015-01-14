//
//  NSManagedObject+Serialize.h
//  iWine
//
//  Created by David Getapp on 22/01/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

@interface NSManagedObject (Serialize)

- (NSDictionary *)JSONToObjectOnServer;
- (NSDictionary *)filesURLToObjectOnServer;

@end
