import SwiftUI
import Speech
import AVFoundation

private let translationDebugLoggingEnabled =
    ProcessInfo.processInfo.environment["TRANSLATE_DEBUG_LOGS"] == "1"

private func appDebugLog(_ message: String) {
    guard translationDebugLoggingEnabled else { return }
    print(message)
    NSLog("%@", message)
}

// ==========================================
// 🎙️ 苹果原生语音识别引擎 (STT - 听)
// ==========================================
class SpeechManager: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func checkPermission() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
    }

    // 🌟 传入不同的语言代码，让麦克风变得聪明
    func toggleRecording(languageCode: String) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(languageCode: languageCode)
        }
    }

    private func startRecording(languageCode: String) {
        // 动态根据方向设置听力语言 (zh-CN 或 en-US)
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))

        if task != nil {
            task?.cancel()
            task = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        guard let request = request else { return }
        request.shouldReportPartialResults = true // 实时吐字

        task = speechRecognizer?.recognitionTask(with: request, resultHandler: { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        })

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        DispatchQueue.main.async {
            self.recognizedText = ""
            self.isRecording = true
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
}

// ==========================================
// 🔊 苹果原生语音播报引擎 (TTS - 说)
// ==========================================
class TTSManager {
    static let shared = TTSManager()

    static var isSupported: Bool {
        true
    }

    private let synthesizer = AVSpeechSynthesizer()

    // 🌟 传入语言代码，决定念中文还是英文
    func speak(text: String, language: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard let voice = AVSpeechSynthesisVoice(language: language) else {
            appDebugLog("⚠️ 未找到可用语音: \(language)")
            return
        }

        let utterance = AVSpeechUtterance(string: normalizedText)
        utterance.voice = voice
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}

// ==========================================
// 📱 你的翻译主界面
// ==========================================
struct ContentView: View {
    @State private var inputText: String = ""
    @State private var translatedText: String = "翻译结果将在这里显示..."
    @State private var isTranslating: Bool = false

    // 🌟 UI 层维护当前的翻译模式状态 (默认英翻中)
    @State private var currentMode: TranslationMode = TranslatorEngine.defaultMode

    @StateObject private var speechManager = SpeechManager()

    private var canSpeakTranslatedText: Bool {
        TTSManager.isSupported &&
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !translatedText.contains("翻译结果") &&
        !translatedText.contains("大脑") &&
        !translatedText.contains("AI 正在思考") &&
        !translatedText.contains("当前包内") &&
        !translatedText.contains("请把") &&
        !translatedText.contains("模型返回空结果") &&
        !isTranslating
    }

    private var isCurrentModeSupported: Bool {
        TranslatorEngine.isModeSupported(currentMode)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("AI 同传翻译官")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 40)

            // 🌟 1. 双向切换器 (Segmented Picker)
            Picker("翻译方向", selection: $currentMode) {
                Text(TranslatorEngine.pickerTitle(for: .en2zh))
                    .tag(TranslationMode.en2zh)
                Text(TranslatorEngine.pickerTitle(for: .zh2en))
                    .tag(TranslationMode.zh2en)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .onChange(of: currentMode) { newMode in
                guard TranslatorEngine.isModeSupported(newMode) else {
                    translatedText = TranslatorEngine.unsupportedModeMessage(for: newMode)
                    currentMode = TranslatorEngine.defaultMode
                    return
                }

                // 切换方向时：清空界面，并在后台切换模型大脑
                inputText = ""
                translatedText = "正在切换底层 AI 大脑..."
                DispatchQueue.global(qos: .userInitiated).async {
                    TranslatorEngine.shared.loadModels(for: newMode)
                    DispatchQueue.main.async {
                        self.translatedText = "翻译结果将在这里显示..."
                    }
                }
            }

            // 输入区 (带麦克风)
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $inputText)
                    .frame(height: 150)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.5), lineWidth: 2))
                    .overlay(
                        // 动态占位符
                        Text(inputText.isEmpty ? (currentMode == .en2zh ? "在此输入英文，或点击麦克风说话..." : "在此输入中文，或点击麦克风说话...") : "")
                            .foregroundColor(.gray)
                            .padding(.top, 16)
                            .padding(.leading, 12),
                        alignment: .topLeading
                    )

                // 🎙️ 录音按钮
                Button(action: {
                    speechManager.toggleRecording(languageCode: currentMode.listenLanguageCode)
                }) {
                    Image(systemName: speechManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .foregroundColor(speechManager.isRecording ? .red : .blue)
                        .padding()
                }
            }
            .padding(.horizontal)
            .onChange(of: speechManager.recognizedText) { newValue in
                if !newValue.isEmpty {
                    inputText = newValue
                }
            }

            // 翻译按钮
            Button(action: {
                startTranslation()
            }) {
                if isTranslating {
                    Text("翻译中...")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12)
                } else {
                    Text("翻译 (Translate)")
                        .font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                isTranslating ||
                speechManager.isRecording ||
                !isCurrentModeSupported
            )

            // 输出结果框 (带小喇叭)
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    Text(translatedText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                // 🔊 播报按钮
                Button(action: {
                    TTSManager.shared.speak(text: translatedText, language: currentMode.speakLanguageCode)
                }) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .foregroundColor(.green)
                        .padding(12)
                }
                .disabled(!canSpeakTranslatedText)
                .opacity(TTSManager.isSupported ? 1 : 0.35)
            }
            .padding(.horizontal)

            Spacer()
        }
        .onAppear {
            speechManager.checkPermission()
            // 把首次引擎初始化放到后台，避免首屏阻塞主线程。
            DispatchQueue.global(qos: .userInitiated).async {
                TranslatorEngine.shared.loadModels(for: currentMode)
                DispatchQueue.main.async {
                    runSmokeTestIfRequested()
                }
            }
        }
    }

    // 点击翻译按钮后执行的动作
    func startTranslation() {
        let sourceText = inputText
        let mode = currentMode
        let engine = TranslatorEngine.shared

        guard engine.isModeSupported(mode) else {
            translatedText = engine.unsupportedModeMessage(for: mode)
            return
        }

        isTranslating = true
        translatedText = "AI 正在思考中，请稍候..."
        appDebugLog("▶️ 开始翻译 mode=\(mode.rawValue) text=\(sourceText)")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.translate(text: sourceText, mode: mode)

            DispatchQueue.main.async {
                self.translatedText = result
                self.isTranslating = false
                appDebugLog("✅ 翻译返回: \(result)")

                // 翻译完成后，自动根据方向发音！
                if TTSManager.isSupported &&
                    !result.contains("失败") &&
                    !result.contains("错误") &&
                    !result.contains("当前包内") &&
                    !result.contains("请把") &&
                    !result.contains("模型返回空结果") {
                    TTSManager.shared.speak(text: result, language: mode.speakLanguageCode)
                }
            }
        }
    }

    private func runSmokeTestIfRequested() {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let arguments = processInfo.arguments

        let defaults = UserDefaults.standard
        let smokeText = environment["TRANSLATE_SMOKETEST_TEXT"]
            ?? argumentValue(named: "smoketest-text", in: arguments)
            ?? defaults.string(forKey: "-smoketest-text")
            ?? defaults.string(forKey: "smoketest-text")

        guard let smokeText,
              !smokeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isTranslating else {
            return
        }

        let requestedModeRaw = environment["TRANSLATE_SMOKETEST_MODE"]
            ?? argumentValue(named: "smoketest-mode", in: arguments)
            ?? defaults.string(forKey: "-smoketest-mode")
            ?? defaults.string(forKey: "smoketest-mode")
        let requestedMode = requestedModeRaw
            .flatMap(TranslationMode.init(rawValue:))
        if let requestedMode, requestedMode != currentMode {
            currentMode = requestedMode
            if TranslatorEngine.isModeSupported(requestedMode) {
                TranslatorEngine.shared.loadModels(for: requestedMode)
            }
        }

        inputText = smokeText
        appDebugLog("🧪 自动自检触发 text=\(smokeText)")
        startTranslation()
#endif
    }

    private func argumentValue(named name: String, in arguments: [String]) -> String? {
        let aliases = [name, "--\(name)", "-\(name)"]
        guard let index = arguments.firstIndex(where: { aliases.contains($0) }),
              index + 1 < arguments.count else {
            return nil
        }

        return arguments[index + 1]
    }
}

#Preview {
    ContentView()
}
