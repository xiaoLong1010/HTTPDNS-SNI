//
//  CFHTTPSURLProtocol.m
//  BDHttpDnsSDKDemo
//
//  Created by Csy on 2018/10/18.
//  Copyright © 2018 baidu. All rights reserved.
//

#import "CFHTTPSURLProtocol.h"
#import <objc/runtime.h>
#import <BDHttpDns/BDHttpDns.h>

// 用于标记是否为同一个请求，防止无限循环请求
static NSString * const kReuqestIdentifiers = @"com.baidu.httpdns.request";

// 标记是否同一个数据流
static char * const kHasEvaluatedStream = "com.baidu.httpdns.stream";

@interface CFHTTPSURLProtocol () <NSStreamDelegate> 

@property(nonatomic, strong) NSMutableURLRequest *mutableRequest;
@property(nonatomic, strong) NSInputStream *inputStream;
@property(nonatomic, strong) NSRunLoop *runloop;

@end

@implementation CFHTTPSURLProtocol

#pragma mark - Override

/**
 *  是否拦截处理指定的请求
 *
 *  @param request 指定的请求
 *
 *  @return YES:拦截处理; NO:不拦截处理
 */
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 防止无限循环
    if ([NSURLProtocol propertyForKey:kReuqestIdentifiers inRequest:request]) {
        return NO;
    }
    
    // 只处理https
    NSString *urlString = request.URL.absoluteString;
    if ([urlString hasPrefix:@"https"]) {
        return YES;
    }
    
    return NO;
}

/**
 *  可以直接返回request; 也可以在这里修改request，比如添加header，修改host等
 *
 *  @param request 原始请求
 *
 *  @return 原始请求或者新的请求
 */
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

/**
 * 开始加载
 */
- (void)startLoading {
    NSMutableURLRequest *mutableRequest = [self.request mutableCopy];
    self.mutableRequest = mutableRequest;
    
    // 防止无限循环,表示该请求已经被处理
    [NSURLProtocol setProperty:@(YES) forKey:kReuqestIdentifiers inRequest:mutableRequest];
    
    // 发送请求
    [self startRequest];
}

/**
 * 取消加载
 */
- (void)stopLoading {
    // 关闭inputStream
    if (self.inputStream.streamStatus == NSStreamStatusOpen) {
        [self closeInputStream];
    }
}

#pragma mark - Request
- (void)startRequest {
    // 创建请求
    CFHTTPMessageRef requestRef = [self createCFRequest];
    CFAutorelease(requestRef);
    
    // 添加请求头
    [self addHeadersToRequestRef:requestRef];
    
    // 添加请求体
    [self addBodyToRequestRef:requestRef];

    // 创建CFHTTPMessage对象的输入流
    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, requestRef);
    self.inputStream = (__bridge_transfer NSInputStream *) readStream;
    
    // 设置SNI
    [self setupSNI];

    // 设置Runloop
    [self setupRunloop];
    
    // 打开输入流
    [self.inputStream open];
}

- (CFHTTPMessageRef)createCFRequest {
    // 创建url
    CFStringRef urlStringRef = (__bridge CFStringRef) [self.mutableRequest.URL absoluteString];
    CFURLRef urlRef = CFURLCreateWithString(kCFAllocatorDefault, urlStringRef, NULL);
    CFAutorelease(urlRef);
    
    // 读取HTTP method
    CFStringRef methodRef = (__bridge CFStringRef) self.mutableRequest.HTTPMethod;
    
    // 创建request
    CFHTTPMessageRef requestRef = CFHTTPMessageCreateRequest(kCFAllocatorDefault, methodRef, urlRef, kCFHTTPVersion1_1);
    
    return requestRef;
}

- (void)addHeadersToRequestRef:(CFHTTPMessageRef)requestRef {
    // 遍历请求头，将数据塞到requestRef
    // 不包含POST请求时存放在header的body信息
    NSDictionary *headFields = self.mutableRequest.allHTTPHeaderFields;
    for (NSString *header in headFields) {
        if (![header isEqualToString:@"originalBody"]) {
            CFStringRef requestHeader = (__bridge CFStringRef) header;
            CFStringRef requestHeaderValue = (__bridge CFStringRef) [headFields valueForKey:header];
            CFHTTPMessageSetHeaderFieldValue(requestRef, requestHeader, requestHeaderValue);
        }
    }
}

