import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ModePanel(viewModel: viewModel)
                    .frame(minWidth: 280, idealWidth: 300, maxWidth: 350)

                MapContainerView(viewModel: viewModel)
                    .frame(minWidth: 400)
            }

            // Status bar
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                SimulatorPicker(viewModel: viewModel)
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.undoManager.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .help("Undo (⌘Z)")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    viewModel.undoManager.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .help("Redo (⇧⌘Z)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.clearLocation() }
                } label: {
                    Label("Clear Location", systemImage: "location.slash")
                }
                .disabled(viewModel.selectedSimulator == nil || viewModel.isLoading)
                .help("Clear simulated location")
            }
        }
        .task {
            await viewModel.refreshSimulators()
            viewModel.startPolling()
            viewModel.setupSearch()
            viewModel.loadPresets()
            viewModel.loadGeofences()
        }
    }
}
