import SwiftUI

struct EmptyReaderStateView: View {
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(MudsnoteColors.muted)
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
            Text(message)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(MudsnoteColors.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MudsnoteColors.canvas)
    }
}
