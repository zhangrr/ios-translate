import Foundation
import SentencepieceTokenizer

private let translationDebugLoggingEnabled =
    ProcessInfo.processInfo.environment["TRANSLATE_DEBUG_LOGS"] == "1"

private func engineDebugLog(_ message: String) {
    guard translationDebugLoggingEnabled else { return }
    print(message)
    NSLog("%@", message)
}

enum TranslationMode: String {
    case en2zh = "en-zh"
    case zh2en = "zh-en"

    var displayName: String {
        switch self {
        case .en2zh:
            return "英 -> 中"
        case .zh2en:
            return "中 -> 英"
        }
    }

    var listenLanguageCode: String {
        switch self {
        case .en2zh:
            return "en-US"
        case .zh2en:
            return "zh-CN"
        }
    }

    var speakLanguageCode: String {
        switch self {
        case .en2zh:
            return "zh-CN"
        case .zh2en:
            return "en-US"
        }
    }
}

final class TranslatorEngine {
    static let shared = TranslatorEngine()

    private struct BundledModel {
        static let requiredFiles = [
            "model.bin",
            "config.json",
            "source.spm",
            "target.spm",
        ]

        static let vocabularyFileSets = [
            ["shared_vocabulary.json"],
            ["source_vocabulary.json", "target_vocabulary.json"],
            ["shared_vocabulary.txt"],
            ["source_vocabulary.txt", "target_vocabulary.txt"],
        ]

        let directory: String
        let mode: TranslationMode
        let sourcePrefixTokens: [String]

        var requiredFileListText: String {
            "model.bin、config.json、source.spm、target.spm，以及 CTranslate2 生成的 vocabulary 文件"
        }
    }

    private static let bundledModels: [TranslationMode: BundledModel] = [
        .en2zh: BundledModel(
            directory: "opus-mt-en-zh-ct2-int8",
            mode: .en2zh,
            sourcePrefixTokens: [">>cmn_Hans<<"]
        ),
        .zh2en: BundledModel(
            directory: "opus-mt-tiny-zh-en-ct2-int8",
            mode: .zh2en,
            sourcePrefixTokens: []
        ),
    ]

    static var defaultMode: TranslationMode {
        .en2zh
    }

    private(set) var currentMode: TranslationMode = TranslatorEngine.defaultMode

    private let maxOutputLength = 96
    private let beamSize = 1

    private var translator: CTranslate2Bridge?
    private var sourceTokenizer: SentencepieceTokenizer?
    private var targetTokenizer: SentencepieceTokenizer?
    private var loadedModel: BundledModel?

    private init() {
        engineDebugLog("⏳ 正在初始化 OPUS-MT 翻译引擎...")
        loadModels(for: Self.defaultMode)
    }

    func loadModels(for mode: TranslationMode) {
        let resolvedMode = Self.isModeSupported(mode) ? mode : Self.defaultMode
        currentMode = resolvedMode

        guard let model = Self.model(for: resolvedMode) else {
            unloadCurrentModel()
            engineDebugLog("❌ 当前包内没有可用的 OPUS-MT 模型资源")
            return
        }

        if loadedModel?.directory == model.directory,
           translator != nil,
           sourceTokenizer != nil,
           targetTokenizer != nil {
            return
        }

        unloadCurrentModel()
        setupEngine(for: model)
    }

    func translate(text: String) -> String {
        translate(text: text, mode: currentMode)
    }

    func translate(text: String, mode: TranslationMode) -> String {
        guard isModeSupported(mode) else {
            return unsupportedModeMessage(for: mode)
        }

        if currentMode != mode {
            loadModels(for: mode)
        }

        guard let translator,
              let sourceTokenizer,
              let targetTokenizer,
              let model = loadedModel else {
            return "❌ 引擎未就绪"
        }

        let safeText = normalizedInput(text, mode: mode)
        guard !safeText.isEmpty else {
            return ""
        }

        do {
            let sourceTokens = try sourceTokens(
                for: safeText,
                sourcePrefixTokens: model.sourcePrefixTokens,
                tokenizer: sourceTokenizer
            )
            let outputTokens = try translator.translateTokens(
                sourceTokens,
                targetPrefix: nil,
                maxDecodingLength: maxOutputLength,
                beamSize: beamSize
            )

            let translated = try decodeOutputTokens(
                outputTokens,
                tokenizer: targetTokenizer
            )
            let cleaned = cleanedTranslationOutput(translated)
            return cleaned.isEmpty ? emptyOutputMessage(for: mode) : cleaned
        } catch {
            return "翻译推理崩溃: \(error.localizedDescription)"
        }
    }

    private func setupEngine(for model: BundledModel) {
        do {
            guard let modelDirectory = Self.modelDirectoryURL(for: model),
                  let sourceTokenizerPath = Self.resourcePath(named: "source.spm", in: model),
                  let targetTokenizerPath = Self.resourcePath(named: "target.spm", in: model) else {
                engineDebugLog("❌ 找不到 OPUS-MT 模型目录或 SentencePiece 文件")
                return
            }

            translator = try CTranslate2Bridge(
                modelPath: modelDirectory.path,
                interThreads: 1,
                intraThreads: 1
            )
            sourceTokenizer = try SentencepieceTokenizer(modelPath: sourceTokenizerPath, tokenOffset: 0)
            targetTokenizer = try SentencepieceTokenizer(modelPath: targetTokenizerPath, tokenOffset: 0)
            loadedModel = model

            engineDebugLog("✅ OPUS-MT 配置加载成功！mode=\(model.mode.rawValue)")
        } catch {
            engineDebugLog("❌ OPUS-MT 初始化失败: \(error)")
        }
    }

