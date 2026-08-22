<p align="center">
  <img src="assets/logo.svg" alt="AcornMed Logo" width="180" height="180">
</p>

<h1 align="center">AcornMed</h1>

<p align="center">
  <strong>A privacy-first, offline-capable medical AI assistant for students and clinicians.</strong>
  <br>
  Runs entirely on-device using llama.cpp — no accounts, no API keys, no cloud.
</p>

<p align="center">
  <a href="https://github.com/SparshMishra09/AcornMed/releases"><img alt="Release" src="https://img.shields.io/github/v/release/SparshMishra09/AcornMed?include_prereleases&label=latest%20release"></a>
  <a href="https://github.com/SparshMishra09/AcornMed/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/SparshMishra09/AcornMed"></a>
  <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white"></a>
  <a href="https://dart.dev"><img alt="Dart" src="https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white"></a>
  <a href="https://github.com/ggerganov/llama.cpp"><img alt="llama.cpp" src="https://img.shields.io/badge/llama.cpp-b4621-FF6B35?logo=llama.cpp&logoColor=white"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%208%2B-green">
  <img alt="Architecture" src="https://img.shields.io/badge/arch-arm64%20%7C%20x86_64-blue">
</p>

---

## 🎯 Overview

**AcornMed** is a medical study companion that puts a capable LLM directly on your Android device. Designed for medical students, residents, and clinicians who need reliable, citeable information without compromising patient data or requiring an internet connection.

### Why AcornMed?

| Problem | AcornMed Solution |
|---------|-------------------|
| 🏥 Patient data privacy | **100% on-device** — nothing leaves your phone |
| 💰 API costs / rate limits | **Zero API keys** — runs locally via llama.cpp |
| 📶 No internet in hospitals | **Fully offline** core functionality |
| 📚 Scattered resources | **Unified RAG** across 6 medical subjects + your PDFs |
| 🔍 Outdated knowledge | **Optional live web search** (PubMed, Wikipedia, Web) |
| 📸 Image-only materials | **On-device OCR** (ML Kit, no cloud) |

---

## ✨ Features

### 🧠 Local LLM Inference
- **Engine**: llama.cpp via `llama_flutter_android` (ARM64 + x86_64)
- **Models**: Any GGUF (tested with Llama-3.1-8B-Instruct-Q4_K_M, Phi-3-mini-4k-Q4)
- **Context**: 4K–8K tokens (configurable)
- **Threads**: Auto-detected, tunable
- **No internet required** for core chat

### 🌐 Web Search (Optional, Keyless)
- **PubMed** — Latest biomedical literature via NCBI E-utilities
- **Wikipedia** — General medical concepts via MediaWiki API
- **DuckDuckGo** — General web via HTML scrape (fallback)
- **Auto-detect** freshness queries ("latest guidelines", "2024 treatment")
- **Manual toggle** in chat input bar
- **Smart intercept**: Model emits `[SEARCH: query]` → app searches → re-prompts with results
- **Citations**: Numbered source chips with tappable URLs

### 📄 Document Library (RAG)
- **Formats**: PDF, DOCX, TXT, Markdown
- **Extraction**: Syncfusion PDF + custom DOCX (ZIP/XML) parser
- **Indexing**: TF-IDF + cosine similarity, per-document chunks
- **Per-chat attachment**: Select docs from library → searched first
- **Management**: Documents screen (add/delete/reindex)

### 🖼️ Image OCR (Offline)
- **Source**: Camera or gallery
- **Engine**: Google ML Kit Text Recognition (bundled model, no Play Services)
- **Flow**: Pick → OCR → preview extracted text → send with query
- **Honest about limits**: "I can't see images" for pure visual questions

### 🎨 Polish
- **Real SVG logo** → crisp at any resolution
- **Adaptive launcher icons** (foreground on sage `#8D9771`)
- **Native splash** (Android 8–11 + Android 12+)
- **Dark / Light theme** (sage/cream palette)
- **Riverpod** state management
- **Hive** local storage (conversations, documents, settings)

---

## 📱 Screenshots

<p align="center">
  <img src="docs/screenshots/chat_light.png" alt="Chat Light" width="280">
  <img src="docs/screenshots/chat_dark.png" alt="Chat Dark" width="280">
  <img src="docs/screenshots/docs_screen.png" alt="Documents Library" width="280">
  <img src="docs/screenshots/attach_docs.png" alt="Attach Documents Sheet" width="280">
  <img src="docs/screenshots/web_search.png" alt="Web Search Results" width="280">
  <img src="docs/screenshots/ocr_flow.png" alt="Image OCR Flow" width="280">
</p>

