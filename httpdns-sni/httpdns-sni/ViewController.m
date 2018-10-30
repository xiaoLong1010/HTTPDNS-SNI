//
//  ViewController.m
//  httpdns-sni
//
//  Created by Csy on 2018/10/23.
//  Copyright © 2018 Csy. All rights reserved.
//

#import "ViewController.h"
#import <BDHttpDns/BDHttpDns.h>
#import "CFHTTPSURLProtocol.h"
#import "CFHttpMessageURLProtocol.h"

@interface ViewController () <NSURLSessionDelegate>
@property (nonatomic, weak) BDHttpDns *httpdns;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self setupHTTPDNS];
    
    [self testSNI];
}

- (void)setupHTTPDNS {
    self.httpdns = [BDHttpDns sharedInstance];
    [self.httpdns setAccountID:@"your account"];
    [self.httpdns setSecret:@"your secret"];
    [self.httpdns setLogEnable:YES];
    [self.httpdns setHttpsRequestEnable:YES];
    
    NSArray * hosts = [[NSArray alloc] initWithObjects:@"www.baidu.com", @"cloud.baidu.com", nil];
    [self.httpdns setPreResolveHosts:hosts];
}

- (void)testNSURLSession {
    NSString *urlString = @"https://www.baidu.com";
    [self doRequestWithURLString:urlString];
}

- (void)testNSURLSessionWithRedirect {
    NSString *urlStr = @"https://dou.bz/23o8PS";
    [self doRequestWithURLString:urlStr];
}

- (void)testSNI {
    // 设置原始url，获取hosSt
    NSString *urlStr = @"https://dou.bz/23o8PS";
    NSURL *url = [NSURL URLWithString:urlStr];
    NSString *host = url.host;
    if (!host) {
        NSLog(@"Err: get nil host from originUrlStr(%@)", urlStr);
        return;
    }
    
    // 通过httpdns解析，使用ip地址的URL
    NSURL *ipURL = [self ipURLByHttpDnsResolve:url];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    // 使用自定义Protocol拦截该请求，Protocol内部使用CFNetwork发送发送请求
    config.protocolClasses = @[[CFHttpMessageURLProtocol class]];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    
    // 将host保存到请求头，Protocol中使用该host进行https的校验
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:ipURL];
    [request setValue:host forHTTPHeaderField:@"host"];
    
    // 发请求
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
    [task resume];
}

- (void)doRequestWithURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    
    // 将host保存到请求头，Protocol中使用该host进行https的校验
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
//    [request setValue:host forHTTPHeaderField:@"host"];
    
    // 发请求
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
    [task resume];
}

- (NSURL *)ipURLByHttpDnsResolve:(NSURL *)originalURL {
    NSString *urlStr = originalURL.absoluteString;
    NSString *host = originalURL.host;
    
    NSURL *url = originalURL;
    // 读取httpdns解析结果
    BDHttpDnsResult *result = [self.httpdns syncResolve:host cacheOnly:NO];
    
    // 获取失败，则使用原url
    if (![result ipv4List] && ![result ipv6List]) {
        NSLog(@"Get empty iplist from httpdns, use origin url");
    } else {
        // httpdns获取解析结果成功，使用ip替换url中host
        // 优先使用ipv6结果，对于ipv6结果，需要在ip前后增加[]字符
        // 若不存在ipv6结果，则使用ipv4结果
        NSRange hostRange = [urlStr rangeOfString:host];
        if (NSNotFound != hostRange.location) {
            NSString *ip = nil;
            if ([result ipv6List]) {
                NSLog(@"Use ipv6List(%@)", [result ipv6List]);
                ip = [[NSString alloc] initWithFormat:@"[%@]", [result ipv6List][0]];
            } else {
                NSLog(@"Use ipv4List(%@)", [result ipv4List]);
                ip = [result ipv4List][0];
            }
            
            // 使用ip替换url
            urlStr = [urlStr stringByReplacingCharactersInRange:hostRange withString:ip];
            url = [NSURL URLWithString:urlStr];
            NSLog(@"Use httpdns ip(%@) for host(%@), url(%@)", ip, host, urlStr);
        }
    }
    return url;
}


#pragma mark -- NSURLSessionDelegate
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)newRequest
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    NSLog(@"-----%@",NSStringFromSelector(_cmd));

    // 将newRequest进行域名解析，生成新的request
    NSString *host = newRequest.URL.host;
    NSURL *ipURL = [self ipURLByHttpDnsResolve:newRequest.URL];
    NSMutableURLRequest *ipRequest = [NSMutableURLRequest requestWithURL:ipURL];
    [ipRequest setValue:host forHTTPHeaderField:@"host"];

    completionHandler(ipRequest);
}

// 处理证书异常，默许IP直连方式
- (void) URLSession:(NSURLSession *)session
               task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
  completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    NSLog(@"-----%@",NSStringFromSelector(_cmd));
    if (!challenge) {
        return;
    }

    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;

    // 判断服务器返回的证书是否是服务器信任的
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        // 创建证书校验策略
        NSMutableArray *policies = [NSMutableArray array];

        // 使用域名代替IP进行校验
        NSString* host = [[task originalRequest] valueForHTTPHeaderField:@"host"];
//        if (host == nil) {
//            host = task.currentRequest.URL.host;
//        }
        [policies addObject:(__bridge_transfer id) SecPolicyCreateSSL(true, (__bridge CFStringRef) host)];

        // 绑定校验策略到服务端的证书上
        SecTrustSetPolicies(challenge.protectionSpace.serverTrust, (__bridge CFArrayRef) policies);

        // 评估当前serverTrust是否可信任，
        // 官方建议在result = kSecTrustResultUnspecified 或 kSecTrustResultProceed
        // 的情况下serverTrust可以被验证通过，https://developer.apple.com/library/ios/technotes/tn2232/_index.html
        // 关于SecTrustResultType的详细信息请参考SecTrust.h
        SecTrustResultType result;
        SecTrustEvaluate(challenge.protectionSpace.serverTrust, &result);
        BOOL isTrusted = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);

        // 新的校验策略添加成功
        if (isTrusted) {
            // disposition：如何处理证书
            // NSURLSessionAuthChallengePerformDefaultHandling:默认方式处理
            // NSURLSessionAuthChallengeUseCredential：使用指定的证书
            // NSURLSessionAuthChallengeCancelAuthenticationChallenge：取消请求
            disposition = NSURLSessionAuthChallengeUseCredential;
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    }

    // 应用证书策略
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSLog(@"-----%@",NSStringFromSelector(_cmd));
//    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
//    NSLog(@"-----Response for url(%@), httpcode(%ld)",httpResponse.URL, (long)httpResponse.statusCode);
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSLog(@"-----%@",NSStringFromSelector(_cmd));
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSLog(@"-----%@",NSStringFromSelector(_cmd));
}

@end
