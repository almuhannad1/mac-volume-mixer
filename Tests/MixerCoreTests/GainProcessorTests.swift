import Testing
@testable import MixerCore

struct GainProcessorTests {
    private func render(
        _ input: [Float], sourceChannels: Int, destinationChannels: Int,
        start: ChannelGains, end: ChannelGains? = nil, isMono: Bool = false
    ) -> (output: [Float], peak: Float) {
        let frames = input.count / sourceChannels
        var output = [Float](repeating: .nan, count: frames * destinationChannels)
        let peak = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                GainProcessor.render(
                    source: source.baseAddress, sourceChannels: sourceChannels,
                    destination: destination.baseAddress!, destinationChannels: destinationChannels,
                    frameCount: frames, startGains: start, endGains: end ?? start, isMono: isMono
                )
            }
        }
        return (output, peak)
    }

    private func flat(_ gain: Float) -> ChannelGains { ChannelGains(left: gain, right: gain) }

    @Test func constantGainScalesStereo() {
        let result = render([1, -1, 0.5, -0.5], sourceChannels: 2, destinationChannels: 2, start: flat(0.5))
        #expect(result.output == [0.5, -0.5, 0.25, -0.25])
        #expect(result.peak == 1)
    }

    @Test func peakIsMeasuredBeforeGain() {
        let result = render([0.8, 0.2], sourceChannels: 2, destinationChannels: 2, start: .silent)
        #expect(result.output == [0, 0])
        #expect(result.peak == 0.8)
    }

    @Test func gainRampsLinearlyAcrossTheBuffer() {
        let result = render([1, 1, 1, 1], sourceChannels: 1, destinationChannels: 1,
                            start: flat(0), end: flat(1))
        // Mono destination averages the two processed sides, which carry the same ramp.
        #expect(result.output == [0, 0.25, 0.5, 0.75])
    }

    @Test func balanceAttenuatesOneSide() {
        let result = render([1, 1, 1, 1], sourceChannels: 2, destinationChannels: 2,
                            start: ChannelGains(left: 1, right: 0))
        #expect(result.output == [1, 0, 1, 0])
    }

    @Test func monoFoldsChannelsTogether() {
        let result = render([1, 0, 0.5, 0.5], sourceChannels: 2, destinationChannels: 2,
                            start: flat(1), isMono: true)
        #expect(result.output == [0.5, 0.5, 0.5, 0.5])
    }

    @Test func stereoToMonoDestinationAveragesSides() {
        let result = render([1, 0, 0.5, 0.5], sourceChannels: 2, destinationChannels: 1, start: flat(1))
        #expect(result.output == [0.5, 0.5])
    }

    @Test func stereoIntoMultichannelSilencesExtraChannels() {
        let result = render([0.1, 0.2], sourceChannels: 2, destinationChannels: 4, start: flat(1))
        #expect(result.output == [0.1, 0.2, 0, 0])
    }

    @Test func monoSourceFeedsBothFrontChannels() {
        let result = render([0.3], sourceChannels: 1, destinationChannels: 3, start: flat(1))
        #expect(result.output == [0.3, 0.3, 0])
    }

    @Test func missingSourceWritesSilence() {
        var output = [Float](repeating: 1, count: 6)
        let peak = output.withUnsafeMutableBufferPointer {
            GainProcessor.render(source: nil, sourceChannels: 2, destination: $0.baseAddress!, destinationChannels: 2,
                                 frameCount: 3, startGains: .silent, endGains: .silent)
        }
        #expect(output == [0, 0, 0, 0, 0, 0])
        #expect(peak == 0)
    }
}

struct VolumeCurveAndMeterTests {
    @Test func curveEndpointsAndTaper() {
        #expect(VolumeCurve.gain(forVolume: 0) == 0)
        #expect(VolumeCurve.gain(forVolume: 1) == 1)
        #expect(VolumeCurve.gain(forVolume: 0.5) == 0.25)
        #expect(VolumeCurve.gain(forVolume: 7) == 1)
        #expect(VolumeCurve.gain(forVolume: -1) == 0)
    }

    @Test func channelGainsFollowBalanceAndDucking() {
        let centred = EffectiveAppSetting(volume: 1, isMuted: false)
        #expect(VolumeCurve.channelGains(for: centred) == ChannelGains(left: 1, right: 1))

        let left = EffectiveAppSetting(volume: 1, isMuted: false, balance: -1)
        #expect(VolumeCurve.channelGains(for: left) == ChannelGains(left: 1, right: 0))

        let right = EffectiveAppSetting(volume: 1, isMuted: false, balance: 0.5)
        #expect(VolumeCurve.channelGains(for: right) == ChannelGains(left: 0.5, right: 1))

        // Ducking scales both sides and never boosts.
        #expect(VolumeCurve.channelGains(for: centred, scaledBy: 0.3) == ChannelGains(left: 0.3, right: 0.3))
        #expect(VolumeCurve.channelGains(for: centred, scaledBy: 5) == ChannelGains(left: 1, right: 1))
    }

    @Test func balanceAndMonoRequireATap() {
        #expect(EffectiveAppSetting(volume: 1, isMuted: false).isDefault)
        #expect(!EffectiveAppSetting(volume: 1, isMuted: false, balance: -0.5).isDefault)
        #expect(!EffectiveAppSetting(volume: 1, isMuted: false, isMono: true).isDefault)
    }

    @Test func mutedSettingHasZeroGain() {
        #expect(VolumeCurve.gain(for: EffectiveAppSetting(volume: 0.8, isMuted: true)) == 0)
        #expect(VolumeCurve.gain(for: EffectiveAppSetting(volume: 0.5, isMuted: false)) == 0.25)
    }

    @Test func meterScaleUsesDecibels() {
        #expect(MeterScale.level(forPeak: 0) == 0)
        #expect(MeterScale.level(forPeak: 1) == 1)
        #expect(MeterScale.level(forPeak: 2) == 1)
        #expect(MeterScale.level(forPeak: .nan) == 0)
        #expect(abs(MeterScale.level(forPeak: 0.001) - 0) < 0.0001) // −60 dB floor
        #expect(abs(MeterScale.level(forPeak: 0.031_622_78) - 0.5) < 0.001) // −30 dB
    }

    @Test func meterDecayFallsSmoothlyAndRisesInstantly() {
        #expect(MeterScale.decayed(previous: 0.2, target: 0.9) == 0.9)
        #expect(MeterScale.decayed(previous: 0.8, target: 0) == 0.6)
        #expect(MeterScale.decayed(previous: 0.004, target: 0) == 0)
    }

    @Test func atomicFloatStoresMaxAndExchanges() {
        let cell = AtomicFloat(0.2)
        cell.storeMax(0.1)
        #expect(cell.load() == 0.2)
        cell.storeMax(0.7)
        #expect(cell.exchange(0) == 0.7)
        #expect(cell.load() == 0)
    }
}
