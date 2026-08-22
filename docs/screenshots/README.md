# Screenshots Directory

Place your app screenshots here with these filenames:

| Filename | Description |
|----------|-------------|
| `chat_light.png` | Chat screen in light mode |
| `chat_dark.png` | Chat screen in dark mode |
| `docs_screen.png` | Documents library screen |
| `attach_docs.png` | Attach documents bottom sheet |
| `web_search.png` | Web search results with citations |
| `ocr_flow.png` | Image OCR preview flow |

## Recommended Specs
- **Device**: Phone (not tablet) for standard aspect ratio
- **Resolution**: 1080×1920 or similar
- **Format**: PNG (lossless)
- **Frame**: Optional device frame for polish

## Quick Capture (Android)
```bash
# Connect device via USB
adb shell screencap -p /sdcard/screenshot.png
adb pull /sdcard/screenshot.png docs/screenshots/chat_light.png
```

Or use Android Studio's **Device File Explorer** or **Screenshot** button in Logcat.