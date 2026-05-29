import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────

class AppColors {
  // Primary palette
  static const Color primary = Color(0xFF1A3C6E);        // Deep navy
  static const Color primaryLight = Color(0xFF2A5298);
  static const Color primaryDark = Color(0xFF0D2044);

  // Secondary
  static const Color secondary = Color(0xFF10B981);       // Emerald green
  static const Color secondaryLight = Color(0xFF34D399);
  static const Color secondaryDark = Color(0xFF059669);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Emergency
  static const Color emergency = Color(0xFFDC2626);
  static const Color emergencyBg = Color(0xFFFEF2F2);

  // Trust levels
  static const Color bronze = Color(0xFFCD7F32);
  static const Color silver = Color(0xFFA8A9AD);
  static const Color gold = Color(0xFFF59E0B);
  static const Color platinum = Color(0xFF7C3AED);

  // Neutral
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF9FAFB);
  static const Color surfaceVariant = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF1F5F9);

  // Text
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFD1D5DB);

  // Background
  static const Color background = Color(0xFFF9FAFB);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1A3C6E), Color(0xFF2A5298)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient trustGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Task status colors
  static Color taskStatusColor(String status) {
    switch (status) {
      case 'posted': return const Color(0xFF3B82F6);
      case 'agents_applied': return const Color(0xFF8B5CF6);
      case 'accepted': return const Color(0xFF10B981);
      case 'in_progress': return const Color(0xFFF59E0B);
      case 'proof_submitted': return const Color(0xFF06B6D4);
      case 'completed': return const Color(0xFF10B981);
      case 'disputed': return const Color(0xFFEF4444);
      case 'cancelled': return const Color(0xFF6B7280);
      case 'expired': return const Color(0xFF9CA3AF);
      default: return const Color(0xFF6B7280);
    }
  }

  static Color trustLevelColor(String level) {
    switch (level) {
      case 'bronze': return bronze;
      case 'silver': return silver;
      case 'gold': return gold;
      case 'platinum': return platinum;
      default: return bronze;
    }
  }
}

// ─── Spacing ──────────────────────────────────────────────────────────────────

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 20.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(vertical: 12.0);
}

// ─── Border Radius ────────────────────────────────────────────────────────────

class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 999.0;

  static BorderRadius get cardRadius => BorderRadius.circular(md);
  static BorderRadius get buttonRadius => BorderRadius.circular(lg);
  static BorderRadius get chipRadius => BorderRadius.circular(full);
  static BorderRadius get inputRadius => BorderRadius.circular(sm);
}

// ─── Text Styles ─────────────────────────────────────────────────────────────

class AppTextStyles {
  // Display
  static TextStyle get displayLarge => GoogleFonts.poppins(
    fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2,
  );
  static TextStyle get displayMedium => GoogleFonts.poppins(
    fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2,
  );

  // Headings
  static TextStyle get h1 => GoogleFonts.poppins(
    fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static TextStyle get h2 => GoogleFonts.poppins(
    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static TextStyle get h3 => GoogleFonts.poppins(
    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );

  // Body
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5,
  );
  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5,
  );
  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4,
  );

  // Labels
  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary,
  );
  static TextStyle get labelMedium => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary,
  );
  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary,
    letterSpacing: 0.4,
  );

  // Trust score — uses Poppins for impact
  static TextStyle get trustScore => GoogleFonts.poppins(
    fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.primary,
  );
  static TextStyle get trustLabel => GoogleFonts.poppins(
    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8,
  );

  // Amount — money displays
  static TextStyle get amountLarge => GoogleFonts.poppins(
    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
  );
  static TextStyle get amountMedium => GoogleFonts.poppins(
    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.primary,
  );

  // Buttons
  static TextStyle get buttonLarge => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.white,
  );
  static TextStyle get buttonMedium => GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.white,
  );
}

// ─── Shadows ──────────────────────────────────────────────────────────────────

class AppShadows {
  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get elevated => [
    BoxShadow(
      color: Colors.black.withOpacity(0.10),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get subtle => [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 8,
      offset: const Offset(0, 1),
    ),
  ];
}

// ─── Theme ────────────────────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.h2,
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        textStyle: AppTextStyles.buttonLarge,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        side: const BorderSide(color: AppColors.primary),
        textStyle: AppTextStyles.buttonLarge.copyWith(color: AppColors.primary),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textTertiary),
      labelStyle: AppTextStyles.labelMedium,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );
}
