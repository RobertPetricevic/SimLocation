import SwiftUI

struct SimulatorPicker: View {
    @Bindable var viewModel: AppViewModel

    private var broadcastCount: Int {
        viewModel.broadcastSimulators.filter { $0 != viewModel.selectedSimulator?.id }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Simulator", selection: $viewModel.selectedSimulator) {
                if viewModel.simulators.isEmpty {
                    Text("No booted simulators").tag(nil as Simulator?)
                }
                ForEach(viewModel.simulators) { sim in
                    Text(sim.displayName).tag(sim as Simulator?)
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
            .help("Broadcast to other simulators")
            .popover(isPresented: $viewModel.showBroadcastPopover, arrowEdge: .bottom) {
                BroadcastPopover(viewModel: viewModel)
            }

            Button {
                Task { await viewModel.refreshSimulators() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh simulator list")
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
                Text("No other booted simulators")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(viewModel.broadcastableSimulators) { sim in
                    Toggle(isOn: Binding(
                        get: { viewModel.broadcastSimulators.contains(sim.id) },
                        set: { _ in viewModel.toggleBroadcast(for: sim) }
                    )) {
                        Text(sim.displayName)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}
