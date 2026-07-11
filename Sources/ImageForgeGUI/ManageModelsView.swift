import SwiftUI

/// The Manage Models window (ADR-0001): browse the curated catalog and install
/// models with live progress, and remove installed models to reclaim disk.
/// Driven by `image-forge models list --catalog --json` / `pull` / `rm --purge`.
struct ManageModelsView: View {
    @EnvironmentObject var model: AppModel
    @State private var pendingRemove: ModelInfo?
    @State private var pendingOptIn: CatalogEntry?

    /// Catalog entries not yet installed — the "Available to install" list.
    private var available: [CatalogEntry] { model.catalog.filter { !$0.isInstalled } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 540, minHeight: 500)
        .onAppear { if model.catalog.isEmpty { model.loadCatalog() } }
        .confirmationDialog(
            "Remove model?",
            isPresented: bindingPresent($pendingRemove),
            presenting: pendingRemove
        ) { m in
            Button("Delete “\(m.name)” and its files", role: .destructive) {
                model.removeModel(m.name); pendingRemove = nil
            }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        } message: { _ in
            Text("This deletes the weight files from disk to reclaim space. Files shared with another installed model are kept.")
        }
        .confirmationDialog(
            "Install a rated model?",
            isPresented: bindingPresent($pendingOptIn),
            presenting: pendingOptIn
        ) { e in
            Button("Install “\(e.name)”", role: .destructive) {
                model.install(e, allowNSFW: true); pendingOptIn = nil
            }
            Button("Cancel", role: .cancel) { pendingOptIn = nil }
        } message: { e in
            Text("“\(e.name)” is rated \(e.rating ?? "questionable"). Install it anyway?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manage Models").font(.headline)
                Text("Install models from the catalog, or remove installed ones to free space.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.loadModels(); model.loadCatalog()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.catalogLoading)
        }
        .padding(12)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if model.catalogLoading && model.catalog.isEmpty {
            ProgressView("Loading catalog…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = model.catalogError, model.catalog.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text("Couldn't load the catalog").font(.headline)
                Text(err).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Button("Try Again") { model.loadCatalog() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section("Installed (\(model.models.count))") {
                    if model.models.isEmpty {
                        Text("No models installed yet — install one below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.models) { m in installedRow(m) }
                }
                Section("Available to install (\(available.count))") {
                    ForEach(available) { e in catalogRow(e) }
                }
            }
        }
    }

    // MARK: - Rows

    private func installedRow(_ m: ModelInfo) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).fontWeight(.medium)
                HStack(spacing: 6) {
                    badge(m.isDiffusion ? m.arch.uppercased() : (m.kind ?? "").capitalized)
                    if let r = m.rating, !r.isEmpty, r != "safe" { ratingBadge(r) }
                    if m.hasLicenseFlags {
                        Label("license", systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button(role: .destructive) { pendingRemove = m } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func catalogRow(_ e: CatalogEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.name).fontWeight(.medium)
                    if e.experimental == true {
                        badge("experimental", color: .orange)
                    }
                }
                HStack(spacing: 6) {
                    badge(e.kindLabel)
                    if let r = e.rating, !r.isEmpty, r != "safe" { ratingBadge(r) }
                    if let ram = e.recRAMGB { Text("\(ram) GB RAM").font(.caption2).foregroundStyle(.secondary) }
                    if let lic = e.license, !lic.isEmpty {
                        Text(lic).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let notes = e.notes, !notes.isEmpty {
                    Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            installControl(e)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func installControl(_ e: CatalogEntry) -> some View {
        if let st = model.installs[e.name] {
            VStack(alignment: .trailing, spacing: 2) {
                if let f = st.fraction {
                    ProgressView(value: f).frame(width: 120)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(st.status).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).frame(maxWidth: 140, alignment: .trailing)
            }
        } else {
            Button {
                if e.requiresOptIn { pendingOptIn = e } else { model.install(e, allowNSFW: false) }
            } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Small helpers

    private func badge(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func ratingBadge(_ rating: String) -> some View { badge(rating, color: .orange) }

    /// A Bool binding that presents while `value` is non-nil and clears it on dismiss.
    private func bindingPresent<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
