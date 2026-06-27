import SwiftUI

struct PaywallModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                PaywallFlowSheet(impressionId: "feature_gate", onClose: { isPresented = false })
            }
    }
}

extension View {
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        modifier(PaywallModifier(isPresented: isPresented))
    }
}
