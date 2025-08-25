import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../models/family_record.dart';
import '../services/auth_service.dart';
import '../services/child_app_service.dart';
import '../services/fcm_token_service.dart';
import '../theme/app_theme.dart';
import 'family_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String? familyCode;
  final FamilyInfo? familyInfo;

  const SettingsScreen({super.key, this.familyCode, this.familyInfo});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ChildAppService _childService = ChildAppService();
  final AuthService _authService = AuthService();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _customAlertController = TextEditingController();
  int _survivalAlertHours = 12;
  bool _useCustomAlertHours = false;
  String? _elderlyName;
  bool _isLoadingFamilyInfo = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadFamilyInfo();
  }

  Future<void> _loadSettings() async {
    try {
      // First try to load from Firebase if we have a family code
      if (widget.familyCode != null) {
        try {
          final familyData = await _childService.getFamilyInfo(widget.familyCode!);
          if (familyData != null && familyData['settings'] != null) {
            final settings = familyData['settings'] as Map<String, dynamic>;
            final firebaseHours = settings['alertHours'] as int? ?? 12;
            
            // Save to local storage for caching
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('survival_alert_hours', firebaseHours);
            
            setState(() {
              _survivalAlertHours = firebaseHours;
              _hoursController.text = firebaseHours.toString();
              
              // Check if it's a custom value (not one of the presets)
              final presetHours = [3, 6, 12, 24];
              _useCustomAlertHours = !presetHours.contains(firebaseHours);
              if (_useCustomAlertHours) {
                _customAlertController.text = firebaseHours.toString();
              }
            });
            
            print('Loaded alert hours from Firebase: $firebaseHours');
            return;
          }
        } catch (e) {
          print('Error loading from Firebase, falling back to local storage: $e');
        }
      }
      
      // Fallback to local storage
      final prefs = await SharedPreferences.getInstance();
      final hours = prefs.getInt('survival_alert_hours') ?? 12;
      setState(() {
        _survivalAlertHours = hours;
        _hoursController.text = hours.toString();
        
        // Check if it's a custom value (not one of the presets)
        final presetHours = [3, 6, 12, 24];
        _useCustomAlertHours = !presetHours.contains(hours);
        if (_useCustomAlertHours) {
          _customAlertController.text = hours.toString();
        }
      });
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _loadFamilyInfo() async {
    if (widget.familyCode == null) {
      setState(() {
        _elderlyName = null;
        _isLoadingFamilyInfo = false;
      });
      return;
    }

    try {
      // Try to get family info from ChildAppService
      final familyData = await _childService.getFamilyInfo(widget.familyCode!);
      
      if (familyData != null && mounted) {
        setState(() {
          _elderlyName = familyData['elderlyName'] ?? '';
          _isLoadingFamilyInfo = false;
        });
        print('Family info loaded: elderlyName = $_elderlyName');
      } else if (mounted) {
        setState(() {
          _elderlyName = widget.familyInfo?.elderlyName;
          _isLoadingFamilyInfo = false;
        });
      }
    } catch (e) {
      print('Error loading family info: $e');
      if (mounted) {
        setState(() {
          _elderlyName = widget.familyInfo?.elderlyName;
          _isLoadingFamilyInfo = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('survival_alert_hours', _survivalAlertHours);

      // Also sync with Firebase
      await _syncSettingsWithFirebase();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('설정이 저장되었습니다')));
    } catch (e) {
      print('Error saving settings: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('설정 저장에 실패했습니다')));
    }
  }

  Future<void> _syncSettingsWithFirebase() async {
    if (widget.familyCode == null) return;

    try {
      print('Syncing settings with Firebase...');
      print('Survival alert hours: $_survivalAlertHours');

      // Update settings in Firebase using the new structure
      await _childService.updateSettings(widget.familyCode!, {
        'alertHours': _survivalAlertHours,
        'survivalSignalEnabled': true,
        'voiceRecordingEnabled': true, // Always enabled for child app
      });

      print('Settings synced successfully');
    } catch (e) {
      print('Error syncing settings with Firebase: $e');
    }
  }

  Future<void> _changeFamilyCode() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon and title
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.warningRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: AppColors.warningRed,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              
              const Text(
                '가족 코드 변경',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              
              Text(
                '이 작업은 되돌릴 수 없습니다',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.warningRed,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // Data deletion warning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warningRed.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warningRed.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '다음 데이터가 모두 삭제됩니다:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDeletedDataItem(Icons.family_restroom, '부모님 연결 정보'),
                    _buildDeletedDataItem(Icons.restaurant, '모든 식사 기록 히스토리'),
                    _buildDeletedDataItem(Icons.health_and_safety, '생존 신호 설정'),
                    _buildDeletedDataItem(Icons.history, '앱 사용 기록'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.softGray,
                          foregroundColor: AppColors.darkText,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '취소',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warningRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '변경',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      // Double confirmation for destructive action
      final finalConfirmation = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.warningRed.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: AppColors.warningRed,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 16),
                
                const Text(
                  '최종 확인',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                
                const Text(
                  '정말로 모든 데이터를 삭제하고\n가족 코드를 변경하시겠습니까?',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.darkText,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                
                Text(
                  '이 작업은 되돌릴 수 없습니다.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.warningRed,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.softGray,
                            foregroundColor: AppColors.darkText,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '취소',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warningRed,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '확인',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (finalConfirmation == true) {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('데이터를 삭제하고 있습니다...'),
              ],
            ),
          ),
        );

        try {
          // Remove family code from user profile
          if (widget.familyCode != null) {
            await _authService.removeFamilyCode(widget.familyCode!);
          }

          // Close loading dialog
          if (mounted) Navigator.of(context).pop();

          Navigator.pushAndRemoveUntil(
            context,
            AppTheme.slideTransition(page: const FamilySetupScreen()),
            (route) => false,
          );
        } catch (e) {
          print('Error changing family code: $e');
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();
          
          // Show error message to user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('가족 코드 변경 중 오류가 발생했습니다.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }


  Widget _buildDeletedDataItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.warningRed,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.darkText,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertHourOption(int hours) {
    final isSelected = _survivalAlertHours == hours && !_useCustomAlertHours;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _survivalAlertHours = hours;
          _useCustomAlertHours = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.gray300,
            width: 2,
          ),
          boxShadow: isSelected ? AppTheme.getCardShadow(elevation: 3) : [],
        ),
        child: Text(
          '${hours}시간',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textMedium,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomInputOption() {
    final isSelected = _useCustomAlertHours;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _useCustomAlertHours = true;
          if (_customAlertController.text.isNotEmpty) {
            final customHours = int.tryParse(_customAlertController.text);
            if (customHours != null && customHours >= 1 && customHours <= 72) {
              _survivalAlertHours = customHours;
            }
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : AppTheme.gray300,
            width: 2,
          ),
          boxShadow: isSelected ? AppTheme.getCardShadow(elevation: 3) : [],
        ),
        child: Text(
          '직접 입력',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textMedium,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: const Text(
          '설정',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text(
              '저장',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 가족 정보 섹션
          _buildSection(
            title: '가족 정보',
            children: [
              _buildInfoItem(
                icon: Icons.family_restroom,
                title: '부모님 이름',
                value: _isLoadingFamilyInfo 
                    ? '정보 로딩 중...' 
                    : (_elderlyName?.isNotEmpty == true 
                        ? _elderlyName! 
                        : (widget.familyInfo?.elderlyName?.isNotEmpty == true 
                            ? widget.familyInfo!.elderlyName 
                            : '연결 정보 없음')),
              ),
              _buildInfoItem(
                icon: Icons.code,
                title: '가족 코드',
                value: widget.familyCode ?? '정보 없음',
              ),
              _buildActionItem(
                icon: Icons.edit,
                title: '가족 코드 변경',
                onTap: _changeFamilyCode,
              ),
            ],
          ),

          const SizedBox(height: 16),


          // 생존 신호 알림 설정
          _buildSection(
            title: '알림 설정',
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.gray50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gray200, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Section
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 20, color: AppTheme.primaryBlue),
                        const SizedBox(width: 8),
                        const Text(
                          '알림 시간 설정',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '몇 시간 동안 활동이 없으면 부모님 안전 안심 알림을 받으시겠습니까?',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Options Layout
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildAlertHourOption(3),
                        _buildAlertHourOption(6),
                        _buildAlertHourOption(12),
                        _buildAlertHourOption(24),
                        _buildCustomInputOption(),
                      ],
                    ),
                    
                    // Custom Input Field
                    if (_useCustomAlertHours) ...[
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryBlue, width: 2),
                        ),
                        child: TextField(
                          controller: _customAlertController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: '시간 입력 (1-72)',
                            suffixText: '시간',
                            suffixStyle: TextStyle(color: AppTheme.primaryBlue),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onChanged: (value) {
                            final hours = int.tryParse(value);
                            if (hours != null && hours >= 1 && hours <= 72) {
                              setState(() {
                                _survivalAlertHours = hours;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppTheme.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '현재 설정: $_survivalAlertHours시간 • 부모님의 앱 사용, 화면 터치 등의 활동이 설정 시간 동안 없으면 알림을 받습니다.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryBlue,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 앱 정보 섹션
          _buildSection(
            title: '앱 정보',
            children: [
              _buildInfoItem(icon: Icons.info, title: '앱 버전', value: '1.0.0'),
              _buildActionItem(
                icon: Icons.privacy_tip,
                title: '개인정보 처리방침',
                onTap: () {
                  // TODO: 개인정보 처리방침 페이지로 이동
                },
              ),
              _buildActionItem(
                icon: Icons.help,
                title: '도움말',
                onTap: () {
                  // TODO: 도움말 페이지로 이동
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primaryBlue,
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryBlue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
