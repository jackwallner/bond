import SwiftUI

struct PremiumGateView: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Unlock Premium", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
