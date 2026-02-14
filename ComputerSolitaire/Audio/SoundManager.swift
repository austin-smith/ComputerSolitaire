import AVFoundation
import Foundation

enum GameSound: String, CaseIterable {
    case cardPlaced = "card-placed"
    case cardDrawFromStock = "card-draw-from-stock"
    case wasteRecycleToStock = "waste-recycle-to-stock"
    case cardFlipFaceUp = "card-flip-face-up"
    case invalidDrop = "invalid-drop"
    case undoMove = "undo-move"

    var fileExtension: String { "wav" }
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var players: [GameSound: AVAudioPlayer] = [:]

    private init() {}

    func play(_ sound: GameSound) {
        let player = player(for: sound)
        player?.currentTime = 0
        player?.play()
    }
}

private extension SoundManager {
    func player(for sound: GameSound) -> AVAudioPlayer? {
        if let existing = players[sound] {
            return existing
        }

        guard let url = resourceURL(for: sound) else {
#if DEBUG
            print("Missing sound resource: \(sound.rawValue).\(sound.fileExtension)")
#endif
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[sound] = player
            return player
        } catch {
#if DEBUG
            print("Failed to load sound resource at \(url): \(error)")
#endif
            return nil
        }
    }

    func resourceURL(for sound: GameSound) -> URL? {
        Bundle.main.url(
            forResource: sound.rawValue,
            withExtension: sound.fileExtension,
            subdirectory: "Audio/Sounds"
        ) ?? Bundle.main.url(
            forResource: sound.rawValue,
            withExtension: sound.fileExtension
        )
    }
}
