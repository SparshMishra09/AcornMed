import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Maps low-level exceptions to short, human, actionable messages.
///
/// Rule of thumb across the app: never show raw exception text (stack
/// traces, URLs, class names) and never fail silently — always show one
/// friendly line telling the user what happened and what to do next.
String friendlyError(Object error) {
  // FormatExceptions thrown by our services already carry curated,
  // user-facing messages (e.g. "No readable text found in this document…").
  if (error is FormatException && error.message.isNotEmpty) {
    return error.message;
  }

  final s = error.toString().toLowerCase();

  final networkish = s.contains('socket') ||
      s.contains('connection closed') ||
      s.contains('connection refused') ||
      s.contains('connection terminated') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('software caused connection') ||
      s.contains('clientexception');
  if (networkish) {
    return 'You seem to be offline or the connection dropped. '
        'Check your internet and try again.';
  }
  if (s.contains('timeout')) {
    return 'That took too long. Check your connection and try again.';
  }
  if (s.contains('out of memory') || s.contains('oom')) {
    return 'The device ran out of memory. Close other apps, or try the '
        'smaller model.';
  }
  if (s.contains('no space left') || s.contains('disk full') || s.contains('enospc')) {
    return 'Your device is out of storage. Free up some space and try again.';
  }
  if (s.contains('permission')) {
    return 'The app doesn\'t have permission to do that. '
        'Check the app settings.';
  }

  if (kDebugMode) {
    debugPrint('[FriendlyError] Unmapped error: $error');
  }
  return 'Something went wrong. Please try again.';
}
