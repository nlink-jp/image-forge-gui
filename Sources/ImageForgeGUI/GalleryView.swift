import AppKit
import SwiftUI

/// Put a string on the general pasteboard.
func setClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

/// The session gallery: a grid of generated thumbnails with a selection inspector
/// along the bottom. Selection is held on the AppModel so File-menu commands
/// (Export, Reveal) can act on it.
struct GalleryView: View {
    @EnvironmentObject var model: AppModel

    /// When set, the full-size lightbox overlay shows this image (tracked by id so
    /// prev/next and newly-arriving generations stay consistent).
    @State private var lightboxID: GeneratedImage.ID?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader
            Divider()
            if model.results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.results) { img in
                            Thumbnail(image: img, isSelected: model.selection.contains(img.id))
                                // Single tap selects immediately (⌘ toggles, ⇧ extends);
                                // a *simultaneous* double-tap opens the lightbox so the
                                // single tap isn't delayed waiting to disambiguate.
                                .onTapGesture { select(img) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { lightboxID = img.id })
                                .contextMenu {
                                    Button("View") { lightboxID = img.id }
                                    Divider()
                                    contextMenu(for: img)
                                }
                        }
                    }
                    .padding(12)
                }
            }

            if model.selection.count > 1 {
                Divider()
                SelectionBar()
            } else if let selected = model.selectedImage {
                Divider()
                InspectorBar(image: selected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if lightboxID != nil {
                LightboxView(images: model.results, currentID: $lightboxID)
                    .transition(.opacity)
            }
        }
        .sheet(item: $model.upscaleRequest) { img in
            UpscaleSheet(image: img, upscalers: model.upscalerModels) { chosen in
                model.upscale(img, model: chosen)
            }
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }),
            presenting: model.pendingDeletion
        ) { ids in
            Button(ids.count == 1 ? "Move to Trash" : "Move \(ids.count) to Trash",
                   role: .destructive) {
                model.delete(ids)
                model.pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDeletion = nil }
        } message: { ids in
            Text("\(ids.count) image\(ids.count == 1 ? "" : "s") will be moved to the Trash — you can restore \(ids.count == 1 ? "it" : "them") from there.")
        }
    }

    /// A slim header above the grid: a library switcher (folder menu) on the left
    /// and an image count on the right. The menu switches libraries, adds a new one
    /// (folder picker), reveals the active folder, or removes it from the list.
    private var libraryHeader: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.libraries) { lib in
                    Button {
                        model.switchLibrary(to: lib.id)
                    } label: {
                        if lib.id == model.activeLibraryID {
                            Label(lib.name, systemImage: "checkmark")
                        } else {
                            Text(lib.name)
                        }
                    }
                }
                Divider()
                Button("New Library…") { chooseNewLibrary() }
                Button("Reveal in Finder") { model.revealLibrary() }
                Button("Remove from List") { model.removeLibrary(model.activeLibraryID) }
                    .disabled(!model.canRemoveActiveLibrary)
            } label: {
                Label(model.activeLibraryName, systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Text("\(model.results.count) image\(model.results.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Present a directory picker for a new library folder, then add + switch to it.
    private func chooseNewLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for the new library"
        if panel.runModal() == .OK, let url = panel.url {
            model.addLibrary(url: url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No images yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Compose a prompt and press Generate.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Modifier-aware selection for a thumbnail click (reads the live modifier
    /// state at click time, since SwiftUI's tap gesture doesn't carry it).
    private func select(_ img: GeneratedImage) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            model.toggleSelection(img.id)
        } else if mods.contains(.shift) {
            model.extendSelection(to: img.id)
        } else {
            model.selectOnly(img.id)
        }
    }

    /// The ids a context-menu action targets: the whole selection when the
    /// right-clicked image is part of it, otherwise just that image.
    private func targets(_ img: GeneratedImage) -> Set<GeneratedImage.ID> {
        model.selection.contains(img.id) ? model.selection : [img.id]
    }

    @ViewBuilder
    private func contextMenu(for img: GeneratedImage) -> some View {
        let sel = targets(img)
        let n = sel.count
        // Single-image actions act on the right-clicked image.
        Button("Reuse Prompt") { model.reuse(img.params, promptOnly: true) }
        Button("Reuse All Parameters") { model.reuse(img.params, promptOnly: false) }
        Button("Use as Init Image (img2img)") { model.useAsInit(img.url) }
        Divider()
        Button("Copy Prompt") { setClipboard(img.prompt) }
        Button("Copy Negative Prompt") { setClipboard(img.params.negative ?? "") }
            .disabled((img.params.negative ?? "").isEmpty)
        Button("Upscale…") { model.upscaleRequest = img }
            .disabled(model.upscalerModels.isEmpty)
        Divider()
        // Batch actions act on the selection (or just this image).
        if !model.otherLibraries.isEmpty {
            Menu(n > 1 ? "Move \(n) to Library" : "Move to Library") {
                ForEach(model.otherLibraries) { lib in
                    Button(lib.name) { model.move(sel, toLibrary: lib.id) }
                }
            }
        }
        Button(n > 1 ? "Export \(n) Images…" : "Export…") { model.export(sel) }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([img.url])
        }
        Divider()
        Button(n > 1 ? "Delete \(n) Images" : "Delete", role: .destructive) { model.requestDelete(sel) }
    }
}

/// A single gallery thumbnail. Loads the PNG from its local file URL.
struct Thumbnail: View {
    let image: GeneratedImage
    let isSelected: Bool

    var body: some View {
        AsyncImage(url: image.url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fit)
            case .failure:
                placeholder(systemImage: "exclamationmark.triangle")
            case .empty:
                ProgressView()
            @unknown default:
                placeholder(systemImage: "photo")
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.1),
                              lineWidth: isSelected ? 3 : 1)
        )
    }

    private func placeholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 28))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom bar shown when several images are selected: a count and batch actions
