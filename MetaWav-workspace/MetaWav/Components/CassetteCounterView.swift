import SwiftUI

/// Mechanical-style three-digit cassette counter with rolling digits and a RESET button.
struct CassetteCounterView: View {
    let value: Int    // 0...999
    let isEnabled: Bool
    let onReset: () -> Void
    
    private var clampedValue: Int {
        min(max(value, 0), 999)
    }
    
    private var digits: [Int] {
        let v = clampedValue
        return [
            (v / 100) % 10,
            (v / 10) % 10,
            v % 10
        ]
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Counter window
            ZStack {
                // Outer frame
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.9),
                                Color.black.opacity(0.4)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.35),
                                        Color.black.opacity(0.9)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    )
                    .shadow(color: Color.black.opacity(0.8), radius: 3, x: 0, y: 1)
                
                // Inner window background
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .inset(by: 2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.10, green: 0.10, blue: 0.11),
                                Color(red: 0.06, green: 0.06, blue: 0.07)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        DigitDrumView(
                            digit: digits[index],
                            isEnabled: isEnabled
                        )
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            .frame(width: 60, height: 20)
            
            // RESET button
            Button(action: onReset) {
                Text("RESET")
                    .font(Font.custom("Roboto", size: 8).weight(.medium))
                    .foregroundColor(Color.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.22, green: 0.22, blue: 0.25),
                                        Color.black.opacity(0.85)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.35),
                                                Color.black.opacity(0.9)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Single rolling digit "drum" for the cassette counter.
private struct DigitDrumView: View {
    let digit: Int
    let isEnabled: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            
            VStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { value in
                    Text("\(value)")
                        .font(Font.custom("Roboto Mono", size: 12).weight(.medium))
                        .foregroundColor(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.4))
                        .frame(height: height, alignment: .center)
                }
            }
            .offset(y: -CGFloat(digit) * height)
            .animation(.easeOut(duration: 0.12), value: digit)
            .frame(height: height, alignment: .top)
            .clipped()
        }
    }
}


