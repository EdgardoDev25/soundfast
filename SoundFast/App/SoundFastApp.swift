import SwiftUI

@main
struct SoundFastApp: App {
    var body: some Scene {
        WindowGroup {
            DiagnosticView()
                .preferredColorScheme(.dark)
        }
    }
}
