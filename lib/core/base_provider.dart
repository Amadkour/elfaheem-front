/// ─────────────────────────────────────────────────────────────────────────────
/// base_provider.dart
/// Shared state machine for all API providers.
///
/// Every feature provider extends [BaseProvider] and calls:
///   • [run(fn)]     — executes fn, handles error state automatically
///   • [setError(e)] — surface an [ApiException] to the UI
///   • [reset()]     — clear error state
///
/// v3.2.0 — retry responsibility split:
///   • Connection-level retries (ngrok drops, socket resets, timeouts) are now
///     handled inside ApiClient._send() at the transport layer — 3 attempts
///     with 1 s / 2 s delays — completely transparent to BaseProvider.
///   • BaseProvider._maxAttempts is therefore reduced to 2: one real attempt
///     (which itself retries internally) plus one outer safety-net retry for
///     anything the transport layer could not recover from.
///   • _baseDelay is reduced to 500 ms — the transport layer already waited
///     up to 3 s total; a long extra pause here would just frustrate the user.
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api_client.dart';

/// Possible states for any async API operation.
enum ProviderState { idle, loading, success, error }

abstract class BaseProvider extends ChangeNotifier {
  // ── State fields ───────────────────────────────────────────────────────────
  ProviderState _state       = ProviderState.idle;
  String?       _errorMessage;

  ProviderState get state        => _state;
  String?       get errorMessage => _errorMessage;

  bool get isLoading => _state == ProviderState.loading;
  bool get hasError  => _state == ProviderState.error;
  bool get isSuccess => _state == ProviderState.success;
  void makeLoading(){
    _state=ProviderState.loading;
    notifyListeners();
  } void stopLoading(){
    _state=ProviderState.success;
    notifyListeners();
  }

  // ── Retry config ───────────────────────────────────────────────────────────

  /// 2 = one attempt (which retries internally in _send) + one safety-net retry.
  static const int _maxAttempts = 2;

  /// Short delay — the transport layer already handled the slow retries.
  static const Duration _baseDelay = Duration(milliseconds: 500);

  // ── Core runner ────────────────────────────────────────────────────────────

  Future<T?> run<T>(Future<T> Function() fn) async {
    _setProviderState(ProviderState.loading);

    int attempt = 0;

    while (attempt < _maxAttempts) {
      attempt++;
      try {
        final result = await fn();
        _setProviderState(ProviderState.success);
        return result;

      } on ApiException catch (e) {
        // Server responded with a proper HTTP error — do NOT retry.
        _errorMessage = e.message;
        debugPrint('⛔ ApiException (attempt $attempt): ${e.message}');
        _setProviderState(ProviderState.error);
        return null;

      } on SocketException catch (e) {
        debugPrint('🔌 SocketException (attempt $attempt): ${e.message}');
        if (attempt >= _maxAttempts) {
          _errorMessage = 'لا يمكن الاتصال بالخادم. تحقق من الإنترنت.';
          _setProviderState(ProviderState.error);
          return null;
        }

      } on HttpException catch (e) {
        debugPrint('🌐 HttpException (attempt $attempt): ${e.message}');
        if (attempt >= _maxAttempts) {
          _errorMessage = 'انقطع الاتصال بالخادم. حاول مجدداً.';
          _setProviderState(ProviderState.error);
          return null;
        }

      } on TimeoutException catch (e) {
        debugPrint('⏱ TimeoutException (attempt $attempt): $e');
        if (attempt >= _maxAttempts) {
          _errorMessage = 'انتهت مهلة الطلب. حاول مجدداً.';
          _setProviderState(ProviderState.error);
          return null;
        }

      } catch (e) {
        final msg             = e.toString();
        final isConnectionDrop = _isTransientError(msg);

        debugPrint('⚠️ ${isConnectionDrop ? "Transient" : "Unknown"} error '
            '(attempt $attempt): $msg');

        if (!isConnectionDrop || attempt >= _maxAttempts) {
          _errorMessage = isConnectionDrop
              ? 'انقطع الاتصال. يُعاد المحاولة…'
              : msg;
          _setProviderState(ProviderState.error);
          return null;
        }
      }

      // Brief pause before the outer safety-net retry.
      debugPrint('🔄 Outer retry (attempt ${attempt + 1}/$_maxAttempts) '
          'in ${_baseDelay.inMilliseconds}ms…');
      await Future.delayed(_baseDelay);
    }

    _setProviderState(ProviderState.error);
    return null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static bool _isTransientError(String message) {
    const patterns = [
      'connection closed before full header',
      'connection reset',
      'connection refused',
      'broken pipe',
      'software caused connection abort',
      'failed host lookup',
      'network is unreachable',
      'clientexception',
      'handshake error',
      'connection timed out',
      'http connection closed',
      'remote host closed',
    ];
    final lower = message.toLowerCase();
    return patterns.any(lower.contains);
  }

  void setError(String message) {
    _errorMessage = message;
    _setProviderState(ProviderState.error);
  }

  void reset() {
    _errorMessage = null;
    _setProviderState(ProviderState.idle);
  }

  void _setProviderState(ProviderState s) {
    _state = s;
    notifyListeners();
  }
}