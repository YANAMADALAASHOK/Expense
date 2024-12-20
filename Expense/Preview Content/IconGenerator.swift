import SwiftUI

struct IconGenerator: View {
    var body: some View {
        ZStack {
            // Background Circle with Gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.6, blue: 0.9),  // Bright Blue
                            Color(red: 0.0, green: 0.4, blue: 0.8)   // Deep Blue
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 10)
            
            // Inner Circle for depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.2),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 500
                    )
                )
                .padding(40)
            
            // Rupee Symbol
            Text("₹")
                .font(.system(size: 500, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white,
                            .white.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
                .offset(y: -20) // Optical center adjustment
        }
        .frame(width: 1024, height: 1024)
        .background(Color.white)
    }
}

#Preview {
    IconGenerator()
} 