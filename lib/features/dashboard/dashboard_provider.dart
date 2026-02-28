import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
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
