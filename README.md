# Translate

一个本地离线的 iOS 双向翻译应用，当前使用 `OPUS-MT (Marian)` + `CTranslate2 int8` 做中英互译，并集成了系统语音输入与语音播报。

## 这个项目现在是什么

- 平台：iOS
- UI：`SwiftUI`
- 默认翻译方向：`en -> zh`
- 支持方向：`en -> zh`、`zh -> en`
- 运行方式：本地推理，不依赖在线翻译 API
- 当前模型方案：两套单向 `OPUS-MT / Marian` 模型，运行时由 `CTranslate2` 驱动

## 接手这个项目，先看什么

如果你是第一次接手，建议按这个顺序看：

1. [Translate/ContentView.swift](/Users/bybon/ios/Translate/Translate/ContentView.swift)
2. [Translate/TranslatorEngine.swift](/Users/bybon/ios/Translate/Translate/TranslatorEngine.swift)
3. [Translate/CTranslate2Bridge.mm](/Users/bybon/ios/Translate/Translate/CTranslate2Bridge.mm)
4. [Translate.xcodeproj/project.pbxproj](/Users/bybon/ios/Translate/Translate.xcodeproj/project.pbxproj)
5. 两个模型目录：
   [opus-mt-en-zh-ct2-int8](/Users/bybon/ios/Translate/opus-mt-en-zh-ct2-int8)
   [opus-mt-zh-en-ct2-int8](/Users/bybon/ios/Translate/opus-mt-zh-en-ct2-int8)

理解这五处，基本就能把整个项目跑通、改通、定位问题。

## 功能

- 文本输入翻译
- 中英双向切换
- 麦克风语音输入
- 翻译结果自动播报
- 调试日志
- 启动时自动 smoke test

## 模块关系图

```text
┌───────────────────────────────┐
│          SwiftUI UI           │
│       ContentView.swift       │
│  文本输入 / 按钮 / STT / TTS   │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│      TranslatorEngine.swift   │
│  方向切换 / 模型选择 / 清洗输出 │
└───────────────┬───────────────┘
                │
     ┌──────────┴──────────┐
     │                     │
     ▼                     ▼
┌───────────────┐   ┌──────────────────┐
│ SentencePiece │   │ CTranslate2Bridge│
│ 分词/反分词    │   │ ObjC++ 桥接层     │
└───────┬───────┘   └────────┬─────────┘
        │                    │
        ▼                    ▼
┌──────────────────┐   ┌────────────────┐
│  .spm / vocab    │   │  CTranslate2   │
│ source/target    │   │ CPU 推理运行时  │
└──────────────────┘   └────────┬───────┘
                                 │
                                 ▼
                 ┌────────────────────────────────┐
                 │ OPUS-MT / Marian int8 模型目录 │
                 │ en->zh / zh->en                │
                 └────────────────────────────────┘
```

## 目录结构

```text
Translate/
├── README.md
├── Translate.xcodeproj
├── Translate
│   ├── TranslateApp.swift
│   ├── ContentView.swift
│   ├── TranslatorEngine.swift
│   ├── CTranslate2Bridge.h
│   ├── CTranslate2Bridge.mm
│   ├── Translate-Bridging-Header.h
│   └── Assets.xcassets
├── Vendor
│   └── CTranslate2
│       ├── include
│       ├── iphoneos
│       └── iphonesimulator
├── opus-mt-en-zh-ct2-int8
└── opus-mt-zh-en-ct2-int8
```

## 每个目录是干什么的

- `Translate/`
  - 业务源码
- `Translate.xcodeproj/`
  - Xcode 工程与构建配置
- `Vendor/CTranslate2/`
  - 本地 vendored 的 CTranslate2 静态库与头文件
- `opus-mt-en-zh-ct2-int8/`
  - 英译中模型
- `opus-mt-zh-en-ct2-int8/`
  - 中译英模型

## 技术栈

### 应用层

- `Swift 5`
- `SwiftUI`
- `Foundation`

### 系统能力

