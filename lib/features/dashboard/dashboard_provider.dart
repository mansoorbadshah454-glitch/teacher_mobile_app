import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  try {
    print('DashboardProvider: Fetching teacher data for ${user.uid}...');
    final doc = await FirebaseFirestore.instance
        .collection('teachers') // Assuming collection name is 'teachers'
        .doc(user.uid)
        .get();
    
    if (doc.exists) {
        print('DashboardProvider: Data found: ${doc.data()}');
        return doc.data();
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
