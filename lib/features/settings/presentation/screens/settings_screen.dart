import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool isDarkMode = true; // Mock state

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
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
            title: const Text("Dark Mode", style: TextStyle(color: Colors.white)),
            secondary: const Icon(Icons.dark_mode, color: Colors.white),
            value: isDarkMode,
            onChanged: (val) {
              setState(() {
                isDarkMode = val;
                // Add actual theme toggle logic here later (e.g. Riverpod provider)
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Theme set to ${val ? 'Dark' : 'Light'} (UI Mock)")),
              );
            },
            activeColor: AppTheme.primary,
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text("About App", style: TextStyle(color: Colors.white)),
            subtitle: const Text("Version 1.0.0", style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