- `Speech`
  - 用于语音识别（STT）
- `AVFoundation`
  - 用于录音会话管理
  - 用于语音播报（TTS）

### 模型与推理

- `OPUS-MT / Marian`
  - 当前使用两套单向模型
- `CTranslate2`
  - 本地 CPU 推理引擎
  - 通过静态库方式接入
- `SentencePiece`
  - 模型分词 / 反分词
- `int8` 量化
  - 用于降低模型体积

### 语言桥接

- `Objective-C++ (.mm)`
  - 把 Swift 层调用桥接到 C++ 的 `CTranslate2`

## 第三方库

### Swift Package Manager

- `swift-sentencepiece`
  - 仓库：`https://github.com/jkrukowski/swift-sentencepiece.git`
  - 产品名：`SentencepieceTokenizer`
- `swift-argument-parser`
  - 当前出现在 `Package.resolved`
  - 属于 SwiftPM 解析到的传递依赖，不是本项目直接业务依赖

### 本地 Vendor 库

- `Vendor/CTranslate2`
  - `iphoneos/libctranslate2.a`
  - `iphonesimulator/libctranslate2.a`
  - 头文件位于 `Vendor/CTranslate2/include`

说明：

- `CTranslate2` 是当前项目的推理运行时。
- 当前工程通过 `SYSTEM_HEADER_SEARCH_PATHS`、`LIBRARY_SEARCH_PATHS` 和 `-lctranslate2` 显式链接它。
- 如果删掉 `Vendor/CTranslate2`，工程会直接编译失败。

## 模型资源

项目当前打包了两套 CTranslate2 模型目录：

- `opus-mt-en-zh-ct2-int8`
- `opus-mt-zh-en-ct2-int8`

每个目录包含：

- `model.bin`
- `config.json`
- `shared_vocabulary.json`
- `source.spm`
- `target.spm`

当前体积大致为：

- 每个方向模型约 `79 MB`
- `Vendor/CTranslate2` 约 `22 MB`

模型之所以比以前更小，主要因为：

- 换成了更小的 `Marian / OPUS-MT`
- 使用了 `int8` 量化
- `CTranslate2` 将推理权重收敛为单个 `model.bin`

## 核心源码说明

### `Translate/TranslateApp.swift`

- 应用入口
- 只负责挂载 `ContentView`

### `Translate/ContentView.swift`

- SwiftUI 主界面
- 管理输入框、按钮、翻译方向切换
- 集成语音输入 `SpeechManager`
- 集成语音播报 `TTSManager`
- 包含调试用 smoke test 入口

### `Translate/TranslatorEngine.swift`

- 翻译核心逻辑
- 管理当前翻译方向
- 校验打包模型是否完整
- 使用 `SentencepieceTokenizer` 做编码 / 解码
- 调用 `CTranslate2Bridge`
- 清洗输出文本

### `Translate/CTranslate2Bridge.h`

- 暴露给 Swift 的桥接接口

### `Translate/CTranslate2Bridge.mm`

- Objective-C++ 到 C++ 的桥接实现
- 实例化 `ctranslate2::Translator`
- 把 token 数组送入推理引擎

### `Translate/Translate-Bridging-Header.h`

- Swift / Objective-C 桥接头

## 翻译流程

1. 用户在 `ContentView` 输入文本，或通过 `Speech` 进行语音识别。
2. `TranslatorEngine` 根据当前方向选择对应模型目录。
3. `SentencepieceTokenizer` 把文本编码成 token。
4. `en -> zh` 方向会在源 token 前附加 `>>cmn_Hans<<`。
5. `CTranslate2Bridge.mm` 调用 `ctranslate2::Translator` 进行推理。
6. 推理输出 token 后，目标端再经过 `SentencePiece` 解码成自然语言。
7. `TranslatorEngine` 对文本做清洗后返回 UI。
8. `AVSpeechSynthesizer` 可自动播报翻译结果。

## 当前工程配置

