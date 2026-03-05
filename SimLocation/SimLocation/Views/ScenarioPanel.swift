import SwiftUI

struct ScenarioPanel: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run a built-in Apple location scenario.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if viewModel.allTargetsAndroid {
                Label("Scenarios are only available for iOS simulators.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            Picker("Scenario", selection: $viewModel.selectedScenario) {
                ForEach(viewModel.scenarios, id: \.self) { scenario in
                    Text(scenario).tag(scenario)
                }
            }
            .padding(.horizontal)
            .disabled(viewModel.allTargetsAndroid)

            Button("Run Scenario") {
                Task { await viewModel.runScenario() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedSimulator == nil || viewModel.isLoading || viewModel.allTargetsAndroid)
            .padding(.horizontal)
        }
    }
}
