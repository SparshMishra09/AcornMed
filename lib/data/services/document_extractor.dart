import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ExtractedDocument {
  const ExtractedDocument({
    required this.text,
    this.pageCount,
  });

  final String text;
  final int? pageCount;
}

class DocumentExtractor {
  DocumentExtractor._();
  static final DocumentExtractor instance = DocumentExtractor._();

  static const Set<String> supportedExtensions = {
    'pdf',
    'docx',
    'txt',
    'md',
    'markdown',
  };

  bool isSupported(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1) return false;
    return supportedExtensions.contains(
      fileName.substring(dot + 1).toLowerCase(),
    );
  }

  Future<ExtractedDocument> extract(File file) async {
    final name = file.uri.pathSegments.last.toLowerCase();
    if (name.endsWith('.pdf')) {
      return _extractPdf(file);
    }
    if (name.endsWith('.docx')) {
      return _extractDocx(file);
    }
    final text = await file.readAsString();
    return ExtractedDocument(text: _clean(text));
  }

  Future<ExtractedDocument> _extractPdf(File file) async {
    final document = PdfDocument(inputBytes: await file.readAsBytes());
    final extractor = PdfTextExtractor(document);
    final pages = extractor.extractTextLines();
    final sb = StringBuffer();
    for (final line in pages) {
      sb.writeln(line.text);
    }
    final pageCount = document.pages.count;
    document.dispose();
    return ExtractedDocument(text: _clean(sb.toString()), pageCount: pageCount);
  }

  Future<ExtractedDocument> _extractDocx(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? documentXml;
    for (final entry in archive.files) {
      if (entry.name == 'word/document.xml') {
        documentXml = entry;
        break;
      }
    }
    if (documentXml == null) {
      throw const FormatException('Not a valid .docx file');
    }
    final xml = utf8.decode(documentXml.content as List<int>);

    final sb = StringBuffer();
    final paragraphPattern = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
    final textPattern = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
    for (final para in paragraphPattern.allMatches(xml)) {
      final paraXml = para.group(0)!;
      final texts = <String>[];
      for (final t in textPattern.allMatches(paraXml)) {
        texts.add(_decodeXmlEntities(t.group(1) ?? ''));
      }
      if (texts.isNotEmpty) {
        sb.writeln(texts.join());
      }
    }
    return ExtractedDocument(text: _clean(sb.toString()));
  }

  String _decodeXmlEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  String _clean(String text) {
    return text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