    private func unloadCurrentModel() {
        translator = nil
        sourceTokenizer = nil
        targetTokenizer = nil
        loadedModel = nil
    }

    private func sourceTokens(
        for text: String,
        sourcePrefixTokens: [String],
        tokenizer: SentencepieceTokenizer
    ) throws -> [String] {
        var tokenIDs = try tokenizer.encode(text)
        if tokenizer.eosTokenId >= 0,
           tokenIDs.last != tokenizer.eosTokenId {
            tokenIDs.append(tokenizer.eosTokenId)
        }

        var tokens = sourcePrefixTokens
        let encodedTokens = try tokenIDs.map { try tokenizer.idToToken($0) }
        tokens.append(contentsOf: encodedTokens)
        return tokens
    }

    private func decodeOutputTokens(
        _ outputTokens: [String],
        tokenizer: SentencepieceTokenizer
    ) throws -> String {
        let ignoredTokens = Set(["</s>", "<pad>"])
        var tokenIDs: [Int] = []
        let unkToken = try tokenizer.idToToken(tokenizer.unkTokenId)

        for token in outputTokens where !ignoredTokens.contains(token) {
            if token.hasPrefix(">>") && token.hasSuffix("<<") {
                continue
            }

            let tokenID = tokenizer.tokenToId(token)
            if tokenID == tokenizer.eosTokenId || tokenID == tokenizer.padTokenId {
                continue
            }

            if tokenID == tokenizer.unkTokenId && token != unkToken {
                continue
            }

            tokenIDs.append(tokenID)
        }

        guard !tokenIDs.isEmpty else {
            return ""
        }

        return try tokenizer.decode(tokenIDs).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedInput(_ text: String, mode: TranslationMode) -> String {
        var safeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let endingPunctuations: [Character] = [".", "!", "?", "。", "！", "？"]

        if let lastChar = safeText.last, !endingPunctuations.contains(lastChar) {
            safeText += (mode == .zh2en) ? "。" : "."
        }

        return safeText
    }

    private func cleanedTranslationOutput(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let stageDirections = [
            "鼓掌",
            "掌声",
            "applause",
            "clapping",
            "cheering",
            "laughs",
            "laughter",
        ]
        let brackets = [("(", ")"), ("（", "）"), ("[", "]"), ("【", "】")]
        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: ":：,，;；-")
        )

        while !cleaned.isEmpty {
            let previous = cleaned

            for (opening, closing) in brackets {
                guard cleaned.hasPrefix(opening),
                      let closingRange = cleaned.range(of: closing) else {
                    continue
                }

                let contentStart = cleaned.index(cleaned.startIndex, offsetBy: opening.count)
                let content = cleaned[contentStart..<closingRange.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                let isStageDirection = stageDirections.contains { marker in
                    content == marker ||
                    content.hasPrefix(marker + " ") ||
                    content.hasSuffix(" " + marker)
                }
                guard isStageDirection else { continue }

                cleaned = String(cleaned[closingRange.upperBound...])
                    .trimmingCharacters(in: separators)
                break
            }

            if cleaned == previous {
                break
            }
        }

        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,.;:!?，。！？；：])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    func isModeSupported(_ mode: TranslationMode) -> Bool {
        Self.isModeSupported(mode)
    }

    static func isModeSupported(_ mode: TranslationMode) -> Bool {
        model(for: mode) != nil
    }

    func unsupportedModeMessage(for mode: TranslationMode) -> String {
        Self.unsupportedModeMessage(for: mode)
    }

    static func unsupportedModeMessage(for mode: TranslationMode) -> String {
        guard let bundledModel = bundledModels[mode] else {
            return "当前方向没有可用的 OPUS-MT 模型。"
        }

        return "当前包内没有可用的 \(mode.displayName) OPUS-MT 模型。请把 \(bundledModel.directory) 目录中的 \(bundledModel.requiredFileListText) 加入 Resources。"
    }

    static func pickerTitle(for mode: TranslationMode) -> String {
        let title: String
        switch mode {
        case .en2zh:
            title = "🇬🇧 英 ➡️ 中 🇨🇳"
        case .zh2en:
            title = "🇨🇳 中 ➡️ 英 🇬🇧"
        }

        return isModeSupported(mode) ? title : "\(title) (未打包)"
    }

    private func emptyOutputMessage(for mode: TranslationMode) -> String {
        "模型返回空结果。请确认当前输入语言与 \(mode.displayName) 模型方向一致。"
    }

    private static func model(for mode: TranslationMode) -> BundledModel? {
        guard let model = bundledModels[mode],
              let directoryURL = modelDirectoryURL(for: model) else {
            return nil
        }

        let hasAllResources = BundledModel.requiredFiles.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(fileName).path)
        }

        let hasVocabularyFiles = BundledModel.vocabularyFileSets.contains { fileSet in
            fileSet.allSatisfy { fileName in
                FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(fileName).path)
            }
        }

        return (hasAllResources && hasVocabularyFiles) ? model : nil
    }

    private static func modelDirectoryURL(for model: BundledModel) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let directoryURL = resourceURL.appendingPathComponent(model.directory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return nil
        }

        return directoryURL
    }

    private static func resourcePath(named fileName: String, in model: BundledModel) -> String? {
        guard let directoryURL = modelDirectoryURL(for: model) else {
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL.path : nil
    }
}
