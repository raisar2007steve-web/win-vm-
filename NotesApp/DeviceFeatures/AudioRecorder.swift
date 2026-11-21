import Foundation
import AVFoundation
import Speech

/// Records a voice note to a temporary file and can transcribe it with
/// on-device speech recognition when the device supports it.
@MainActor
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case recording
        case finished
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var level: Double = 0
    private(set) var transcript: String = ""
    private(set) var isTranscribing = false

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var fileURL: URL?

    var isRecording: Bool { state == .recording }

    var formattedDuration: String {
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() async {
        guard await requestPermission() else {
            state = .failed("Microphone access is off. Enable it in Settings to record voice notes.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
            self.fileURL = url
            duration = 0
            transcript = ""
            state = .recording
            startMetering()
        } catch {
            state = .failed("Could not start recording.")
        }
    }

    func stop() {
        recorder?.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .recording {
            state = .finished
        }
    }

    func cancel() {
        recorder?.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        recorder = nil
        fileURL = nil
        duration = 0
        transcript = ""
        state = .idle
    }

    /// Returns the recorded file URL and discards recorder state.
    func takeRecording() -> URL? {
        defer {
            recorder = nil
            fileURL = nil
            state = .idle
            duration = 0
        }
        return fileURL
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                self.duration = recorder.currentTime
                let power = recorder.averagePower(forChannel: 0)
                self.level = Double(max(0, (power + 60) / 60))
            }
        }
    }

    // MARK: - Transcription

    /// Transcribes the recording on-device where possible.
    func transcribe(_ url: URL) async -> String? {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            return nil
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current), recognizer.isAvailable else {
            return nil
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return await withCheckedContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let result, result.isFinal {
                    didResume = true
                    self.transcript = result.bestTranscription.formattedString
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
