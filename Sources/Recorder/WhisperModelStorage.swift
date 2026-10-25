import Foundation
import WhisperKit

enum WhisperModelStorage {
    static var base: URL { PrivateStorage.applicationRoot.appendingPathComponent("Models") }
    static func tokenizerID(_ name: String) -> String {
        if name.contains("tiny") { return "tokenizer-tiny" }
        if name.contains("small") { return "tokenizer-small" }
        if name.contains("large") { return "tokenizer-large-v3-turbo" }
        return "tokenizer-base"
    }
    static func localFolder(for name: String) -> URL {
        ((try? ModelManager.folder(name)) ?? base).appendingPathComponent(name)
    }
    static func isDownloaded(_ name: String) -> Bool {
        ModelManager.ready(name) && ModelManager.ready(tokenizerID(name))
    }
    @MainActor
    static func makeHost() -> WhisperModelHost {
        WhisperModelHost(
            isDownloaded: { isDownloaded($0) },
            download: { name, report in
                try await ModelManager.shared.download(name) { _ in report(0.2) }
                try await ModelManager.shared.download(tokenizerID(name)) { _ in report(0.9) }
                report(1)
                return localFolder(for: name)
            },
            load: { name, folder in
                _ = try ModelManager.verifiedFolder(name)
                let tokenizerFolder = try ModelManager.verifiedFolder(tokenizerID(name))
                // Set a locally parsed tokenizer before loading models. WhisperKit's tokenizer
                // convenience loader can fall back to a network fetch even with download:false.
                let wrapper = try await AutoTokenizerWrapper.from(modelFolder: tokenizerFolder)
                let config = WhisperKitConfig(model: name, downloadBase: base, modelFolder: folder.path,
                                              tokenizerFolder: tokenizerFolder, verbose: false, logLevel: .none,
                                              load: false, download: false)
                let kit = try await WhisperKit(config)
                kit.tokenizer = LocalWhisperTokenizer(tokenizer: wrapper, at: tokenizerFolder)
                try await kit.loadModels()
                return kit
            }
        )
    }
}
