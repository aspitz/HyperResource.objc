//
//  ZHyperResource.m
//
//  Created by Ayal Spitz on 5/14/14.
//

#import "ZHyperResource.h"
#import "NWURLTemplate.h"

#import <libextobjc/extobjc.h>
#import <AFNetworking/AFNetworking.h>
#import <AFNetworking-RACExtensions/RACAFNetworking.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

NSString *const HalEmbedded = @"_embedded";
NSString *const HalLinks = @"_links";
NSString *const HalHref = @"href";
NSString *const HalTemplated = @"templated";

@interface ZHyperResource ()
@property (nonatomic, strong) AFHTTPRequestOperationManager *httpRequestOperationManager;

@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSString *href;
@property (nonatomic, assign) BOOL templated;
@property (nonatomic, strong) NSDictionary *responseBody;

@property (nonatomic, strong) NSMutableDictionary *objects;
@property (nonatomic, strong) NSMutableDictionary *links;
@property (nonatomic, strong) NSMutableDictionary *attributes;

@property (nonatomic, assign) BOOL loaded;
@end

@implementation ZHyperResource

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.objects = [NSMutableDictionary dictionary];
        self.links = [NSMutableDictionary dictionary];
        self.attributes = [NSMutableDictionary dictionary];
        self.href = @"";
    }
    return self;
}

+ (instancetype)resourceWithRoot:(NSString *)root
{
    ZHyperResource *hyperResource = [[ZHyperResource alloc]init];
    hyperResource.root = root;

    hyperResource.httpRequestOperationManager = [AFHTTPRequestOperationManager manager];
    hyperResource.httpRequestOperationManager.requestSerializer = [AFJSONRequestSerializer serializer];
    hyperResource.httpRequestOperationManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return hyperResource;
}

//+ (id)copyWithZone:(struct _NSZone *)zone{
//}

- (instancetype)childResource{
    ZHyperResource *hyperResource = [[ZHyperResource alloc]init];
    hyperResource.root = self.root;
    hyperResource.httpRequestOperationManager = self.httpRequestOperationManager;
    
    return hyperResource;
}

- (void)getJSON:(NSDictionary *)values
{
    NSString *href = self.href;
    NSURL *url = nil;
    
    if (self.templated){
        href = [NWURLTemplate StringForTemplate:href withObject:values error:nil];
    }
    url = [NSURL URLWithString:href relativeToURL:[NSURL URLWithString:self.root]];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block AFHTTPRequestOperation *srcOperation = nil;
    __block NSError *error = nil;
    __block BOOL success = NO;
    
    @weakify(self)
    AFHTTPRequestOperation *operation = [self.httpRequestOperationManager GET:[url absoluteString] parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        @strongify(self)
        success = YES;
        srcOperation = operation;
        self.responseBody = responseObject;

        dispatch_semaphore_signal(semaphore);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        success = NO;
        srcOperation = operation;
        error = error;

        dispatch_semaphore_signal(semaphore);
    }];
    
    if (error)
    {
        NSLog(@"We had an error");
    }
    
    [operation waitUntilFinished];
    
    while (dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW))
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:10]];
    }
}

- (ZHyperResource *)get{
    return [self get:nil];
}

- (ZHyperResource *)get:(NSDictionary *)values{
    if (!self.loaded)
    {
        [self getJSON:values];
        [self parseHAL:self.responseBody];
        self.loaded = YES;
    }
    
    return self;
}

- (RACSignal *)rac_GET:(NSDictionary *)parameters {
    @weakify(self);
    return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (self.loaded)
        {
            [subscriber sendNext:self];
            [subscriber sendCompleted];
        }
        else
        {
            NSString *path = nil;
            NSDictionary *params = nil;
            [self.httpRequestOperationManager GET:path parameters:params success:^(AFHTTPRequestOperation *_, id json) {
                @strongify(self)
                
                [self parseHAL:json];
                [subscriber sendNext:self];
                [subscriber sendCompleted];
                
            } failure:^(AFHTTPRequestOperation *_, NSError *err) {
                
                [subscriber sendError:err];
                
            }];
        }
        
        return [RACDisposable disposableWithBlock:^{
            //@strongify(self);
            
            // If you need to cancel the HTTP request when
            // the signal subscription is disposed, you do
            // it in this block. If you don't need to do
            // anything, you can return nil instead of a
            // disposable that has nothing in its block.
            
        }];
    }];
}

#pragma mark - 

- (void)setHref:(NSString *)href{
    if (!href){
        href = @"";
    }
    
    _href = href;
}

#pragma mark - Parse HAL

- (void)parseHAL:(NSDictionary *)body
{
    [self initObjectsFromHAL:body];
    [self initLinksFromHAL:body];
    [self initAttributesFromHAL:body];
}

- (void)initObjectsFromHAL:(NSDictionary *)body{
    NSDictionary *embeddedDictionary = body[HalEmbedded];
    @weakify(self)
    [embeddedDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *collection, BOOL *stop){
        __block NSMutableArray *objects = [NSMutableArray array];
        [collection enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            ZHyperResource *resource = [self childResource];
            [resource parseHAL:obj];
            
            [objects addObject:resource];
        }];
        
        @strongify(self)
        self.objects[key] = objects;
    }];
}

- (void)initLinksFromHAL:(NSDictionary *)body{
    NSDictionary *linksDictionary = body[HalLinks];
    @weakify(self)
    [linksDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop){
        @strongify(self)
        
        ZHyperResource *resource = [self childResource];
        resource.href = obj[HalHref];
        resource.templated = [obj[HalTemplated] boolValue];
        
        self.links[key] = resource;
    }];
}

- (void)initAttributesFromHAL:(NSDictionary *)body{
    NSMutableDictionary *attributeDictionary = [body mutableCopy];
    [attributeDictionary removeObjectForKey:HalLinks];
    [attributeDictionary removeObjectForKey:HalEmbedded];
    
    [self.attributes addEntriesFromDictionary:attributeDictionary];
}

#pragma mark -

- (id)objectForKeyedSubscript:(id)key{
    id value = self.links[key];
    if (!value){
        value = self.objects[key];
    }
    if (!value){
        value = self.attributes[key];
    }
    return value;
}


#pragma mark - AFNetwork methods
                      
- (void)acceptableContentTypes:(NSSet *)acceptableContentTypes
{
    self.httpRequestOperationManager.responseSerializer.acceptableContentTypes = acceptableContentTypes;
}

- (void)username:(NSString *)username andPassword:(NSString *)password
{
    [self.httpRequestOperationManager.requestSerializer clearAuthorizationHeader];
    [self.httpRequestOperationManager.requestSerializer setAuthorizationHeaderFieldWithUsername:username password:password];
}

@end
