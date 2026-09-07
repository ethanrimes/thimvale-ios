#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Calls other than cancel must be serialized on the inference queue.
@interface PMInference : NSObject
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
@property(nonatomic, readonly) NSUInteger articleCount;
@end
NS_ASSUME_NONNULL_END
