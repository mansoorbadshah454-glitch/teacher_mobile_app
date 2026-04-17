import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.person_outline, color: isDarkBackground ? Colors.white : Colors.black87),
            title: Text("Profile", style: TextStyle(color: isDarkBackground ? Colors.white : Colors.black87)),
            onTap: () => context.push('/profile'),
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
    );
  }
}
