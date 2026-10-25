import Foundation
import AVFoundation
import CoreAudio
import Darwin

/// Bounded-memory stereo encoding. Raw sources are retained and output is published only after AAC finalization.
enum StereoMixer {
    private static let rate = 48_000.0
    private static let chunk = 16_384
    enum MixError: LocalizedError {
        case invalidFormat, bothSourcesEmpty, writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Audioformat konnte nicht konvertiert werden."
            case .bothSourcesEmpty: return "Beide Audioquellen sind leer."
            case .writeFailed(let message): return "Audio konnte nicht gespeichert werden: \(message)"
            }
        }
    }
    static func mix(desktopURL: URL, micURL: URL, desktopResult: CaptureResult, micResult: CaptureResult, outputURL: URL) throws {
        let left = try MonoReader(desktopURL), right = try MonoReader(micURL)
        guard left.hasAudio || right.hasAudio else { throw MixError.bothSourcesEmpty }
        let offsets = leadingSilence(desktopResult.firstHostTime, micResult.firstHostTime)
        left.leading = offsets.0; right.leading = offsets.1
        let temporary = outputURL.deletingLastPathComponent().appendingPathComponent(".audio-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try encode(left, right, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard rename(temporary.path, outputURL.path) == 0 else { throw MixError.writeFailed(String(cString: strerror(errno))) }
    }
    static func leadingSilence(_ desktop: UInt64?, _ mic: UInt64?) -> (Int, Int) {
        guard let desktop, let mic else { return (0, 0) }
        let difference = desktop > mic ? desktop - mic : mic - desktop
        let seconds = Double(AudioConvertHostTimeToNanos(difference)) / 1_000_000_000
        // Real capture onsets are seconds apart. Reject corrupt metadata instead of allocating unbounded silence.
        guard seconds.isFinite, seconds <= 3600 else { return (0, 0) }
        let frames = Int((seconds * rate).rounded())
        return desktop < mic ? (0, frames) : (frames, 0)
    }
    private final class MonoReader {
        var leading = 0
        private var file: AVAudioFile?
        private var converter: AVAudioConverter?
        private var target: AVAudioFormat?
        private var eof = false
        var hasAudio: Bool { (file?.length ?? 0) > 0 }
        init(_ url: URL) throws {
            guard FileManager.default.fileExists(atPath: url.path) else { eof = true; return }
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard file.length > 0 else { eof = true; return }
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: file.processingFormat, to: target) else { throw MixError.invalidFormat }
            self.file = file; self.converter = converter; self.target = target
        }
        func read() throws -> [Float] {
            let zeros = min(leading, chunk); leading -= zeros
            var result = [Float](repeating: 0, count: zeros)
            guard zeros < chunk, !eof, let file, let converter, let target,
                  let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(chunk - zeros)) else { return result }
            var readError: Error?, conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { count, status in
                do {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { throw MixError.invalidFormat }
                    let remaining = max(0, file.length - file.framePosition)
                    guard remaining > 0 else { status.pointee = .endOfStream; return nil }
                    try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(count), remaining)))
                    status.pointee = buffer.frameLength > 0 ? .haveData : .endOfStream
                    return buffer.frameLength > 0 ? buffer : nil
                } catch { readError = error; status.pointee = .endOfStream; return nil }
            }
            if let readError { throw readError }; if let conversionError { throw conversionError }
            if status == .error { throw MixError.invalidFormat }
            if let samples = output.floatChannelData?[0], output.frameLength > 0 {
                result.append(contentsOf: UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
            }
            if status == .endOfStream { eof = true }
            return result
        }
    }
    private static func encode(_ left: MonoReader, _ right: MonoReader, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)), let channels = buffer.floatChannelData else { throw MixError.invalidFormat }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        while true {
            try Task.checkCancellation()
            let l = try left.read(), r = try right.read(), count = max(l.count, r.count)
            if count == 0 { break }
            buffer.frameLength = AVAudioFrameCount(count)
            for i in 0..<count { channels[0][i] = i < l.count ? l[i] : 0; channels[1][i] = i < r.count ? r[i] : 0 }
            try file.write(from: buffer)
        }
    }
}
