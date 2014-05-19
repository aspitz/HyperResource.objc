//
//  ZHyperResource.h
//
//  Created by Ayal Spitz on 5/14/14.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const HalEmbedded;
FOUNDATION_EXPORT NSString *const HalLinks;
FOUNDATION_EXPORT NSString *const HalHref;
FOUNDATION_EXPORT NSString *const HalTemplated;

@interface ZHyperResource : NSObject

+ (instancetype)resourceWithRoot:(NSString *)root;

- (void)acceptableContentTypes:(NSSet *)acceptableContentTypes;
- (void)username:(NSString *)username andPassword:(NSString *)password;

- (ZHyperResource *)get;
- (ZHyperResource *)get:(NSDictionary *)values;

- (id)objectForKeyedSubscript:(id)key;

@end
