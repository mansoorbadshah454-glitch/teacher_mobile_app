
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  try {
    print('DashboardProvider: Fetching teacher data for ${user.uid}...');
    final teacherData = await ref.read(teacherDataProvider.future);
    
    if (teacherData != null) {
        print('DashboardProvider: Data found: $teacherData');
        return teacherData;
    } else {
        print('DashboardProvider: No teacher document found!');
        return null;
    }
  } catch (e, st) {
    print('DashboardProvider: Error fetching data: $e');
    print(st);
    throw e;
  }
});
