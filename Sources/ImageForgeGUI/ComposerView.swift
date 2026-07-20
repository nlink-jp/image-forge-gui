import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// hires override presented in the Composer. `Default` sends no `hires` field so
/// the engine uses the model profile's default.
enum HiresMode: String, CaseIterable, Identifiable {
    case standard = "Default"
    case off = "Off"
    case auto = "Auto"
    case on = "On"

    var id: String { rawValue }

    /// Map a request's `hires` value ("off"/"auto"/"on"/nil) back to a mode.
    init(value: String?) {
        switch value {
        case "off": self = .off
        case "auto": self = .auto
        case "on": self = .on
        default: self = .standard
        }
    }

    /// The `hires` value sent to serve (nil for the profile default).
    var value: String? {
        switch self {
        case .standard: return nil
        case .off: return "off"
        case .auto: return "auto"
        case .on: return "on"
        }
    }
}

/// One LoRA selection in the Composer: which installed LoRA, and its weight.
/// LoRAs are applied per render (no model reload), so several can be stacked.
struct LoRARow: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var weight: Double = 1.0
}

/// The left-hand composer: prompt, negative, model, and the core generation
/// parameters. Numeric fields left blank mean "use the model profile default".
struct ComposerView: View {
    @EnvironmentObject var model: AppModel

    @State private var prompt = ""
    @State private var negative = ""
    @State private var selectedModel: String?
    @State private var randomSeed = true
    @State private var seedText = ""
    @State private var stepsText = ""
    @State private var cfgText = ""
    @State private var width: Int?
    @State private var height: Int?
    @State private var count = 1
    @State private var hires: HiresMode = .standard
    @State private var samplerOverride = ""   // "" = model profile default
    @State private var schedulerOverride = "" // "" = engine/profile default
    @State private var clipSkipOverride = 0    // 0 = model profile default
    @State private var initImageURL: URL?      // set => img2img
    @State private var strength: Double = 0.6  // img2img denoise strength
    @State private var maskEnabled = false     // reveal the inpaint mask editor (with an init image)
    @State private var maskDrawing = MaskDrawing()
    @State private var loraRows: [LoRARow] = []
    @State private var controlNetName: String?      // set + a control image => ControlNet
    @State private var controlImageURL: URL?
    @State private var controlStrength: Double = 0.9 // matches gen's --control-strength default
    @State private var canny = false                 // edge-preprocess the control image
    /// Hide questionable/explicit models from the picker when on.
    @AppStorage("safeOnly") private var safeOnly = false
    /// Merge the selected LoRAs' trigger words into the prompt at generation time
    /// (kept out of the prompt field to avoid clutter/accumulation).
    @AppStorage("autoAddTriggers") private var autoAddTriggers = true

    /// Presents the "stop now / finish current" choice (batch runs only).
    @State private var showStopOptions = false

    @FocusState private var promptFocused: Bool

    /// Largest batch the Count slider offers. Images render one at a time, so a
    /// big batch is a long unattended run rather than a memory risk — which is why
    /// it's paired with a graceful stop (see `AppModel.stopAfterCurrentImage`).
    static let maxCount = 50

    /// Common SDXL-friendly dimensions; nil = the model profile default.
    private static let sizes: [Int] = [512, 640, 768, 832, 896, 1024, 1152, 1216, 1344]
    /// sd.cpp sampler / scheduler names (empty selection = the profile default).
    private static let samplers = ["euler_a", "euler", "heun", "dpm2", "dpm++2s_a",
                                   "dpm++2m", "dpm++2mv2", "ipndm", "ipndm_v", "lcm",
                                   "ddim_trailing", "tcd"]
    private static let schedulers = ["discrete", "karras", "exponential", "ays",
                                     "sgm_uniform", "simple", "kl_optimal", "gits",
                                     "smoothstep", "beta"]

    private var diffusionModels: [ModelInfo] {
        model.models.filter { $0.isDiffusion && (!safeOnly || ($0.rating ?? "") == "safe") }
    }

