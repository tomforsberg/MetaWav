import SwiftUI

// MARK: - Standard 3D Button Style (73.80 x 35.01)
struct Realistic3DButtonStyle: ButtonStyle {
    var width: CGFloat = 73.80
    var height: CGFloat = 35.01
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(
                ZStack {
                    // Base button background with gradient
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: configuration.isPressed ?
                                          Color(red: 0.25, green: 0.25, blue: 0.25) :
                                          Color(red: 0.40, green: 0.40, blue: 0.40), location: 0.0),
                                    .init(color: Color(red: 0.33, green: 0.33, blue: 0.33), location: 0.5),
                                    .init(color: configuration.isPressed ?
                                          Color(red: 0.30, green: 0.30, blue: 0.30) :
                                          Color(red: 0.25, green: 0.25, blue: 0.25), location: 1.0)
                                ]),
                                startPoint: configuration.isPressed ? .bottomLeading : .topLeading,
                                endPoint: configuration.isPressed ? .topTrailing : .bottomTrailing
                            )
                        )
                    
                    // Top highlight (specular reflection)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(configuration.isPressed ? 0.05 : 0.15), location: 0.0),
                                    .init(color: Color.clear, location: configuration.isPressed ? 0.3 : 0.5)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Bottom shadow/depth
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.clear, location: configuration.isPressed ? 0.4 : 0.6),
                                    .init(color: Color.black.opacity(configuration.isPressed ? 0.25 : 0.15), location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            // Main border
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .inset(by: 0.5)
                    .stroke(
                        Color.black.opacity(configuration.isPressed ? 0.8 : 0.6),
                        lineWidth: configuration.isPressed ? 1.5 : 1.0
                    )
            )
            // Outer shadow for depth
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 1 : 3,
                x: configuration.isPressed ? 0.5 : 2,
                y: configuration.isPressed ? 0.5 : 3
            )
            // Inner shadow for pressed effect
            .overlay(
                configuration.isPressed ?
                RoundedRectangle(cornerRadius: 2)
                    .inset(by: 1)
                    .stroke(
                        Color.black.opacity(0.3),
                        lineWidth: 1
                    )
                : nil
            )
            // Position shift for depth
            .offset(
                x: configuration.isPressed ? 1 : 0,
                y: configuration.isPressed ? 1.5 : 0
            )
            // Scale for subtle size change
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            // Smooth spring animations
            .animation(
                configuration.isPressed ?
                    .easeOut(duration: 0.12) :  // Press down: 120ms
                    .spring(response: 0.08, dampingFraction: 0.8, blendDuration: 0), // Release: 80ms spring
                value: configuration.isPressed
            )
    }
}

// MARK: - Square 3D Button Style (41.48 x 41.48 by default, can be overridden)
struct Realistic3DSquareButtonStyle: ButtonStyle {
    var width: CGFloat
    var height: CGFloat
    
    init(size: CGFloat = 41.48) {
        self.width = size
        self.height = size
    }
    
    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(
                ZStack {
                    // Base button background with gradient
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: configuration.isPressed ?
                                          Color(red: 0.25, green: 0.25, blue: 0.25) :
                                          Color(red: 0.40, green: 0.40, blue: 0.40), location: 0.0),
                                    .init(color: Color(red: 0.33, green: 0.33, blue: 0.33), location: 0.5),
                                    .init(color: configuration.isPressed ?
                                          Color(red: 0.30, green: 0.30, blue: 0.30) :
                                          Color(red: 0.25, green: 0.25, blue: 0.25), location: 1.0)
                                ]),
                                startPoint: configuration.isPressed ? .bottomLeading : .topLeading,
                                endPoint: configuration.isPressed ? .topTrailing : .bottomTrailing
                            )
                        )
                    
                    // Top highlight (specular reflection)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(configuration.isPressed ? 0.05 : 0.15), location: 0.0),
                                    .init(color: Color.clear, location: configuration.isPressed ? 0.3 : 0.5)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Bottom shadow/depth
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.clear, location: configuration.isPressed ? 0.4 : 0.6),
                                    .init(color: Color.black.opacity(configuration.isPressed ? 0.25 : 0.15), location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            // Main border
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .inset(by: 0.5)
                    .stroke(
                        Color.black.opacity(configuration.isPressed ? 0.8 : 0.6),
                        lineWidth: configuration.isPressed ? 1.5 : 1.0
                    )
            )
            // Outer shadow for depth
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 1 : 3,
                x: configuration.isPressed ? 0.5 : 2,
                y: configuration.isPressed ? 0.5 : 3
            )
            // Inner shadow for pressed effect
            .overlay(
                configuration.isPressed ?
                RoundedRectangle(cornerRadius: 2)
                    .inset(by: 1)
                    .stroke(
                        Color.black.opacity(0.3),
                        lineWidth: 1
                    )
                : nil
            )
            // Position shift for depth
            .offset(
                x: configuration.isPressed ? 1 : 0,
                y: configuration.isPressed ? 1.5 : 0
            )
            // Scale for subtle size change
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            // Smooth spring animations
            .animation(
                configuration.isPressed ?
                    .easeOut(duration: 0.12) :  // Press down: 120ms
                    .spring(response: 0.08, dampingFraction: 0.8, blendDuration: 0), // Release: 80ms spring
                value: configuration.isPressed
            )
    }
}

