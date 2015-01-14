//
//  NSPredicate+Fields.h
//  Ramondin
//
//  Created by David Getapp on 19/09/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSPredicate (Fields)

+(NSPredicate *)predicateWithFields:(NSArray *)fields searchText:(NSString *)aSearchText;

@end
