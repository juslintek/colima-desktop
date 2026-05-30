import SwiftUI

struct ToastView: View {
    let message: String

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
                .accessibilityIdentifier("toast_notification_text")
                .padding(.bottom, 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: message)
    }
}
