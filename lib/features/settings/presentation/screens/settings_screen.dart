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
        title: const Text("Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
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