> **Note**: Screenshots go in `docs/screenshots/`. Add your own device captures there.

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── theme/           # AppTheme (light/dark), AppColors
│   └── widgets/         # AppLogo (SVG + fallback)
├── data/
│   ├── models/          # ChatMessage, Conversation, DocumentItem, WebSource (Hive adapters)
│   └── services/
│       ├── ai_engine.dart        # llama.cpp wrapper (load/chat/stop)
│       ├── model_manager.dart    # Model file discovery, validation
│       ├── storage_service.dart  # Hive boxes (conversations, documents)
│       ├── knowledge_service.dart# TF-IDF RAG (bundled + user docs)
│       ├── document_extractor.dart # PDF/DOCX/TXT text extraction
│       ├── document_service.dart # Import, delete, reindex
│       ├── ocr_service.dart      # ML Kit text recognition
│       └── web_search_service.dart # PubMed/Wiki/DDG search
├── features/
│   ├── home/            # ChatView, AttachDocumentsSheet, HistoryDrawer
│   ├── documents/       # DocumentsScreen (library UI)
│   ├── settings/        # SettingsScreen (model, theme, stats)
│   ├── model_setup/     # ModelSetupScreen (GGUF picker)
│   ├── onboarding/      # OnboardingScreen
│   └── splash/          # SplashScreen
├── providers/
│   └── chat_providers.dart   # ChatController (Riverpod Notifier)
└── main.dart
```

### Data Flow

```
User Query
    │
    ├─▶ Attached Doc IDs ──▶ KnowledgeService.retrieve(docIds) ──▶
    │                                                        │
    ├─▶ Web Search (toggle/auto) ──▶ WebSearchService.search() ──▶
    │                                                        │
    └─▶ OCR Text (if image) ─────────────────────────────────▶
                                                             ▼
                                                buildContext() → System Prompt
                                                             │
                                                             ▼
                                                   llama.cpp Stream
                                                             │
                                                             ▼
                                                   [SEARCH:] intercept?
                                                             │
                                            ┌────────────────┴────────────────┐
                                            ▼                                 ▼
                                      Yes (re-search)                      No (finalize)
                                            │                                 │
                                            ▼                                 ▼
                                    _generate() again                   Save + UI
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter 3.24+** (Dart 3.5+)
- **Android SDK 34**, NDK 26+
- **Java 17** (for Gradle)
- **Device/emulator** with Android 8.0+ (API 26)

### Installation

```bash
# Clone
git clone https://github.com/SparshMishra09/AcornMed.git
cd AcornMed

# Get dependencies
flutter pub get

# (Optional) Generate Hive adapters if models change
dart run build_runner build --delete-conflicting-outputs

# Debug build
flutter run --debug

# Release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Model Setup
1. Download a GGUF model (e.g., from Hugging Face):
   - `Llama-3.1-8B-Instruct-Q4_K_M.gguf` (~4.7 GB)
   - `Phi-3-mini-4k-instruct-q4.gguf` (~2.3 GB)
2. Transfer to device (Downloads, Documents, or any folder)
3. Open app → **Settings → Model** → **Select model file**
4. App loads model (first load ~10–30s depending on device)

> **Tip**: Place model in `Android/data/com.acornmed.acorn_med/files/Models/` for auto-detection.

---

## 📖 Usage Guide

### Chat
- Type a medical question → send
- **Web toggle** (🌐 chip): force live search
- **Auto-search**: detected for freshness terms ("latest", "2024", "new guideline")
- **Citations**: tap numbered chips to open source URLs

### Attach Documents
1. Tap **📎 Docs** chip in input bar
2. Select from library or tap **Add** → Documents screen → upload
3. Selected docs show badge count on chip
4. Query → RAG searches your docs **first**, then bundled knowledge

### Manage Documents
- **Drawer → Documents** (or from attach sheet)
- **Add**: PDF, DOCX, TXT, MD (multi-select)
- **Delete**: swipe or tap delete icon
- **Reindex**: automatic on app start, or pull-to-refresh in Documents screen

### Image OCR
1. Tap **🖼️ Image** chip → Camera or Gallery
2. App runs on-device OCR (shows progress)
3. Preview extracted text (editable)
4. Send → text included as context for the model

### Settings
- **Model**: change GGUF, adjust threads/context
- **Theme**: Light / Dark / System
- **Knowledge stats**: bundled chunks, your document chunks
- **Privacy**: all local, no telemetry

---

## 🔧 Configuration

### Model Parameters (Settings)
| Parameter | Range | Default | Notes |
|-----------|-------|---------|-------|
| Context length | 512–8192 | 4096 | Higher = more memory |
| Threads | 1–8 | Auto | CPU cores |
| Temperature | 0.0–1.5 | 0.7 | Creativity |
| Top-P | 0.1–1.0 | 0.95 | Nucleus sampling |

### Knowledge Base (Bundled)
Six subjects in `assets/knowledge/`:
- `anatomy.md`
- `physiology.md`
- `pharmacology.md`
- `pathology.md`
- `biochemistry.md`
- `microbiology.md`

Add/edit markdown files → rebuild app → auto-indexed on first launch.

### Colors (`lib/core/theme/app_theme.dart`)
```dart
static const sage = Color(0xFF8D9771);        // Primary (logo match)
static const sageDark = Color(0xFF6B7A55);
static const sagePale = Color(0xFFE8ECE3);
static const cream = Color(0xFFFDFBF5);       // Surface
static const coffee = Color(0xFF3D342C);      // Text primary
```

---

## 🧪 Testing

```bash
# Unit/widget tests
flutter test

