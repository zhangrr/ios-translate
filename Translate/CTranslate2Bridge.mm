#import "CTranslate2Bridge.h"

#ifdef __cplusplus
#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include <ctranslate2/translation.h>
#include <ctranslate2/translator.h>
#endif

NSErrorDomain const CTranslate2ErrorDomain = @"CTranslate2ErrorDomain";

@implementation CTranslate2Bridge {
#ifdef __cplusplus
    std::unique_ptr<ctranslate2::Translator> _translator;
#endif
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                              interThreads:(NSInteger)interThreads
                              intraThreads:(NSInteger)intraThreads
                                     error:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (!self) {
        return nil;
    }

#ifdef __cplusplus
    try {
        ctranslate2::ReplicaPoolConfig config;
        config.num_threads_per_replica = std::max<NSInteger>(1, intraThreads);

        _translator = std::make_unique<ctranslate2::Translator>(
            std::string(modelPath.UTF8String),
            ctranslate2::Device::CPU,
            ctranslate2::ComputeType::DEFAULT,
            std::vector<int>{0},
            false,
            config
        );
    } catch (const std::exception& exception) {
        if (error) {
            *error = [NSError errorWithDomain:CTranslate2ErrorDomain
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithUTF8String:exception.what()]
                                     }];
        }
        return nil;
    }
#else
    if (error) {
        *error = [NSError errorWithDomain:CTranslate2ErrorDomain
                                     code:2
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"CTranslate2 bridge requires Objective-C++"
                                 }];
    }
    return nil;
#endif

    (void)interThreads;
    return self;
}

- (nullable NSArray<NSString *> *)translateTokens:(NSArray<NSString *> *)sourceTokens
                                     targetPrefix:(nullable NSArray<NSString *> *)targetPrefix
                                maxDecodingLength:(NSInteger)maxDecodingLength
                                         beamSize:(NSInteger)beamSize
                                            error:(NSError * _Nullable * _Nullable)error {
#ifdef __cplusplus
    try {
        std::vector<std::string> source;
        source.reserve(sourceTokens.count);
        for (NSString *token in sourceTokens) {
            source.emplace_back(token.UTF8String);
        }

        ctranslate2::TranslationOptions options;
        options.beam_size = std::max<NSInteger>(1, beamSize);
        options.max_decoding_length = std::max<NSInteger>(1, maxDecodingLength);
        options.return_end_token = false;
        options.num_hypotheses = 1;

        std::vector<ctranslate2::TranslationResult> results;
        if (targetPrefix.count > 0) {
            std::vector<std::string> prefix;
            prefix.reserve(targetPrefix.count);
            for (NSString *token in targetPrefix) {
                prefix.emplace_back(token.UTF8String);
            }

            results = _translator->translate_batch({source}, {prefix}, options);
        } else {
            results = _translator->translate_batch({source}, options);
        }

        if (results.empty()) {
            return @[];
        }

        const auto& output = results.front().output();
        NSMutableArray<NSString *> *translatedTokens = [NSMutableArray arrayWithCapacity:output.size()];
        for (const auto& token : output) {
            [translatedTokens addObject:[NSString stringWithUTF8String:token.c_str()]];
        }

        return translatedTokens;
    } catch (const std::exception& exception) {
        if (error) {
            *error = [NSError errorWithDomain:CTranslate2ErrorDomain
                                         code:3
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithUTF8String:exception.what()]
                                     }];
        }
        return nil;
    }
#else
    if (error) {
        *error = [NSError errorWithDomain:CTranslate2ErrorDomain
                                     code:2
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"CTranslate2 bridge requires Objective-C++"
                                 }];
    }
    return nil;
#endif
}

@end
