import SwiftUI

struct SimulatorPicker: View {
    @Bindable var viewModel: AppViewModel

    private var broadcastCount: Int {
        viewModel.broadcastSimulators.filter { $0 != viewModel.selectedSimulator?.id }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Device", selection: $viewModel.selectedSimulator) {
                if viewModel.simulators.isEmpty {
                    Text("No booted devices").tag(nil as Simulator?)
                }
                ForEach(viewModel.simulators) { sim in
                    Label {
                        Text(sim.displayName)
                    } icon: {
                        Image(systemName: sim.platform == .ios ? "iphone" : "candybarphone")
                    }
                    .tag(sim as Simulator?)
                }
            }
            .frame(minWidth: 250)

            Button {
                viewModel.showBroadcastPopover.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    if broadcastCount > 0 {
                        Text("\(broadcastCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
            }
            .help("Broadcast to other devices")
            .popover(isPresented: $viewModel.showBroadcastPopover, arrowEdge: .bottom) {
                BroadcastPopover(viewModel: viewModel)
            }

            if !viewModel.adbAvailable && !viewModel.adbGuidanceDismissed {
                Button {
                    viewModel.showAdbGuidancePopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.orange)
                }
                .help("Android emulator support")
                .popover(isPresented: $viewModel.showAdbGuidancePopover, arrowEdge: .bottom) {
                    AdbGuidancePopover(viewModel: viewModel)
                }
            }

            Button {
                Task { await viewModel.refreshSimulators() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh device list")
        }
    }
}

private struct BroadcastPopover: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Broadcast to")
                .font(.headline)

            if viewModel.broadcastableSimulators.isEmpty {
                Text("No other booted devices")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(viewModel.broadcastableSimulators) { sim in
                    Toggle(isOn: Binding(
                        get: { viewModel.broadcastSimulators.contains(sim.id) },
                        set: { _ in viewModel.toggleBroadcast(for: sim) }
                    )) {
                        Label {
                            Text(sim.displayName)
                        } icon: {
                            Image(systemName: sim.platform == .ios ? "iphone" : "candybarphone")
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}

private struct AdbGuidancePopover: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Android Emulator Support", systemImage: "candybarphone")
                .font(.headline)

            Text("To simulate locations on Android emulators, install ADB (Android Debug Bridge):")
                .font(.callout)

            VStack(alignment: .leading, spacing: 4) {
                Text("Option 1: Install Android Studio")
                    .font(.callout.weight(.medium))
                Text("ADB is included with Android Studio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Option 2: Standalone Platform Tools")
                    .font(.callout.weight(.medium))
                    .padding(.top, 4)
                Link("Download from developer.android.com",
                     destination: URL(string: "https://developer.android.com/tools/releases/platform-tools")!)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Dismiss") {
                    viewModel.dismissAdbGuidance()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
