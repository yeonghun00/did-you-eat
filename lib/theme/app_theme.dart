import 'package:flutter/material.dart';
import '../models/family_record.dart';

/// Modern, professional theme for busy adults monitoring their parents
/// Designed for quick scanning and efficient information display
class AppTheme {
  // ================== BASE COLORS ==================

  // Primary Colors - Professional and modern
  static const Color primaryBlue = Color(
    0xFF2563EB,
  ); // Modern blue - trustworthy, professional
  static const Color darkBlue = Color(0xFF1D4ED8); // Navigation/headers
  static const Color lightBlue = Color(0xFF3B82F6); // Accent actions

  // Neutral Colors - Clean and professional
  static const Color white = Color(0xFFFFFFFF); // Pure white backgrounds
  static const Color gray50 = Color(0xFFF8FAFC); // Light background
  static const Color gray100 = Color(0xFFF1F5F9); // Card backgrounds
  static const Color gray200 = Color(0xFFE2E8F0); // Borders
  static const Color gray300 = Color(0xFFCBD5E1); // Dividers

  // ================== STATUS COLORS ==================

  // Clear status indicators for quick scanning
  static const Color successGreen = Color(0xFF11DE9A); // Parent is okay
  static const Color warningAmber = Color(0xFFF59E0B); // Needs attention
  static const Color errorRed = Color(0xFFEF4444); // Urgent situation
  static const Color infoTeal = Color(0xFF06B6D4); // Information

  // ================== TEXT COLORS ==================

  static const Color textDark = Color(
    0xFF0F172A,
  ); // Primary text - high contrast
  static const Color textMedium = Color(0xFF475569); // Secondary text
  static const Color textLight = Color(0xFF94A3B8); // Tertiary text
  static const Color textOnDark = Color(0xFFFFFFFF); // Text on dark backgrounds
  static const Color textOnColor = Color(
    0xFFFFFFFF,
  ); // Text on colored backgrounds

  // ================== SEMANTIC COLOR MAPPINGS ==================

  // Status monitoring for busy professionals
  static const Color parentActiveColor =
      successGreen; // Parent is active and healthy
  static const Color parentCautionColor = warningAmber; // Needs attention
  static const Color parentInactiveColor = errorRed; // Urgent - no activity
  static const Color parentInfoColor = infoTeal; // General information

  // Action colors
  static const Color primaryAction = primaryBlue; // Primary actions
  static const Color secondaryAction = gray200; // Secondary actions
  static const Color destructiveAction = errorRed; // Delete/emergency actions

  // ================== GRADIENTS ==================

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, darkBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [successGreen, Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [warningAmber, Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient errorGradient = LinearGradient(
    colors: [errorRed, Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ================== THEME DATA ==================

  /// Professional light theme for busy adults
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,

      // Color scheme
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        primary: primaryBlue,
        secondary: infoTeal,
        surface: white,
        error: errorRed,
        onPrimary: textOnColor,
        onSecondary: textOnColor,
        onSurface: textDark,
        onError: textOnColor,
      ),

      // Scaffold background
      scaffoldBackgroundColor: gray50,

      // App bar theme - Clean and professional
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        surfaceTintColor: Colors.transparent,
      ),

      // Card theme - Clean with subtle shadows
      cardTheme: CardThemeData(
        color: white,
        shadowColor: textLight.withValues(alpha: 0.1),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        surfaceTintColor: Colors.transparent,
      ),

      // Elevated button theme - Professional
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: textOnColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: textOnColor,
        elevation: 4,
      ),

      // Bottom navigation bar theme
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: white,
        selectedItemColor: primaryBlue,
        unselectedItemColor: textLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showUnselectedLabels: true,
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: gray100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: gray300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),

      // Text theme - Professional typography
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: textDark,
          height: 1.2,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: textDark,
          height: 1.2,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: textDark,
          height: 1.3,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textDark,
          height: 1.3,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textDark,
          height: 1.4,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textDark,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: textDark,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textMedium,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textLight,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textDark,
          height: 1.4,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textMedium,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textLight,
          height: 1.4,
        ),
      ),

      // Icon theme
      iconTheme: const IconThemeData(color: textDark, size: 24),

      // Divider theme
      dividerTheme: const DividerThemeData(color: gray200, thickness: 1),
    );
  }

  // ================== HELPER METHODS ==================

  /// Get color based on parent status - professional and clear
  static Color getStatusColor(ParentStatus status) {
    switch (status) {
      case ParentStatus.normal:
        return parentActiveColor;
      case ParentStatus.caution:
        return parentCautionColor;
      case ParentStatus.warning:
        return parentCautionColor;
      case ParentStatus.emergency:
        return parentInactiveColor;
    }
  }

  /// Get gradient based on parent status
  static LinearGradient getStatusGradient(ParentStatus status) {
    switch (status) {
      case ParentStatus.normal:
        return successGradient;
      case ParentStatus.caution:
        return warningGradient;
      case ParentStatus.warning:
        return warningGradient;
      case ParentStatus.emergency:
        return errorGradient;
    }
  }

  /// Get meal type color for quick identification
  static Color getMealTypeColor(int mealNumber) {
    switch (mealNumber) {
      case 1:
        return warningAmber; // Breakfast - amber
      case 2:
        return successGreen; // Lunch - green
      case 3:
        return primaryBlue; // Dinner - blue
      default:
        return infoTeal;
    }
  }

  /// Create professional shadow for cards
  static List<BoxShadow> getCardShadow({double elevation = 2}) {
    return [
      BoxShadow(
        color: textLight.withValues(alpha: 0.08),
        blurRadius: elevation * 4,
        offset: Offset(0, elevation),
        spreadRadius: 0,
      ),
    ];
  }

  /// Create border radius for consistent UI
  static BorderRadius getBorderRadius({double radius = 8}) {
    return BorderRadius.circular(radius);
  }

  /// Status icon for quick visual identification
  static IconData getStatusIcon(ParentStatus status) {
    switch (status) {
      case ParentStatus.normal:
        return Icons.check_circle;
      case ParentStatus.caution:
        return Icons.warning;
      case ParentStatus.warning:
        return Icons.error_outline;
      case ParentStatus.emergency:
        return Icons.error;
    }
  }

  /// Get human-readable status text
  static String getStatusText(ParentStatus status) {
    switch (status) {
      case ParentStatus.normal:
        return 'Active';
      case ParentStatus.caution:
        return 'Attention';
      case ParentStatus.warning:
        return 'Warning';
      case ParentStatus.emergency:
        return 'Emergency';
    }
  }

  // ================== NAVIGATION TRANSITIONS ==================

  /// Standard slide transition for consistent navigation
  static PageRouteBuilder<T> slideTransition<T extends Object?>({
    required Widget page,
    RouteSettings? settings,
    bool rightToLeft = true,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final begin = rightToLeft
            ? const Offset(1.0, 0.0)
            : const Offset(0.0, 1.0);
        final end = Offset.zero;

        final slideTween = Tween(begin: begin, end: end);
        final slideAnimation = animation.drive(
          slideTween.chain(CurveTween(curve: Curves.easeInOut)),
        );

        // Add fade transition for smoothness
        final fadeAnimation = animation.drive(
          Tween(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeInOut)),
        );

        return SlideTransition(
          position: slideAnimation,
          child: FadeTransition(opacity: fadeAnimation, child: child),
        );
      },
    );
  }
}