- iOS Deployment Target：`16.0`
- 推理设备：`CPU`
- 推理线程：
  - `interThreads = 1`
  - `intraThreads = 1`
- 当前 beam：`1`
- 资源打包方式：
  - 两个模型目录作为 `Resources` 打进 App

## 构建与运行

### 开发环境

- Xcode
- iOS SDK
- iOS Deployment Target：`16.0`

### 打开方式

- 直接用 Xcode 打开 `Translate.xcodeproj`

### 构建说明

- Swift Package 依赖会由 Xcode 自动解析
- `Vendor/CTranslate2` 必须保留，否则静态库无法链接
- 两个 `opus-mt-*-ct2-int8` 目录必须继续作为应用资源打包

## 常用命令

### 命令行构建

```bash
xcodebuild \
  -project Translate.xcodeproj \
  -scheme Translate \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 启动模拟器 App

```bash
xcrun simctl launch --console-pty <SIMULATOR_UDID> com.bajie.Translate
```

### 启动时自动做 en -> zh smoke test

```bash
SIMCTL_CHILD_TRANSLATE_DEBUG_LOGS=1 \
SIMCTL_CHILD_TRANSLATE_SMOKETEST_TEXT='The translation engine initialized successfully.' \
SIMCTL_CHILD_TRANSLATE_SMOKETEST_MODE='en-zh' \
xcrun simctl launch --console-pty <SIMULATOR_UDID> com.bajie.Translate
```

### 启动时自动做 zh -> en smoke test

```bash
SIMCTL_CHILD_TRANSLATE_DEBUG_LOGS=1 \
SIMCTL_CHILD_TRANSLATE_SMOKETEST_TEXT='翻译引擎初始化成功。' \
SIMCTL_CHILD_TRANSLATE_SMOKETEST_MODE='zh-en' \
xcrun simctl launch --console-pty <SIMULATOR_UDID> com.bajie.Translate
```

## 语音相关

### 语音输入

- `SFSpeechRecognizer`
- `SFSpeechAudioBufferRecognitionRequest`
- `AVAudioEngine`

### 语音输出

- `AVSpeechSynthesizer`
- 根据翻译方向动态选择语言：
  - `en -> zh` 使用 `zh-CN`
  - `zh -> en` 使用 `en-US`

## 调试与自检

项目保留了调试日志和自动自检入口。

可用环境变量：

- `TRANSLATE_DEBUG_LOGS=1`
  - 打开调试日志
- `TRANSLATE_SMOKETEST_TEXT`
  - 启动后自动填入文本并触发翻译
- `TRANSLATE_SMOKETEST_MODE`
  - 可选值：`en-zh`、`zh-en`

## 常见问题

### 1. 为什么删了 `Vendor/CTranslate2` 就编不过

因为当前工程不是通过 Pod、SPM 或 XCFramework 拉取 CTranslate2，而是直接链接本地静态库。

### 2. 为什么模型目录里只有一个 `model.bin`

因为现在走的是 `CTranslate2` 的导出格式，不是旧的多 ONNX 文件拆分格式。

### 3. 为什么 `en -> zh` 要加 `>>cmn_Hans<<`

因为当前 `opus-mt-en-zh` 模型在输入侧需要这个源端语言控制 token。

### 4. 为什么仓库里有两套模型目录

因为当前采用的是两套单向模型，而不是一个真正双向共享权重模型。

## 如果你要继续改这个项目

最常见的改动点：

- 改 UI：看 `ContentView.swift`
- 改翻译策略：看 `TranslatorEngine.swift`
- 改推理参数：看 `CTranslate2Bridge.mm`
- 换模型：替换 `opus-mt-*-ct2-int8` 目录，并同步校验资源格式
- 改构建方式：看 `Translate.xcodeproj/project.pbxproj`

## 后续可优化方向

- 把 `Vendor/CTranslate2` 打成 `XCFramework`
- 继续缩小模型体积
- 提升 beam/search 策略
- 加更多语言方向
- 增加自动化测试
- 增加模型替换文档