- (void)addBodyToRequestRef:(CFHTTPMessageRef)requestRef {
    NSDictionary *headFields = self.mutableRequest.allHTTPHeaderFields;
    
    // POST请求时，将原始HTTPBody从header中取出
    CFStringRef requestBody = CFSTR("");
    CFDataRef bodyDataRef = CFStringCreateExternalRepresentation(kCFAllocatorDefault, requestBody, kCFStringEncodingUTF8, 0);
    if (self.mutableRequest.HTTPBody) {
        bodyDataRef = (__bridge_retained CFDataRef) self.mutableRequest.HTTPBody;
    } else if (headFields[@"originalBody"]) {
        bodyDataRef = (__bridge_retained CFDataRef) [headFields[@"originalBody"] dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    // 将body数据塞到requestRef
    CFHTTPMessageSetBody(requestRef, bodyDataRef);
    
    CFRelease(bodyDataRef);
}

- (void)setupSNI {
    // 读取请求头中的host
    NSString *host = [self.mutableRequest.allHTTPHeaderFields objectForKey:@"host"];
    if (!host) {
        host = self.mutableRequest.URL.host;
    }
    
    // 设置HTTPS的校验策略
    [self.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    NSDictionary *sslProperties = [[NSDictionary alloc] initWithObjectsAndKeys:
                                   host, (__bridge id) kCFStreamSSLPeerName,
                                   nil];
    [self.inputStream setProperty:sslProperties forKey:(__bridge NSString *) kCFStreamPropertySSLSettings];
    [self.inputStream setDelegate:self];
}

- (void)setupRunloop {
    // 保存当前线程的runloop，这对于重定向的请求很关键
    if (!self.runloop) {
        self.runloop = [NSRunLoop currentRunLoop];
    }
    
    // 将请求放入当前runloop的事件队列
    [self.inputStream scheduleInRunLoop:self.runloop forMode:NSRunLoopCommonModes];
}

#pragma mark - Response

/**
 * 响应结束
 */
- (void)endResponse {
    // 读取响应头部信息
    CFReadStreamRef readStream = (__bridge CFReadStreamRef) self.inputStream;
    CFHTTPMessageRef messageRef = (CFHTTPMessageRef) CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
    CFAutorelease(messageRef);
    
    // 头部信息不完整，关闭inputstream，通知client
    if (!CFHTTPMessageIsHeaderComplete(messageRef)) {
        [self closeInputStream];
        [self.client URLProtocolDidFinishLoading:self];
        return;
    }
    
    // 把当前请求关闭
    [self closeInputStream];
    
    // 通知上层响应结束
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)doRedirect:(NSDictionary *)headDict {
    // 读取重定向的location，设置成新的url
    NSString *location = headDict[@"Location"];
    if (!location)
        location = headDict[@"location"];
    NSURL *url = [[NSURL alloc] initWithString:location];
    self.mutableRequest.URL = url;
    
    // 根据RFC文档，当重定向请求为POST请求时，要将其转换为GET请求
    if ([[self.mutableRequest.HTTPMethod lowercaseString] isEqualToString:@"post"]) {
        self.mutableRequest.HTTPMethod = @"GET";
        self.mutableRequest.HTTPBody = nil;
    }
    
    // 内部处理，将url中的host通过HTTPDNS转换为IP
    // 解析出IP
    // 优先使用ipv6结果，对于ipv6结果，需要在ip前后增加[]字符
    // 若不存在ipv6结果，则使用ipv4结果
    BDHttpDnsResult *result = [[BDHttpDns sharedInstance] syncResolve:url.host cacheOnly:NO];
    NSString *ip = nil;
    if (![result ipv4List] && ![result ipv6List]) {
        NSLog(@"Get empty iplist from httpdns, use origin url");
    } else {
        if ([result ipv6List]) {
            NSLog(@"Use ipv6List(%@)", [result ipv6List]);
            ip = [[NSString alloc] initWithFormat:@"[%@]", [result ipv6List][0]];
        } else {
            NSLog(@"Use ipv4List(%@)", [result ipv4List]);
            ip = [result ipv4List][0];
        }
    }
    
    // 使用ip替换host
    if (ip) {
        NSLog(@"Get IP from HTTPDNS Successfully!");
        NSRange hostFirstRange = [location rangeOfString:url.host];
        if (NSNotFound != hostFirstRange.location) {
            NSString *newUrl = [location stringByReplacingCharactersInRange:hostFirstRange withString:ip];
            self.mutableRequest.URL = [NSURL URLWithString:newUrl];
            [self.mutableRequest setValue:url.host forHTTPHeaderField:@"host"];
        }
    }
    
    [self startRequest];
}

- (void)closeInputStream {
    [self closeStream:self.inputStream];
}

- (void)closeStream:(NSStream *)aStream {
    [aStream removeFromRunLoop:self.runloop forMode:NSRunLoopCommonModes];
    [aStream setDelegate:nil];
    [aStream close];
}

#pragma mark - NSStreamDelegate
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            // stream类型校验
            if (![aStream isKindOfClass:[NSInputStream class]]) {
                break;
            }
            NSInputStream *inputStream = (NSInputStream *) aStream;
            CFReadStreamRef readStream = (__bridge CFReadStreamRef) inputStream;
            
            // 响应头完整性校验
            CFHTTPMessageRef messageRef = (CFHTTPMessageRef) CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
            CFAutorelease(messageRef);
            if (!CFHTTPMessageIsHeaderComplete(messageRef)) {
                return;
            }
            CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(messageRef);
            
            // https校验过了，直接读取数据
            if ([self hasEvaluatedStreamSuccess:aStream]) {
                [self readStreamData:inputStream];
            } else {
                // 添加校验标记
                objc_setAssociatedObject(aStream,
                                         kHasEvaluatedStream,
                                         @(YES),
                                         OBJC_ASSOCIATION_RETAIN);
                
                if ([self evaluateStreamSuccess:aStream]) {     // 校验成功，则读取数据
                    // 非重定向
                    if (![self isRedirectCode:statusCode]) {
                        // 读取响应头
                        [self readStreamHeader:messageRef];
                        
                        // 读取响应数据
                        [self readStreamData:inputStream];
                    } else {    // 重定向
                        // 关闭流
                        [self closeStream:aStream];
                        
                        // 处理重定向
                        [self handleRedirect:messageRef];
                    }
                } else {
                    // 校验失败，关闭stream
                    [self closeStream:aStream];
                    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"fail to evaluate the server trust" code:-1 userInfo:nil]];
                }
            }
        }
            break;
            
        case NSStreamEventErrorOccurred: {
            [self closeStream:aStream];
            
            // 通知client发生错误了
            [self.client URLProtocol:self didFailWithError:[aStream streamError]];
        }
            break;
        
        case NSStreamEventEndEncountered: {
            [self endResponse];
        }
            break;
            
        default:
            break;
    }
}

