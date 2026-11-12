import CoreAudio

// Descobre se você está em chamada olhando se o microfone está em uso.
// Não grava nem ouve nada: só pergunta ao sistema se algum app está captando áudio.

enum CallDetector {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static var micInUse: Bool {
        guard inputDeviceRunning() else { return false }
        // Um fone com microfone também aparece "em uso" quando só toca música.
        // No macOS 14 ou mais novo dá pra confirmar se alguém está mesmo captando.
        if let recording = anyProcessRecording() {
            return recording
        }
        return true
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Lista de objetos de áudio (aparelhos ou processos) de uma propriedade do sistema.
    private static func objects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0 else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &list) == 0 else { return nil }
        return list
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == 0 else { return false }
        return value != 0
    }

    /// Algum aparelho com entrada de áudio está ligado por algum app.
    private static func inputDeviceRunning() -> Bool {
        guard let devices = objects(kAudioHardwarePropertyDevices) else { return false }
        for device in devices {
            var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == 0, size > 0 else { continue }
            if flag(device, kAudioDevicePropertyDeviceIsRunningSomewhere) {
                return true
            }
        }
        return false
    }

    /// Algum app está captando áudio. Devolve nil se o sistema não souber dizer.
    private static func anyProcessRecording() -> Bool? {
        #if compiler(>=5.9)
        guard let processes = objects(kAudioHardwarePropertyProcessObjectList) else { return nil }
        for process in processes {
            if flag(process, kAudioProcessPropertyIsRunningInput) {
                return true
            }
        }
        return false
        #else
        return nil
        #endif
    }
}
