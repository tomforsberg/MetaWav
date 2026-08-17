#import "JuceDSPBridge.h"
#import <atomic>

@interface JuceDSPBridge () {
@private
    double sampleRate;
    int numChannels;
    int blockSize;
    std::atomic<float> gainParam;
}
@end

@implementation JuceDSPBridge

- (instancetype)initWithSampleRate:(double)sr channels:(int)channels blockSize:(int)bs {
    self = [super init];
    if (self) {
        sampleRate = sr;
        numChannels = channels;
        blockSize = bs;
        gainParam.store(1.0f);
    }
    return self;
}

- (void)prepareToPlay:(double)sr blockSize:(int)bs {
    sampleRate = sr;
    blockSize = bs;
}

- (void)processFloatPointers:(float * _Nullable * _Nonnull)channelData frames:(int)frames channels:(int)channels {
    float gain = gainParam.load();
    for (int c = 0; c < channels; ++c) {
        float *buf = channelData[c];
        if (!buf) continue;
        for (int i = 0; i < frames; ++i) {
            buf[i] *= gain;
        }
    }
}

- (void)setParameter:(int)paramID value:(float)value {
    (void)paramID;
    gainParam.store(value);
}

@end



