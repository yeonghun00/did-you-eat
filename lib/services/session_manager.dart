import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/secure_logger.dart';

/// Session manager to maintain family connection and membership status across app restarts
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  SharedPreferences? _prefs;
  String? _currentFamilyCode;
  Map<String, dynamic>? _cachedFamilyData;
  bool _isUserInMemberIds = false;
  String? _cachedUserId;
  
  static const String _familyCodeKey = 'current_family_code';
  static const String _familyDataKey = 'cached_family_data';
  static const String _sessionTimestampKey = 'session_timestamp';
  static const String _userMembershipKey = 'user_membership_status';
  static const String _cachedUserIdKey = 'cached_user_id';

  /// Initialize session manager
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      secureLog.info('SessionManager initialized');
    } catch (e) {
      secureLog.error('Failed to initialize SessionManager', e);
    }
  }

  /// Start a new session with family code and data
  /// Now caches membership status for security validation
  Future<void> startSession(String familyCode, Map<String, dynamic>? familyData) async {
    try {
      _currentFamilyCode = familyCode;
      _cachedFamilyData = familyData;
      
      // Cache membership status
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && familyData != null) {
        final memberIds = List<String>.from(familyData['memberIds'] ?? []);
        _isUserInMemberIds = memberIds.contains(currentUser.uid);
        _cachedUserId = currentUser.uid;
        
        await _prefs?.setBool(_userMembershipKey, _isUserInMemberIds);
        await _prefs?.setString(_cachedUserIdKey, currentUser.uid);
        
        secureLog.security('User membership status cached: $_isUserInMemberIds');
      }
      
      await _prefs?.setString(_familyCodeKey, familyCode);
      if (familyData != null) {
        await _prefs?.setString(_familyDataKey, jsonEncode(familyData));
      }
      await _prefs?.setInt(_sessionTimestampKey, DateTime.now().millisecondsSinceEpoch);
      
      secureLog.security('Session started with family connection and membership validation');
    } catch (e) {
      secureLog.error('Failed to start session', e);
    }
  }

  /// Restore session from storage
  /// Now restores membership status for security validation
  Future<bool> restoreSession() async {
    try {
      _currentFamilyCode = _prefs?.getString(_familyCodeKey);
      
      if (_currentFamilyCode != null) {
        final familyDataJson = _prefs?.getString(_familyDataKey);
        if (familyDataJson != null) {
          _cachedFamilyData = jsonDecode(familyDataJson) as Map<String, dynamic>;
        }
        
        // Restore membership status
        _isUserInMemberIds = _prefs?.getBool(_userMembershipKey) ?? false;
        _cachedUserId = _prefs?.getString(_cachedUserIdKey);
        
        // Validate cached user matches current user
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && _cachedUserId != currentUser.uid) {
          secureLog.warning('Cached user ID does not match current user - clearing membership status');
          _isUserInMemberIds = false;
          _cachedUserId = currentUser.uid;
        }
        
        secureLog.security('Session restored with family connection and membership status: $_isUserInMemberIds');
        return true;
      }
      
      return false;
    } catch (e) {
      secureLog.error('Failed to restore session', e);
      return false;
    }
  }

  /// Save session with family data
  /// Now saves membership status for security validation
  Future<void> saveSession(String familyCode, Map<String, dynamic> familyData) async {
    try {
      _currentFamilyCode = familyCode;
      _cachedFamilyData = familyData;
      
      // Save membership status
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final memberIds = List<String>.from(familyData['memberIds'] ?? []);
        _isUserInMemberIds = memberIds.contains(currentUser.uid);
        _cachedUserId = currentUser.uid;
        
        await _prefs?.setBool(_userMembershipKey, _isUserInMemberIds);
        await _prefs?.setString(_cachedUserIdKey, currentUser.uid);
        
        secureLog.security('User membership status saved: $_isUserInMemberIds');
      }
      
      await _prefs?.setString(_familyCodeKey, familyCode);
      await _prefs?.setString(_familyDataKey, jsonEncode(familyData));
      await _prefs?.setInt(_sessionTimestampKey, DateTime.now().millisecondsSinceEpoch);
      
      secureLog.info('Session saved successfully for family code with membership validation');
    } catch (e) {
      secureLog.error('Failed to save session', e);
    }
  }

  /// Clear current session
  /// Now clears membership status as well
  Future<void> clearSession() async {
    try {
      _currentFamilyCode = null;
      _cachedFamilyData = null;
      _isUserInMemberIds = false;
      _cachedUserId = null;
      
      await _prefs?.remove(_familyCodeKey);
      await _prefs?.remove(_familyDataKey);
      await _prefs?.remove(_sessionTimestampKey);
      await _prefs?.remove(_userMembershipKey);
      await _prefs?.remove(_cachedUserIdKey);
      
      secureLog.info('Session and membership status cleared');
    } catch (e) {
      secureLog.error('Failed to clear session', e);
    }
  }

  /// Check if session is valid
  bool get hasValidSession {
    return _currentFamilyCode != null && _currentFamilyCode!.isNotEmpty;
  }
  
  /// Check if session is valid with membership validation
  bool get hasValidMembership {
    return hasValidSession && _isUserInMemberIds;
  }

  /// Get current family code
  String? get currentFamilyCode => _currentFamilyCode;

  /// Get cached family data
  Map<String, dynamic>? get cachedFamilyData => _cachedFamilyData;
  
  /// Get user membership status
  bool get isUserInMemberIds => _isUserInMemberIds;
  
  /// Get cached user ID
  String? get cachedUserId => _cachedUserId;
  
  /// Update membership status (for real-time updates)
  Future<void> updateMembershipStatus(bool isInMemberIds) async {
    try {
      _isUserInMemberIds = isInMemberIds;
      await _prefs?.setBool(_userMembershipKey, isInMemberIds);
      secureLog.security('Membership status updated: $isInMemberIds');
    } catch (e) {
      secureLog.error('Failed to update membership status', e);
    }
  }

  /// Get session timestamp
  DateTime? get sessionTimestamp {
    final timestamp = _prefs?.getInt(_sessionTimestampKey);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }
}