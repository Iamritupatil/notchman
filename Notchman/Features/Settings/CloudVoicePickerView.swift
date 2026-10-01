import AVFoundation
import SwiftUI

/// Choose the ElevenLabs voice. Each row can play a short sample in that
/// voice (a real request to the voice service), so the choice is audible.
struct CloudVoicePickerView: View {
    @Environment(PlaybackManager.self) private var playback
    @State private var selected = CloudVoice.selected
    @State private var previewing: CloudVoice?
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewError: String?

    var body: some View {
        List {
            ForEach(CloudVoice.Style.allCases, id: \.self) { style in
                Section(style.title) {
                    ForEach(CloudVoice.all.filter { $0.style == style }) { voice in
                        HStack(spacing: 12) {
                            Button {
                                Haptics.tap()
                                selected = voice
                                playback.setVoice(voice)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voice.name).font(.body.weight(.semibold))
                                        Text("\(voice.gender == .male ? "Male" : voice.gender == .female ? "Female" : "Neutral") · \(voice.detail)")
                                            .font(.caption).foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    if voice == selected {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.amber)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                preview(voice)
                            } label: {
                                Group {
                                    if previewing == voice {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "play.circle.fill").font(.title2)
                                    }
                                }
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.amber)
                            .accessibilityLabel("Preview \(voice.name)")
                        }
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                if let previewError {
                    Text(previewError).foregroundStyle(.red)
                } else {
                    Text("Used for TL;DRs and full reads. Changing it switches what's playing right away. Each voice's audio is kept on your iPhone, so replays don't use your listening time.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .navigationTitle("Voice")
        .onDisappear { previewPlayer?.stop() }
    }

    private func preview(_ voice: CloudVoice) {
        previewPlayer?.stop()
        previewing = voice
        previewError = nil
        Task {
            defer { previewing = nil }
            do {
                let text = "Hi, I'm \(voice.name). Here's the gist of your message, read the Notchman way."
                let audio: Data
                if let cached = VoiceCache.load(voice: voice.id, text: text) {
                    audio = cached
                } else {
                    audio = try await NotchmanCloud().speak(text: text, previousText: nil, nextText: nil, voiceID: voice.id)
                    VoiceCache.save(audio, voice: voice.id, text: text)
                }
                let player = try AVAudioPlayer(data: audio)
                previewPlayer = player
                player.play()
            } catch {
                previewError = "Couldn't play \(voice.name): \(error.localizedDescription)"
            }
        }
    }
}
