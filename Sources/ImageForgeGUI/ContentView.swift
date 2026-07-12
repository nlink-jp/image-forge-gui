import SwiftUI

/// The main window: Composer on the left, Gallery filling the rest, a status bar
/// with live progress along the bottom.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

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
        // Open the Manage Models window when requested from a menu / empty state
        // (the tick pattern mirrors newGenerationTick / reuseTick).
        .onChange(of: model.manageModelsTick) { openWindow(id: "manage-models") }
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
            } else if model.isUpscaling {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
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
        // Fixed height so the bar doesn't jump when the progress indicator (taller
        // than the text) appears/disappears between idle and generating/upscaling.
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
    }
}
