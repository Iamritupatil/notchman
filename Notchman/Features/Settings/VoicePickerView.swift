import AVFoundation
import SwiftUI

struct VoicePickerView: View {
    let language: String
    @Binding var selection: String

    @Environment(PlaybackManager.self) private var playback
    @State private var previewer = VoicePreviewer()
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        List {
            Section {
                row(title: "Automatic", subtitle: "Best voice installed", identifier: "", voice: nil)
            }
            Section {
                ForEach(voices, id: \.identifier) { voice in
                    row(title: voice.name,
                        subtitle: [VoiceCatalog.displayName(for: voice.language), VoiceCatalog.qualityLabel(voice)]
                            .compactMap { $0 }.joined(separator: " · "),
                        identifier: voice.identifier, voice: voice)
                }
            } footer: {
                Text("For more natural voices, download Enhanced or Premium voices in Settings → Accessibility → Spoken Content → Voices.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .pushedPage("Voice")
        .onAppear { voices = VoiceCatalog.voices(forLanguage: language) }
        .onDisappear { previewer.stop() }
    }

    private func row(title: String, subtitle: String, identifier: String, voice: AVSpeechSynthesisVoice?) -> some View {
        HStack {
            Button {
                selection = identifier
                Haptics.tap()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(.primary)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selection == identifier {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let voice {
                Button {
                    playback.pause()
                    previewer.preview(voice)
                } label: {
                    Image(systemName: "play.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview \(voice.name)")
            }
        }
    }
}

/// Speaks a short sample with a separate synthesizer.
final class VoicePreviewer {
    private let synthesizer = AVSpeechSynthesizer()

    func preview(_ voice: AVSpeechSynthesisVoice) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Long message? Let Notchman read it.")
        utterance.voice = voice
        utterance.rate = PlaybackSpeed.utteranceRate(for: AppSettings().defaultSpeed)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

struct LanguagePickerView: View {
    @Binding var selection: String
    @State private var languages: [String] = []

    var body: some View {
        List {
            Button {
                selection = ""
            } label: {
                checkRow("Automatic", isSelected: selection.isEmpty)
            }
            ForEach(languages, id: \.self) { code in
                Button {
                    selection = code
                } label: {
                    checkRow(VoiceCatalog.displayName(for: code), isSelected: selection == code)
                }
            }
        }
        .buttonStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .pushedPage("Language")
        .onAppear { languages = VoiceCatalog.availableLanguages() }
    }

    private func checkRow(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }
}
