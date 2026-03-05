import SwiftUI

struct ScenarioPanel: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run a built-in Apple location scenario.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Picker("Scenario", selection: $viewModel.selectedScenario) {
                ForEach(viewModel.scenarios, id: \.self) { scenario in
                    Text(scenario).tag(scenario)
                }
            }
            .padding(.horizontal)

            Button("Run Scenario") {
                Task { await viewModel.runScenario() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedSimulator == nil || viewModel.isLoading)
            .padding(.horizontal)
        }
    }
}