    /// Picker label: "name — ARCH", plus the catalog content rating for non-safe
    /// entries (`· questionable` / `· explicit`).
    private func modelLabel(_ m: ModelInfo) -> String {
        var s = "\(m.name) — \(m.arch.uppercased())"
        if let r = m.rating, !r.isEmpty, r != "safe" { s += "  ·  \(r)" }
        return s
    }

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isGenerating
            && !model.isUpscaling
            && selectedModel != nil
    }

    var body: some View {
        Form {
            Section("Prompt") {
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 150)
                    .focused($promptFocused)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Negative prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $negative)
                        .font(.body)
                        .frame(minHeight: 90)
                }
            }

            Section("Model") {
                Picker("Model", selection: $selectedModel) {
                    if diffusionModels.isEmpty {
                        Text(safeOnly ? "No safe models installed" : "No models installed")
                            .tag(String?.none)
                    }
                    ForEach(diffusionModels) { m in
                        Text(modelLabel(m)).tag(String?.some(m.name))
                    }
                }
                .disabled(diffusionModels.isEmpty)
                Toggle("Safe only (hide questionable / explicit)", isOn: $safeOnly)

                // First-run onboarding: with no model installed, the picker is a
                // dead end — offer an in-app way to get one (ADR-0001) instead of
                // sending the user to the terminal.
                if diffusionModels.isEmpty {
                    Button {
                        model.requestManageModels()
                    } label: {
                        Label(model.models.isEmpty ? "Get your first model…" : "Manage Models…",
                              systemImage: "arrow.down.circle")
                    }
                    .help("Browse the catalog and install a model")
                }
            }

            Section("LoRA") {
                loraControl
            }

            Section("Init image (img2img)") {
                initImageControl
            }

            Section("ControlNet") {
                controlNetControl
            }

            Section("Parameters") {
                Toggle("Random seed", isOn: $randomSeed)
                if !randomSeed {
                    TextField("Seed", text: $seedText)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Steps (default)", text: $stepsText)
                    .textFieldStyle(.roundedBorder)
                TextField("CFG (default)", text: $cfgText)
                    .textFieldStyle(.roundedBorder)
                Picker("Width", selection: $width) {
                    Text("Default").tag(Int?.none)
                    ForEach(Self.sizes, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                Picker("Height", selection: $height) {
                    Text("Default").tag(Int?.none)
                    ForEach(Self.sizes, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                Picker("Hires", selection: $hires) {
                    ForEach(HiresMode.allCases) { Text($0.rawValue).tag($0) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count: \(count)")
                    // No `step:` — on macOS that draws a tick mark per increment,
                    // which at 50 is a comb of hairlines. The binding rounds to a
                    // whole number anyway, so the slider still lands on integers.
                    Slider(
                        value: Binding(
                            get: { Double(count) },
                            set: { count = Int($0.rounded()) }),
                        in: 1...Double(Self.maxCount),
                        minimumValueLabel: Text("1"), maximumValueLabel: Text("\(Self.maxCount)")
                    ) { Text("Count") }
                }
            }

            Section("Advanced") {
                Picker("Sampler", selection: $samplerOverride) {
                    Text("Profile default").tag("")
                    ForEach(Self.samplers, id: \.self) { Text($0).tag($0) }
                }
                Picker("Scheduler", selection: $schedulerOverride) {
                    Text("Default").tag("")
                    ForEach(Self.schedulers, id: \.self) { Text($0).tag($0) }
                }
                Picker("Clip skip", selection: $clipSkipOverride) {
                    Text("Profile default").tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
            }

            Section {
                licenseControl
            } header: {
                HStack(spacing: 6) {
                    Text("License")
                    if anyLicenseFlags {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption)
                    }
                }
            }

            Section {
                if model.isGenerating {
                    // With images still queued, stopping is ambiguous — the current
                    // render may be minutes in and worth keeping — so ask. With
                    // nothing queued there's only one outcome; stop straight away.
                    Button(role: .destructive, action: requestStop) {
                        Label("Cancel", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(".", modifiers: .command)
                    .confirmationDialog(
                        "Stop generating?", isPresented: $showStopOptions, titleVisibility: .visible
                    ) {
                        Button("Stop Now", role: .destructive, action: model.cancelGeneration)
                        Button("Finish Current Image", action: model.stopAfterCurrentImage)
                        Button("Keep Generating", role: .cancel) {}
                    } message: {
                        Text(stopDialogMessage)
                    }
                } else {
                    Button(action: generate) {
                        Label("Generate", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canGenerate)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: syncSelectedModel)
        .onChange(of: model.models) { _, _ in syncSelectedModel(); pruneIncompatibleAuxModels() }
        .onChange(of: safeOnly) { _, _ in syncSelectedModel() }
        // A LoRA / ControlNet is bound to its base architecture — switching models
        // drops the ones that no longer apply.
        .onChange(of: selectedModel) { _, _ in pruneIncompatibleAuxModels() }
        .onChange(of: model.newGenerationTick) { _, _ in resetComposer() }
        .onChange(of: model.reuseTick) { _, _ in applyReuse() }
        .onChange(of: model.setInitTick) { _, _ in
            if let u = model.pendingInitURL { initImageURL = u }
        }
    }

    // MARK: - LoRA

    /// The base model's architecture (LoRAs are bound to it).
    private var selectedArch: String { model.arch(ofModel: selectedModel) }

    /// Installed LoRAs compatible with the selected base model.
    private var compatibleLoRAs: [ModelInfo] {
        selectedModel == nil ? [] : model.loras(forArch: selectedArch)
    }

    /// Compatible LoRAs not already stacked (so each is offered once).
    private var unusedLoRAs: [ModelInfo] {
        let used = Set(loraRows.map(\.name))
        return compatibleLoRAs.filter { !used.contains($0.name) }
    }

    /// The `loras` payload sent to serve: "<path>:<weight>" per row.
    private var loraPayload: [String] {
        AppModel.loraPayload(
            selections: loraRows.map { (name: $0.name, weight: $0.weight) },
            models: model.models)
    }

    @ViewBuilder private var loraControl: some View {
        if compatibleLoRAs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedModel == nil
                     ? "Select a model first."
                     : "No LoRAs installed for \(selectedArch.uppercased()).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if selectedModel != nil {
                    Button("Get LoRAs in Manage Models…") { model.requestManageModels() }
                        .buttonStyle(.link)
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach($loraRows) { $row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Picker("", selection: $row.name) {
                            ForEach(compatibleLoRAs) { Text($0.name).tag($0.name) }
                        }
                        .labelsHidden()
                        Button {
                            loraRows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this LoRA")
                    }
                    HStack(spacing: 8) {
                        Text("Weight").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $row.weight, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", row.weight))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    let triggers = model.triggerWords(forLoRA: row.name)
                    if !triggers.isEmpty {
                        Text("trigger: \(triggers.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            Button { addLoRA() } label: {
                Label("Add LoRA", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(unusedLoRAs.isEmpty)

            triggerControl
        }
    }

    /// Section-level trigger handling: rather than editing the prompt when a LoRA
    /// is picked (which piles up stale tokens), the selected LoRAs' trigger words
    /// are shown here and merged into the prompt only at generation — toggleable,
    /// so the user can instead place them by hand.
    @ViewBuilder private var triggerControl: some View {
        if !selectedLoRATriggers.isEmpty {
            let joined = selectedLoRATriggers.joined(separator: ", ")
            Divider()
            Toggle("Add trigger words automatically", isOn: $autoAddTriggers)
                .font(.callout)
            // A read-only, selectable box holding just the trigger words, plus a
            // one-click Copy — so they're easy to paste in when auto-add is off.
            HStack(spacing: 6) {
                Text(joined)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))
                Button { setClipboard(joined) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy trigger words")
            }
            Text(autoAddTriggers
                 ? "Prepended when you Generate (words already in the prompt are skipped)."
                 : "Not added — paste these into your prompt yourself, or the LoRA won't take effect.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The de-duplicated trigger words of all stacked LoRAs (not in the prompt).
    private var selectedLoRATriggers: [String] {
        AppModel.combinedTriggerWords(forLoRAs: loraRows.map(\.name), models: model.models)
    }

    // MARK: - License

    /// The base model + stacked LoRAs + the selected ControlNet currently in use,
    /// for the License section (so a ControlNet's license/credit surfaces too).
    private var modelsInUse: [ModelInfo] {
        var out: [ModelInfo] = []
        if let sel = selectedModel, let m = model.models.first(where: { $0.name == sel }) {
            out.append(m)
        }
        for row in loraRows {
            if let m = model.models.first(where: { $0.name == row.name }) { out.append(m) }
        }
        if let cn = controlNetName, let m = model.models.first(where: { $0.name == cn }) {
            out.append(m)
        }
        return out
    }

    /// True when any model in use carries a notable license restriction.
    private var anyLicenseFlags: Bool { modelsInUse.contains { $0.hasLicenseFlags } }

    /// Always-on license summary: one row per model in use. Restricted models are
    /// highlighted (orange) with flag chips; permissive ones are shown plainly.
    @ViewBuilder private var licenseControl: some View {
        if modelsInUse.isEmpty {
            Text("Select a model to see its license.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(modelsInUse) { m in licenseRow(m) }
            if anyLicenseFlags {
                Text("You are using models with usage restrictions — check each license before sharing or selling the output.")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            creditControl
        }
    }

    /// The combined credit for the models in use — the same text image-forge writes
    /// into the PNG metadata's `credit` field. Empty when none require attribution.
    private var combinedCredit: String {
        AppModel.combinedCredit(forModels: modelsInUse)
    }

    /// When a model in use requires attribution, show the credit to include — a
    /// read-only selectable box plus one-click Copy. It matches what's recorded in
    /// the image metadata, so the user can paste it wherever they share the image.
    @ViewBuilder private var creditControl: some View {
        if !combinedCredit.isEmpty {
            Divider()
            Text("Credit to include")
                .font(.caption.weight(.medium))
            HStack(spacing: 6) {
                Text(combinedCredit)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))
                Button { setClipboard(combinedCredit) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy credit")
            }
            Text("Also written into the image metadata (never burned into the pixels).")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func licenseRow(_ m: ModelInfo) -> some View {
        let flags = m.licenseFlags ?? []
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: flags.isEmpty ? "checkmark.seal" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(flags.isEmpty ? Color.secondary : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.name).font(.caption.weight(.medium))
                if !flags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(flags, id: \.self) { f in
                            Text(licenseFlagLabel(f))
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.5)))
                        }
                    }
                }
                if let lic = m.license, !lic.isEmpty {
                    Text(lic).font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }

    private func licenseFlagLabel(_ f: String) -> String {
        switch f {
        case "non-commercial": return "Non-commercial"
        case "no-derivatives": return "No derivatives"
        case "attribution": return "Attribution"
        case "share-alike": return "Share-alike"
        case "review-license": return "Review license"
        default: return f
        }
    }

    /// The prompt actually sent: with trigger words merged in when the toggle is on.
    private var effectivePrompt: String {
        autoAddTriggers
            ? AppModel.prompt(prompt, insertingTriggers: selectedLoRATriggers)
            : prompt
    }

    private func addLoRA() {
        guard let next = unusedLoRAs.first else { return }
        loraRows.append(LoRARow(name: next.name))
    }

    /// Drop stacked LoRAs that don't match the (newly selected) base model's arch.
    /// Drop any selected LoRA or ControlNet that no longer matches the base model's
    /// architecture (called when the base model or the installed set changes) — an
    /// SDXL aux model must not linger when the base switches to SD1.5 (ADR-0006).
    private func pruneIncompatibleAuxModels() {
        let okLoRA = Set(compatibleLoRAs.map(\.name))
        loraRows.removeAll { !okLoRA.contains($0.name) }
        if let cn = controlNetName,
           !compatibleControlNets.contains(where: { $0.name == cn }) {
            controlNetName = nil
        }
    }

    /// The init-image control shown in the "Init image (img2img)" section: a
    /// drop target + file picker when empty, or a thumbnail + strength slider +
    /// Clear when set. Dropping an image file (from Finder or the gallery via
    /// "Use as Init Image") sets it.
    @ViewBuilder private var initImageControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = initImageURL {
                HStack(alignment: .top, spacing: 10) {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) }
                        placeholder: { ProgressView() }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(url.lastPathComponent)
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                        Button("Clear") {
                            initImageURL = nil
                            maskEnabled = false
                            maskDrawing.clear()
                        }.controlSize(.small)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("Strength").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $strength, in: 0.05...1.0, step: 0.05)
                    Text(String(format: "%.2f", strength))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                Toggle("Inpaint: paint the area to regenerate", isOn: $maskEnabled)
                    .font(.caption)
                if maskEnabled {
                    MaskCanvasView(initURL: url, drawing: $maskDrawing)
                }
            } else {
                Button { chooseInitImage() } label: {
                    Label("Choose or drop an image…", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("Generate variations from an existing image. Leave empty for txt2img.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: isImageFile) else { return false }
            initImageURL = url
            return true
        }
    }

    /// Installed ControlNets compatible with the selected base model (arch-bound).
    private var compatibleControlNets: [ModelInfo] {
        selectedModel == nil ? [] : model.controlNetModels(forArch: selectedArch)
    }

    /// The ControlNet section: pick an arch-compatible ControlNet + a control image
    /// to steer generation by its structure. Single-select (one model + one image).
    /// Only SD1.5 ships today, so this is empty unless an SD1.5 base is selected.
    @ViewBuilder private var controlNetControl: some View {
        if compatibleControlNets.isEmpty {
            Text(selectedModel == nil
                 ? "Select a model first."
                 : "No ControlNet installed for this model's architecture. Pull one — e.g. `image-forge models pull controlnet-canny-sd15` (SD1.5 only for now).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("ControlNet", selection: $controlNetName) {
                Text("None").tag(String?.none)
                ForEach(compatibleControlNets) { m in Text(m.name).tag(String?.some(m.name)) }
            }
            if controlNetName != nil {
                controlImagePicker
                HStack(spacing: 8) {
                    Text("Strength").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $controlStrength, in: 0.0...1.0, step: 0.05)
                    Text(String(format: "%.2f", controlStrength))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                Toggle("Canny edge preprocessing", isOn: $canny)
                    .font(.callout)
                Text("Canny extracts edges from the control image; turn it off if the image is already an edge/structure map. Switching the ControlNet reloads the base model.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Control-image drop/choose target (mirrors the init-image control), shown once
    /// a ControlNet model is selected.
    @ViewBuilder private var controlImagePicker: some View {
        if let url = controlImageURL {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) }
                    placeholder: { ProgressView() }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                    Button("Clear") { controlImageURL = nil }.controlSize(.small)
                }
                Spacer()
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first(where: isImageFile) else { return false }
                controlImageURL = u
                return true
            }
        } else {
            Button { chooseControlImage() } label: {
                Label("Choose or drop a control image…", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first(where: isImageFile) else { return false }
                controlImageURL = u
                return true
            }
        }
    }

    /// Default the picker to the first diffusion model once the list loads.
    private func syncSelectedModel() {
        if selectedModel == nil || !diffusionModels.contains(where: { $0.name == selectedModel }) {
            selectedModel = diffusionModels.first?.name
        }
    }

    private func resetComposer() {
        prompt = ""
        negative = ""
        seedText = ""
        stepsText = ""
        cfgText = ""
        width = nil
        height = nil
        count = 1
        hires = .standard
        samplerOverride = ""
        schedulerOverride = ""
        clipSkipOverride = 0
        initImageURL = nil
        strength = 0.6
        loraRows = []
        controlNetName = nil
        controlImageURL = nil
        controlStrength = 0.9
        canny = false
        randomSeed = true
        promptFocused = true
    }

    /// Load a gallery image's parameters (from AppModel.pendingReuse) into the
    /// composer fields. promptOnly loads just the prompt + negative.
    private func applyReuse() {
        guard let (p, promptOnly) = model.pendingReuse else { return }
        prompt = p.prompt
        negative = p.negative ?? ""
        if !promptOnly {
            if let m = p.model, diffusionModels.contains(where: { $0.name == m }) {
                selectedModel = m
            }
            if let s = p.seed, s >= 0 {
                randomSeed = false
                seedText = String(s)
            } else {
                randomSeed = true
                seedText = ""
            }
            stepsText = p.steps.map(String.init) ?? ""
            cfgText = p.cfg.map { String(format: "%g", $0) } ?? ""
            width = p.width
            height = p.height
            samplerOverride = p.sampler ?? ""
            schedulerOverride = p.scheduler ?? ""
            clipSkipOverride = p.clipSkip ?? 0
            hires = HiresMode(value: p.hires)
            if let ip = p.initPath, !ip.isEmpty, FileManager.default.fileExists(atPath: ip) {
                initImageURL = URL(fileURLWithPath: ip)
                strength = p.strength ?? 0.6
            } else {
                initImageURL = nil
            }
            // Restore ControlNet by mapping the recorded path back to its registry
            // name (the request stores a path; the picker binds to the name).
            if let cnPath = p.controlNet, !cnPath.isEmpty,
               let cn = model.models.first(where: { $0.isControlNet && $0.path == cnPath }) {
                controlNetName = cn.name
                if let ci = p.control, !ci.isEmpty, FileManager.default.fileExists(atPath: ci) {
                    controlImageURL = URL(fileURLWithPath: ci)
                } else {
                    controlImageURL = nil
                }
                controlStrength = p.controlStrength ?? 0.9
                canny = p.canny ?? false
            } else {
                controlNetName = nil
                controlImageURL = nil
            }
        }
        promptFocused = true
    }

    /// Cancel pressed (or ⌘.): offer the stop choices when a batch still has
    /// queued images, otherwise stop immediately — with nothing queued, "finish
    /// the current image" and "stop now" differ only in whether the in-flight
    /// render is thrown away, and a one-image run has no queue to save.
    private func requestStop() {
        if model.canStopAfterCurrentImage {
            showStopOptions = true
        } else {
            model.cancelGeneration()
        }
    }

    private var stopDialogMessage: String { Self.stopDialogMessage(queued: model.queuedCount) }

    /// Pure so the wording is testable. `queued` excludes the image being rendered.
    static func stopDialogMessage(queued: Int) -> String {
        let images = "\(queued) image\(queued == 1 ? "" : "s")"
        return "\(images) still queued. Stopping now discards the image being "
            + "rendered; finishing it keeps it and drops the rest."
    }

    private func generate() {
        model.generate(
            prompt: effectivePrompt,
            negative: negative.isEmpty ? nil : negative,
            model: selectedModel,
            seed: randomSeed ? nil : Int64(seedText.trimmingCharacters(in: .whitespaces)),
            randomSeed: randomSeed,
            steps: Int(stepsText.trimmingCharacters(in: .whitespaces)),
            cfg: Double(cfgText.trimmingCharacters(in: .whitespaces)),
            width: width,
            height: height,
            count: count,
            hires: hires.value,
            sampler: samplerOverride.isEmpty ? nil : samplerOverride,
            scheduler: schedulerOverride.isEmpty ? nil : schedulerOverride,
            clipSkip: clipSkipOverride == 0 ? nil : clipSkipOverride,
            initPath: initImageURL?.path,
            strength: initImageURL == nil ? nil : strength,
            maskPath: renderMaskFile(),
            loras: loraPayload.isEmpty ? nil : loraPayload,
            controlNet: AppModel.controlNetPath(name: controlNetName, models: model.models),
            control: controlImageURL?.path,
            controlStrength: controlStrength,
            canny: canny
        )
    }

    /// Render the painted inpaint mask to a same-size PNG in a temp file and return
    /// its path — or nil when inpaint isn't enabled, there's no init image, or the
    /// mask is empty. The mask must match the init image's pixel size (image-forge
    /// requires it), so it's rendered at the init image's dimensions.
    private func renderMaskFile() -> String? {
        guard let url = initImageURL, maskEnabled, !maskDrawing.isEmpty,
              let (w, h) = MaskCanvasView.pixelSize(of: url),
              let png = maskDrawing.renderPNG(width: w, height: h) else { return nil }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("ifgui-mask-\(UUID().uuidString).png")
        do {
            try png.write(to: dest)
            return dest.path
        } catch {
            return nil
        }
    }

    /// Present an open panel to pick an init image for img2img.
    private func chooseInitImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.prompt = "Choose"
        panel.message = "Choose an init image for img2img"
        if panel.runModal() == .OK, let url = panel.url { initImageURL = url }
    }

    /// Present an open panel to pick a ControlNet control image.
    private func chooseControlImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.prompt = "Choose"
        panel.message = "Choose a ControlNet control image"
        if panel.runModal() == .OK, let url = panel.url { controlImageURL = url }
    }

    /// True for a file URL with a raster-image extension (drop filter).
    private func isImageFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "webp", "heic", "bmp", "gif", "tif", "tiff"]
            .contains(url.pathExtension.lowercased())
    }
}
