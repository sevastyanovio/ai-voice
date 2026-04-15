import AVFoundation

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var playingFilename: String?

    private var player: AVAudioPlayer?
    private var delegate: PlayerDelegate?

    func play(url: URL, filename: String) {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            let del = PlayerDelegate { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.playingFilename = nil
                }
            }
            audioPlayer.delegate = del
            audioPlayer.play()

            self.player = audioPlayer
            self.delegate = del
            self.isPlaying = true
            self.playingFilename = filename
        } catch {
            isPlaying = false
            playingFilename = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        delegate = nil
        isPlaying = false
        playingFilename = nil
    }

    func toggle(url: URL, filename: String) {
        if playingFilename == filename && isPlaying {
            stop()
        } else {
            play(url: url, filename: filename)
        }
    }
}

private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
