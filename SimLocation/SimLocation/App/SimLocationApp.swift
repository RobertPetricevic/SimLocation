import SwiftUI

@main
struct SimLocationApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}
