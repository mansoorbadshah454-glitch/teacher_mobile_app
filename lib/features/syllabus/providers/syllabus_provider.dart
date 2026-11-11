import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';

// Represents a unique Syllabus Assignment for a teacher
class SyllabusAssignment {
  final String className;
  final String subject;

  SyllabusAssignment({required this.className, required this.subject});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyllabusAssignment &&
          runtimeType == other.runtimeType &&
          className == other.className &&
          subject == other.subject;

  @override
  int get hashCode => className.hashCode ^ subject.hashCode;
}

// 1. Extracts unique {class, subject} pairs from the Timetable
final mySyllabusesProvider = Provider<AsyncValue<List<SyllabusAssignment>>>((ref) {
  final timetableAsync = ref.watch(timetableProvider);

  return timetableAsync.when(
    data: (slots) {
      final assignments = <SyllabusAssignment>{};
      
      for (var slot in slots) {
        if (!slot.isFree && !slot.isBreak && slot.className.isNotEmpty && slot.subject.isNotEmpty) {
          assignments.add(SyllabusAssignment(
            className: slot.className,
            subject: slot.subject,
          ));
        }
      }

      final sortedList = assignments.toList()
        ..sort((a, b) {
          int classCompare = a.className.compareTo(b.className);
          if (classCompare != 0) return classCompare;
          return a.subject.compareTo(b.subject);
        });

      return AsyncValue.data(sortedList);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

// Helper for safe timestamp comparison
int _compareTimes(dynamic a, dynamic b) {
  int aMs = 0;
  int bMs = 0;
  if (a is Timestamp) aMs = a.millisecondsSinceEpoch;
  else if (a is DateTime) aMs = a.millisecondsSinceEpoch;
  else if (a is String) aMs = DateTime.tryParse(a)?.millisecondsSinceEpoch ?? 0;

  if (b is Timestamp) bMs = b.millisecondsSinceEpoch;
  else if (b is DateTime) bMs = b.millisecondsSinceEpoch;
  else if (b is String) bMs = DateTime.tryParse(b)?.millisecondsSinceEpoch ?? 0;

  return aMs.compareTo(bMs);
}

// Helper to generate default dummy chapters for testing when Firestore is empty
List<Map<String, dynamic>> _buildDefaultDummyChapters(String subject) {
  final sub = subject.trim();
  return [
    {
      'id': 'dummy_ch_1',
      'title': 'Introduction to $sub',
      'status': 'Completed',
      'time': '1 Week',
      'topics': ['Basic Concepts', 'Core Definitions', 'Summary & Review'],
      'createdAt': '2026-01-01T08:00:00.000Z',
    },
    {
      'id': 'dummy_ch_2',
      'title': 'Fundamental Principles & Rules',
      'status': 'Completed',
      'time': '2 Weeks',
      'topics': ['Key Theories', 'Solved Examples', 'Class Worksheet'],
      'createdAt': '2026-01-02T08:00:00.000Z',
    },
    {
      'id': 'dummy_ch_3',
      'title': 'Core Methods & Applications',
      'status': 'In Progress',
      'time': '2 Weeks',
      'topics': ['Step-by-step Practice', 'Real-world Problems', 'Q&A Session'],
      'createdAt': '2026-01-03T08:00:00.000Z',
    },
    {
      'id': 'dummy_ch_4',
      'title': 'Advanced Concepts & Analysis',
      'status': 'Pending',
      'time': '2 Weeks',
      'topics': ['Deep Dive', 'Case Studies', 'Group Activity'],
      'createdAt': '2026-01-04T08:00:00.000Z',
    },
    {
      'id': 'dummy_ch_5',
      'title': 'Practical Exercises & Lab Work',
      'status': 'Pending',
      'time': '1 Week',
      'topics': ['Hands-on Practice', 'Assessment Tasks'],
      'createdAt': '2026-01-05T08:00:00.000Z',
    },
    {
      'id': 'dummy_ch_6',
      'title': 'Final Revision & Past Papers',
      'status': 'Pending',
      'time': '1 Week',
      'topics': ['Full Syllabus Review', 'Mock Test Preparation'],
      'createdAt': '2026-01-06T08:00:00.000Z',
    },
  ];
}

// 3. Fetch Syllabus Chapters for a specific Class and Subject (REAL-TIME STREAM WITH OFFLINE CACHE)
final syllabusChaptersProvider = StreamProvider.family<List<Map<String, dynamic>>, SyllabusAssignment>((ref, assignment) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    yield _buildDefaultDummyChapters(assignment.subject);
    return;
  }

  final schoolId = teacherData['schoolId'] as String;
  final cacheKey = 'syllabus_chapters_${schoolId}_${assignment.className}_${assignment.subject}';

  // 1. Immediately yield cached chapters offline
  final cached = LocalDbService.getCache(cacheKey);
  if (cached is List && cached.isNotEmpty) {
    try {
      final list = cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      yield list;
    } catch (_) {}
  }

  String classId = '';
  try {
    final classSnapshot = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('name', isEqualTo: assignment.className)
        .limit(1)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(const Duration(seconds: 3));

    if (classSnapshot.docs.isNotEmpty) {
      classId = classSnapshot.docs.first.id;
    } else {
      final allClasses = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));

      final cleanAssignName = assignment.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      for (var cDoc in allClasses.docs) {
        final cName = (cDoc.data()['name'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        if (cName == cleanAssignName || cDoc.id.toLowerCase() == cleanAssignName) {
          classId = cDoc.id;
          break;
        }
      }
    }
  } catch (e) {
    debugPrint('Error finding class for syllabus: $e');
  }

  if (classId.isEmpty) {
    final fallback = _buildDefaultDummyChapters(assignment.subject);
    await LocalDbService.saveCache(cacheKey, fallback);
    yield fallback;
    return;
  }

  final chaptersCollection = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .doc(classId)
      .collection('syllabus')
      .doc(assignment.subject)
      .collection('chapters');

  final chaptersStream = chaptersCollection
      .snapshots()
      .handleError((e) {
        debugPrint('Syllabus chapters stream error suppressed: $e');
      });

  bool seededDummy = false;

  await for (final snapshot in chaptersStream) {
    if (snapshot.docs.isEmpty && !seededDummy) {
      seededDummy = true;
      final dummyList = _buildDefaultDummyChapters(assignment.subject);
      await LocalDbService.saveCache(cacheKey, dummyList);
      yield dummyList;

      // Also seed into Firestore so tapping the status toggle button works seamlessly
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final ch in dummyList) {
          final docRef = chaptersCollection.doc(ch['id'] as String);
          batch.set(docRef, {
            'title': ch['title'],
            'status': ch['status'],
            'time': ch['time'],
            'topics': ch['topics'],
            'createdAt': ch['createdAt'],
          });
        }
        await batch.commit();
      } catch (e) {
        debugPrint('Failed to auto-seed dummy chapters to Firestore: $e');
      }
      continue;
    }

    final docs = snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();

    // Sort locally by createdAt if available safely
    docs.sort((a, b) => _compareTimes(a['createdAt'], b['createdAt']));

    await LocalDbService.saveCache(cacheKey, docs);
    yield docs;
  }
});

