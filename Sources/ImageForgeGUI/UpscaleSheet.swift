import SwiftUI

/// A small sheet to upscale a gallery image with an installed ESRGAN model. The
/// output factor is the model's native one (image-forge ignores a requested
/// factor for Real-ESRGAN), so there's no scale control — just a model picker.
/// `onUpscale` is called with the chosen model name on confirm.
struct UpscaleSheet: View {
    let image: GeneratedImage
    let upscalers: [ModelInfo]
    let onUpscale: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upscale image").font(.headline)

            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: image.url) { $0.resizable().aspectRatio(contentMode: .fit) }
                    placeholder: { ProgressView() }
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3)))

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Model", selection: $selected) {
                        ForEach(upscalers) { Text($0.name).tag($0.name) }
                    }
                    LabeledContent("Output", value: "×4 (model native)")
                    Text("Real-ESRGAN upscales by its native factor. The result is written to the current library.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Upscale") {
                    onUpscale(selected)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear { if selected.isEmpty { selected = upscalers.first?.name ?? "" } }
    }
}
