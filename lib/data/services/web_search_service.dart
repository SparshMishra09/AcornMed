import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

void _debugLog(String message) {
  if (kDebugMode) {
    print('[WebSearch] $message');
  }
}

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.snippet,
    required this.url,
    required this.source,
    this.date,
  });

  final String title;
  final String snippet;
  final String url;
  final String source;
  final String? date;
}

class WebSearchService {
  WebSearchService._();
  static final WebSearchService instance = WebSearchService._();

  static const Duration _timeout = Duration(seconds: 12);

  Future<List<WebSearchResult>> search(String query, {int maxPerSource = 4}) async {
    _debugLog('Searching for: "$query"');
    final results = await Future.wait([
      _safe(() => _searchPubMed(query, maxPerSource)),
      _safe(() => _searchWikipedia(query, maxPerSource)),
      _safe(() => _searchDuckDuckGo(query, maxPerSource)),
    ]);

    final merged = <WebSearchResult>[];
    final seenUrls = <String>{};
    for (final list in results) {
      for (final r in list) {
        if (seenUrls.add(r.url)) {
          merged.add(r);
        }
      }
    }
    _debugLog('Total results: ${merged.length} (PubMed: ${results[0].length}, Wiki: ${results[1].length}, DDG: ${results[2].length})');
    return merged;
  }

  Future<List<WebSearchResult>> _safe(
    Future<List<WebSearchResult>> Function() fn,
  ) async {
    try {
      return await fn().timeout(_timeout);
    } catch (e) {
      _debugLog('Search error: $e');
      return const [];
    }
  }

  Future<List<WebSearchResult>> _searchPubMed(String query, int max) async {
    _debugLog('PubMed: querying...');
    final encoded = Uri.encodeComponent(query);
    final searchUri = Uri.parse(
      'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi'
      '?db=pubmed&term=$encoded&retmax=$max&retmode=json&sort=date',
    );
    final searchResp = await http.get(searchUri);
    _debugLog('PubMed: search status ${searchResp.statusCode}');
    if (searchResp.statusCode != 200) return const [];
    final searchJson = jsonDecode(searchResp.body) as Map<String, dynamic>;
    final ids = ((searchJson['esearchresult']?['idlist'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (ids.isEmpty) {
      _debugLog('PubMed: no IDs found');
      return const [];
    }
    _debugLog('PubMed: found ${ids.length} IDs');

    final summaryUri = Uri.parse(
      'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi'
      '?db=pubmed&id=${ids.join(',')}&retmode=json',
    );
    final summaryResp = await http.get(summaryUri);
    _debugLog('PubMed: summary status ${summaryResp.statusCode}');
    if (summaryResp.statusCode != 200) return const [];
    final summaryJson = jsonDecode(summaryResp.body) as Map<String, dynamic>;
    final result = summaryJson['result'] as Map<String, dynamic>?;
    if (result == null) {
      _debugLog('PubMed: no result map');
      return const [];
    }

    final out = <WebSearchResult>[];
    for (final id in ids) {
      final item = result[id] as Map<String, dynamic>?;
      if (item == null) continue;
      final title = (item['title'] as String?) ?? '';
      final pubDate = item['pubdate'] as String?;
      final source = item['fulljournalname'] as String? ?? item['source'] as String?;
      final snippetParts = <String>[];
      if (source != null && source.isNotEmpty) snippetParts.add(source);
      if (pubDate != null && pubDate.isNotEmpty) snippetParts.add(pubDate);
      final authors = item['authors'] as List?;
      if (authors != null && authors.isNotEmpty) {
        final first = (authors.first as Map<String, dynamic>?)?['name'] as String?;
        if (first != null) snippetParts.add('$first et al.');
      }
      out.add(WebSearchResult(
        title: title,
        snippet: snippetParts.join(' \u00b7 '),
        url: 'https://pubmed.ncbi.nlm.nih.gov/$id/',
        source: 'PubMed',
        date: pubDate,
      ));
    }
    _debugLog('PubMed: returning ${out.length} results');
    return out;
  }

  Future<List<WebSearchResult>> _searchWikipedia(String query, int max) async {
    _debugLog('Wikipedia: querying...');
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://en.wikipedia.org/w/api.php?action=query&list=search'
      '&srsearch=$encoded&format=json&srlimit=$max&srprop=snippet|timestamp',
    );
    final resp = await http.get(uri);
    _debugLog('Wikipedia: status ${resp.statusCode}');
    if (resp.statusCode != 200) return const [];
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final hits = (json['query']?['search'] as List?) ?? [];
    _debugLog('Wikipedia: found ${hits.length} hits');
    final out = <WebSearchResult>[];
    for (final hit in hits) {
      final map = hit as Map<String, dynamic>;
      final title = (map['title'] as String?) ?? '';
      var snippet = (map['snippet'] as String?) ?? '';
      snippet = snippet
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('"', '"')
          .replaceAll('&', '&')
          .replaceAll('&#039;', "'")
          .trim();
      final timestamp = map['timestamp'] as String?;
      out.add(WebSearchResult(
        title: title,
        snippet: snippet,
        url: 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
        source: 'Wikipedia',
        date: timestamp?.substring(0, 10),
      ));
    }
    _debugLog('Wikipedia: returning ${out.length} results');
    return out;
  }

  Future<List<WebSearchResult>> _searchDuckDuckGo(String query, int max) async {
    _debugLog('DuckDuckGo: querying...');
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse('https://html.duckduckgo.com/html/?q=$encoded');
    final resp = await http.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    });
    _debugLog('DuckDuckGo: status ${resp.statusCode}');
    if (resp.statusCode != 200) return const [];
    final html = resp.body;
    _debugLog('DuckDuckGo: HTML length ${html.length}');

    final out = <WebSearchResult>[];
    final resultPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    for (final match in resultPattern.allMatches(html)) {
      if (out.length >= max) break;
      var url = match.group(1) ?? '';
      final title = _stripHtml(match.group(2) ?? '');
      final snippet = _stripHtml(match.group(3) ?? '');
      if (url.contains('uddg=')) {
        final uddg = Uri.splitQueryString(url.split('?').last)['uddg'];
        if (uddg != null) url = uddg;
      }
      if (url.isEmpty || title.isEmpty) continue;
      out.add(WebSearchResult(
        title: title,
        snippet: snippet,
        url: url,
        source: 'Web',
      ));
    }
    _debugLog('DuckDuckGo: returning ${out.length} results');
    return out;
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('"', '"')
        .replaceAll('&', '&')
        .replaceAll('\u2019', "'")
        .replaceAll('&#039;', "'")
        .replaceAll('<', '<')
        .replaceAll('>', '>')
        .trim();
  }

  String buildContext(List<WebSearchResult> results, {int maxChars = 3500}) {
    if (results.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln(
      'Live web search results (retrieved just now). Prefer the most recent '
      'and authoritative sources. Cite them by number in your answer.',
    );
    var index = 1;
    var length = sb.length;
    for (final r in results) {
      final entry = StringBuffer();
      entry.writeln('[$index] ${r.title} (${r.source}${r.date != null ? ', ${r.date}' : ''})');
      if (r.snippet.isNotEmpty) entry.writeln(r.snippet);
      entry.writeln('URL: ${r.url}');
      entry.writeln();
      if (length + entry.length > maxChars) break;
      sb.write(entry);
      length += entry.length;
      index++;
    }
    return sb.toString();
  }
}