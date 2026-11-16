import AVFoundation
import Foundation
import Observation

enum AudioPlaybackError: LocalizedError {
    case noAudio
    case unableToPlay

    var errorDescription: String? {
        switch self {
        case .noAudio: "This recording has no audio file."
        case .unableToPlay: "This audio file could not be played."
        }
    }
}

@MainActor
@Observable
final class AudioPlayer: NSObject {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var hasAudio = false
    private(set) var rate: Float = 1
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in self?.pause(message: "Playback paused by an audio interruption.") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard rawReason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.pause(message: "Playback paused because the audio output changed.") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause(message: "The audio system restarted. Reopen this recording to play it again.")
            }
        })
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func load(url: URL) throws {
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            guard newPlayer.duration.isFinite, newPlayer.duration > 0 else { throw AudioPlaybackError.unableToPlay }
            stop()
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = rate
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
            hasAudio = true
            errorMessage = nil
        } catch {
            // A failed selection must not leave a different recording ready to play.
            stop()
            player = nil
            hasAudio = false
            duration = 0
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func playPause() throws {
        guard let player else {
            errorMessage = AudioPlaybackError.noAudio.localizedDescription
            throw AudioPlaybackError.noAudio
        }
        if isPlaying {
            pause()
            return
        }
        var activatedSession = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            activatedSession = true
            if currentTime >= duration { player.currentTime = 0; currentTime = 0 }
            guard player.play() else { throw AudioPlaybackError.unableToPlay }
            isPlaying = true
            errorMessage = nil
            startTimer()
        } catch {
            if activatedSession { deactivateSession() }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func seek(to time: TimeInterval) {
        guard let player, time.isFinite else { return }
        let clamped = min(duration, max(0, time))
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        seek(to: currentTime + seconds)
    }

    func setRate(_ rate: Float) {
        guard rate.isFinite else { return }
        self.rate = min(2, max(0.5, rate))
        player?.enableRate = true
        player?.rate = self.rate
    }

    func stop() {
        let wasPlaying = isPlaying
        player?.stop()
        player?.currentTime = 0
        timer?.invalidate()
        timer = nil
        isPlaying = false
        currentTime = 0
        if wasPlaying { deactivateSession() }
    }

    private func pause(message: String? = nil) {
        guard isPlaying else { return }
        player?.pause()
        currentTime = player?.currentTime ?? currentTime
        isPlaying = false
        timer?.invalidate()
        timer = nil
        deactivateSession()
        if let message { errorMessage = message }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player, self.isPlaying else { return }
                self.currentTime = min(self.duration, max(0, player.currentTime))
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.isPlaying = false
            self.currentTime = flag ? self.duration : player.currentTime
            self.timer?.invalidate()
            self.timer = nil
            self.deactivateSession()
            if !flag { self.errorMessage = "Playback stopped because the audio could not be decoded." }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "This audio file could not be decoded."
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.pause(message: message)
            self.errorMessage = message
        }
    }
}
