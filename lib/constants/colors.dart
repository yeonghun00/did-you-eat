import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Legacy color constants for backward compatibility
/// @deprecated Use AppTheme colors instead for new code
class AppColors {
  // 상태별 색상 (mapped to new professional theme)
  static const Color normalGreen = AppTheme.successGreen;
  static const Color cautionOrange = AppTheme.warningAmber;
  static const Color warningRed = AppTheme.errorRed;
  static const Color emergencyBlack = AppTheme.errorRed;

  // 기본 UI 색상 (mapped to new professional theme)
  static const Color primaryBlue = AppTheme.primaryBlue;
  static const Color softGray = AppTheme.gray50;
  static const Color darkText = AppTheme.textDark;
  static const Color lightText = AppTheme.textLight;
  static const Color cardBackground = AppTheme.white;
  static const Color dividerColor = AppTheme.gray200;

  // 액션 버튼 색상 (mapped to new professional theme)
  static const Color heartRed = AppTheme.errorRed;
  static const Color chartBlue = AppTheme.primaryBlue;

  // 그라데이션 (mapped to new professional theme)
  static const LinearGradient normalGradient = AppTheme.successGradient;
  static const LinearGradient cautionGradient = AppTheme.warningGradient;
  static const LinearGradient warningGradient = AppTheme.warningGradient;
  static const LinearGradient emergencyGradient = AppTheme.errorGradient;

  // 상태별 색상 및 그라데이션 가져오기
  static Color getStatusColor(String status) {
    switch (status) {
      case 'normal':
        return normalGreen;
      case 'caution':
        return cautionOrange;
      case 'warning':
        return warningRed;
      case 'emergency':
        return emergencyBlack;
      default:
        return normalGreen;
    }
  }

  static LinearGradient getStatusGradient(String status) {
    switch (status) {
      case 'normal':
        return normalGradient;
      case 'caution':
        return cautionGradient;
      case 'warning':
        return warningGradient;
      case 'emergency':
        return emergencyGradient;
      default:
        return normalGradient;
    }
  }
}

/// Professional semantic color helpers for better code readability
class SemanticColors {
  // Parent App colors
  static const Color mealLogging = AppTheme.primaryBlue;
  static const Color checkIn = AppTheme.infoTeal;
  static const Color emergency = AppTheme.errorRed;
  
  // Child App colors - Professional status indicators
  static const Color parentActive = AppTheme.parentActiveColor;
  static const Color parentInactive = AppTheme.parentInactiveColor;
  static const Color parentCaution = AppTheme.parentCautionColor;
  static const Color parentEmergency = AppTheme.parentInactiveColor;
  
  // Meal type colors - Professional and clear
  static const Color breakfast = AppTheme.warningAmber;
  static const Color lunch = AppTheme.successGreen;
  static const Color dinner = AppTheme.primaryBlue;
  
  // UI element colors - Modern and clean
  static const Color cardBackground = AppTheme.white;
  static const Color surfaceBackground = AppTheme.gray50;
  static const Color primaryAction = AppTheme.primaryBlue;
  static const Color secondaryAction = AppTheme.gray200;
  
  // Professional status colors
  static const Color statusActive = AppTheme.successGreen;
  static const Color statusWarning = AppTheme.warningAmber;
  static const Color statusError = AppTheme.errorRed;
  static const Color statusInfo = AppTheme.infoTeal;
}