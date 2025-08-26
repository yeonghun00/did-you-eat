import 'package:flutter/material.dart';
import '../models/family_record.dart';
import '../services/auth_service.dart';
import '../services/child_app_service.dart';
import '../services/fcm_token_service.dart';
import '../services/session_manager.dart';
import '../constants/colors.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class FamilySetupScreen extends StatefulWidget {
  const FamilySetupScreen({Key? key}) : super(key: key);

  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends State<FamilySetupScreen> {
  final TextEditingController _codeController = TextEditingController();
  final ChildAppService _childService = ChildAppService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _isApproving = false;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }
  
  Future<void> _initializeAuth() async {
    // Ensure authentication is properly set up
    try {
      await _authService.initialize();
      
      // Ensure we have some form of authentication for Firebase access
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        print('🔄 No current user, attempting anonymous authentication...');
        final result = await _authService.signInAnonymously();
        if (result.isSuccess) {
          print('✅ Anonymous authentication successful');
        } else {
          print('❌ Anonymous authentication failed: ${result.errorMessage}');
        }
      } else {
        print('✅ User already authenticated: ${currentUser.uid}');
      }
    } catch (e) {
      print('❌ Authentication initialization failed: $e');
    }
  }

  Future<void> _validateCode() async {
    if (_codeController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '가족 코드를 입력해주세요';
      });
      return;
    }

    if (_codeController.text.trim().length != 4) {
      setState(() {
        _errorMessage = '가족 코드는 4자리입니다';
      });
      return;
    }

    _validateAndNavigate(_codeController.text.trim());
  }

  Future<void> _validateAndNavigate(String code) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Use the new child app service to get family info
      print('🔍 Validating family code: $code');
      final familyData = await _childService.getFamilyInfo(code);
      
      if (familyData != null && familyData.isNotEmpty) {
        // Check if already processed
        final approved = familyData['approved'];
        print('Family code $code approval status: $approved');
        
        if (approved != null) {
          setState(() {
            _errorMessage = '이미 처리된 코드입니다';
          });
          return;
        }
        
        // Show approval dialog with elderly person's name
        _showApprovalDialog(code, familyData);
      } else {
        print('❌ Family data is null or empty for code: $code');
        setState(() {
          _errorMessage = '가족 코드 $code를 찾을 수 없습니다.\n부모님이 앱에서 가족 코드를 생성했는지 확인해주세요.';
        });
      }
    } catch (e) {
      print('❌ ERROR: Family code validation failed: $e');
      
      // Enhanced error handling for new security model
      String errorMessage = '연결에 실패했습니다. 다시 시도해주세요';
      
      if (e.toString().contains('permission-denied')) {
        errorMessage = '가족 코드에 접근할 권한이 없습니다.\n보안 설정을 확인해주세요.';
      } else if (e.toString().contains('not found') || e.toString().contains('does not exist')) {
        errorMessage = '가족 코드 $code를 찾을 수 없습니다.\n부모님이 앱에서 가족 코드를 생성했는지 확인해주세요.';
      } else if (e.toString().contains('network') || e.toString().contains('timeout')) {
        errorMessage = '네트워크 연결을 확인하고 다시 시도해주세요.';
      }
      
      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showApprovalDialog(String code, Map<String, dynamic> familyData) {
    final elderlyName = familyData['elderlyName'] as String? ?? '부모님';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.family_restroom, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            const Text('연결 확인'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$elderlyName님과 연결하시겠습니까?',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.primaryBlue),
                      const SizedBox(width: 4),
                      const Text('가족 코드: ', style: TextStyle(fontSize: 12)),
                      Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '연결하면 부모님의 안부와 식사 기록을 실시간으로 확인할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isApproving ? null : () async {
              setState(() {
                _isApproving = true;
              });
              
              try {
                // REJECT - elderly app will reset
                print('❌ REJECTING family code $code');
                final success = await _childService.approveFamilyCode(code, false);
                print('Rejection result: $success');
                
                setState(() {
                  _isApproving = false;
                });
                
                Navigator.pop(context);
                setState(() {
                  _errorMessage = '연결이 취소되었습니다';
                });
              } catch (e) {
                print('❌ ERROR: Exception during rejection: $e');
                
                // Enhanced error handling for rejection failures
                String errorMessage = '연결 취소에 실패했습니다';
                
                if (e.toString().contains('permission-denied')) {
                  errorMessage = '보안 규칙으로 인해 취소 요청이 차단되었습니다.';
                } else if (e.toString().contains('network') || e.toString().contains('timeout')) {
                  errorMessage = '네트워크 연결 문제가 발생했습니다.';
                }
                
                setState(() {
                  _isApproving = false;
                });
                
                Navigator.pop(context);
                setState(() {
                  _errorMessage = errorMessage;
                });
              }
            },
            child: const Text('아니요'),
          ),
          ElevatedButton(
            onPressed: _isApproving ? null : () async {
              setState(() {
                _isApproving = true;
              });
              
              try {
                // CRITICAL: APPROVE - elderly app will proceed immediately
                print('🚨 CRITICAL: Attempting to approve family code $code');
                final success = await _childService.approveFamilyCode(code, true);
                
                print('Approval result: $success');
                
                if (success) {
                  print('✅ SUCCESS: Family code approved, saving locally and navigating');
                  
                  // Save family code to user profile
                  await _authService.addFamilyCode(code);
                  
                  // Save session data for persistence
                  final sessionManager = SessionManager();
                  await sessionManager.initialize();
                  await sessionManager.saveSession(code, familyData);
                  print('💾 Session saved with familyId: ${familyData['familyId']}');
                  
                  // Register FCM token for this family
                  final familyId = familyData['familyId'] as String?;
                  if (familyId != null) {
                    try {
                      final registered = await FCMTokenService.registerChildToken(familyId);
                      if (registered) {
                        print('✅ FCM token registered for new family: $familyId');
                      } else {
                        print('⚠️ FCM token registration failed');
                      }
                    } catch (e) {
                      print('❌ Failed to register FCM token: $e');
                    }
                  }
                  
                  // Create FamilyInfo object for navigation
                  final familyInfo = FamilyInfo.fromMap({
                    'familyCode': code,
                    ...familyData,
                  });
                  
                  Navigator.pop(context);
                  
                  // Navigate to home screen
                  Navigator.pushReplacement(
                    context,
                    AppTheme.slideTransition(
                      page: HomeScreen(
                        familyCode: code,
                        familyInfo: familyInfo,
                      ),
                    ),
                  );
                } else {
                  print('❌ ERROR: Approval failed');
                  throw Exception('승인 처리에 실패했습니다');
                }
              } catch (e) {
                print('❌ ERROR: Exception during approval: $e');
                
                // Enhanced error handling for approval failures
                String errorMessage = '연결 승인에 실패했습니다. 다시 시도해주세요';
                
                if (e.toString().contains('permission-denied')) {
                  errorMessage = '보안 규칙으로 인해 연결이 차단되었습니다.\n부모님께서 새로운 가족 코드를 생성해주세요.';
                } else if (e.toString().contains('Transaction failed') || e.toString().contains('already exists')) {
                  errorMessage = '이미 처리된 요청입니다.\n페이지를 새로고침하고 다시 시도해주세요.';
                } else if (e.toString().contains('network') || e.toString().contains('timeout')) {
                  errorMessage = '네트워크 연결 문제가 발생했습니다.\n인터넷 연결을 확인하고 다시 시도해주세요.';
                }
                
                setState(() {
                  _isApproving = false;
                });
                
                Navigator.pop(context);
                setState(() {
                  _errorMessage = errorMessage;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: _isApproving 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('예, 연결합니다'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 60),
              
              // 앱 로고 및 제목
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              Text(
                '식사하셨어요?',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 8),
              
              Text(
                '부모님 안부를 확인하세요',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.lightText,
                ),
              ),
              
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 60),
              
              // 설명 카드
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      spreadRadius: 1,
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.primaryBlue,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '가족 코드 입력',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '부모님이 "식사 기록" 앱에서 생성한 4자리 가족 코드를 입력해주세요.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.lightText,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: AppColors.primaryBlue,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '부모님 앱의 "가족 코드 보기"에서 확인할 수 있습니다',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 40),
              
              // 가족 코드 입력 필드
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  hintText: '0000',
                  hintStyle: TextStyle(
                    color: AppColors.lightText.withOpacity(0.5),
                    letterSpacing: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primaryBlue, width: 2),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (value) {
                  if (_errorMessage.isNotEmpty) {
                    setState(() {
                      _errorMessage = '';
                    });
                  }
                },
                onSubmitted: (value) {
                  if (!_isLoading) {
                    _validateCode();
                  }
                },
              ),
              
              // 에러 메시지
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 40),
              
              // 연결 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _validateCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '연결하기',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 20 : 60),
              
              // 하단 도움말
              Text(
                '문제가 있으시면 부모님께 가족 코드를 다시 확인해 주세요',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.lightText,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}