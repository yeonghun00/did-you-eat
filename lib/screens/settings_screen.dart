import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../models/family_record.dart';
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
  final TextEditingController _hoursController = TextEditingController();
  int _emergencyDays = 3;
  int _survivalAlertHours = 12;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _emergencyDays = prefs.getInt('emergency_days') ?? 3;
        _survivalAlertHours = prefs.getInt('survival_alert_hours') ?? 12;
        _hoursController.text = _survivalAlertHours.toString();
      });
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('emergency_days', _emergencyDays);
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
      print('Emergency days: $_emergencyDays');

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
      builder: (context) => AlertDialog(
        title: const Text('가족 코드 변경'),
        content: const Text(
          '가족 코드를 변경하시겠습니까?\n현재 연결이 해제되고 새로운 가족 코드를 입력해야 합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('family_code');

        Navigator.pushAndRemoveUntil(
          context,
          AppTheme.slideTransition(page: const FamilySetupScreen()),
          (route) => false,
        );
      } catch (e) {
        print('Error changing family code: $e');
      }
    }
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
                value: widget.familyInfo?.elderlyName ?? '정보 없음',
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


          // 비상 알림 설정
          _buildSection(
            title: '비상 알림',
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: AppColors.warningRed),
                        const SizedBox(width: 12),
                        const Text(
                          '비상 알림 기준',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '몇 일 동안 식사 기록이 없으면 비상 알림을 받으시겠습니까?',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [2, 3, 5, 7].map((days) {
                        final isSelected = _emergencyDays == days;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _emergencyDays = days;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryBlue
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$days일',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 생존 신호 알림 설정
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.heart_broken, color: AppColors.warningRed),
                        const SizedBox(width: 12),
                        const Text(
                          '생존 신호 알림',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '몇 시간 동안 활동이 없으면 생존 신호 알림을 받으시겠습니까?',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hoursController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: '시간',
                              hintText: '예: 12',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: AppColors.warningRed,
                                  width: 2,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.access_time,
                                color: AppColors.warningRed,
                              ),
                              suffixText: '시간',
                            ),
                            onChanged: (value) {
                              final hours = int.tryParse(value);
                              if (hours != null && hours > 0 && hours <= 72) {
                                setState(() {
                                  _survivalAlertHours = hours;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warningRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '현재: $_survivalAlertHours시간',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warningRed,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '1-72시간 사이',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warningRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: AppColors.warningRed,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '부모님의 앱 사용, 화면 터치 등의 활동이 설정 시간 동안 없으면 알림을 받습니다.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.warningRed,
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

          // FCM 테스트 섹션
          _buildSection(
            title: 'FCM 테스트',
            children: [
              _buildActionItem(
                icon: Icons.app_registration,
                title: 'FCM 토큰 등록 테스트',
                onTap: () async {
                  if (widget.familyCode != null) {
                    try {
                      HapticFeedback.lightImpact();
                      // Get familyId from the familyCode
                      final familyData = await _childService.getFamilyInfo(
                        widget.familyCode!,
                      );
                      final familyId = familyData?['familyId'] as String?;

                      if (familyId != null) {
                        final registered = await FCMTokenService.registerChildToken(familyId);
                        if (registered) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ FCM 토큰 등록 성공!')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('❌ FCM 토큰 등록 실패')),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('❌ 가족 ID를 찾을 수 없습니다')),
                        );
                      }
                    } catch (e) {
                      String errorMessage = '❌ FCM 토큰 등록 실패';
                      if (e.toString().contains('FIS_AUTH_ERROR')) {
                        errorMessage = '❌ Firebase 인증 오류 - 네트워크 연결을 확인하고 다시 시도해주세요';
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }
                },
              ),
              _buildActionItem(
                icon: Icons.token,
                title: 'FCM 토큰 생성 테스트',
                onTap: () async {
                  HapticFeedback.lightImpact();
                  final success = await FCMTokenService.testFCMTokenGeneration();
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ FCM 토큰 생성 성공!')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('❌ FCM 토큰 생성 실패')),
                    );
                  }
                },
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