// MARK: - Large Load Button Style (308.12 x 71.10)
struct Realistic3DLoadButtonStyle: ButtonStyle {
    var width: CGFloat = 308.12
    var height: CGFloat = 71.10
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: height)
            .background(
                ZStack {
                    // Base button background with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: configuration.isPressed ?
                                          Color(red: 0.25, green: 0.25, blue: 0.25) :
                                          Color(red: 0.40, green: 0.40, blue: 0.40), location: 0.0),
                                    .init(color: Color(red: 0.33, green: 0.33, blue: 0.33), location: 0.5),
                                    .init(color: configuration.isPressed ?
                                          Color(red: 0.30, green: 0.30, blue: 0.30) :
                                          Color(red: 0.25, green: 0.25, blue: 0.25), location: 1.0)
                                ]),
                                startPoint: configuration.isPressed ? .bottomLeading : .topLeading,
                                endPoint: configuration.isPressed ? .topTrailing : .bottomTrailing
                            )
                        )
                    
                    // Top highlight (specular reflection)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(configuration.isPressed ? 0.05 : 0.15), location: 0.0),
                                    .init(color: Color.clear, location: configuration.isPressed ? 0.3 : 0.5)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Bottom shadow/depth
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.clear, location: configuration.isPressed ? 0.4 : 0.6),
                                    .init(color: Color.black.opacity(configuration.isPressed ? 0.25 : 0.15), location: 1.0)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            // Main border
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .inset(by: 0.5)
                    .stroke(
                        Color.black.opacity(configuration.isPressed ? 0.8 : 0.6),
                        lineWidth: configuration.isPressed ? 1.5 : 1.0
                    )
            )
            // Outer shadow for depth
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.15 : 0.35),
                radius: configuration.isPressed ? 2 : 5,
                x: configuration.isPressed ? 1 : 3,
                y: configuration.isPressed ? 1.5 : 4
            )
            // Inner shadow for pressed effect
            .overlay(
                configuration.isPressed ?
                RoundedRectangle(cornerRadius: 4)
                    .inset(by: 1)
                    .stroke(
                        Color.black.opacity(0.3),
                        lineWidth: 1
                    )
                : nil
            )
            // Position shift for depth
            .offset(
                x: configuration.isPressed ? 2 : 0,
                y: configuration.isPressed ? 2.5 : 0
            )
            // Scale for subtle size change
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            // Smooth spring animations
            .animation(
                configuration.isPressed ?
                    .easeOut(duration: 0.12) :  // Press down: 120ms
                    .spring(response: 0.08, dampingFraction: 0.8, blendDuration: 0), // Release: 80ms spring
                value: configuration.isPressed
            )
    }
}

// MARK: - Convenience Extensions
extension View {
    func realistic3DButton(width: CGFloat = 73.80, height: CGFloat = 35.01) -> some View {
        self.buttonStyle(Realistic3DButtonStyle(width: width, height: height))
    }
    
    func realistic3DSquareButton(size: CGFloat = 41.48) -> some View {
        self.buttonStyle(Realistic3DSquareButtonStyle(size: size))
    }
    
    func realistic3DLoadButton(width: CGFloat = 308.12, height: CGFloat = 71.10) -> some View {
        self.buttonStyle(Realistic3DLoadButtonStyle(width: width, height: height))
    }
}