/// (move to another library, export, delete). Single-selection shows InspectorBar.
struct SelectionBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Text("\(model.selection.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                if !model.otherLibraries.isEmpty {
                    Menu {
                        ForEach(model.otherLibraries) { lib in
                            Button(lib.name) { model.move(model.selection, toLibrary: lib.id) }
                        }
                    } label: {
                        Label("Move to Library", systemImage: "folder")
                    }
                    .fixedSize()
                }
                Button { model.exportSelected() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { model.requestDeleteSelected() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A compact inspector for the selected image: prompt, seed, and a prompt-copy
/// button. (A fuller Inspector with all parameters is Phase 2.)
struct InspectorBar: View {
    @EnvironmentObject var model: AppModel
    let image: GeneratedImage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(image.prompt.isEmpty ? "—" : image.prompt)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    if let seed = image.seed {
                        Text("seed \(seed)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let w = image.pixelWidth ?? image.params.width,
                       let h = image.pixelHeight ?? image.params.height {
                        Text("\(w)×\(h)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(image.url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Menu {
                    Button("Reuse Prompt") { model.reuse(image.params, promptOnly: true) }
                    Button("Reuse All Parameters (make similar)") { model.reuse(image.params, promptOnly: false) }
                    Button("Use as Init Image (img2img)") { model.useAsInit(image.url) }
                    Divider()
                    Button("Upscale…") { model.upscaleRequest = image }
                        .disabled(model.upscalerModels.isEmpty)
                } label: {
                    Label("Reuse", systemImage: "arrow.uturn.backward")
                }
                .fixedSize()

                Button { setClipboard(image.prompt) } label: {
                    Label("Copy Prompt", systemImage: "doc.on.doc")
                }
                .disabled(image.prompt.isEmpty)

                Button { setClipboard(image.params.negative ?? "") } label: {
                    Label("Copy Negative", systemImage: "doc.on.doc")
                }
                .disabled((image.params.negative ?? "").isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Full-size lightbox overlay: the selected image large on a dimmed backdrop,
/// with prev/next (buttons + ←/→ keys), reveal-in-Finder, and close (button, ESC,
/// or clicking the backdrop). Tracks the image by id so prev/next wrap correctly.
struct LightboxView: View {
    @EnvironmentObject var model: AppModel
    let images: [GeneratedImage]
    @Binding var currentID: GeneratedImage.ID?

    private var index: Int? { images.firstIndex { $0.id == currentID } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture { currentID = nil }

            if let i = index {
                let img = images[i]
                VStack(spacing: 10) {
                    AsyncImage(url: img.url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        case .failure:
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        default:
                            ProgressView().controlSize(.large).tint(.white)
                        }
                    }
                    caption(img, i)
                }
                .padding(40)

                HStack {
                    navButton("chevron.left.circle.fill") { step(-1) }
                    Spacer()
                    navButton("chevron.right.circle.fill") { step(1) }
                }
                .padding(.horizontal, 20)

                VStack {
                    HStack(spacing: 14) {
                        Spacer()
                        Menu {
                            Button("Reuse Prompt") { model.reuse(img.params, promptOnly: true); currentID = nil }
                            Button("Reuse All Parameters (make similar)") { model.reuse(img.params, promptOnly: false); currentID = nil }
                            Button("Use as Init Image (img2img)") { model.useAsInit(img.url); currentID = nil }
                            Divider()
                            Button("Copy Prompt") { setClipboard(img.prompt) }
                            Button("Copy Negative") { setClipboard(img.params.negative ?? "") }
                                .disabled((img.params.negative ?? "").isEmpty)
                            Divider()
                            Button("Upscale…") { model.upscaleRequest = img; currentID = nil }
                                .disabled(model.upscalerModels.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 22))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        iconButton("folder") { NSWorkspace.shared.activateFileViewerSelecting([img.url]) }
                        iconButton("xmark.circle.fill") { currentID = nil }
                    }
                    Spacer()
                }
                .padding(18)
            }
        }
        .foregroundStyle(.white)
        // Hidden buttons carry the keyboard shortcuts (←/→ navigate, Esc closes).
        .background {
            Group {
                Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { currentID = nil }.keyboardShortcut(.cancelAction)
            }
            .opacity(0)
        }
    }

    private func step(_ delta: Int) {
        guard let i = index, !images.isEmpty else { return }
        let n = images.count
        currentID = images[(i + delta + n) % n].id
    }

    @ViewBuilder
    private func caption(_ img: GeneratedImage, _ i: Int) -> some View {
        VStack(spacing: 4) {
            Text(img.prompt.isEmpty ? "—" : img.prompt)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: 720)
            HStack(spacing: 12) {
                if let s = img.seed { Text("seed \(s)") }
                if let w = img.pixelWidth ?? img.params.width,
                   let h = img.pixelHeight ?? img.params.height { Text("\(w)×\(h)") }
                Text("\(i + 1) / \(images.count)")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func navButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 32)) }
            .buttonStyle(.plain)
            .opacity(images.count > 1 ? 0.85 : 0.2)
            .disabled(images.count <= 1)
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).font(.system(size: 22)) }
            .buttonStyle(.plain)
    }
}
