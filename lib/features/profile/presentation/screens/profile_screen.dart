import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teacherAsync = ref.watch(teacherDataProvider);
    final schoolAsync = ref.watch(schoolDataProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text("My Profile"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: teacherAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
        data: (teacherData) {
          final teacher = teacherData ?? {};
          final tName = teacher['name'] ?? 'Teacher';
          final tEmail = teacher['email'] ?? 'teacher@example.com';
          final tPhone = teacher['phone'] ?? '+1 (555) 000-0000';
          
          List<dynamic> classesList = teacher['assignedClasses'] ?? [];
          List<dynamic> subjectsList = teacher['subjects'] ?? [];

          return schoolAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
            data: (schoolData) {
              final school = schoolData ?? {};
              final logoUrl = school['logo'] ?? '';
              final schoolName = school['name'] ?? 'School Name';

              return SingleChildScrollView(
                child: Column(
                  children: [
                    // --- Header Area ---
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                      padding: const EdgeInsets.only(top: 20, bottom: 40),
                      child: Column(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            backgroundImage: logoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(logoUrl)
                                : null,
                            child: logoUrl.isEmpty
                                ? const Icon(Icons.school, size: 50, color: AppTheme.primary)
                                : null,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            tName,
                            style: AppTheme.displayLarge.copyWith(fontSize: 26, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            schoolName,
                            style: const TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),

                    // --- Card Content Area ---
                    Transform.translate(
                      offset: const Offset(0, -20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.background,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Contact Information",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(Icons.email, "Email", tEmail, isDark),
                            const Divider(height: 24),
                            _buildInfoRow(Icons.phone, "Phone", tPhone, isDark),
                            const SizedBox(height: 32),

                            Text(
                              "Academic Details",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                            const SizedBox(height: 16),
                            _buildChipRow("Assigned Classes", classesList.isNotEmpty ? classesList : ["Unassigned"], isDark),
                            const SizedBox(height: 16),
                            _buildChipRow("Subjects", subjectsList.isNotEmpty ? subjectsList : ["General"], isDark),


                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600])),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChipRow(String title, List<dynamic> items, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[400] : Colors.grey[600])),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            return Chip(
              label: Text(item.toString()),
              backgroundColor: isDark ? Colors.grey[800] : Colors.white,
              labelStyle: TextStyle(color: isDark ? Colors.white : AppTheme.primary, fontWeight: FontWeight.bold),
              side: BorderSide(color: isDark ? Colors.grey[700]! : AppTheme.primary, width: 1.5),
            );
          }).toList(),
        ),
      ],
    );
  }
}
