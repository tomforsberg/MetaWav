import SwiftUI

// Shared glass background with subtle top sheen. Safe for click-through.
public struct GlassFillBackground: ViewModifier {
    let material: Material

    public func body(content: Content) -> some View {
        content
            .background(material)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.03),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)
            )
    }
}

public extension View {
    // System Liquid Glass wrapper with safe availability and graceful fallback
    func liquidGlass(_ shape: some Shape = RoundedRectangle(cornerRadius: 14, style: .continuous)) -> some View {
        // Always provide a real blur using system Material.
        // On macOS 15+, we can augment with the new Glass API elsewhere when ready.
        self
            .background(
                shape.fill(.ultraThinMaterial)
            )
            .clipShape(shape)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(shape)
                .allowsHitTesting(false)
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.06))
            )
    }
    func glassFill(_ material: Material = .ultraThinMaterial) -> some View {
        self.modifier(GlassFillBackground(material: material))
    }

    // Secondary, lighter glass for chips, fields, and small UI
    func secondaryGlass(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            // Very subtle tint to lighten without turning white
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0, green: 0.75, blue: 0.39).opacity(0.03))
                    .allowsHitTesting(false)
            )
            // Whisper-light highlight to lift the surface slightly
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.02))
                    .allowsHitTesting(false)
            )
            // Soft edge definition
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06))
                    .allowsHitTesting(false)
            )
    }

    // Darker, focused glass for selected states (opposite of secondaryGlass)
    func selectedGlass(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            // Subtle darkening to increase focus without losing glass feel
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .allowsHitTesting(false)
            )
            // Soft inner lift to prevent looking flat
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.01))
                    .allowsHitTesting(false)
            )
            // Slightly stronger edge to differentiate from hover
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10))
                    .allowsHitTesting(false)
            )
    }

    // Glass 3: Neutral input-field glass (between secondary and selected)
    func glass3(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial)
            // Gentle dark tint to cue input affordance
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .allowsHitTesting(false)
            )
            // Very soft edge for definition
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
                    .allowsHitTesting(false)
            )
    }
}

// Internal container to isolate the usage of the new glass API.
// If the real API is `.glass(...)`, we call it here to keep edits localized.
@available(macOS 15.0, *)
private struct GlassBackgroundContainer<S: Shape>: View {
    let shape: S
    var body: some View {
        // Adopt Apple's Liquid Glass. Replace with the exact API as needed.
        // Prefer keeping the call in one place for easy maintenance.
        shape
            .fill(.clear)
            .background(
                // Expected API (Apple docs): `.glass(...)` on a view.
                // Using conditional compilation-like isolation to avoid widespread changes.
                shape
                    .stroke(.clear)
                    .modifier(GlassEffectShim())
            )
            .clipShape(shape)
    }
}

// A shim modifier to host the real `.glass` call when building on macOS 15+.
@available(macOS 15.0, *)
private struct GlassEffectShim: ViewModifier {
    func body(content: Content) -> some View {
        // Replace with the real API call once available in the toolchain.
        // Example targets described by Apple docs:
        // content.glass(.regular, in: .rect(cornerRadius: 14))
        content
    }
}

// Type eraser for Shape to allow storing shape in variables
private struct AnyShape: Shape, @unchecked Sendable {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ wrapped: S) {
        self.pathBuilder = { rect in
            wrapped.path(in: rect)
        }
    }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}


