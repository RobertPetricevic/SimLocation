import SwiftUI

struct SimulatorPicker: View {
    @Bindable var viewModel: AppViewModel

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
                Task { await viewModel.refreshSimulators() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh simulator list")
        }
    }
}
