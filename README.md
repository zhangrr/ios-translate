# Translate

一个本地离线的 iOS 双向翻译应用，使用 `OPUS-MT` 做中英互译，并集成了系统语音输入与语音播报。

- `en -> zh`：`opus-mt-small512d-opus100-ft-mix-coffee` 模型（d_model=512）
- `zh -> en`：`OPUS-MT Tiny` 模型（25.4M 参数）

两套模型均使用 `CTranslate2 int8` 量化，运行时本地 CPU 推理。

## 这个项目现在是什么

- 平台：iOS
- UI：`SwiftUI`
- 默认翻译方向：`en -> zh`
- 支持方向：`en -> zh`、`zh -> en`
- 运行方式：本地推理，不依赖在线翻译 API
- 当前模型方案：两套不同大小的单向模型混合部署

## 接手这个项目，建议先看什么

1. [Translate/ContentView.swift](/Users/bybon/ios/Translate/Translate/ContentView.swift)
2. [Translate/TranslatorEngine.swift](/Users/bybon/ios/Translate/Translate/TranslatorEngine.swift)
3. [Translate/CTranslate2Bridge.mm](/Users/bybon/ios/Translate/Translate/CTranslate2Bridge.mm)
4. [Translate.xcodeproj/project.pbxproj](/Users/bybon/ios/Translate/Translate.xcodeproj/project.pbxproj)
5. 两个模型目录：
   [opus-mt-small320d-opus100-joint32k-ft-money-coffee-ct2-int8](/Users/bybon/ios/Translate/opus-mt-small320d-opus100-joint32k-ft-money-coffee-ct2-int8)
   [opus-mt-tiny-zh-en-ct2-int8](/Users/bybon/ios/Translate/opus-mt-tiny-zh-en-ct2-int8)

## 功能

- 文本输入翻译
- 中英双向切换
- 麦克风语音输入
- 翻译结果自动播报
- 调试日志
- 启动时自动 smoke test

## 目录结构

```text
Translate/
├── README.md
├── Translate.xcodeproj
│   ├── project.pbxproj
│   └── project.xcworkspace
│       ├── contents.xcworkspacedata
│       └── xcshareddata/
├── Translate
│   ├── TranslateApp.swift
│   ├── ContentView.swift
│   ├── TranslatorEngine.swift
│   ├── CTranslate2Bridge.h
│   ├── CTranslate2Bridge.mm
│   ├── Translate-Bridging-Header.h
│   ├── Assets.xcassets
│   │   ├── AccentColor.colorset/
│   │   ├── AppIcon.appiconset/
│   │   └── Contents.json
│   └── Preview Content/
│       └── Preview Assets.xcassets/
├── Vendor
│   └── CTranslate2
│       ├── include/
│       │   └── ctranslate2/
│       ├── iphoneos/
│       │   └── libctranslate2.a
│       └── iphonesimulator/
│           └── libctranslate2.a
├── opus-mt-small320d-opus100-joint32k-ft-money-coffee-ct2-int8
│   ├── model.bin
│   ├── config.json
│   ├── source.spm
│   ├── target.spm
│   └── shared_vocabulary.json
└── opus-mt-tiny-zh-en-ct2-int8
    ├── model.bin
    ├── config.json
    ├── source.spm
    ├── target.spm
    └── shared_vocabulary.json
```

## 每个目录/文件是干什么的

- `README.md`
  - 项目说明文档（就是你现在看的这个）
- `Translate.xcodeproj/`
  - Xcode 工程文件，包含构建配置和资源引用
  - `project.pbxproj`：工程的核心配置文件，包含编译设置、链接参数、资源引用
- `Translate/`
  - 业务源码
  - `TranslateApp.swift`：应用入口，挂载 `ContentView`
  - `ContentView.swift`：SwiftUI 主界面，管理输入框、方向切换、语音输入/播报
  - `TranslatorEngine.swift`：翻译核心逻辑，方向切换、模型选择、分词/反分词、清洗输出
  - `CTranslate2Bridge.h`：暴露给 Swift 的桥接接口声明
  - `CTranslate2Bridge.mm`：Objective-C++ 到 C++ 的桥接实现，调用 `CTranslate2`
  - `Translate-Bridging-Header.h`：Swift / Objective-C 桥接头
  - `Assets.xcassets/`：应用图标、主题色等资源
  - `Preview Content/`：Xcode 预览用的资源
