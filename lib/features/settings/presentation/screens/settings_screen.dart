import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;
    final isDarkBackground = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: Icon(Icons.person_outline, color: isDarkBackground ? Colors.white : Colors.black87),
                  title: Text("Profile", style: TextStyle(color: isDarkBackground ? Colors.white : Colors.black87)),
                  onTap: () => context.push('/profile'),
                ),
                Divider(color: isDarkBackground ? Colors.white24 : Colors.black12),
                ListTile(
                  leading: const Icon(Icons.document_scanner_rounded, color: Color(0xFF10b981)),
                  title: Text(
                    "Scan Book Index (Syllabus)",
                    style: TextStyle(
                      color: isDarkBackground ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    "Snap book index page to auto-add chapters",
                    style: TextStyle(
                      color: isDarkBackground ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: isDarkBackground ? Colors.white54 : Colors.black45,
                  ),
                  onTap: () => context.push('/scan-book-index'),
                ),
                Divider(color: isDarkBackground ? Colors.white24 : Colors.black12),
                SwitchListTile(
                  title: Text("Dark Mode", style: TextStyle(color: isDarkBackground ? Colors.white : Colors.black87)),
                  secondary: Icon(Icons.dark_mode, color: isDarkBackground ? Colors.white : Colors.black87),
                  value: isDarkMode,
                  onChanged: (val) {
                    ref.read(themeProvider.notifier).toggleTheme(val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Theme set to ${val ? 'Dark' : 'Light'}")),
                    );
                  },
                  activeColor: AppTheme.primary,
                ),
                Divider(color: isDarkBackground ? Colors.white24 : Colors.black12),
                ListTile(
                  leading: Icon(Icons.info_outline, color: isDarkBackground ? Colors.white : Colors.black87),
                  title: Text("About App", style: TextStyle(color: isDarkBackground ? Colors.white : Colors.black87)),
                  subtitle: Text("Version 1.0.0", style: TextStyle(color: isDarkBackground ? Colors.white54 : Colors.black54)),
                ),
              ],
            ),
          ),

          // Sticky Bottom Watermark Footer (Exact Parent App Style)
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isDarkBackground ? const Color(0xFF1E293B) : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: isDarkBackground ? Colors.white12 : Colors.grey.shade200,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_user_rounded, size: 12, color: AppTheme.primary),
                      const SizedBox(width: 5),
                      Text(
                        'POWERED BY',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: isDarkBackground ? Colors.white60 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'MAI TECH (SMC-PVT) LTD',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDarkBackground ? Colors.white : Colors.black87,
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v1.0.0 • Secure School Cloud',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      color: isDarkBackground ? Colors.white54 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
