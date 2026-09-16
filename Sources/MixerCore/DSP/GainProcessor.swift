/// Realtime-safe sample processing used by the tap engine's IOProc.
///
/// Performs no allocation, locking or reference counting.
public enum GainProcessor {
    /// Copies interleaved Float32 audio from `source` into `destination`, applying a gain that
    /// ramps linearly from `startGain` to `endGain` over the buffer.
    ///
    /// Channel mapping:
    /// - equal channel counts map 1:1
    /// - stereo → mono averages both channels
    /// - mono → stereo/multichannel feeds the first two channels
    /// - extra destination channels (e.g. a 5.1 device) receive silence
    ///
    /// - Returns: the peak absolute sample value of `source` *before* gain, so activity is
    ///   visible even while an app is muted.
    @discardableResult
    public static func render(
        source: UnsafePointer<Float>?,
        sourceChannels: Int,
        destination: UnsafeMutablePointer<Float>,
        destinationChannels: Int,
        frameCount: Int,
        startGain: Float,
        endGain: Float
    ) -> Float {
        guard frameCount > 0, destinationChannels > 0 else { return 0 }
        guard let source, sourceChannels > 0 else {
            destination.update(repeating: 0, count: frameCount * destinationChannels)
            return 0
        }

        let gainStep = (endGain - startGain) / Float(frameCount)
        var gain = startGain
        var peak: Float = 0

        for frame in 0..<frameCount {
            let input = source + frame * sourceChannels
            let output = destination + frame * destinationChannels

            var sum: Float = 0
            for channel in 0..<sourceChannels {
                let sample = input[channel]
                sum += sample
                let magnitude = abs(sample)
                if magnitude > peak { peak = magnitude }
            }

            if destinationChannels == 1 {
                output[0] = (sum / Float(sourceChannels)) * gain
            } else {
                for channel in 0..<destinationChannels {
                    let sample: Float
                    if channel < sourceChannels {
                        sample = input[channel]
                    } else if sourceChannels == 1 && channel == 1 {
                        sample = input[0]
                    } else {
                        sample = 0
                    }
                    output[channel] = sample * gain
                }
            }
            gain += gainStep
        }
        return peak
    }
}
