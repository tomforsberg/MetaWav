import SwiftUI

// Glassy wrapper for the NPS panel bar
public struct NPSPanelContainer: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .allowsHitTesting(false),
                alignment: .top
            )
    }
}

public extension View {
    func npsGlass() -> some View { self.modifier(NPSPanelContainer()) }
}


