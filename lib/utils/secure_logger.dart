import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Secure logger that sanitizes sensitive data before logging
class SecureLogger {
  static final SecureLogger _instance = SecureLogger._internal();
  factory SecureLogger() => _instance;
  SecureLogger._internal();

  late final Logger _logger;
  
  /// Initialize the logger with production-safe settings
  void initialize() {
    _logger = Logger(
      level: kDebugMode ? Level.debug : Level.error, // Only errors in production
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: kDebugMode ? 5 : 0, // No stack traces in production
        lineLength: 80,
        colors: false, // No colors in production logs
        printEmojis: false, // No emojis in production logs
        printTime: true, // Always include timestamps
      ),
    );
  }

  /// Debug level - only in debug mode
  void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _logger.d(_sanitize(message), error: error, stackTrace: stackTrace);
    }
  }

  /// Info level
  void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(_sanitize(message), error: error, stackTrace: stackTrace);
  }

  /// Warning level
  void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(_sanitize(message), error: error, stackTrace: stackTrace);
  }

  /// Error level
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(_sanitize(message), error: error, stackTrace: stackTrace);
  }

  /// Critical/Fatal level
  void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(_sanitize(message), error: error, stackTrace: stackTrace);
  }

  /// Sanitize sensitive data from log messages
  String _sanitize(String message) {
    String sanitized = message;
    
    // Sanitize connection/family codes (4-digit numbers)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b\d{4}\b'), 
      (match) => '****'
    );
    
    // Sanitize user IDs (Firebase format: alphanumeric strings)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b[a-zA-Z0-9]{20,}\b'), 
      (match) => '***[${match.group(0)?.substring(0, 4)}...]'
    );
    
    // Sanitize email addresses
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'), 
      (match) {
        final email = match.group(0)!;
        final parts = email.split('@');
        return '${parts[0].substring(0, 2)}***@${parts[1]}';
      }
    );
    
    // Sanitize FCM tokens (long alphanumeric strings)
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\bfcm[_-]?token[:\s=]*[a-zA-Z0-9:_-]{50,}\b', caseSensitive: false),
      (match) => 'fcm_token: ***[REDACTED]'
    );
    
    // Sanitize device IDs
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\bdevice[_\s]?id[:\s=]*[a-zA-Z0-9\-]{10,}\b', caseSensitive: false),
      (match) => 'device_id: ***[REDACTED]'
    );
    
    // Sanitize family IDs
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\bfamily[_\s]?[a-fA-F0-9\-]{20,}\b', caseSensitive: false),
      (match) => 'family_***[REDACTED]'
    );
    
    return sanitized;
  }

  /// Log operation start
  void operationStart(String operation) {
    debug('🚀 Starting: $operation');
  }

  /// Log operation success
  void operationSuccess(String operation) {
    debug('✅ Success: $operation');
  }

  /// Log operation failure
  void operationFailure(String operation, dynamic error) {
    warning('❌ Failed: $operation', error);
  }

  /// Log security event
  void security(String event) {
    warning('🔒 Security: $event');
  }

  /// Log user action
  void userAction(String action) {
    info('👤 User: $action');
  }

  /// Log connection status
  void connection(String status) {
    info('📡 Connection: $status');
  }
}

/// Global logger instance
final secureLog = SecureLogger();