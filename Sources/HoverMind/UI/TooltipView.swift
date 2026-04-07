import SwiftUI

@Observable
final class TooltipViewModel {
    var text: String = ""
    var isStreaming: Bool = false
    var appName: String = ""
    var elementRole: String = ""
    var modelLabel: String = ""
    var fontSize: CGFloat = 12.0
    var showDismiss: Bool = false
    var onDismiss: (() -> Void)?
}

struct TooltipView: View {
    var viewModel: TooltipViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: app name + element role + dismiss button
            HStack {
                if !viewModel.appName.isEmpty {
                    HStack(spacing: 4) {
                        Text(viewModel.appName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        if !viewModel.elementRole.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(viewModel.elementRole)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        if !viewModel.modelLabel.isEmpty {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(viewModel.modelLabel)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if viewModel.showDismiss && !viewModel.isStreaming {
                    Button {
                        viewModel.onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss tooltip")
                }
            }

            // Body: streaming explanation or loading state
            if viewModel.text.isEmpty && viewModel.isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking...")
                        .font(.system(size: viewModel.fontSize))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(viewModel.text)
                    .font(.system(size: viewModel.fontSize))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if viewModel.isStreaming && !viewModel.text.isEmpty {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(10)
        .frame(minWidth: 200, maxWidth: 400, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        // Anchor to top-left of the hosting view. Without this, NSHostingView
        // centers the content vertically, causing the tooltip to shift down
        // as text grows during streaming.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
