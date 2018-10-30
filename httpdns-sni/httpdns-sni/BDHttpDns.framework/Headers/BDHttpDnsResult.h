//
//  BDHttpDnsResult.h
//  BDHttpDns
//
//  Created by Liu,Xue(OP) on 2017/12/18.
//  Copyright © 2017年 baidu. All rights reserved.
//

#ifndef BDHttpDnsResult_h
#define BDHttpDnsResult_h

#import <Foundation/Foundation.h>

/**
 * Httpdns解析状态码
 */
typedef NS_ENUM(NSInteger, BDHttpDnsResolveStatus) {
    BDHttpDnsResolveOK = 0,         // 解析成功
    BDHttpDnsInputError,            // 输入参数错误
    BDHttpDnsResolveErrCacheMiss,   // 由于cache未命中导致的解析失败，仅在解析时指定cache only标志时有效
    BDHttpDnsResolveErrDnsResolve,  //  dns解析失败
};

/**
 * Httpdns解析结果来源
 */
typedef NS_ENUM(NSInteger, BDHttpDnsResolveType) {
    BDHttpDnsResolveNone = 0,                   // 没有有效的解析结果
    BDHttpDnsResolveFromHttpDnsCache,           // 解析结果来自httpdns cache
    BDHttpDnsResolveFromHttpDnsExpiredCache,    // 解析结果来自过期的httpdns cache
    BDHttpDnsResolveFromDnsCache,               // 解析结果来自dns cache
    BDHttpDnsResolveFromDns,                    // 解析结果来自dns解析
};

/**
 * Httpdns解析结果类
 */
@interface BDHttpDnsResult : NSObject

/**
 * 初始化BDHttpDnsResult实例
 *
 * @param status        // 解析状态码，取值为BDHttpDnsResolveStatus枚举
 * @param type          // 解析结果来源类型，取值为枚举BDHttpDnsResolveType
 * @param ipv4List      // ipv4解析结果数组，数组元素为IPv4地址格式的字符串，如“192.168.1.2”
 * @param ipv6List      // ipv6解析结果，数组元素为IPv6地址格式的字符串，如“2000:0:0:0:0:0:0:1”
 */
- (nullable instancetype)initWithStatus:(NSInteger)status
                          type:(NSInteger)type
                      ipv4List:(nullable NSArray *)ipv4List
                      ipv6List:(nullable NSArray *)ipv6List;

/**
 * 解析状态码，取值为枚举BDHttpDnsResolveStatus
 */
@property (readonly) NSInteger status;

/**
 * 解析结果来源类型，取值为枚举BDHttpDnsResolveType
 */
@property (readonly) NSInteger type;

/**
 * ipv4解析结果列表
 */
@property (nullable, readonly, copy) NSArray *ipv4List;

/**
 * ipv6解析结果列表
 */
@property (nullable, readonly, copy) NSArray *ipv6List;

@end

#endif /* BDHttpDnsResult_h */
