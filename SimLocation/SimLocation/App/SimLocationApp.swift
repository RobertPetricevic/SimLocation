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
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    viewModel.undoManager.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!viewModel.canUndo)

                Button("Redo") {
                    viewModel.undoManager.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!viewModel.canRedo)
            }
        }
    }
}
