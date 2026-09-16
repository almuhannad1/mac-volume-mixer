import SwiftUI

struct OutputSectionView: View {
    let model: MixerViewModel

    private var controller: MixerController { model.controller }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Output")
            VStack(alignment: .leading, spacing: 10) {
                devicePicker
                VolumeControlRow(
                    title: "Master Volume",
                    volume: Double(controller.masterVolume ?? 0),
                    isMuted: controller.isMasterMuted,
                    isEnabled: controller.masterVolume != nil,
                    canMute: controller.canMuteMaster,
                    onVolumeChange: model.setMasterVolume,
                    onToggleMute: model.toggleMasterMute
                ) {
                    Image(systemName: controller.currentOutputDevice?.symbolName ?? "speaker.wave.2")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                if controller.currentOutputDevice != nil, controller.masterVolume == nil {
                    Text("This device doesn't offer software volume control.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        }
    }

    private var devicePicker: some View {
        Picker("Output device", selection: Binding(
            get: { controller.currentOutputDevice?.id ?? 0 },
            set: { model.selectOutputDevice($0) }
        )) {
            if let current = controller.currentOutputDevice, !controller.outputDevices.contains(current) {
                Label(current.name, systemImage: current.symbolName).tag(current.id)
            }
            if controller.currentOutputDevice == nil {
                Text("No Output Device").tag(UInt32(0))
            }
            ForEach(controller.outputDevices) { device in
                Label(device.name, systemImage: device.symbolName).tag(device.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("Output device")
    }
}
