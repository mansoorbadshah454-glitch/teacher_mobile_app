import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

// Provides a combined list of Admins (Principal + School Admins)
final adminsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final teacherData = await ref.watch(teacherDataProvider.future);
  if (teacherData == null || !teacherData.containsKey('schoolId')) return [];

  final schoolId = teacherData['schoolId'];
  List<Map<String, dynamic>> adminsList = [];

  try {
    print('AdminDataProvider: Fetching admin profiles for school $schoolId');
    
    // 1. Fetch Principal from School Root or Settings
    final schoolDoc = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .get();

    String principalName = 'Principal';
    String principalLogo = '';

    if (schoolDoc.exists) {
        final data = schoolDoc.data()!;
        if (data.containsKey('principalName')) {
            principalName = data['principalName'];
        } else if (data.containsKey('name')) {
             // Fallback
             principalName = data['name'];
        }
        
        if (data.containsKey('logo')) {
            principalLogo = data['logo'];
        } else if (data.containsKey('profileImage')) {
            principalLogo = data['profileImage'];
        }

        // Try looking in settings/profile as a fallback
        try {
            final settingsDoc = await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('settings')
                .doc('profile')
                .get();
            if (settingsDoc.exists) {
                final settingsData = settingsDoc.data()!;
                if (settingsData.containsKey('profileImage') && principalLogo.isEmpty) {
                    principalLogo = settingsData['profileImage'];
                }
            }
        } catch (e) {
            print('AdminDataProvider: Could not fetch settings/profile for school logo: $e');
        }
    }

    adminsList.add({
        'id': 'principal', // special ID matched by db rules/web app
        'name': principalName,
        'role': 'Principal',
        'photo': principalLogo,
        'type': 'principal',
    });

    // 2. Fetch other Admin users
    final adminsQuery = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('admin_users')
        .where('role', isEqualTo: 'school Admin')
        .get();

    for (var doc in adminsQuery.docs) {
        final data = doc.data();
        adminsList.add({
            'id': doc.id,
            'name': data['displayName'] ?? data['name'] ?? 'Admin',
            'role': 'Admin',
            'photo': data['profileImage'] ?? '',
            'type': 'admin',
        });
    }

    return adminsList;
  } catch (e, st) {
    print('Error fetching admins data: $e');
    print(st);
    return [];
  }
});
