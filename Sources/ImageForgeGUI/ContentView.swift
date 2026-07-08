import SwiftUI

/// The main window: Composer on the left, Gallery filling the rest, a status bar
/// with live progress along the bottom.
struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ComposerView()
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
                GalleryView()
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            StatusBar()
        }
    }
}

/// Bottom status bar: a progress bar while generating, the current status
/// message, and any error surfaced from the engine.
struct StatusBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isGenerating {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
            }
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let err = model.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(err)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
