//
//  NSString+Hashes.h
//  iWine
//
//  Created by David Getapp on 18/07/13.
//  Copyright (c) 2013 get-app. All rights reserved.
//

@interface NSString (Hashes)

- (NSString *)md5;
- (NSString *)sha1;
- (NSString *)sha256;
- (NSString *)sha512;

@end
