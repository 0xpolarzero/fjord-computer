import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@main
struct GuestRecorder {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3, arguments[0] == "--agent" else { exit(64) }
        let agent = AquaRecorderAgent(controlDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
                                      videoURL: URL(fileURLWithPath: arguments[2]))
        await agent.run()
    }
}

private actor AquaRecorderAgent {
    private let controlDirectory: URL
    private let videoURL: URL
    private var activeStream: SCStream?
    private var streamHandler: AquaRecorderStreamHandler?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedWriter = false
    private var firstTime: CMTime?
    private var lastTime: CMTime?
    private var captureError: String?
    private var displayWidth = 0
    private var displayHeight = 0

    init(controlDirectory: URL, videoURL: URL) {
        self.controlDirectory = controlDirectory
        self.videoURL = videoURL
    }

    func run() async {
        do {
            try FileManager.default.createDirectory(at: controlDirectory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try await startCapture()
            try await writeJSON(["state": "ready"], to: controlDirectory.appendingPathComponent("recorder-ready.json"))
            while captureError == nil {
                if let command = try? Data(contentsOf: controlDirectory.appendingPathComponent("recorder-command.json")),
                   let value = try? JSONSerialization.jsonObject(with: command) as? [String: String],
                   value["action"] == "stop" {
                    try await finish()
                    return
                }
                try await Task.sleep(for: .milliseconds(150))
            }
            throw RecorderError.capture(captureError ?? "ScreenCaptureKit stopped unexpectedly.")
        } catch {
            let detail = Self.safe(error)
            try? await writeJSON(["state": "error", "error": detail],
                                 to: controlDirectory.appendingPathComponent("recorder-ready.json"))
            try? await writeJSON(["state": "failed", "error": detail, "videoPath": videoURL.path],
                                 to: controlDirectory.appendingPathComponent("manifest.json"))
        }
    }

    private func startCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }
        displayWidth = display.width
        displayHeight = display.height
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let assetWriter = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
        let assetInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: display.width,
            AVVideoHeightKey: display.height,
        ])
        assetInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(assetInput) else { throw RecorderError.writer("H.264 video input is unavailable.") }
        assetWriter.add(assetInput)
        writer = assetWriter
        input = assetInput

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let handler = AquaRecorderStreamHandler(agent: self)
        let screenStream = SCStream(filter: filter, configuration: configuration, delegate: handler)
        try screenStream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.fjord.guestruns.frames"))
        streamHandler = handler
        activeStream = screenStream
        try await screenStream.startCapture()
    }

    private func finish() async throws {
        guard let activeStream, let writer, let input else { throw RecorderError.writer("Recording did not start.") }
        try await activeStream.stopCapture()
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed, let firstTime, let lastTime,
              let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue > 0 else {
            throw RecorderError.writer(writer.error?.localizedDescription ?? "The movie was not finalized.")
        }
        let duration = CMTimeGetSeconds(CMTimeSubtract(lastTime, firstTime))
        try await writeJSON(["kind": "screencapturekit", "state": "complete", "videoPath": videoURL.path,
                             "bytes": size.intValue, "durationSeconds": duration.isFinite ? duration : 0,
                             "width": displayWidth, "height": displayHeight],
                            to: controlDirectory.appendingPathComponent("manifest.json"))
    }

    fileprivate func append(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, let input, writer.status != .failed else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !startedWriter {
            guard writer.startWriting() else {
                captureError = writer.error?.localizedDescription ?? "The movie writer could not start."
                return
            }
            writer.startSession(atSourceTime: time)
            firstTime = time
            startedWriter = true
        }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) { lastTime = time }
        else { captureError = writer.error?.localizedDescription ?? "The movie writer rejected a screen frame." }
    }

    fileprivate func stopped(_ detail: String) { captureError = detail }

    private func writeJSON(_ value: [String: Any], to url: URL) async throws {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func safe(_ error: Error) -> String {
        String(error.localizedDescription.replacingOccurrences(of: #"\$MSB_[A-Z0-9_]+"#, with: "[secret-placeholder]", options: .regularExpression).prefix(400))
    }
}

private final class AquaRecorderStreamHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    private weak var agent: AquaRecorderAgent?

    init(agent: AquaRecorderAgent) { self.agent = agent }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .screen, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let frame = UncheckedSampleBuffer(sampleBuffer)
        Task { await agent?.append(frame.value) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let detail = error.localizedDescription
        Task { await agent?.stopped(detail) }
    }
}

private struct UncheckedSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
    init(_ value: CMSampleBuffer) { self.value = value }
}

private enum RecorderError: LocalizedError {
    case noDisplay
    case writer(String)
    case capture(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: "The guest Aqua session has no active display."
        case .writer(let message), .capture(let message): message
        }
    }
}
