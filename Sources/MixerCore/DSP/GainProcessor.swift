/// Per-channel gains applied to one app's audio.
public struct ChannelGains: Equatable, Sendable {
    public var left: Float
    public var right: Float

    public static let silent = ChannelGains(left: 0, right: 0)

    public init(left: Float, right: Float) {
        self.left = left
        self.right = right
    }
}

/// Realtime-safe sample processing used by the tap engine's IOProc.
///
/// Performs no allocation, locking or reference counting.
public enum GainProcessor {
    /// Copies interleaved Float32 audio from `source` into `destination`, ramping each channel's
    /// gain from `startGains` to `endGains` across the buffer.
    ///
    /// Channel mapping:
    /// - stereo in, stereo (or wider) out maps 1:1; extra destination channels get silence
    /// - `isMono` folds the source channels together and sends the mix to both sides
    /// - a mono destination receives the average of the two processed sides
    /// - a mono source feeds both sides
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
        startGains: ChannelGains,
        endGains: ChannelGains,
        isMono: Bool = false
    ) -> Float {
        guard frameCount > 0, destinationChannels > 0 else { return 0 }
        guard let source, sourceChannels > 0 else {
            destination.update(repeating: 0, count: frameCount * destinationChannels)
            return 0
        }

        let leftStep = (endGains.left - startGains.left) / Float(frameCount)
        let rightStep = (endGains.right - startGains.right) / Float(frameCount)
        var leftGain = startGains.left
        var rightGain = startGains.right
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

            let sourceLeft: Float
            let sourceRight: Float
            if isMono {
                let mix = sum / Float(sourceChannels)
                sourceLeft = mix
                sourceRight = mix
            } else {
                sourceLeft = input[0]
                sourceRight = sourceChannels > 1 ? input[1] : input[0]
            }

            let left = sourceLeft * leftGain
            let right = sourceRight * rightGain

            if destinationChannels == 1 {
                output[0] = (left + right) / 2
            } else {
                output[0] = left
                output[1] = right
                for channel in 2..<destinationChannels {
                    output[channel] = 0
                }
            }

            leftGain += leftStep
            rightGain += rightStep
        }
        return peak
    }
}
