import Foundation


/// How an audio device is connected (`kAudioDevicePropertyTransportType`).
public enum AudioTransportType: Hashable, Sendable {
    case builtIn, usb, bluetooth, bluetoothLE, hdmi, displayPort, airPlay, thunderbolt
    case pci, fireWire, avb, virtual, aggregate, continuityCapture
    case unknown(UInt32)

    public init(code: UInt32) {
        switch code {
        case FourCharCode.make("bltn"): self = .builtIn
        case FourCharCode.make("usb "): self = .usb
        case FourCharCode.make("blue"): self = .bluetooth
        case FourCharCode.make("blea"): self = .bluetoothLE
        case FourCharCode.make("hdmi"): self = .hdmi
        case FourCharCode.make("dprt"): self = .displayPort
        case FourCharCode.make("airp"): self = .airPlay
        case FourCharCode.make("thun"): self = .thunderbolt
        case FourCharCode.make("pci "): self = .pci
        case FourCharCode.make("1394"): self = .fireWire
        case FourCharCode.make("eavb"): self = .avb
        case FourCharCode.make("virt"): self = .virtual
        case FourCharCode.make("grup"), FourCharCode.make("fgrp"): self = .aggregate
        case FourCharCode.make("ccwd"), FourCharCode.make("ccwl"): self = .continuityCapture
        default: self = .unknown(code)
        }
    }
}

public struct AudioOutputDevice: Hashable, Sendable, Identifiable {
    public let id: UInt32
    /// Persistent identifier; survives reconnects and reboots, unlike `id`.
    public let uid: String
    public let name: String
    public let transportType: AudioTransportType
    public let outputChannelCount: Int
    public let isHidden: Bool

    public init(id: UInt32, uid: String, name: String, transportType: AudioTransportType, outputChannelCount: Int, isHidden: Bool) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transportType = transportType
        self.outputChannelCount = outputChannelCount
        self.isHidden = isHidden
    }

    /// SF Symbol that best represents the device.
    public var symbolName: String {
        if name.localizedCaseInsensitiveContains("airpods max") { return "airpodsmax" }
        if name.localizedCaseInsensitiveContains("airpods pro") { return "airpodspro" }
        if name.localizedCaseInsensitiveContains("airpods") { return "airpods" }
        switch transportType {
        case .builtIn: return "laptopcomputer"
        case .bluetooth, .bluetoothLE: return "headphones"
        case .hdmi, .displayPort, .thunderbolt: return "display"
        case .airPlay: return "airplayaudio"
        case .usb, .fireWire, .pci, .avb: return "hifispeaker"
        case .virtual, .aggregate: return "waveform"
        case .continuityCapture: return "iphone"
        case .unknown: return "speaker.wave.2"
        }
    }
}

public enum OutputDeviceFilter {
    /// Devices that make sense in an output picker.
    public static func selectable(_ devices: [AudioOutputDevice], excludingUIDPrefix prefix: String) -> [AudioOutputDevice] {
        devices
            .filter { $0.outputChannelCount > 0 && !$0.isHidden && !$0.uid.hasPrefix(prefix) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
