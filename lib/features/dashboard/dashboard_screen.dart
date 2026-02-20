import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/dashboard/dashboard_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    print('DashboardScreen: Building...'); // LOG
    final teacherAsync = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
               print('DashboardScreen: Logout pressed'); // LOG
               await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: teacherAsync.when(
        data: (data) {
          print('DashboardScreen: Data loaded: $data'); // LOG
          final name = data?['name'] ?? 'Teacher';
          final email = data?['email'] ?? 'No Email';
          
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.school, size: 80, color: Colors.blue),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome, $name!',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildStatCard(context, 'Total Classes', '0', Icons.class_),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(
          child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               CircularProgressIndicator(),
               SizedBox(height: 16),
               Text('Loading Teacher Profile...'),
             ],
          ),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 const Icon(Icons.error_outline, size: 48, color: Colors.red),
                 const SizedBox(height: 16),
                 Text('Error loading dashboard: $err'),
                 const SizedBox(height: 16),
                 ElevatedButton(
                   onPressed: () => ref.refresh(dashboardProvider),
                   child: const Text('Retry'),
                 ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Theme.of(context).primaryColor),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
