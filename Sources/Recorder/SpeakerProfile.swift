import Foundation
import Accelerate

// MARK: - VoiceCentroid

/// One stored voiceprint: the mean speaker embedding of a single diarized cluster.
///
/// `addedAt` doubles as the identity of this centroid within a profile, which is how a
/// correction retracts exactly the centroid a recording contributed without touching
/// the rest.
struct VoiceCentroid: Codable, Equatable {
    var vector: [Float]
    var sampleSeconds: Double
    var addedAt: Date
}

// MARK: - SpeakerProfile

/// One person, and up to `maxCentroids` recordings of how they sound.
///
/// Several centroids rather than one running mean: matching is nearest-of-any, which
/// survives a change of microphone or room far better than an average of them does.
struct SpeakerProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var centroids: [VoiceCentroid]

    // Optional metadata keeps old exports readable, but legacy profiles are excluded from matching.
    var scope: String?
    var category: String?
    var email: String?
    var embeddingVersion: String?

    static let maxCentroids = 8

    /// Append, evicting oldest-first past the cap.
    mutating func appendCentroid(_ centroid: VoiceCentroid) {
        centroids.append(centroid)
        if centroids.count > Self.maxCentroids {
            centroids.removeFirst(centroids.count - Self.maxCentroids)
        }
        updatedAt = centroid.addedAt
    }

    mutating func removeCentroid(addedAt stamp: Date) {
        centroids.removeAll { $0.addedAt == stamp }
    }
}

// MARK: - VoiceMatching

/// Cosine comparison of speaker embeddings.
///
/// SpeakerKit's own `MathOps.cosineDistance` is internal to that module, so this
/// reproduces its convention exactly: distance in `[0, 2]`, `0` identical direction,
/// `1` orthogonal, `2` opposite, with `1.0` as the sentinel for unusable input.
/// Centroids are raw embedder output (unnormalised, pre-PLDA), which is fine because
/// the division by magnitudes normalises them here.
enum VoiceMatching {

    static func cosineDistance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty, lhs.allSatisfy(\.isFinite), rhs.allSatisfy(\.isFinite) else { return 1.0 }

        // Double accumulation prevents Float overflow from turning invalid magnitudes into a perfect match.
        let dot = zip(lhs, rhs).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        let l = sqrt(lhs.reduce(0.0) { $0 + Double($1) * Double($1) })
        let r = sqrt(rhs.reduce(0.0) { $0 + Double($1) * Double($1) })
        guard l > 0, r > 0, l.isFinite, r.isFinite else { return 1 }
        let distance = 1 - dot / (l * r)
        guard distance.isFinite else { return 1 }
        return Float(max(0, min(2, distance)))
    }

    /// Closest centroid across every profile. Ties resolve to the lowest profile id so
    /// the result does not depend on dictionary ordering.
    static func nearest(
        to embedding: [Float],
        in profiles: [SpeakerProfile]
    ) -> (profileID: UUID, distance: Float)? {
        guard !embedding.isEmpty else { return nil }

        var best: (profileID: UUID, distance: Float)?
        for profile in profiles.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            for centroid in profile.centroids where centroid.vector.count == embedding.count {
                let distance = cosineDistance(embedding, centroid.vector)
                if best == nil || distance < best!.distance {
                    best = (profile.id, distance)
                }
            }
        }
        return best
    }
}