- `Vendor/CTranslate2/`
  - 本地 vendored 的 CTranslate2 静态库与头文件
  - `include/ctranslate2/`：C++ 头文件
  - `iphoneos/libctranslate2.a`：真机静态库（~6.6 MB）
  - `iphonesimulator/libctranslate2.a`：模拟器静态库（~14 MB）
- `opus-mt-small320d-opus100-joint32k-ft-money-coffee-ct2-int8/`
  - 英译中模型（`opus-mt-small512d-opus100-ft-mix-coffee`，int8 量化后 ~64 MB）
- `opus-mt-tiny-zh-en-ct2-int8/`
  - 中译英模型（OpusDistillery 蒸馏 Tiny，25.4M 参数，int8 量化后 ~19 MB）

## 模块关系图

```text
┌───────────────────────────────┐
│          SwiftUI UI           │
│       ContentView.swift       │
│  文本输入 / 方向切换 / STT / TTS │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│      TranslatorEngine.swift   │
│  方向切换 / 模型选择 / 清洗输出  │
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
              ┌─────────────────┴─────────────────┐
              │                                   │
              ▼                                   ▼
┌─────────────────────────────────────────┐      ┌────────────────────────────┐
│ opus-mt-small512d-opus100-ft-mix-coffee │      │ opus-mt-tiny-zh-en-ct2-int8│
│ en -> zh (~64 MB)                       │      │ zh -> en (Tiny, ~19 MB)     │
│ Marian NMT, d_model=512                 │      │ Marian 25.4M 参数           │
└─────────────────────────────────────────┘      └────────────────────────────┘
```

## 模型资源

| 方向 | 模型 | 参数量 | int8 体积 |
|------|------|--------|-----------|
| `en -> zh` | `opus-mt-small512d-opus100-ft-mix-coffee` | — | **~64 MB** |
| `zh -> en` | `Helsinki-NLP/opus-mt_tiny_zho-eng` | 25.4M | **~19 MB** |
| **合计** | — | — | **~83 MB** |

### 模型目录内容

每个模型目录包含 5 个文件：

| 文件 | 作用 |
|------|------|
| `model.bin` | CTranslate2 格式的推理权重（二进制） |
| `config.json` | 模型配置（特殊 token、层归一化 epsilon 等） |
| `source.spm` | 源语言 SentencePiece 分词器模型 |
| `target.spm` | 目标语言 SentencePiece 分词器模型 |
| `shared_vocabulary.json` | 词表（JSON 数组格式，按 token ID 排序） |

### 模型来源与选择

- `en->zh`：基于 `opus-mt-small512d-opus100` 在混合语料上微调的模型，d_model=512，int8 量化后约 **64 MB**。
- `zh->en`：Helsinki-NLP `OpusDistillery` 蒸馏的 Tiny 模型（25.4M 参数），int8 量化后约 **19 MB**。

两套模型均为单向模型，混合部署以平衡质量与体积。

## 技术栈

### 应用层

- `Swift 5`
- `SwiftUI`
- `Foundation`

### 系统能力

- `Speech`
  - `SFSpeechRecognizer`：语音识别（STT）
  - `SFSpeechAudioBufferRecognitionRequest`：实时音频流识别
  - `AVAudioEngine`：录音会话管理
- `AVFoundation`
  - `AVAudioSession`：录音/播放会话管理
  - `AVSpeechSynthesizer`：语音播报（TTS）

### 模型与推理

- `OPUS-MT / Marian`
  - `en->zh`：`opus-mt-small512d-opus100-ft-mix-coffee`（d_model=512）
  - `zh->en`：Tiny 蒸馏模型（6 enc + 2 dec，d_model=256）
- `CTranslate2`
  - 本地 CPU 推理引擎
  - 通过静态库方式接入（`libctranslate2.a`）
- `SentencePiece`
  - 模型分词 / 反分词
  - Swift 侧通过 `swift-sentencepiece` 调用
- `int8` 量化
  - 降低模型体积和内存占用

### 语言桥接

- `Objective-C++ (.mm)`
  - `CTranslate2Bridge.mm`：把 Swift 层调用桥接到 C++ 的 `CTranslate2`

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
  - `iphoneos/libctranslate2.a`：真机静态库（~6.6 MB）
  - `iphonesimulator/libctranslate2.a`：模拟器静态库（~14 MB）
  - 头文件位于 `Vendor/CTranslate2/include/ctranslate2/`

说明：

