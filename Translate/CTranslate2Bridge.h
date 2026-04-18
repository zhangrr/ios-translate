#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const CTranslate2ErrorDomain;

@interface CTranslate2Bridge : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                              interThreads:(NSInteger)interThreads
                              intraThreads:(NSInteger)intraThreads
                                     error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (nullable NSArray<NSString *> *)translateTokens:(NSArray<NSString *> *)sourceTokens
                                     targetPrefix:(nullable NSArray<NSString *> *)targetPrefix
                                maxDecodingLength:(NSInteger)maxDecodingLength
                                         beamSize:(NSInteger)beamSize
                                            error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
