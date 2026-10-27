import SwiftUI

private struct ShowWelcomeKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showWelcome: (() -> Void)? {
        get { self[ShowWelcomeKey.self] }
        set { self[ShowWelcomeKey.self] = newValue }
    }
}

struct WelcomeCommands: Commands {
    @FocusedValue(\.showWelcome) private var showWelcome

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Welcome to IconMator…") { showWelcome?() }
                .disabled(showWelcome == nil)
        }
    }
}