- (BOOL)hasEvaluatedStreamSuccess:(NSStream *)aStream {
    NSNumber *hasEvaluated = objc_getAssociatedObject(aStream, kHasEvaluatedStream);
    if (hasEvaluated && hasEvaluated.boolValue) {
        return YES;
    }
    return NO;
}

- (void)readStreamHeader:(CFHTTPMessageRef )message {
    // 读取响应头
    CFDictionaryRef headerFieldsRef = CFHTTPMessageCopyAllHeaderFields(message);
    NSDictionary *headDict = (__bridge_transfer NSDictionary *)headerFieldsRef;
    
    // 读取http version
    CFStringRef httpVersionRef = CFHTTPMessageCopyVersion(message);
    NSString *httpVersion = (__bridge_transfer NSString *)httpVersionRef;
    
    // 读取状态码
    CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
    
    // 非重定向的数据，才上报
    if (![self isRedirectCode:statusCode]) {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.mutableRequest.URL statusCode:statusCode HTTPVersion: httpVersion headerFields:headDict];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    }
}

- (BOOL)evaluateStreamSuccess:(NSStream *)aStream {
    // 证书相关数据
    SecTrustRef trust = (__bridge SecTrustRef) [aStream propertyForKey:(__bridge NSString *) kCFStreamPropertySSLPeerTrust];
    SecTrustResultType res = kSecTrustResultInvalid;
    NSMutableArray *policies = [NSMutableArray array];
    NSString *domain = [[self.mutableRequest allHTTPHeaderFields] valueForKey:@"host"];
    if (domain) {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateSSL(true, (__bridge CFStringRef) domain)];
    } else {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateBasicX509()];
    }
   
    // 证书校验
    SecTrustSetPolicies(trust, (__bridge CFArrayRef) policies);
    if (SecTrustEvaluate(trust, &res) != errSecSuccess) {
        return NO;
    }
    if (res != kSecTrustResultProceed && res != kSecTrustResultUnspecified) {
        return NO;
    }
    return YES;
}

- (void)readStreamData:(NSInputStream *)aInputStream {
    UInt8 buffer[16 * 1024];
    UInt8 *buf = NULL;
    NSUInteger length = 0;
    
    // 从stream读数据
    if (![aInputStream getBuffer:&buf length:&length]) {
        NSInteger amount = [self.inputStream read:buffer maxLength:sizeof(buffer)];
        buf = buffer;
        length = amount;
    }
    NSData *data = [[NSData alloc] initWithBytes:buf length:length];
    
    // 数据上报
    [self.client URLProtocol:self didLoadData:data];
}

- (BOOL)isRedirectCode:(NSInteger)statusCode {
    if (statusCode >= 300 && statusCode < 400) {
        return YES;
    }
    return NO;
}

- (void)handleRedirect:(CFHTTPMessageRef )messageRef {
    // 响应头
    CFDictionaryRef headerFieldsRef = CFHTTPMessageCopyAllHeaderFields(messageRef);
    NSDictionary *headDict = (__bridge_transfer NSDictionary *)headerFieldsRef;
    
    // 响应头的loction
    NSString *location = headDict[@"Location"];
    if (!location)
        location = headDict[@"location"];
    NSURL *redirectUrl = [[NSURL alloc] initWithString:location];
    
    // 读取http version
    CFStringRef httpVersionRef = CFHTTPMessageCopyVersion(messageRef);
    NSString *httpVersion = (__bridge_transfer NSString *)httpVersionRef;
    
    // 读取状态码
    CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(messageRef);
    
    // 生成response
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.mutableRequest.URL statusCode:statusCode HTTPVersion: httpVersion headerFields:headDict];
    
    // 上层实现了redirect协议，则回调到上层
    // 否则，内部进行redirect
    if ([self.client respondsToSelector:@selector(URLProtocol:wasRedirectedToRequest:redirectResponse:)]) {
        [self.client URLProtocol:self
          wasRedirectedToRequest:[NSURLRequest requestWithURL:redirectUrl]
                redirectResponse:response];
    } else {
        [self doRedirect:headDict];
    }
}

@end
