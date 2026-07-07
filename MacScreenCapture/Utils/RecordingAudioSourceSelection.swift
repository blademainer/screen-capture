import Foundation

struct RecordingAudioSourceSelection: Equatable {
    let includeSystemAudio: Bool
    let includeMicrophone: Bool

    var hasAnySource: Bool {
        includeSystemAudio || includeMicrophone
    }

    static func resolved(
        includeSystemAudio: Bool,
        includeMicrophonePreference: Bool,
        microphoneDeviceAvailable: Bool,
        microphonePermissionGranted: Bool
    ) -> RecordingAudioSourceSelection {
        RecordingAudioSourceSelection(
            includeSystemAudio: includeSystemAudio,
            includeMicrophone: includeMicrophonePreference && microphoneDeviceAvailable && microphonePermissionGranted
        )
    }
}
