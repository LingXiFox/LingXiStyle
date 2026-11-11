import Foundation
import LingXiKit
import StylePortCore

/// Everything the engine needs for one Live Photo: the still, the paired movie and the mode the
/// user picked. One request is one asset and therefore one free slot.
public struct LivePhotoRequest: Sendable {
    public let stillURL: URL
    public let videoURL: URL
    public let mode: LivePhotoProcessingMode
    public let traits: AssetTraits
    public let outputDirectory: URL?

    public init(stillURL: URL,
                videoURL: URL,
                mode: LivePhotoProcessingMode,
                traits: AssetTraits = AssetTraits(),
                outputDirectory: URL? = nil) {
        self.stillURL = stillURL
        self.videoURL = videoURL
        self.mode = mode
        self.traits = traits
        self.outputDirectory = outputDirectory
    }
}

extension ConversionEngine {
    /// Converts a Live Photo as one asset. The still always goes through the lossless texture
    /// injection. The movie is either copied byte for byte (still-only) or gets the Texture/Grain
    /// style track that iOS renders every frame with; its samples, sound and keyframes stay put.
    public func convertLivePhoto(_ request: LivePhotoRequest,
                                 onStage: (@Sendable (ConversionStage) -> Void)? = nil) async throws -> ConversionOutput {
        onStage?(.readingOriginal)
        let stillData = try read(request.stillURL)
        var traits = request.traits
        traits.isLivePhoto = true
        let still = try styledStill(from: stillData, traits: traits, onStage: onStage)

        var frameCount: Int?
        var styledVideo: Data?
        switch request.mode {
        case .stillOnly:
            // The movie is not touched, but the frame count still belongs to the result so the
            // app can report what it left alone.
            frameCount = (try? read(request.videoURL)).flatMap { try? LivePhotoVideo.frameCount(of: $0) }
        case .full:
            onStage?(.processingFrames)
            let movie = try await styledMovie(at: request.videoURL)
            frameCount = movie.frameCount
            styledVideo = movie.data
        }

        onStage?(.verifying)
        let verified = try verifyStill(original: stillData, styled: still.data)
        // The pair only survives if both files keep the identifier Photos matched them by.
        guard ContentIdentifierScanner.isPreserved(from: stillData, to: still.data) else {
            throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.pairing", defaultValue: "主照片的配对标识丢失"))
        }

        let directory = request.outputDirectory ?? request.stillURL.deletingLastPathComponent()
        let outputURL = directory.appendingPathComponent(Self.outputName(for: request.stillURL))
        let videoURL = directory.appendingPathComponent(Self.outputVideoName(for: request.videoURL))
        try write(still.data, to: outputURL)

        var videoByteCount = 0
        if let styledVideo {
            try write(styledVideo, to: videoURL)
            videoByteCount = styledVideo.count
        } else {
            do {
                if FileManager.default.fileExists(atPath: videoURL.path) {
                    try FileManager.default.removeItem(at: videoURL)
                }
                try FileManager.default.copyItem(at: request.videoURL, to: videoURL)
            } catch {
                throw ConversionFailure.writeFailed(error.localizedDescription)
            }
            videoByteCount = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
        }

        return ConversionOutput(outputURL: outputURL,
                                outputByteCount: still.data.count,
                                inspectionBefore: still.inspectionBefore,
                                inspectionAfter: verified.inspection,
                                integrity: verified.integrity,
                                mode: still.mode,
                                texture: still.texture,
                                warnings: still.warnings,
                                pairedVideoURL: videoURL,
                                livePhotoMode: request.mode,
                                videoFrameCount: frameCount,
                                videoByteCount: videoByteCount)
    }

    /// Adds the Texture/Grain style track to the paired movie. Everything the movie already owns
    /// (main samples, audio, metadata, still-image-time markers, pairing identifier) is kept.
    private func styledMovie(at url: URL) async throws -> (data: Data, frameCount: Int) {
        let original = try read(url)
        let frames: Int
        let parts: LivePhotoVideo.Parts
        do {
            frames = try LivePhotoVideo.frameCount(of: original)
            parts = try LivePhotoVideo.parts(of: original)
        } catch {
            throw ConversionFailure.livePhotoVideo(String(describing: error))
        }
        guard frames > 0 else {
            throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.emptyMovie", defaultValue: "没有可处理的帧"))
        }
        // The texture track is rendered together with the movie's own style tracks. Inventing a
        // base style would change the look the user chose in the camera, so refuse instead.
        guard parts.contains([.mattes, .styleInfo]) else {
            throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.noStyleTracks", defaultValue: "动态视频没有原始风格数据"))
        }

        var wanted: LivePhotoVideo.Parts = [.textureInfo]
        var linearThumbnail: LivePhotoVideo.LinearThumbnail?
        if !parts.contains(.linearThumbnail) {
            do {
                linearThumbnail = try await LinearThumbnailEncoder.encode(videoURL: url)
            } catch {
                throw ConversionFailure.livePhotoVideo(String(describing: error))
            }
            wanted.insert(.linearThumbnail)
        }

        let styled: Data
        do {
            let (data, added) = try LivePhotoVideo.add(wanted, to: original, linearThumbnail: linearThumbnail)
            guard added.contains(.textureInfo) else {
                throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.trackMissing", defaultValue: "风格轨道没有写入"))
            }
            styled = data
        } catch let failure as ConversionFailure {
            throw failure
        } catch {
            throw ConversionFailure.livePhotoVideo(String(describing: error))
        }

        do {
            guard try LivePhotoVideo.frameCount(of: styled) == frames else {
                throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.frameCount", defaultValue: "帧数在写入后发生变化"))
            }
            guard try LivePhotoVideo.parts(of: styled).isSuperset(of: [.mattes, .styleInfo, .textureInfo]) else {
                throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.trackMissing", defaultValue: "风格轨道没有写入"))
            }
        } catch let failure as ConversionFailure {
            throw failure
        } catch {
            throw ConversionFailure.livePhotoVideo(String(describing: error))
        }
        guard ContentIdentifierScanner.isPreserved(from: original, to: styled) else {
            throw ConversionFailure.livePhotoVideo(String(localized: "engine.error.pairing", defaultValue: "主照片的配对标识丢失"))
        }
        return (styled, frames)
    }
}

/// Finds UUID strings in a file and checks that a rewritten file still carries all of the
/// original ones. Photos pairs a Live Photo by the content identifier that lives in both the
/// still and the movie, so this is the cheapest proof that the pairing survived.
enum ContentIdentifierScanner {
    static func isPreserved(from original: Data, to candidate: Data) -> Bool {
        let before = uuids(in: original)
        guard !before.isEmpty else { return true }
        return before.isSubset(of: uuids(in: candidate))
    }

    static func uuids(in data: Data) -> Set<String> {
        var found: Set<String> = []
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= 36 else { return }
            var index = 0
            let last = bytes.count - 36
            while index <= last {
                if let uuid = uuid(at: index, in: bytes) {
                    found.insert(uuid)
                    index += 36
                } else {
                    index += 1
                }
            }
        }
        return found
    }

    private static func uuid(at index: Int, in bytes: UnsafeBufferPointer<UInt8>) -> String? {
        var characters: [UInt8] = []
        characters.reserveCapacity(36)
        for offset in 0..<36 {
            let byte = bytes[index + offset]
            if offset == 8 || offset == 13 || offset == 18 || offset == 23 {
                guard byte == 0x2D else { return nil }
            } else {
                guard (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66) else {
                    return nil
                }
            }
            characters.append(byte)
        }
        return String(bytes: characters, encoding: .utf8)
    }
}