// 4. Update Chapter Status
class SyllabusService {
  final Ref ref;
  SyllabusService(this.ref);

  Future<void> toggleChapterStatus(SyllabusAssignment assignment, String chapterId, String currentStatus) async {
    final teacherData = ref.read(teacherDataProvider).value;
    if (teacherData == null || !teacherData.containsKey('schoolId')) return;

    final schoolId = teacherData['schoolId'] as String;
    String classId = '';

    try {
      final classSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .where('name', isEqualTo: assignment.className)
          .limit(1)
          .get();

      if (classSnapshot.docs.isNotEmpty) {
        classId = classSnapshot.docs.first.id;
      } else {
        final allClasses = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .get();

        final cleanAssignName = assignment.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        for (var cDoc in allClasses.docs) {
          final cName = (cDoc.data()['name'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          if (cName == cleanAssignName || cDoc.id.toLowerCase() == cleanAssignName) {
            classId = cDoc.id;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error finding class for toggleChapterStatus: $e');
    }

    String newStatus;
    if (currentStatus == 'Pending') {
      newStatus = 'In Progress';
    } else if (currentStatus == 'In Progress') {
      newStatus = 'Completed';
    } else {
      newStatus = 'Pending';
    }

    // Update local cache immediately so UI works 100% offline & instantaneously
    final cacheKey = 'syllabus_chapters_${schoolId}_${assignment.className}_${assignment.subject}';
    final cached = LocalDbService.getCache(cacheKey);
    if (cached is List) {
      final updatedCache = cached.map((e) {
        final item = Map<String, dynamic>.from(e as Map);
        if (item['id'] == chapterId) {
          item['status'] = newStatus;
        }
        return item;
      }).toList();
      await LocalDbService.saveCache(cacheKey, updatedCache);
    }

    if (classId.isEmpty) return;

    FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('syllabus')
        .doc(assignment.subject)
        .collection('chapters')
        .doc(chapterId)
        .set({'status': newStatus}, SetOptions(merge: true))
        .catchError((e) {
      debugPrint('toggleChapterStatus queued/error: $e');
    });
  }

  /// Saves scanned Book Index chapters to Offline Cache + Firestore (and removes dummy chapters)
  Future<void> saveScannedChapters({
    required SyllabusAssignment assignment,
    required List<Map<String, dynamic>> scannedChapters,
    bool replaceExisting = true,
  }) async {
    final teacherData = ref.read(teacherDataProvider).value;
    if (teacherData == null || !teacherData.containsKey('schoolId')) {
      throw Exception('Teacher school data not loaded.');
    }

    final schoolId = teacherData['schoolId'] as String;
    final cacheKey = 'syllabus_chapters_${schoolId}_${assignment.className}_${assignment.subject}';
    final baseTimeMs = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;

    final List<Map<String, dynamic>> formattedList = [];
    for (int i = 0; i < scannedChapters.length; i++) {
      final ch = scannedChapters[i];
      final num = i + 1;
      final title = (ch['title'] ?? 'Chapter $num').toString().trim();
      final slugTitle = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final safeSlug = slugTitle.isEmpty
          ? 'chapter_$num'
          : (slugTitle.length > 28 ? slugTitle.substring(0, 28) : slugTitle);
      final docId = 'ch_${num}_$safeSlug';
      final createdAtIso = DateTime.fromMillisecondsSinceEpoch(
        baseTimeMs + (num * 60 + i) * 1000,
        isUtc: true,
      ).toIso8601String();

      final topics = (ch['topics'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          <String>[];

      formattedList.add({
        'id': docId,
        'title': title,
        'status': (ch['status'] ?? 'Pending').toString(),
        'time': (ch['time'] ?? '2 Weeks').toString(),
        'topics': topics,
        'createdAt': createdAtIso,
      });
    }

    // 1. Save immediately to LocalDbService for 0ms offline access
    await LocalDbService.saveCache(cacheKey, formattedList);
    ref.invalidate(syllabusChaptersProvider(assignment));

    // 2. Resolve classId & sync to Firestore (works with Firestore offline persistence too)
    String classId = '';
    try {
      final classSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .where('name', isEqualTo: assignment.className)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));

      if (classSnapshot.docs.isNotEmpty) {
        classId = classSnapshot.docs.first.id;
      } else {
        final allClasses = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 3));

        final cleanAssignName = assignment.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        for (var cDoc in allClasses.docs) {
          final cName = (cDoc.data()['name'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          if (cName == cleanAssignName || cDoc.id.toLowerCase() == cleanAssignName) {
            classId = cDoc.id;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error resolving classId in saveScannedChapters: $e');
    }

    if (classId.isEmpty) return;

    final chaptersCol = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('syllabus')
        .doc(assignment.subject)
        .collection('chapters');

    final batch = FirebaseFirestore.instance.batch();

    // Remove old dummy chapters or existing chapters if replaceExisting is true
    try {
      final existingSnap = await chaptersCol
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));
      for (final doc in existingSnap.docs) {
        if (replaceExisting || doc.id.startsWith('dummy_ch_')) {
          batch.delete(doc.reference);
        }
      }
    } catch (_) {
      // Even if offline get fails, explicitly delete known dummy IDs
      for (int d = 1; d <= 6; d++) {
        batch.delete(chaptersCol.doc('dummy_ch_$d'));
      }
    }

    // Queue all new chapters in the batch
    for (final ch in formattedList) {
      final docRef = chaptersCol.doc(ch['id'] as String);
      batch.set(docRef, {
        'title': ch['title'],
        'status': ch['status'],
        'time': ch['time'],
        'topics': ch['topics'],
        'createdAt': ch['createdAt'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Commit without blocking forever if offline (Firestore queues batch offline automatically)
    batch.commit().catchError((e) {
      debugPrint('Batch commit queued/error: $e');
    });
  }
}

final syllabusServiceProvider = Provider((ref) => SyllabusService(ref));
