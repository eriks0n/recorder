import Foundation
import CoreML
import WhisperKit

/// WhisperKit 1.1.0 strips prompt tokens from DecodingResult.tokens, but leaves their
/// rows in the alignment matrix (upstream #542). Rebase the matrix before alignment.
/// This adapter is deliberately tied to the pinned 1.1.0 decoder implementation.
final class VocabularySegmentSeeker: SegmentSeeking {
    private let base = SegmentSeeker()
    func findSeekPointAndSegments(decodingResult: DecodingResult, options: DecodingOptions, allSegmentsCount: Int,
                                 currentSeek: Int, segmentSize: Int, sampleRate: Int, timeToken: Int,
                                 specialToken: Int, tokenizer: WhisperTokenizer) -> (Int, [TranscriptionSegment]?) {
        base.findSeekPointAndSegments(decodingResult: decodingResult, options: options, allSegmentsCount: allSegmentsCount,
                                     currentSeek: currentSeek, segmentSize: segmentSize, sampleRate: sampleRate,
                                     timeToken: timeToken, specialToken: specialToken, tokenizer: tokenizer)
    }
    static func alignmentOffset(options: DecodingOptions, specialToken: Int) -> Int {
        guard options.usePrefillPrompt else { return 0 }
        let count = (options.promptTokens ?? []).suffix((Constants.maxTokenContext / 2) - 1).filter { $0 < specialToken }.count
        return count == 0 ? 0 : count + 1
    }
    static func rebase(_ weights: MLMultiArray, offset: Int) throws -> MLMultiArray {
        guard offset > 0 else { return weights }
        guard weights.shape.count == 2, weights.shape[0].intValue > offset else {
            throw LocalError.message("Wortzeitstempel konnten nicht auf das Fachwörterbuch abgestimmt werden.")
        }
        let rows = weights.shape[0].intValue - offset, columns = weights.shape[1].intValue
        // A strided view avoids another matrix allocation; used only within the synchronous delegate call.
        let bytes: Int
        switch weights.dataType {
        case .float16: bytes = 2
        case .float32, .int32: bytes = 4
        case .double: bytes = 8
        default: throw LocalError.message("Unbekanntes Format der Wortzeitstempel.")
        }
        return try MLMultiArray(dataPointer: weights.dataPointer.advanced(by: offset * weights.strides[0].intValue * bytes),
                                shape: [NSNumber(value: rows), NSNumber(value: columns)], dataType: weights.dataType,
                                strides: weights.strides, deallocator: { _ in _ = weights })
    }
    func addWordTimestamps(segments: [TranscriptionSegment], alignmentWeights: MLMultiArray, tokenizer: WhisperTokenizer,
                           seek: Int, segmentSize: Int, prependPunctuations: String, appendPunctuations: String,
                           lastSpeechTimestamp: Float, options: DecodingOptions, timings: TranscriptionTimings) throws -> [TranscriptionSegment]? {
        let offset = Self.alignmentOffset(options: options, specialToken: tokenizer.specialTokens.specialTokenBegin)
        let weights = try Self.rebase(alignmentWeights, offset: offset)
        return try base.addWordTimestamps(segments: segments, alignmentWeights: weights, tokenizer: tokenizer, seek: seek,
                                         segmentSize: segmentSize, prependPunctuations: prependPunctuations,
                                         appendPunctuations: appendPunctuations, lastSpeechTimestamp: lastSpeechTimestamp,
                                         options: options, timings: timings)
    }
}
