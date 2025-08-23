import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/family_record.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // CRITICAL: Family ID resolution cache
  static final Map<String, String> _familyIdCache = {};

  /// Resolve familyId from connectionCode (CRITICAL for child app)
  static Future<String?> getFamilyIdFromConnectionCode(String connectionCode) async {
    try {
      print('🔍 Resolving familyId for connectionCode: $connectionCode');
      
      // Check cache first
      if (_familyIdCache.containsKey(connectionCode)) {
        print('✅ Found cached familyId: ${_familyIdCache[connectionCode]}');
        return _familyIdCache[connectionCode];
      }

      // Query families collection to find matching connectionCode
      print('📡 Querying families collection...');
      final querySnapshot = await _firestore
          .collection('families')
          .where('connectionCode', isEqualTo: connectionCode)
          .limit(1) // Remove isActive filter - let child app see all families
          .get();

      print('📊 Query result: ${querySnapshot.docs.length} documents found');

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final familyId = doc.id;
        final data = doc.data();
        
        print('✅ Family document found:');
        print('   - Family ID: $familyId');
        print('   - Connection Code: ${data['connectionCode']}');
        print('   - Is Active: ${data['isActive']}');
        print('   - Approved: ${data['approved']}');
        
        // Cache the result
        _familyIdCache[connectionCode] = familyId;
        
        print('✅ Cached familyId $familyId for connectionCode $connectionCode');
        return familyId;
      }
      
      print('❌ No family found for connectionCode: $connectionCode');
      
      // Debug: Check what families exist
      try {
        final allFamilies = await _firestore.collection('families').limit(3).get();
        print('🔍 Debug: Total families in collection: ${allFamilies.docs.length}');
        for (final family in allFamilies.docs) {
          final familyData = family.data();
          print('   - Family ${family.id}: code=${familyData['connectionCode']}, active=${familyData['isActive']}');
        }
      } catch (e) {
        print('❌ Debug query failed: $e');
      }
      
      return null;
    } catch (e) {
      print('❌ Error resolving family ID: $e');
      return null;
    }
  }

  /// Get complete family data for child app
  static Future<Map<String, dynamic>?> getFamilyDataForChild(String connectionCode) async {
    try {
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) return null;

      final doc = await _firestore.collection('families').doc(familyId).get();
      if (doc.exists) {
        final data = doc.data()!;
        // Add familyId to the data for child app use
        data['familyId'] = familyId;
        return data;
      }
      return null;
    } catch (e) {
      print('Error getting family data: $e');
      return null;
    }
  }

  // 가족 코드 검증 및 정보 가져오기 (UPDATED for new structure)
  static Future<FamilyInfo?> validateFamilyCode(String connectionCode) async {
    try {
      print('🔍 Attempting to validate connection code: $connectionCode');
      
      // Ensure authentication (anonymous is fine for reading)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('🔄 No current user, signing in anonymously...');
        try {
          final userCredential = await FirebaseAuth.instance.signInAnonymously();
          print('✅ Anonymous auth successful: ${userCredential.user?.uid}');
        } catch (e) {
          print('❌ Anonymous auth failed: $e');
          return null;
        }
      } else {
        print('✅ User already authenticated: ${currentUser.uid} (anonymous: ${currentUser.isAnonymous})');
      }
      
      // Use new family data resolution
      final familyData = await getFamilyDataForChild(connectionCode);
      if (familyData == null) {
        print('❌ No family found for connection code: $connectionCode');
        return null;
      }
      
      print('✅ Family data loaded successfully');
      print('📊 Family data keys: ${familyData.keys.toList()}');
      
      // Check if approved (if null, it's still pending)
      final approved = familyData['approved'] as bool?;
      print('📋 Approval status: $approved');
      
      // Only return family info if approved or still pending
      if (approved != false) {
        final familyInfo = FamilyInfo.fromMap({
          'familyCode': connectionCode,
          ...familyData,
        });
        print('✅ Family info created successfully');
        return familyInfo;
      } else {
        print('❌ Family connection was rejected');
        return null;
      }
    } catch (e) {
      print('❌ Error validating family code: $e');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  // 오늘 식사 기록 가져오기 (UPDATED for new structure)
  static Future<List<MealRecord>> getTodayMeals(String connectionCode) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      print('Getting today meals for connection code: $connectionCode, date: $today');
      
      // Resolve familyId from connectionCode
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) {
        print('Could not resolve family ID for connection code: $connectionCode');
        return [];
      }
      
      final doc = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('meals')
          .doc(today)
          .get();

      print('Today meals document exists: ${doc.exists}');
      
      if (doc.exists) {
        final data = doc.data()!;
        print('Today meals data: $data');
        final meals = data['meals'] as List<dynamic>? ?? [];
        print('Number of meals found: ${meals.length}');
        
        return meals
            .map((meal) => MealRecord.fromMap(meal as Map<String, dynamic>))
            .toList();
      }
      print('No meals found for today');
      return [];
    } catch (e) {
      print('Error getting today meals: $e');
      print('Error type: ${e.runtimeType}');
      return [];
    }
  }

  // 날짜 범위별 식사 기록 가져오기 (UPDATED for new structure)
  static Future<Map<String, List<MealRecord>>> getMealsInRange(
    String connectionCode,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final Map<String, List<MealRecord>> mealsByDate = {};
      
      DateTime currentDate = startDate;
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        final dateString = DateFormat('yyyy-MM-dd').format(currentDate);
        final meals = await getMealsForDate(connectionCode, dateString);
        if (meals.isNotEmpty) {
          mealsByDate[dateString] = meals;
        }
        currentDate = currentDate.add(const Duration(days: 1));
      }
      
      return mealsByDate;
    } catch (e) {
      print('Error getting meals in range: $e');
      return {};
    }
  }

  // 특정 날짜 식사 기록 가져오기 (UPDATED for new structure)
  static Future<List<MealRecord>> getMealsForDate(
    String connectionCode,
    String date,
  ) async {
    try {
      print('Getting meals for date: $connectionCode, $date');
      
      // Resolve familyId from connectionCode
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) {
        print('Could not resolve family ID for connection code: $connectionCode');
        return [];
      }
      
      final doc = await _firestore
          .collection('families')
          .doc(familyId)
          .collection('meals')
          .doc(date)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        print('Meals data for $date: $data');
        final meals = data['meals'] as List<dynamic>? ?? [];
        return meals
            .map((meal) => MealRecord.fromMap(meal as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('Error getting meals for date: $e');
      return [];
    }
  }

  // 오늘 식사 개수 가져오기 (UPDATED for new structure)
  static Future<int> getTodayMealCount(String connectionCode) async {
    try {
      // Try to get from family document first (more efficient)
      final familyData = await getFamilyDataForChild(connectionCode);
      if (familyData != null) {
        final mealData = familyData['lastMeal'] as Map<String, dynamic>?;
        final todayMealCount = mealData?['count'] as int?;
        if (todayMealCount != null) {
          return todayMealCount;
        }
      }
      
      // Fallback to querying meals collection
      final meals = await getTodayMeals(connectionCode);
      return meals.length;
    } catch (e) {
      print('Error getting today meal count: $e');
      return 0;
    }
  }

  // 부모님 상태 분석 (UPDATED for new structure)
  static Future<ParentStatusInfo> getParentStatus(String connectionCode) async {
    try {
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      print('Getting parent status for connection code: $connectionCode, today: $today');
      
      // Use new family data resolution
      final familyData = await getFamilyDataForChild(connectionCode);
      if (familyData == null) {
        print('No family found for connection code: $connectionCode');
        return ParentStatusInfo(
          status: ParentStatus.normal,
          daysSinceLastRecord: 0,
          message: "부모님의 첫 식사 기록을 기다리고 있습니다",
        );
      }
      
      final familyId = familyData['familyId'] as String;
      
      final approved = familyData['approved'] as bool?;
      
      // 승인 대기 중인 경우
      if (approved == null) {
        return ParentStatusInfo(
          status: ParentStatus.caution,
          daysSinceLastRecord: 0,
          message: "연결 승인을 기다리고 있습니다",
        );
      }
      
      // 연결이 거부된 경우
      if (approved == false) {
        return ParentStatusInfo(
          status: ParentStatus.normal,
          daysSinceLastRecord: 0,
          message: "부모님의 첫 식사 기록을 기다리고 있습니다",
        );
      }
      
      // 생존 신호 확인 (alerts 기반 - parent app native monitoring, optimized structure)
      final alerts = familyData['alerts'] as Map<String, dynamic>?;
      final isActive = familyData['isActive'] as bool? ?? false;
      
      // 생존 알림이 활성화된 경우
      if (alerts?['survival'] != null) {
        return ParentStatusInfo(
          status: ParentStatus.emergency,
          daysSinceLastRecord: 0,
          message: "🚨 생존 신호 알림 활성화",
        );
      }
      
      // 앱이 비활성화된 경우
      if (!isActive) {
        return ParentStatusInfo(
          status: ParentStatus.normal,
          daysSinceLastRecord: 0,
          message: "부모님의 첫 식사 기록을 기다리고 있습니다",
        );
      }
      
      // 오늘 식사 기록 확인 (use cached data first from optimized structure)
      final mealData = familyData['lastMeal'] as Map<String, dynamic>?;
      final todayMealCount = mealData?['count'] as int? ?? 0;
      
      // Handle timestamp conversion (Firebase returns Timestamp, not String)
      DateTime? lastMealDateTime;
      final mealTimestamp = mealData?['timestamp'];
      if (mealTimestamp != null) {
        if (mealTimestamp is Timestamp) {
          lastMealDateTime = mealTimestamp.toDate();
        } else if (mealTimestamp is String) {
          lastMealDateTime = DateTime.parse(mealTimestamp);
        }
      }
      
      if (todayMealCount > 0) {
        print('Found today meals: $todayMealCount meals');
        
        return ParentStatusInfo(
          status: ParentStatus.normal,
          lastRecording: lastMealDateTime,
          daysSinceLastRecord: 0,
          message: "오늘 ${todayMealCount}번 식사했습니다",
        );
      }

      // 최근 식사 기록 찾기 (check lastMealDateTime from family doc first)
      DateTime? lastMealDate;
      int daysBack = 1;
      bool hasAnyMeals = false;
      
      // First check if we have lastMealDateTime in family document
      if (lastMealDateTime != null) {
        lastMealDate = lastMealDateTime;
        final daysSinceLastMeal = now.difference(lastMealDate).inDays;
        if (daysSinceLastMeal == 0) {
          // Same day, already handled above
          hasAnyMeals = true;
        } else {
          daysBack = daysSinceLastMeal;
          hasAnyMeals = true;
        }
      } else {
        // Fallback to querying meals collection
        while (daysBack <= 7) {
          final checkDate = now.subtract(Duration(days: daysBack));
          final checkDateString = DateFormat('yyyy-MM-dd').format(checkDate);
          final meals = await getMealsForDate(connectionCode, checkDateString);
          
          if (meals.isNotEmpty) {
            lastMealDate = meals.last.timestamp;
            hasAnyMeals = true;
            break;
          }
          daysBack++;
        }
      }

      // 식사 기록이 전혀 없는 경우 (새로운 가족 코드)
      if (!hasAnyMeals) {
        print('No meals found for connection code: $connectionCode');
        return ParentStatusInfo(
          status: ParentStatus.normal,
          daysSinceLastRecord: 0,
          message: "부모님의 첫 식사 기록을 기다리고 있습니다",
        );
      }

      // 상태 결정 (식사 기록 기반)
      ParentStatus status;
      String message;
      
      if (daysBack == 1) {
        status = ParentStatus.normal;
        message = "어제 식사하셨습니다";
      } else if (daysBack <= 2) {
        status = ParentStatus.caution;
        message = "${daysBack}일 전 마지막 식사";
      } else if (daysBack <= 4) {
        status = ParentStatus.warning;
        message = "⚠️ ${daysBack}일째 식사 기록이 없습니다";
      } else {
        status = ParentStatus.emergency;
        message = "🚨 ${daysBack}일째 식사 기록이 없습니다";
      }

      return ParentStatusInfo(
        status: status,
        lastRecording: lastMealDate,
        daysSinceLastRecord: daysBack,
        message: message,
      );
    } catch (e) {
      print('Error getting parent status: $e');
      return ParentStatusInfo(
        status: ParentStatus.warning,
        daysSinceLastRecord: 0,
        message: "상태 확인 중 오류가 발생했습니다",
      );
    }
  }

  // 실시간 오늘 식사 기록 스트림
  static Stream<List<MealRecord>> getTodayMealsStream(String familyCode) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return _firestore
        .collection('families')
        .doc(familyCode)
        .collection('meals')
        .doc(today)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        final meals = data['meals'] as List<dynamic>? ?? [];
        return meals
            .map((meal) => MealRecord.fromMap(meal as Map<String, dynamic>))
            .toList();
      }
      return <MealRecord>[];
    });
  }

  // 가족 정보 실시간 스트림
  static Stream<FamilyInfo?> getFamilyInfoStream(String familyCode) {
    return _firestore
        .collection('families')
        .doc(familyCode)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        final data = doc.data()!;
        return FamilyInfo.fromMap({
          'familyCode': familyCode,
          ...data,
        });
      }
      return null;
    });
  }

  /// Store location data for a family
  /// 
  /// [connectionCode] - Family connection code
  /// [latitude] - Location latitude
  /// [longitude] - Location longitude
  /// [address] - Optional address string
  /// [timestamp] - Optional timestamp (defaults to now)
  /// 
  /// Returns true if successful, false otherwise
  static Future<bool> storeLocation({
    required String connectionCode,
    required double latitude,
    required double longitude,
    String? address,
    DateTime? timestamp,
  }) async {
    try {
      final familyId = await getFamilyIdFromConnectionCode(connectionCode);
      if (familyId == null) {
        print('Could not resolve family ID for connection code: $connectionCode');
        return false;
      }
      
      timestamp ??= DateTime.now();
      
      // Create location data structure
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        if (address != null) 'address': address,
      };
      
      // Store in Firebase
      await _firestore.collection('families').doc(familyId).update({
        'location': locationData,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      
      print('Successfully stored location for family: $familyId');
      return true;
    } catch (e) {
      print('Error storing location: $e');
      return false;
    }
  }

  /// Clear family ID cache (useful for testing or when family changes)
  static void clearFamilyIdCache() {
    _familyIdCache.clear();
  }

  /// Get cached family ID without querying database
  static String? getCachedFamilyId(String connectionCode) {
    return _familyIdCache[connectionCode];
  }
}