import 'package:flutter/material.dart';
import '../constants/colors.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.softGray,
      appBar: AppBar(
        title: const Text(
          '도움말',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHelpSection(
            icon: Icons.family_restroom,
            title: '가족 연결하기',
            content: '1. 부모님의 스마트폰에서 부모 앱을 설치하고 가족 코드를 생성합니다.\n'
                   '2. 자녀 앱에서 받은 4자리 가족 코드를 입력합니다.\n'
                   '3. 부모님 이름을 확인하고 "승인"을 누르면 연결이 완료됩니다.',
          ),
          
          _buildHelpSection(
            icon: Icons.notifications,
            title: '알림 설정',
            content: '• 부모님이 설정한 시간 동안 활동이 없으면 안전 확인 알림을 받습니다.\n'
                   '• 3, 6, 12, 24시간 중 선택하거나 직접 시간을 입력할 수 있습니다.\n'
                   '• 설정 변경 후 반드시 "저장" 버튼을 눌러주세요.',
          ),
          
          _buildHelpSection(
            icon: Icons.restaurant,
            title: '식사 기록',
            content: '• 부모님이 식사하신 시간과 내용을 확인할 수 있습니다.\n'
                   '• 음성 녹음을 통해 부모님의 상태를 파악할 수 있습니다.\n'
                   '• 설정한 시간 동안 식사 기록이 없으면 알림을 받습니다.',
          ),
          
          _buildHelpSection(
            icon: Icons.location_on,
            title: '위치 정보',
            content: '• 부모님의 현재 위치와 이동 경로를 확인할 수 있습니다.\n'
                   '• 안전한 장소에 계신지 실시간으로 모니터링됩니다.\n'
                   '• 위치 정보는 가족 구성원에게만 공유됩니다.',
          ),
          
          _buildHelpSection(
            icon: Icons.settings,
            title: '가족 코드 변경',
            content: '• 새로운 가족과 연결하려면 기존 연결을 해제해야 합니다.\n'
                   '• 변경 시 모든 식사 기록과 설정이 삭제됩니다.\n'
                   '• 신중하게 결정하시고, 필요한 데이터는 미리 백업하세요.',
          ),
          
          _buildHelpSection(
            icon: Icons.security,
            title: '데이터 보안',
            content: '• 모든 데이터는 Google Firebase 보안 시스템을 통해 안전하게 보관됩니다.\n'
                   '• Firebase는 업계 표준 암호화 및 보안 프로토콜을 사용합니다.\n'
                   '• 가족 구성원만 정보에 접근할 수 있도록 접근 제어가 설정되어 있습니다.\n'
                   '• 개인정보 처리방침에서 자세한 내용을 확인하세요.',
          ),
          
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.primaryBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '추가 문의사항이 있으시면 앱 스토어 리뷰를 통해 문의해주세요.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.darkText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: AppColors.primaryBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.darkText,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}