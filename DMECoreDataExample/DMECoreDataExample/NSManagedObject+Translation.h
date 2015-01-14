//
//  NSManagedObject+Translation.h
//  iWine
//
//  Created by David Getapp on 23/12/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

@interface NSManagedObject (Translation)

//Obtiene la traducción a un idioma
-(NSManagedObject *)translationToLocale:(NSString *)aLocale;

+(NSString *)localizedEntityName;

@end
