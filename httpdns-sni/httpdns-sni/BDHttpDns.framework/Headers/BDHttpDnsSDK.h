//
//  BDHttpDnsSDK.h
//  BDHttpdns
//
//  Created by Liu,Xue(OP) on 2017/9/11.
//  Copyright © 2017年 baidu. All rights reserved.
//

#ifndef BDHttpDnsSDK_h
#define BDHttpDnsSDK_h

#import <Foundation/Foundation.h>

#import "BDHttpDnsResult.h"

/**
 * Httpdns缓存的处理策略
 */
typedef NS_ENUM(NSInteger, BDHttpDnsCachePolicy) {
    BDHttpDnsCachePolicyAggressive = 1, // 激进的使用策略，即使缓存过期也无条件使用
    BDHttpDnsCachePolicyTolerant,       // 一定限度容忍过期缓存，容忍至下次请求httpdns服务端得到结果，默认策略
    BDHttpDnsCachePolicyStrict,         // 严格的使用策略，不使用过期缓存
};

/**
 * Httpdns服务接口类
 */
@interface BDHttpDns : NSObject

/**
 * 获取Httpdns服务实例
 */
+ (instancetype _Nonnull)sharedInstance;

/**
 * 设置Httpdns服务的account id
 *
 * @param accountID     用户的account id，需要预先申请
 */
- (void)setAccountID:(NSString *_Nonnull)accountID;

/**
 * 设置Httpdns服务的secret
 *
 * @param secret     用户的secret，需要预先申请
 */
- (void)setSecret:(NSString *_Nonnull)secret;

/**
 * 设置Httpdns缓存处理策略
 *
 * @param  policy       过期缓存处理策略，取值范围见枚举BDHttpdnsCachePolicy
 *                      默认为BDHttpdnsCachePolicyTolerate
 */
- (void)setCachePolicy:(BDHttpDnsCachePolicy)policy;

/**
 * 设置预加载域名，调用此接口后会立刻发起异步解析
 * 域名数量上限为8个
 *
 * @param  hosts       预加载域名列表
 */
- (void)setPreResolveHosts:(NSArray *_Nonnull)hosts;

/**
 * 设置网络切换处理策略，默认为清理缓存并立刻发送批量域名预解析
 *
 * @param   clearCache  网络切换时，是否清除Httpdns缓存，避免在缓存中获取跨网解析结果
 * @param   isPrefetch  网络切换时，是否立刻发送批量域名预解析，及时更新缓存
 */
- (void)setNetworkSwitchPolicyClearCache:(BOOL)clearCache httpDnsPrefetch:(BOOL)isPrefetch;

/**
 * 设置HttpDns解析所使用的请求类型，默认为https
 *
 * @param   enable     YES: https请求；NO: http请求
 */
- (void)setHttpsRequestEnable:(BOOL)enable;

/**
 * 设置Log开关，默认关闭
 *
 * @param   enable     YES: 打开Log；NO: 关闭Log
 */
- (void)setLogEnable:(BOOL)enable;

/**
 * 同步解析接口
 *
 * @param   host        待解析域名
 * @param   cacheOnly   是否使用HttpDnsCache
 *                      cacheOnly为YES: 仅使用httpDnsCahe，此时接口行为表现为同步非阻塞接口
 *                      cacheOnly为NO:  若cache不命中，则SDK会继续进行DNS解析，此时接口行为表现为同步阻塞接口
 *
 * @return  BDHttpDnsResult*    使用BDHttpDnsResult结构封装的域名解析结果
 */
- (BDHttpDnsResult *_Nonnull)syncResolve:(NSString *_Nonnull)host cacheOnly:(BOOL)cacheOnly;

/**
 * 异步解析接口
 *
 * @param   host                待解析域名
 * @param   completionHandler   异步解析回调函数，参数为使用BDHttpDnsResult结构封装的域名解析结果
 */
- (void)asyncResolve:(NSString *_Nonnull)host completionHandler:(void (^_Nonnull)(BDHttpDnsResult * _Nonnull result))completionHandler;

@end

#endif /* BDHttpDnsSDK_h */
