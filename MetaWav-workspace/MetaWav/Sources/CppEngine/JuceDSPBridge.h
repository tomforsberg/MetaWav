// JuceDSPBridge.h - Objective-C++ bridge header for internal DSP
#ifdef __OBJC__
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JuceDSPBridge : NSObject

- (instancetype)initWithSampleRate:(double)sampleRate
                          channels:(int)channels
                         blockSize:(int)blockSize;

- (void)prepareToPlay:(double)sampleRate blockSize:(int)blockSize;

- (void)processFloatPointers:(float * _Nullable * _Nonnull)channelData
                      frames:(int)frames
                     channels:(int)channels;

- (void)setParameter:(int)paramID value:(float)value;

@end

NS_ASSUME_NONNULL_END
#endif


