import 'package:flutter/material.dart';
import 'package:love_everyday/models/family_record.dart';
import 'app_theme.dart';
import '../constants/colors.dart';

/// Professional theme usage examples for busy adults
/// Clean, modern components for efficient parent monitoring
class ThemeUsageExamples {
  /// Professional status card for busy adults
  static Widget getParentStatusCard({
    required String parentName,
    required ParentStatus status,
    required String statusMessage,
    required int mealCount,
    required DateTime? lastActivity,
  }) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.getStatusColor(status).withOpacity(0.1),
                    borderRadius: AppTheme.getBorderRadius(radius: 8),
                  ),
                  child: Icon(
                    AppTheme.getStatusIcon(status),
                    color: AppTheme.getStatusColor(status),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        parentName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppTheme.getStatusText(status),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.getStatusColor(status),
                        ),
                      ),
                    ],
                  ),
                ),
                // Meal count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: AppTheme.getBorderRadius(radius: 12),
                  ),
                  child: Text(
                    '$mealCount 식사',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status message
            Text(
              statusMessage,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textMedium,
                height: 1.4,
              ),
            ),

            if (lastActivity != null) ...[
              const SizedBox(height: 8),
              Text(
                '마지막 활동: ${_formatTime(lastActivity)}',
                style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Quick action button for monitoring
  static Widget getQuickActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? textColor,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppTheme.primaryBlue,
          foregroundColor: textColor ?? AppTheme.white,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.getBorderRadius(radius: 12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  /// Meal tracking card
  static Widget getMealTrackingCard({
    required int mealNumber,
    required String mealName,
    required DateTime timestamp,
    required String parentName,
  }) {
    final mealColor = AppTheme.getMealTypeColor(mealNumber);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Meal indicator
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: mealColor.withOpacity(0.1),
                borderRadius: AppTheme.getBorderRadius(radius: 8),
              ),
              child: Icon(Icons.restaurant, color: mealColor, size: 20),
            ),

            const SizedBox(width: 16),

            // Meal info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$parentName님의 $mealName',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(timestamp),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textMedium,
                    ),
                  ),
                ],
              ),
            ),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mealColor.withOpacity(0.1),
                borderRadius: AppTheme.getBorderRadius(radius: 12),
              ),
              child: Text(
                '완료',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: mealColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Statistics card for dashboard
  static Widget getStatisticsCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    Color? color,
  }) {
    final cardColor = color ?? AppTheme.primaryBlue;

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMedium,
                  ),
                ),
                Icon(icon, size: 20, color: cardColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cardColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
            ),
          ],
        ),
      ),
    );
  }

  /// Alert banner for important notifications
  static Widget getAlertBanner({
    required String message,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? textColor,
  }) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.warningAmber.withOpacity(0.1),
        borderRadius: AppTheme.getBorderRadius(radius: 12),
        border: Border.all(
          color: (backgroundColor ?? AppTheme.warningAmber).withOpacity(0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.getBorderRadius(radius: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: textColor ?? AppTheme.warningAmber,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor ?? AppTheme.textDark,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: textColor ?? AppTheme.textLight,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Professional bottom navigation bar
  static Widget getBottomNavigation({
    required int currentIndex,
    required Function(int) onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.textLight.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.white,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textLight,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '기록'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: '알림'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }

  /// Professional app bar
  static PreferredSizeWidget getAppBar({
    required String title,
    List<Widget>? actions,
    VoidCallback? onBackPressed,
  }) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textDark,
        ),
      ),
      backgroundColor: AppTheme.white,
      foregroundColor: AppTheme.textDark,
      elevation: 0,
      centerTitle: true,
      leading: onBackPressed != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBackPressed,
            )
          : null,
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.gray200),
      ),
    );
  }

  /// Helper method to format time
  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }
}

/// Professional theme migration guide
class ProfessionalThemeMigration {
  /// Color migration from old theme to new professional theme
  static const Map<String, String> colorMigration = {
    'Old pastels': 'Modern blues and grays',
    'AppTheme.primaryPurple': 'AppTheme.primaryBlue',
    'AppTheme.sageGreen': 'AppTheme.successGreen',
    'AppTheme.coral': 'AppTheme.warningAmber',
    'AppTheme.ivory': 'AppTheme.gray50',
    'AppTheme.warmIvory': 'AppTheme.white',
  };

  /// Design principles for busy professionals
  static const List<String> designPrinciples = [
    'High contrast for quick scanning',
    'Minimal visual noise',
    'Clear status indicators',
    'Professional color palette',
    'Efficient information hierarchy',
    'Touch-friendly but not oversized',
    'Native iOS/Android feel',
    'Clean typography',
  ];

  /// Usage recommendations
  static const Map<String, String> usageRecommendations = {
    'Status cards': 'Use clear icons and colors for quick status recognition',
    'Navigation': 'Keep it simple with standard bottom navigation',
    'Alerts': 'Use professional amber/red for warnings, not cute colors',
    'Typography': 'Use proper font weights for information hierarchy',
    'Buttons': 'Standard elevated buttons, not rounded cute buttons',
    'Cards': 'Clean white cards with subtle shadows',
    'Colors':
        'Professional blue primary, green success, amber warning, red error',
  };
}
