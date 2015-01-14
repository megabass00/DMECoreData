//
//  NSPredicate+Fields.m
//  Ramondin
//
//  Created by David Getapp on 19/09/14.
//  Copyright (c) 2014 get-app. All rights reserved.
//

#import "NSPredicate+Fields.h"

@implementation NSPredicate (Fields)

+(NSPredicate *)predicateWithFields:(NSArray *)fields searchText:(NSString *)aSearchText
{
    NSPredicate * pred = nil;
    NSArray *searchTerms = [aSearchText componentsSeparatedByString:@" "];
    
    
    NSString *predicateFormat = @"";
    NSInteger i = 0;
    for (NSString *field in fields) {
        if(i > 0){
            predicateFormat = [predicateFormat stringByAppendingString:@" OR "];
        }
        predicateFormat = [predicateFormat stringByAppendingString:[[NSString stringWithFormat:@"(%@", field] stringByAppendingString:@" contains[cd] %@)"]];
        i++;
    }
    if ([searchTerms count] == 1) {
        NSString *term = [searchTerms objectAtIndex:0];
        NSMutableArray *terms = [NSMutableArray array];
        for (NSInteger i = 0;i<fields.count;i++) {
            [terms addObject:term];
        }
        pred = [NSPredicate predicateWithFormat:predicateFormat argumentArray:terms];
    } else {
        NSMutableArray *subPredicates = [NSMutableArray array];
        for (NSString *term in searchTerms) {
            NSMutableArray *terms = [NSMutableArray array];
            for (NSInteger i = 0;i<fields.count;i++) {
                [terms addObject:term];
            }
            
            NSPredicate *p = [NSPredicate predicateWithFormat:predicateFormat argumentArray:terms];
            [subPredicates addObject:p];
        }
        pred = [NSCompoundPredicate andPredicateWithSubpredicates:subPredicates];
    }
    
    return pred;
}

@end
