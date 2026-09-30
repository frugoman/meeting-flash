import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var connected: [AudioOutput] = []
    @State private var current: AudioOutput?

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
                Toggle("Only play sounds on selected outputs", isOn: $settings.restrictOutputs)
                if settings.restrictOutputs {
                    ForEach(outputList) { output in
                        Toggle(isOn: allowed(output.uid)) {
                            HStack {
                                Text(output.name)
                                if output.uid == current?.uid {
                                    Text("current").font(.caption).foregroundStyle(.green)
                                } else if !connected.contains(where: { $0.uid == output.uid }) {
                                    Text("not connected").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                LabeledContent("Current output") {
                    HStack(spacing: 6) {
                        Text(current?.name ?? "Unknown")
                        Image(systemName: settings.soundAllowedOnCurrentOutput ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundStyle(settings.soundAllowedOnCurrentOutput ? .green : .red)
                    }
                }
            } header: {
                Text("Sound Output")
            } footer: {
                Text("E.g. pick only your AirPods so alerts stay silent on the laptop speakers at the office. The flash always shows.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 420)
        .onAppear(perform: reloadOutputs)
        .onReceive(refresh) { _ in reloadOutputs() }
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
    }
}

private struct AlertRow: View {
    static let timings = [0, 1, 2, 3, 5, 10, 15, 30]

    @Binding var alert: MeetingAlert
    var onDelete: () -> Void

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

            Picker("Sound", selection: $alert.sound) {
                Text("No sound").tag(String?.none)
                Divider()
                ForEach(Sounds.names, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden()
            .frame(width: 120)

            Button {
                if let s = alert.sound { Sounds.play(s) }
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .disabled(alert.sound == nil)
            .help("Preview sound")

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove alert")
        }
    }
}
