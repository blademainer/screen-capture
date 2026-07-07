import Foundation

struct RecordingCompletionSummary: Equatable {
    enum Severity: Equatable {
        case success
        case warning
        case error
    }

    let severity: Severity
    let title: String
    let detail: String
    let modeLabel: String

    static func make(outputURL: URL?, diagnostics: RecordingAudioDiagnostics?, fallbackModeLabel: String) -> RecordingCompletionSummary {
        let audioOnly = diagnostics?.audioOnly ?? (outputURL?.pathExtension.lowercased() == "m4a")
        let subject = audioOnly ? "录音" : "录制"
        let modeLabel = audioOnly ? "仅录音" : fallbackModeLabel

        guard let diagnostics else {
            return RecordingCompletionSummary(
                severity: .success,
                title: "\(subject)已保存",
                detail: "文件已保存",
                modeLabel: modeLabel
            )
        }

        if diagnostics.hasOutputIssue {
            return RecordingCompletionSummary(
                severity: .error,
                title: "\(subject)完成，文件需检查",
                detail: diagnostics.outputIssueText,
                modeLabel: modeLabel
            )
        }

        if diagnostics.hasAudioIssue {
            return RecordingCompletionSummary(
                severity: .warning,
                title: "\(subject)完成，音频需检查",
                detail: diagnostics.summaryText,
                modeLabel: modeLabel
            )
        }

        return RecordingCompletionSummary(
            severity: .success,
            title: "\(subject)已保存",
            detail: diagnostics.summaryText,
            modeLabel: modeLabel
        )
    }
}
