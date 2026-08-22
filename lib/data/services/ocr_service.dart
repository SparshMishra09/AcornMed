import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get _instance {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  Future<String> recognizeText(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw FileSystemException('Image file not found', imagePath);
    }
    final input = InputImage.fromFilePath(imagePath);
    final result = await _instance.processImage(input);
    return result.text.trim();
  }
}
