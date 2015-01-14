//
//  NSManagedObject+Translation.m
//  iWine
//
//  Created by David Getapp on 23/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

#import "CoreData+DMECoreData.h"
#import "NSManagedObject+Translation.h"

@implementation NSManagedObject (Translation)

//Obtiene la traducción a un idioma
-(NSManagedObject *)translationToLocale:(NSString *)aLocale
{
    //Obtenemos las relaciones
    NSEntityDescription *entityDescription = [self entity];
    NSDictionary *relationsDictionary = [entityDescription relationshipsByName];
    
    //Buscamos la relacion de traduccion
    NSRelationshipDescription *translationRelation = nil;
    for (NSString *relation in [relationsDictionary allKeys]) {
        if ([relation rangeOfString:@"Translation"].location != NSNotFound) {
            translationRelation = [relationsDictionary objectForKey:relation];
        }
    }
    
    //Devolvemos la traduccion
    if(translationRelation == nil){
        return nil;
    }
    else{
        NSArray *todasTraducciones = [NSArray array];
        NSSet *relacion = [[self valueForKey:[translationRelation name]] copy];
        if(relacion && [relacion count] > 0){
            todasTraducciones = [relacion allObjects];
        }
            
        if(todasTraducciones && [todasTraducciones isKindOfClass:[NSArray class]] && todasTraducciones.count > 1){
            NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
                return [[evaluatedObject valueForKey:@"language_id"] rangeOfString:[aLocale substringToIndex:2] options:NSCaseInsensitiveSearch range:NSMakeRange(0,2)].location != NSNotFound;
            }];
            NSArray *traducciones = [todasTraducciones filteredArrayUsingPredicate:p];
            if(traducciones.count > 0){    //Si esta el idioma del dispositivo lo devolvemos
                return [traducciones objectAtIndex:0];
            }
        }
        
        if(todasTraducciones && [todasTraducciones isKindOfClass:[NSArray class]] && todasTraducciones.count > 0){  //Si no encontramos el idioma devolvemos el primero
            NSSortDescriptor *ordenado = [[NSSortDescriptor alloc] initWithKey:@"language_id" ascending:YES];
            return [[[relacion allObjects] sortedArrayUsingDescriptors:@[ordenado]] objectAtIndex:0];
        }
        else{   //Si no encontramos nombre devolvemos vacio
            return nil;
        }
    }
}

+(NSString *)localizedEntityName{
    Class class = self;
    return NSStringFromClass(class);
}

@end
