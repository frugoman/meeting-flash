import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var previewFlash: () -> Void
    @State private var connected: [AudioOutput] = []
    @State private var current: AudioOutput?
    @State private var ssid: String?
    @ObservedObject private var wifi = WiFi.shared

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                ForEach($settings.alerts) { $alert in
                    AlertRow(alert: $alert) {
                        settings.alerts.removeAll { $0.id == alert.id }
                    }
                }
                Button {
                    let used = Set(settings.alerts.map(\.minutesBefore))
                    let next = AlertRow.timings.first { !used.contains($0) } ?? 5
                    settings.alerts.append(MeetingAlert(minutesBefore: next))
                } label: {
                    Label("Add Alert", systemImage: "plus")
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("If several alerts are due at once (say, right after your Mac wakes up), only the most recent one fires.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Show", selection: $settings.flashStyle) {
                    Text("Colour").tag(FlashStyle.color)
                    Text("Photo").tag(FlashStyle.photo)
                }
                .pickerStyle(.segmented)

                if settings.flashStyle == .color {
                    HStack {
                        ColorPicker("Colour", selection: flashColor, supportsOpacity: true)
                        if settings.flashColor != .defaultRed {
                            Button("Reset to Red") { settings.flashColor = .defaultRed }
                                .buttonStyle(.link)
                        }
                    }
                } else {
                    LabeledContent("Photo") {
                        HStack {
                            if let url = settings.flashPhoto, let image = NSImage(contentsOf: url) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(settings.flashPhotoName ?? url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("None — the colour is used").foregroundStyle(.secondary)
                            }
                            Button("Choose…", action: choosePhoto)
                        }
                    }
                }

                Button("Preview Flash", action: previewFlash)
            } header: {
                Text("Flash")
            } footer: {
                Text("The flash stays on screen until you click anywhere or press a key. Lower the colour's opacity to keep seeing what's underneath.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Only play sounds on selected outputs", isOn: $settings.restrictOutputs)
                if settings.restrictOutputs {
                    ForEach(outputList) { output in
                        HStack {
                            Toggle(output.name, isOn: allowed(output.uid))
                                .toggleStyle(.checkbox)
                            if output.uid == current?.uid {
                                Text("current").font(.caption).foregroundStyle(.green)
                            } else if !connected.contains(where: { $0.uid == output.uid }) {
                                Text("not connected").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.allowedOutputUIDs.contains(output.uid) {
                                outputNetworkMenu(output.uid)
                            }
                        }
                    }
                }
                LabeledContent("Current output") {
                    HStack(spacing: 6) {
                        Text(current?.name ?? "Unknown")
                        Image(systemName: settings.soundAllowedNow ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundStyle(settings.soundAllowedNow ? .green : .red)
                            .help(settings.soundAllowedNow ? "An alert would play sound right now" : "Alerts are silent right now")
                    }
                }
            } header: {
                Text("Sound Output")
            } footer: {
                Text("E.g. pick only your AirPods so alerts stay silent on the laptop speakers at the office, or allow the speakers only on your home Wi-Fi. Paired Bluetooth speakers and headphones show up even when they're not connected. The flash always shows.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if !wifi.authorized {
                    HStack {
                        Text("macOS only shares Wi-Fi names with apps that have Location access.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(wifi.undetermined ? "Allow Access" : "Open Settings…") {
                            if wifi.undetermined {
                                wifi.requestAccess()
                            } else {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                            }
                        }
                    }
                }
                LabeledContent("Current Wi-Fi", value: ssid ?? (wifi.authorized ? "Not connected" : "Unknown"))
                LabeledContent("Never play sounds on") {
                    Menu(settings.quietNetworks.isEmpty ? "No networks" : settings.quietNetworks.sorted().joined(separator: ", ")) {
                        networkToggles(
                            isOn: { settings.quietNetworks.contains($0) },
                            set: { name, on in
                                if on { settings.quietNetworks.insert(name) } else { settings.quietNetworks.remove(name) }
                            })
                    }
                    .fixedSize()
                }
            } header: {
                Text("Wi-Fi")
            } footer: {
                Text("E.g. keep every alert silent on the office Wi-Fi. Networks this Mac has joined before are listed even when you're not on them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 700)
        .onAppear(perform: reloadOutputs)
        .task {
            let paired = await Task.detached { AudioOutputs.pairedBluetooth() }.value
            // Don't let the paired-list name ("… - Find My") replace a name already learned from CoreAudio.
            settings.remember(paired.filter { settings.knownOutputs[$0.uid] == nil })
        }
        .onReceive(refresh) { _ in reloadOutputs() }
        .onChange(of: wifi.authorized) { reloadOutputs() }
        .onChange(of: settings.usesNetworkRules) {
            if settings.usesNetworkRules && wifi.undetermined { wifi.requestAccess() }
        }
    }

    /// Connected devices first, then remembered ones that aren't plugged in right now.
    private var outputList: [AudioOutput] {
        let connectedIDs = Set(connected.map(\.uid))
        let remembered = settings.knownOutputs
            .filter { !connectedIDs.contains($0.key) }
            .map { AudioOutput(uid: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
        return connected + remembered
    }

    private var flashColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.flashColor.nsColor) },
            set: { settings.flashColor = RGBA(NSColor($0)) })
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a photo to fill the screen before meetings"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.setFlashPhoto(from: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func allowed(_ uid: String) -> Binding<Bool> {
        Binding(
            get: { settings.allowedOutputUIDs.contains(uid) },
            set: { on in
                if on { settings.allowedOutputUIDs.insert(uid) } else { settings.allowedOutputUIDs.remove(uid) }
            })
    }

    private func reloadOutputs() {
        connected = AudioOutputs.all()
        current = AudioOutputs.current()
        settings.remember(connected)
        ssid = wifi.currentSSID
        settings.remember(networks: wifi.savedNetworks + [ssid].compactMap { $0 })
    }

    private var networkList: [String] {
        settings.knownNetworks.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    private func networkToggles(isOn: @escaping (String) -> Bool, set: @escaping (String, Bool) -> Void) -> some View {
        if networkList.isEmpty {
            Text(wifi.authorized ? "No Wi-Fi networks found" : "Allow Location access to list Wi-Fi networks")
        }
        ForEach(networkList, id: \.self) { name in
            Toggle(name, isOn: Binding(get: { isOn(name) }, set: { set(name, $0) }))
        }
    }

    /// "Anywhere" or "Only on <networks>" for one allowed output.
    private func outputNetworkMenu(_ uid: String) -> some View {
        let networks = settings.outputNetworks[uid] ?? []
        return Menu(networks.isEmpty ? "Anywhere" : "Only on " + networks.joined(separator: ", ")) {
            Toggle("Anywhere", isOn: Binding(
                get: { networks.isEmpty },
                set: { if $0 { settings.outputNetworks[uid] = nil } }))
            Divider()
            Text("Only on Wi-Fi")
            networkToggles(
                isOn: { networks.contains($0) },
                set: { name, on in
                    var list = settings.outputNetworks[uid] ?? []
                    list.removeAll { $0 == name }
                    if on { list.append(name) }
                    settings.outputNetworks[uid] = list.isEmpty ? nil : list
                })
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct AlertRow: View {
    static let timings = [0, 1, 2, 3, 5, 10, 15, 30]
    /// Picker tag for the "Add Sound…" item, which opens a file picker instead of being selected.
    private static let addSoundTag = "\u{0}add-sound"

    @Binding var alert: MeetingAlert
    var onDelete: () -> Void

    private var soundSelection: Binding<String?> {
        Binding(
            get: { alert.sound },
            set: { value in
                if value == Self.addSoundTag {
                    if let added = Self.chooseSound() { alert.sound = added }
                } else {
                    alert.sound = value
                }
            })
    }

    /// Lets the user pick an audio file (MP3, M4A, WAV, AIFF…) and copies it into the app's sounds.
    private static func chooseSound() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a sound for this alert"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let name = try Sounds.add(url)
            Sounds.play(name)
            return name
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("When", selection: $alert.minutesBefore) {
                ForEach(Self.timings, id: \.self) { m in
                    Text(m == 0 ? "At start" : "\(m) min before").tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Toggle("Flash", isOn: $alert.flash)
                .toggleStyle(.checkbox)

            Picker("Sound", selection: soundSelection) {
                Text("No sound").tag(String?.none)
                Divider()
                let custom = Sounds.customNames
                if !custom.isEmpty {
                    ForEach(custom, id: \.self) { Text(Sounds.displayName($0)).tag(String?.some($0)) }
                    Divider()
                }
                ForEach(Sounds.names, id: \.self) { Text($0).tag(String?.some($0)) }
                Divider()
                Text("Add Sound…").tag(String?.some(Self.addSoundTag))
            }
            .labelsHidden()
            .frame(width: 120)

            Button {
                if Sounds.isPlaying { Sounds.stop() } else if let s = alert.sound { Sounds.play(s) }
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .disabled(alert.sound == nil)
            .help("Preview sound (click again to stop)")

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove alert")
        }
    }
}
