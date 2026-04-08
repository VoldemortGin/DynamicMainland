import AppKit
import AVFoundation

/// 8-bit 风格音效通知管理
final class SoundManager {
    static let shared = SoundManager()

    private var synthesizer: AVAudioEngine?

    private init() {}

    func playNotification(for event: PendingEvent) {
        switch event {
        case .permissionRequest:
            playSystemSound(.basso)
        case .question:
            playSystemSound(.purr)
        case .notification(_, _, let level, _):
            switch level {
            case "success": playSystemSound(.glass)
            case "error": playSystemSound(.sosumi)
            case "warning": playSystemSound(.basso)
            default: playSystemSound(.pop)
            }
        }
    }

    func playApproved() {
        playSystemSound(.pop)
    }

    func playDenied() {
        playSystemSound(.funk)
    }

    func playTaskComplete() {
        playSystemSound(.glass)
    }

    private func playSystemSound(_ sound: NSSound.Name) {
        NSSound(named: sound)?.play()
    }
}

private extension NSSound.Name {
    static let basso = NSSound.Name("Basso")
    static let purr = NSSound.Name("Purr")
    static let glass = NSSound.Name("Glass")
    static let sosumi = NSSound.Name("Sosumi")
    static let pop = NSSound.Name("Pop")
    static let funk = NSSound.Name("Funk")
}
