import Testing
@testable import MixerCore

struct GainProcessorTests {
    private func render(
        _ input: [Float], sourceChannels: Int, destinationChannels: Int, startGain: Float, endGain: Float
    ) -> (output: [Float], peak: Float) {
        let frames = input.count / sourceChannels
        var output = [Float](repeating: .nan, count: frames * destinationChannels)
        let peak = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                GainProcessor.render(
                    source: source.baseAddress, sourceChannels: sourceChannels,
                    destination: destination.baseAddress!, destinationChannels: destinationChannels,
                    frameCount: frames, startGain: startGain, endGain: endGain
                )
            }
        }
        return (output, peak)
    }

    @Test func constantGainScalesStereo() {
        let result = render([1, -1, 0.5, -0.5], sourceChannels: 2, destinationChannels: 2, startGain: 0.5, endGain: 0.5)
        #expect(result.output == [0.5, -0.5, 0.25, -0.25])
        #expect(result.peak == 1)
    }

    @Test func peakIsMeasuredBeforeGain() {
        let result = render([0.8, 0.2], sourceChannels: 2, destinationChannels: 2, startGain: 0, endGain: 0)
        #expect(result.output == [0, 0])
        #expect(result.peak == 0.8)
    }

    @Test func gainRampsLinearlyAcrossTheBuffer() {
        let result = render([1, 1, 1, 1], sourceChannels: 1, destinationChannels: 1, startGain: 0, endGain: 1)
        #expect(result.output == [0, 0.25, 0.5, 0.75])
    }

    @Test func stereoToMonoAveragesChannels() {
        let result = render([1, 0, 0.5, 0.5], sourceChannels: 2, destinationChannels: 1, startGain: 1, endGain: 1)
        #expect(result.output == [0.5, 0.5])
    }

    @Test func stereoIntoMultichannelSilencesExtraChannels() {
        let result = render([0.1, 0.2], sourceChannels: 2, destinationChannels: 4, startGain: 1, endGain: 1)
        #expect(result.output == [0.1, 0.2, 0, 0])
    }

    @Test func monoSourceFeedsBothFrontChannels() {
        let result = render([0.3], sourceChannels: 1, destinationChannels: 3, startGain: 1, endGain: 1)
        #expect(result.output == [0.3, 0.3, 0])
    }

    @Test func missingSourceWritesSilence() {
        var output = [Float](repeating: 1, count: 6)
        let peak = output.withUnsafeMutableBufferPointer {
            GainProcessor.render(source: nil, sourceChannels: 2, destination: $0.baseAddress!, destinationChannels: 2,
                                 frameCount: 3, startGain: 1, endGain: 1)
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

    @Test func mutedSettingHasZeroGain() {
        #expect(VolumeCurve.gain(for: AppVolumeSetting(volume: 0.8, isMuted: true)) == 0)
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