- `CTranslate2` 是当前项目的推理运行时。
- 当前工程通过 `SYSTEM_HEADER_SEARCH_PATHS`、`LIBRARY_SEARCH_PATHS` 和 `-lctranslate2` 显式链接它。
- 如果删掉 `Vendor/CTranslate2`，工程会直接编译失败。

## 核心源码说明

### `Translate/TranslateApp.swift`

- 应用入口
- 只负责挂载 `ContentView`

### `Translate/ContentView.swift`

- SwiftUI 主界面
- 管理输入框、翻译按钮、翻译方向切换 Segmented Picker
- 集成语音输入 `SpeechManager`
- 集成语音播报 `TTSManager`
- 包含调试用 smoke test 入口

### `Translate/TranslatorEngine.swift`

- 翻译核心逻辑
- 管理当前翻译方向
- 校验打包模型是否完整
- 使用 `SentencepieceTokenizer` 做编码 / 解码
- 调用 `CTranslate2Bridge`
- `en -> zh` 方向会在源 token 前附加 `>>cmn_Hans<<`
- 清洗输出文本

### `Translate/CTranslate2Bridge.h`

- 暴露给 Swift 的桥接接口声明

### `Translate/CTranslate2Bridge.mm`

- Objective-C++ 到 C++ 的桥接实现
- 实例化 `ctranslate2::Translator`
- 把 token 数组送入推理引擎
- 当前推理参数：
  - `interThreads = 1`
  - `intraThreads = 1`
  - `compute_type = DEFAULT`（int8 模型回退到 float32）

### `Translate/Translate-Bridging-Header.h`

- Swift / Objective-C 桥接头

## 翻译流程

1. 用户在 `ContentView` 输入文本，或通过 `Speech` 进行语音识别。
2. `TranslatorEngine` 根据当前方向选择对应模型目录：
   - `en -> zh`：`opus-mt-small320d-opus100-joint32k-ft-money-coffee-ct2-int8`
   - `zh -> en`：`opus-mt-tiny-zh-en-ct2-int8`
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
  - 两个模型目录作为 `Resources` 打进 App Bundle

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
- 两个模型目录必须继续作为应用资源打包

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

## Smoke Test

### en -> zh

```bash
SIMCTL_CHILD_TRANSLATE_DEBUG_LOGS=1 \
SIMCTL_CHILD_TRANSLATE_SMOKETEST_TEXT='The translation engine initialized successfully.' \
SIMCTL_CHILD_TRANSLATE_SMOKETEST_MODE='en-zh' \
xcrun simctl launch --console-pty <SIMULATOR_UDID> com.bajie.Translate
```

### zh -> en

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

因为当前 `en->zh` 模型在输入侧需要这个源端语言控制 token。

### 4. 为什么两套模型大小不一样

- `en->zh`：`opus-mt-small512d-opus100-ft-mix-coffee`（d_model=512，int8 量化后 ~64 MB）
- `zh->en`：OpusDistillery 蒸馏的 Tiny 模型（25.4M 参数，6 enc + 2 dec，d_model=256，int8 量化后 ~19 MB）

`zh->en` 方向使用了层数更少的蒸馏模型，因此体积更小。

## 后续可优化方向

### 短期（不训练）

- 把 `Vendor/CTranslate2` 打成 `XCFramework`
- 使用 On-Demand Resources (ODR) 按需加载模型
- 升级 CTranslate2 静态库，消除 `int8_float32 -> float32 fallback` 警告
- 评估模型按需下载（只打包默认方向，另一方向首次使用时下载）

### 中期（需训练资源）

- **蒸馏自己的 `en->zh` Tiny 模型**
  - 使用 `OpusDistillery` 框架
  - 教师模型：当前 `en->zh` 模型
  - 学生架构：d_model=256，6 enc + 2 dec layers，vocab=32000
  - 预计训练时间：A100 上 2-4 小时
  - 预期体积：从 ~64 MB 降到 ~18 MB
  - 总模型体积可从 ~83 MB 降到 **~36 MB**

### 长期

- 评估多语言模型（M2M-100、NLLB）的单语对质量
- 探索 `int4` 量化（需更换推理框架，CTranslate2 CPU 不支持 INT4）

## 如果你要继续改这个项目

最常见的改动点：

- 改 UI：看 `ContentView.swift`
- 改翻译策略：看 `TranslatorEngine.swift`
- 改推理参数：看 `CTranslate2Bridge.mm`
- 换模型：替换 `opus-mt-*-ct2-int8` 目录，并同步校验资源格式
- 改构建方式：看 `Translate.xcodeproj/project.pbxproj`
