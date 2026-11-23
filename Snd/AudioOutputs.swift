import CoreAudio
import Foundation

struct AudioOutput {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioOutputs {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func list() throws -> [AudioOutput] {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size))
        let idSize = UInt32(MemoryLayout<AudioDeviceID>.stride)
        guard size >= idSize else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size / idSize))
        let status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, buffer.baseAddress!)
        }
        try check(status)

        return ids.prefix(Int(size / idSize)).compactMap { id -> AudioOutput? in
            guard isSelectable(id),
                  let uid = try? stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  let name = try? stringProperty(kAudioObjectPropertyName, of: id)
            else { return nil }
            return AudioOutput(id: id, uid: uid, name: name)
        }.sorted { left, right in
            let order = left.name.localizedStandardCompare(right.name)
            return order == .orderedSame ? left.uid < right.uid : order == .orderedAscending
        }
    }

    static func current() throws -> AudioDeviceID {
        try integerProperty(kAudioHardwarePropertyDefaultOutputDevice, of: system)
    }

    static func select(uid: String) throws {
        guard let output = try list().first(where: { $0.uid == uid }) else {
            throw AudioError.deviceUnavailable
        }
        try select(output)
    }

    static func select(_ output: AudioOutput) throws {
        guard isSelectable(output.id),
              (try? stringProperty(kAudioDevicePropertyDeviceUID, of: output.id)) == output.uid
        else { throw AudioError.deviceUnavailable }

        if try current() == output.id { return }

        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var id = output.id
        let size = UInt32(MemoryLayout.size(ofValue: id))
        try check(AudioObjectSetPropertyData(system, &address, 0, nil, size, &id))
        guard try current() == id else { throw AudioError.selectionFailed }
    }

    private static func isSelectable(_ id: AudioDeviceID) -> Bool {
        let outputScope = kAudioObjectPropertyScopeOutput
        return (try? integerProperty(kAudioDevicePropertyDeviceIsAlive, of: id)) == 1
            && (try? integerProperty(
                kAudioDevicePropertyDeviceCanBeDefaultDevice, of: id, scope: outputScope
            )) == 1
    }

    private static func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func integerProperty(
        _ selector: AudioObjectPropertySelector,
        of id: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> UInt32 {
        var address = property(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value))
        return value
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector, of id: AudioObjectID
    ) throws -> String {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value))
        guard let value else { throw AudioError.deviceUnavailable }
        return value.takeRetainedValue() as String
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioError.coreAudio(status) }
    }
}

private enum AudioError: LocalizedError {
    case coreAudio(OSStatus)
    case deviceUnavailable
    case selectionFailed

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status): "Core Audio viga (\(status))."
        case .deviceUnavailable: "Valitud väljund pole enam saadaval."
        case .selectionFailed: "macOS ei kinnitanud väljundi vahetust."
        }
    }
}
