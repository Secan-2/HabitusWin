import AppKit
import AudioToolbox

final class SoundPlayer {
    static let shared = SoundPlayer()

    /// 第一个是随包提供的切纸声，其余取自系统音效目录。
    static let bundledName = "Snip"
    static let available: [String] = [
        bundledName, "Pop", "Tink", "Morse", "Bottle", "Funk", "Purr", "Sosumi", "Glass", "Ping", "Blow", "Frog", "Hero"
    ]

    private var cache: [String: NSSound] = [:]

    private func makeSound(_ name: String) -> NSSound? {
        if name == Self.bundledName,
           let url = Bundle.main.url(forResource: "Snip", withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: true)
        }
        return NSSound(named: NSSound.Name(name))
    }

    func play(_ name: String, volume: Double) {
        guard !name.isEmpty else { return }
        let sound: NSSound?
        if let cached = cache[name] {
            sound = cached
        } else {
            sound = makeSound(name)
            if let sound {
                cache[name] = sound
            }
        }

        if let sound {
            sound.volume = Float(max(0, min(1, volume)))
            if sound.isPlaying {
                sound.stop()
            }
            if sound.play() {
                return
            }
        }

        // 系统音效缺失或被路由异常时，退回到内置提示音，保证至少有一声反馈。
        AudioServicesPlaySystemSound(1104)
    }

    func preview(_ name: String, volume: Double) {
        play(name, volume: volume)
    }
}