# Integration test (requires device)
flutter test integration_test/
```

### Manual Test Checklist
- [ ] Model loads and generates
- [ ] Web search returns PubMed/Wiki/DDG results
- [ ] Document import extracts text (PDF, DOCX, TXT)
- [ ] Document attachment filters RAG to selected docs
- [ ] Image OCR extracts text (camera + gallery)
- [ ] Dark/light theme toggle persists
- [ ] Conversation history saves/restores
- [ ] Model change works without restart

---

## 📦 Dependencies

| Package | Purpose | Version |
|---------|---------|---------|
| `flutter_riverpod` | State management | ^2.5.1 |
| `hive` + `hive_flutter` | Local NoSQL storage | ^2.2.3 |
| `llama_flutter_android` | llama.cpp bindings | ^1.0.0 |
| `syncfusion_flutter_pdf` | PDF text extraction | ^33.2.13 |
| `archive` | DOCX (ZIP) parsing | ^4.0.4 |
| `google_mlkit_text_recognition` | On-device OCR | ^0.16.0 |
| `image_picker` | Camera/gallery | ^1.1.2 |
| `flutter_svg` | SVG logo rendering | ^2.0.10 |
| `url_launcher` | Open citation URLs | ^6.2.5 |
| `file_picker` | Document selection | ^8.1.2 |
| `uuid` | Unique IDs | ^4.4.0 |
| `intl` | Date formatting | ^0.19.0 |

---

## 🔐 Privacy & Security

- **No network calls** unless you enable web search or check for model updates
- **No accounts, no telemetry, no analytics**
- **Model weights** stored in app-private directory
- **Documents** copied to app-private storage, indexed locally
- **Conversations** encrypted at rest via Hive (AES-256 optional)
- **OCR** runs entirely on-device (bundled ML Kit model)

---

## 🐛 Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| "Model not found" | GGUF not in expected location | Settings → Model → pick file |
| "Could not load model" | Insufficient RAM / wrong arch | Use smaller quant (Q3/Q4), close apps |
| Web search returns 0 results | Network / API changes | Check logs (`[WebSearch]`), retry |
| Document shows "no readable text" | Scanned PDF / encrypted | OCR the PDF first, or use text-based PDF |
| OCR fails | Image too blurry / no text | Retake photo, ensure good lighting |
| Theme not applying | System theme override | Settings → Theme → explicit Light/Dark |

### Debug Logs
Run with verbose logging:
```bash
flutter run --verbose 2>&1 | grep -E "\[KnowledgeService\]|\[WebSearch\]|\[DocumentService\]"
```

Key log prefixes:
- `[KnowledgeService]` — RAG indexing, retrieval, context building
- `[WebSearch]` — PubMed/Wiki/DDG queries, status codes, result counts
- `[DocumentService]` — Import, extraction, reindex progress
- `[ChatController]` — Search intercept, generation flow

---

## 🗺️ Roadmap

- [ ] **Cross-platform**: iOS, Desktop (Windows/macOS/Linux)
- [ ] **Model quantization UI**: Download/convert models in-app
- [ ] **Citation export**: Copy conversation with references
- [ ] **Voice input**: STT for hands-free queries
- [ ] **Anki export**: Generate flashcards from answers
- [ ] **Multi-modal**: Image understanding (when local VLMs mature)
- [ ] **Plugin system**: Custom knowledge packs

---

## 🤝 Contributing

1. Fork → create feature branch
2. Follow existing code style (run `flutter analyze`)
3. Add tests for new functionality
4. Update README if user-facing changes
5. Open PR with clear description

### Code Style
- `flutter analyze` — must pass
- `dart format .` — before commit
- Conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`)

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

> **Medical Disclaimer**: AcornMed is an educational tool. It is **not a substitute for professional medical advice, diagnosis, or treatment**. Always consult qualified clinicians for patient care decisions.

---

## 🙏 Acknowledgments

- **llama.cpp** by Georgi Gerganov — making local LLMs practical
- **Google ML Kit** — on-device OCR without cloud
- **Syncfusion** — PDF text extraction (free community license)
- **NCBI / Wikipedia / DuckDuckGo** — free public APIs
- **Flutter team** — excellent framework
- **Medical students** who tested early builds and gave feedback

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/SparshMishra09/AcornMed/issues)
- **Discussions**: [GitHub Discussions](https://github.com/SparshMishra09/AcornMed/discussions)
- **Email**: sparsh.mishra09@example.com (replace with real)

---

<p align="center">
  Made with ❤️ for medical students everywhere.<br>
  <sub>Stay curious. Stay offline. Stay accurate.</sub>
</p>