import AVFoundation

/// Text-to-speech using macOS built-in AVSpeechSynthesizer.
final class TTSService {
    private let synthesizer = AVSpeechSynthesizer()

    var voiceIdentifier: String?
    var volume: Float = 1.0

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = volume
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Available English voices on this system.
    static var availableVoices: [(id: String, name: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
            .map { ($0.identifier, $0.name) }
    }
}
