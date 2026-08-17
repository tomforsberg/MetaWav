// UIComponents.swift
import SwiftUI

// MARK: - Explicit Indicator View
struct ExplicitIndicatorTraditional: View {
    let size: CGFloat
    
    init(size: CGFloat = 16) {
        self.size = size
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(Color(red: 0.8, green: 0.1, blue: 0.1))
                .frame(width: size, height: size)
            
            Text("E")
                .font(.system(size: size * 0.65, weight: .black, design: .default))
                .foregroundColor(.white)
        }
    }
}
