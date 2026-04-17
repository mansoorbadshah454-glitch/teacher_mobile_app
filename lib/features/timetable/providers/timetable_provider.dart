import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

class TimetableSlot {
  final String time;
  final String period;
  final String className;
  final String subject;
  final bool isFree;

  TimetableSlot({
    required this.time,
    required this.period,
    required this.className,
    required this.subject,
    this.isFree = false,
  });
}

// 1. Live Firestore Timetable Stream
final timetableProvider = StreamProvider<List<TimetableSlot>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
    yield [];
    return;
  }

  final String schoolId = teacherData['schoolId'];

  final stream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('timetables')
      .doc('weeklyMaster')
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) return <TimetableSlot>[];
    
    final data = snapshot.data()!;
    final List<dynamic> cols = data['cols'] ?? [];
    final List<dynamic> rows = data['rows'] ?? [];

    // Find row belonging to current teacher
    final myRow = rows.firstWhere(
      (r) => r['teacherId'] == user.uid,
      orElse: () => null,
    );

    if (myRow == null) return <TimetableSlot>[];

    final List<dynamic> cells = myRow['cells'] ?? [];
    final List<TimetableSlot> slots = [];

    for (var i = 0; i < cells.length; i++) {
      if (i >= cols.length) break; // safeguard against mismatched lengths
      final cell = cells[i];
      final className = cell['class'] as String? ?? '';
      final subject = cell['subject'] as String? ?? '';
      final timeStr = cols[i] as String;
      
      final isFree = className.isEmpty || className == 'FREE' || className == 'BREAK';

      slots.add(TimetableSlot(
        time: timeStr,
        // Calculate period mapping correctly (1-based index)
        period: 'P${i + 1}',
        className: className,
        subject: subject,
        isFree: isFree,
      ));
    }
    return slots;
  });

  yield* stream;
});

// 2. Emergency Notification Badge Logic
// We use a StateNotifier to handle SharedPreferences persistence for emergency unread badge
class EmergencyBadgeNotifier extends StateNotifier<String?> {
  EmergencyBadgeNotifier() : super(null) {
    _loadState();
  }

  static const String _prefKey = 'timetable_emergency_message';
  static const String _dateKey = 'timetable_emergency_date';

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDateStr = prefs.getString(_dateKey);
    
    if (savedDateStr != null) {
       final savedDate = DateTime.tryParse(savedDateStr);
       final now = DateTime.now();
       if (savedDate != null && (savedDate.year != now.year || savedDate.month != now.month || savedDate.day != now.day)) {
          // It's a new day! Clear the outdated emergency alert gracefully.
          await clearEmergency();
          return;
       }
    }
    
    state = prefs.getString(_prefKey);
  }

  Future<void> reload() async {
    await _loadState();
  }

  Future<void> setEmergency(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, message);
    await prefs.setString(_dateKey, DateTime.now().toIso8601String());
    state = message;
  }

  Future<void> clearEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_dateKey);
    state = null;
  }
}

final emergencyBadgeProvider = StateNotifierProvider<EmergencyBadgeNotifier, String?>((ref) {
  return EmergencyBadgeNotifier();
});

final hasUnreadEmergencyProvider = Provider<bool>((ref) {
  return ref.watch(emergencyBadgeProvider) != null;
});
