import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import AppKit

@DependencyClient
struct ContextClient {
    var getClipboardContext: @Sendable () async -> String = { "" }
}

extension ContextClient: DependencyKey {
    static var liveValue: Self {
        let live = ContextClientLive()
        return .init(
            getClipboardContext: {
                await live.getClipboardContext()
            }
        )
    }
}

extension DependencyValues {
    var context: ContextClient {
        get { self[ContextClient.self] }
        set { self[ContextClient.self] = newValue }
    }
}

struct ContextClientLive {
    @MainActor
    func getClipboardContext() async -> String {
        let pasteboard = NSPasteboard.general
        
        // Get text from clipboard
        if let clipboardText = pasteboard.string(forType: .string) {
            // Limit context to a reasonable size (e.g., 2000 characters)
            let maxLength = 2000
            if clipboardText.count > maxLength {
                let truncated = String(clipboardText.prefix(maxLength))
                return truncated + "... (truncated)"
            }
            return clipboardText
        }
        
        return ""
    }
} 