import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';

class TimetableSlot {
  final String time;
  final String period;
  final String className;
  final String subject;
  final bool isFree;
  final bool isBreak;

  TimetableSlot({
    required this.time,
    required this.period,
    required this.className,
    required this.subject,
    this.isFree = false,
    this.isBreak = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'time': time,
      'period': period,
      'className': className,
      'subject': subject,
      'isFree': isFree,
      'isBreak': isBreak,
    };
  }

  factory TimetableSlot.fromMap(Map<String, dynamic> map) {
    return TimetableSlot(
      time: map['time'] as String? ?? '',
      period: map['period'] as String? ?? '',
      className: map['className'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      isFree: map['isFree'] as bool? ?? false,
      isBreak: map['isBreak'] as bool? ?? false,
    );
  }
}

// 1. Live Firestore Timetable Stream
final schoolSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
    yield {};
    return;
  }

  final String schoolId = teacherData['schoolId'];
  final cacheKey = 'school_settings_$schoolId';

  final cached = LocalDbService.getCache(cacheKey);
  if (cached != null && cached is Map) {
    yield Map<String, dynamic>.from(cached);
  }

  final stream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('settings')
      .doc('profile')
      .snapshots();

  await for (final snapshot in stream) {
    if (snapshot.exists && snapshot.data() != null) {
      final data = snapshot.data() as Map<String, dynamic>;
      await LocalDbService.saveCache(cacheKey, data);
      yield data;
    }
  }
});

// 2. Live Firestore Timetable Stream with Hive Offline Persistence
final timetableProvider = StreamProvider<List<TimetableSlot>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (user == null) {
    yield [];
    return;
  }

  final cacheKey = 'timetable_${user.uid}';

  // 1. Immediately yield cached timetable so teacher sees today's periods offline instantly
  final cachedRaw = LocalDbService.getCache(cacheKey);
  if (cachedRaw != null && cachedRaw is List && cachedRaw.isNotEmpty) {
    final cachedSlots = cachedRaw
        .map((e) => TimetableSlot.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    yield cachedSlots;
  }

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    if (cachedRaw == null) yield [];
    return;
  }

  final String schoolId = teacherData['schoolId'];

  final stream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('timetables')
      .doc('weeklyMaster')
      .snapshots();

  await for (final snapshot in stream) {
    if (!snapshot.exists || snapshot.data() == null) {
      if (cachedRaw == null) yield <TimetableSlot>[];
      continue;
    }

    final data = snapshot.data()!;
    final List<dynamic> cols = data['cols'] ?? [];
    final List<dynamic> rows = data['rows'] ?? [];

    final myRow = rows.firstWhere(
      (r) => r != null && (r as Map)['teacherId'] == user.uid,
      orElse: () => <String, dynamic>{},
    );

    if (myRow == null || (myRow as Map).isEmpty) {
      if (cachedRaw == null) yield <TimetableSlot>[];
      continue;
    }

    final List<dynamic> cells = myRow['cells'] ?? [];
    final List<TimetableSlot> slots = [];

    for (var i = 0; i < cells.length; i++) {
      if (i >= cols.length) break;
      final cell = cells[i];
      final className = cell['class'] as String? ?? '';
      final subject = cell['subject'] as String? ?? '';
      final timeStr = cols[i] as String;

      final isFree = className.isEmpty || className == 'FREE';
      final isBreak = className == 'BREAK';

      slots.add(TimetableSlot(
        time: timeStr,
        period: 'P${i + 1}',
        className: className,
        subject: subject,
        isFree: isFree,
        isBreak: isBreak,
      ));
    }

    // Save to Hive cache
    await LocalDbService.saveCache(cacheKey, slots.map((s) => s.toMap()).toList());
    yield slots;
  }
});

// 3. Emergency Notification Badge Logic
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
