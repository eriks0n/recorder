import Foundation
import CoreAudio
import AudioToolbox

enum MicrophoneDevices {
    struct Device: Identifiable { let id: String; let name: String; let audioID: AudioDeviceID }
    static func inputs() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty else { return [] }
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: uid, name: name, audioID: id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString?; var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String?
    }
    static func requireSelected(_ uid: String, unit: AudioUnit?) throws {
        guard !uid.isEmpty else { return }
        guard let expected = inputs().first(where: { $0.id == uid })?.audioID, let unit else {
            throw LocalError.message("Das gewählte Mikrofon wurde getrennt. Die Aufnahme wird beendet.")
        }
        var actual: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actual, &size) == noErr, actual == expected else {
            throw LocalError.message("Die Mikrofonquelle hat gewechselt. Bitte die gewählte Quelle prüfen.")
        }
    }
    static func select(_ uid: String, unit: AudioUnit?) throws {
        var selected: AudioDeviceID?
        if uid.isEmpty {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var id: AudioDeviceID = 0; var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 { selected = id }
        } else { selected = inputs().first(where: { $0.id == uid })?.audioID }
        guard var id = selected, let unit else {
            throw LocalError.message("Das gewählte Mikrofon ist nicht verfügbar. Bitte anschließen oder in den Einstellungen Systemstandard wählen.")
        }
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
            throw LocalError.message("Das gewählte Mikrofon konnte nicht aktiviert werden.")
        }
    }
}
