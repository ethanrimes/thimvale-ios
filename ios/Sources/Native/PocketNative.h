#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Calls other than cancel must be serialized on the inference queue.
@interface PMInference : NSObject
/// Set before loading; zero selects the runtime default. Access on the inference queue only.
@property(nonatomic) int threadCount;
@property(nonatomic) int batchSize;
@property(nonatomic) int microBatchSize;
/// Reuse only the exact token prefix retained by this loaded context. Never persisted.
@property(nonatomic) BOOL reusePromptCache;
/// Counts and monotonic timings only; never contains prompts or generated text.
@property(nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *generationStatistics;
- (BOOL)loadModelAtPath:(NSString *)path contextSize:(int)contextSize error:(NSError **)error;
- (nullable NSString *)generateMessages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                             maxTokens:(int)maxTokens
                           temperature:(float)temperature
                               onToken:(void (^)(NSString *))onToken
                                 error:(NSError **)error;
- (void)cancel;
- (void)resetCancellation;
- (void)unload;
@end

@interface PMArchive : NSObject
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;
- (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)search:(NSString *)query limit:(int)limit error:(NSError **)error;
/// Metadata only: does not decompress every article in a page of results.
- (nullable NSArray<NSDictionary<NSString *, NSString *> *> *)browse:(NSString *)query offset:(int)offset limit:(int)limit error:(NSError **)error;
- (nullable NSDictionary<NSString *, NSString *> *)articleAtPath:(NSString *)path error:(NSError **)error;
@property(nonatomic, readonly) NSUInteger articleCount;
@end
NS_ASSUME_NONNULL_END
