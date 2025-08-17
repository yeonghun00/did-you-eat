import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Simple session manager to maintain family connection across app restarts
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  SharedPreferences? _prefs;
  String? _currentFamilyCode;
  Map<String, dynamic>? _cachedFamilyData;
  
  static const String _familyCodeKey = 'current_family_code';
  static const String _familyDataKey = 'cached_family_data';
  static const String _sessionTimestampKey = 'session_timestamp';

  /// Initialize session manager
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      print('✅ SessionManager initialized');
    } catch (e) {
      print('❌ Failed to initialize SessionManager: $e');
    }
  }

  /// Start a new session with family code and data
  Future<void> startSession(String familyCode, Map<String, dynamic>? familyData) async {
    try {
      _currentFamilyCode = familyCode;
      _cachedFamilyData = familyData;
      
      await _prefs?.setString(_familyCodeKey, familyCode);
      if (familyData != null) {
        await _prefs?.setString(_familyDataKey, jsonEncode(familyData));
      }
      await _prefs?.setInt(_sessionTimestampKey, DateTime.now().millisecondsSinceEpoch);
      
      print('✅ Session started with family code: $familyCode');
    } catch (e) {
      print('❌ Failed to start session: $e');
    }
  }

  /// Restore session from storage
  Future<bool> restoreSession() async {
    try {
      _currentFamilyCode = _prefs?.getString(_familyCodeKey);
      
      if (_currentFamilyCode != null) {
        final familyDataJson = _prefs?.getString(_familyDataKey);
        if (familyDataJson != null) {
          _cachedFamilyData = jsonDecode(familyDataJson) as Map<String, dynamic>;
        }
        
        print('✅ Session restored with family code: $_currentFamilyCode');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Failed to restore session: $e');
      return false;
    }
  }

  /// Clear current session
  Future<void> clearSession() async {
    try {
      _currentFamilyCode = null;
      _cachedFamilyData = null;
      
      await _prefs?.remove(_familyCodeKey);
      await _prefs?.remove(_familyDataKey);
      await _prefs?.remove(_sessionTimestampKey);
      
      print('✅ Session cleared');
    } catch (e) {
      print('❌ Failed to clear session: $e');
    }
  }

  /// Check if session is valid
  bool get hasValidSession {
    return _currentFamilyCode != null && _currentFamilyCode!.isNotEmpty;
  }

  /// Get current family code
  String? get currentFamilyCode => _currentFamilyCode;

  /// Get cached family data
  Map<String, dynamic>? get cachedFamilyData => _cachedFamilyData;

  /// Get session timestamp
  DateTime? get sessionTimestamp {
    final timestamp = _prefs?.getInt(_sessionTimestampKey);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }
}