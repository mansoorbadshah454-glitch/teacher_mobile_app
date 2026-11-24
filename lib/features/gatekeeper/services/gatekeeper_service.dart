import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';

enum GateScanMode { entry, exit }

enum GateScanOutcome {
  successOnline,
  successOfflineQueued,
  alreadyScanned,
  wrongSchool,
  studentNotFound,
  invalidQr,
}

class GateScanResult {
  final GateScanOutcome outcome;
  final String message;
  final Map<String, dynamic>? student;
  final String? timeFormatted;
  final GateScanMode mode;

  const GateScanResult({
    required this.outcome,
    required this.message,
    this.student,
    this.timeFormatted,
    required this.mode,
  });
}

class GatekeeperService {
  GatekeeperService._();
  static final GatekeeperService instance = GatekeeperService._();

  static bool _isConnectivityListening = false;
  static StreamSubscription<List<ConnectivityResult>>? _connSub;
  static bool _isFlushing = false;

  /// In-memory fast O(1) lookup map: studentId -> student map
  final Map<String, Map<String, dynamic>> _studentsById = {};
  String? _activeSchoolId;

  final ValueNotifier<int> cachedStudentsCount = ValueNotifier<int>(0);
  final ValueNotifier<int> pendingQueueCount = ValueNotifier<int>(0);
  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<List<Map<String, dynamic>>> recentScansNotifier =
      ValueNotifier<List<Map<String, dynamic>>>(<Map<String, dynamic>>[]);

  String _todayStr() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _timeStr([DateTime? dt]) => DateFormat('hh:mm a').format(dt ?? DateTime.now());

  String _studentsCacheKey(String schoolId) => 'gate_students_cache_$schoolId';
  String _queueCacheKey(String schoolId) => 'gate_offline_queue_$schoolId';
  String _todayLogsCacheKey(String schoolId) => 'gate_today_logs_${schoolId}_${_todayStr()}';

  /// Check whether the signed-in user has appRole == 'gatekeeper' (offline-first)
  static Future<bool> isGatekeeperUser(String uid, String schoolId) async {
    try {
      final cached = LocalDbService.getCache('teacher_profile_$uid');
      if (cached is Map) {
        final role = cached['appRole']?.toString().toLowerCase();
        if (role == 'gatekeeper') return true;
        if (role == 'teacher') return false;
      }

      final docSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (docSnap.exists && docSnap.data() != null) {
        final data = docSnap.data()!;
        final role = data['appRole']?.toString().toLowerCase() ?? 'teacher';
        await LocalDbService.saveCache('teacher_profile_$uid', {
          ...data,
          'uid': uid,
          'schoolId': schoolId,
        });
        return role == 'gatekeeper';
      }
    } catch (e) {
      debugPrint('⚠️ [GatekeeperService] isGatekeeperUser error: $e');
    }
    return false;
  }

  /// Initialize connectivity listener once (singleton pattern per release safety rules)
  Future<void> initForSchool(String schoolId) async {
    _activeSchoolId = schoolId;

    // 1. Hydrate students & today's logs immediately from local Hive cache (0ms offline ready)
    _hydrateFromLocalCache(schoolId);
    _updatePendingCount(schoolId);

    // 2. Check current connectivity
    try {
      isOnlineNotifier.value = await SyncQueueService.isOnline();
    } catch (_) {
      isOnlineNotifier.value = false;
    }

    // 3. Attach singleton connectivity listener for auto-sync
    if (!_isConnectivityListening) {
      _isConnectivityListening = true;
      _connSub = Connectivity().onConnectivityChanged.listen((results) {
        final online = results.any((r) => r != ConnectivityResult.none);
        isOnlineNotifier.value = online;
        if (online && _activeSchoolId != null) {
          syncPendingQueue(_activeSchoolId!);
        }
      });
    }

    // 4. Refresh cache & flush any pending offline scans if online
    if (isOnlineNotifier.value) {
      await syncAllSchoolStudents(schoolId);
      await syncPendingQueue(schoolId);
    }
  }

  void _hydrateFromLocalCache(String schoolId) {
    try {
      final rawList = LocalDbService.getCache(_studentsCacheKey(schoolId));
      _studentsById.clear();
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final id = map['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              _studentsById[id] = map;
            }
          }
        }
      }
      cachedStudentsCount.value = _studentsById.length;

      final rawLogs = LocalDbService.getCache(_todayLogsCacheKey(schoolId));
      if (rawLogs is List) {
        recentScansNotifier.value = rawLogs
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        recentScansNotifier.value = <Map<String, dynamic>>[];
      }
    } catch (e) {
      debugPrint('⚠️ [GatekeeperService] Local hydrate error: $e');
    }
  }

  void _updatePendingCount(String schoolId) {
    try {
      final raw = LocalDbService.getCache(_queueCacheKey(schoolId));
      if (raw is List) {
        pendingQueueCount.value = raw.length;
      } else {
        pendingQueueCount.value = 0;
      }
    } catch (_) {
      pendingQueueCount.value = 0;
    }
  }

  /// Download all students of the school and save to local Hive cache for 0ms offline scanning
  Future<int> syncAllSchoolStudents(String schoolId) async {
    try {
      final classesSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get();

      final List<Map<String, dynamic>> allStudents = [];
      final today = _todayStr();

      await Future.wait(classesSnap.docs.map((clsDoc) async {
        final clsData = clsDoc.data();
        final className = clsData['name']?.toString() ?? 'Class';
        final classId = clsDoc.id;

        final studentsSnap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .get();

        for (final stDoc in studentsSnap.docs) {
          final d = stDoc.data();
          final parentDetails = d['parentDetails'] is Map
              ? Map<String, dynamic>.from(d['parentDetails'] as Map)
              : <String, dynamic>{};

          final String parentId = parentDetails['parentId']?.toString() ??
              d['parentId']?.toString() ??
              '';
          final String fatherName = d['fatherName']?.toString() ??
              parentDetails['fatherName']?.toString() ??
              '';
          final String photo = d['avatar']?.toString() ??
              d['photoUrl']?.toString() ??
              d['image']?.toString() ??
              '';
          final String rollNo = (d['rollNo'] ?? d['rollNumber'] ?? '').toString();

          // Preserve local today check-in/out if offline scan hasn't synced yet
          final existingLocal = _studentsById[stDoc.id];
          final String? remoteIn = d['gateInDate'] == today ? d['gateInTime']?.toString() : null;
          final String? remoteOut = d['gateOutDate'] == today ? d['gateOutTime']?.toString() : null;
          final String? localIn = (existingLocal != null && existingLocal['gateInDate'] == today)
              ? existingLocal['gateInTime']?.toString()
              : null;
          final String? localOut = (existingLocal != null && existingLocal['gateOutDate'] == today)
              ? existingLocal['gateOutTime']?.toString()
              : null;

          allStudents.add({
            'id': stDoc.id,
            'classId': classId,
            'className': className,
            'name': d['name']?.toString() ?? 'Student',
            'fatherName': fatherName,
            'rollNo': rollNo,
            'photo': photo,
            'parentId': parentId,
            'gateInTime': localIn ?? remoteIn,
            'gateInDate': (localIn ?? remoteIn) != null ? today : null,
            'gateOutTime': localOut ?? remoteOut,
            'gateOutDate': (localOut ?? remoteOut) != null ? today : null,
            'lastAttendanceDate': d['lastAttendanceDate']?.toString() ?? '',
            'status': d['status']?.toString() ?? '',
          });
        }
      }));

      _studentsById.clear();
      for (final st in allStudents) {
        _studentsById[st['id'].toString()] = st;
      }

      await LocalDbService.saveCache(_studentsCacheKey(schoolId), allStudents);
      cachedStudentsCount.value = allStudents.length;
      debugPrint('✅ [Gatekeeper] Cached ${allStudents.length} students locally.');
      return allStudents.length;
    } catch (e) {
      debugPrint('⚠️ [Gatekeeper] syncAllSchoolStudents error: $e');
      return _studentsById.length;
    }
  }

  /// Parse QR code string generated by Principal App: SV5|<schoolId>|<classId>|<studentId>
  Map<String, String>? parseQrPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('SV5|')) {
      final parts = trimmed.split('|');
      if (parts.length >= 4) {
        return {
          'schoolId': parts[1].trim(),
          'classId': parts[2].trim(),
          'studentId': parts[3].trim(),
        };
      }
    }
    return null;
  }

  /// Process a scanned QR code (works 100% offline & online, sends live parent alert)
  Future<GateScanResult> processGateScan({
    required String rawQr,
    required String currentSchoolId,
    required GateScanMode mode,
    required String gatekeeperId,
    required String gatekeeperName,
  }) async {
    final parsed = parseQrPayload(rawQr);
    if (parsed == null) {
      return GateScanResult(
        outcome: GateScanOutcome.invalidQr,
        message: 'Invalid QR Code. Please scan an official Student ID Card.',
        mode: mode,
      );
    }

    final qrSchoolId = parsed['schoolId'] ?? '';
    final qrClassId = parsed['classId'] ?? '';
    final studentId = parsed['studentId'] ?? '';

    if (qrSchoolId != currentSchoolId) {
      return GateScanResult(
        outcome: GateScanOutcome.wrongSchool,
        message: 'This ID card belongs to a different school.',
        mode: mode,
      );
    }

    // Look up student in O(1) from local cache
    Map<String, dynamic>? student = _studentsById[studentId];

    // If not in local cache and online, try a direct single-doc fetch fallback
    if (student == null && qrClassId.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('schools')
            .doc(currentSchoolId)
            .collection('classes')
            .doc(qrClassId)
            .collection('students')
            .doc(studentId)
            .get();
        if (snap.exists && snap.data() != null) {
          final d = snap.data()!;
          final parentDetails = d['parentDetails'] is Map
              ? Map<String, dynamic>.from(d['parentDetails'] as Map)
              : <String, dynamic>{};
          student = {
            'id': studentId,
            'classId': qrClassId,
            'className': d['className']?.toString() ?? 'Class',
            'name': d['name']?.toString() ?? 'Student',
            'fatherName': d['fatherName']?.toString() ?? parentDetails['fatherName']?.toString() ?? '',
            'rollNo': (d['rollNo'] ?? d['rollNumber'] ?? '').toString(),
            'photo': d['avatar']?.toString() ?? d['photoUrl']?.toString() ?? '',
            'parentId': parentDetails['parentId']?.toString() ?? d['parentId']?.toString() ?? '',
          };
          _studentsById[studentId] = student;
          cachedStudentsCount.value = _studentsById.length;
        }
      } catch (_) {}
    }

    if (student == null) {
      return GateScanResult(
        outcome: GateScanOutcome.studentNotFound,
        message: 'Student not found. Tap "Sync Cache" to refresh student list.',
        mode: mode,
      );
    }

    final today = _todayStr();
    final now = DateTime.now();
    final formattedTime = _timeStr(now);

    // Duplicate Scan Protection for same mode on the same day
    if (mode == GateScanMode.entry &&
        student['gateInDate'] == today &&
        (student['gateInTime']?.toString().isNotEmpty ?? false)) {
      return GateScanResult(
        outcome: GateScanOutcome.alreadyScanned,
        message: 'Already Checked IN at ${student['gateInTime']}',
        student: Map<String, dynamic>.from(student),
        timeFormatted: student['gateInTime']?.toString(),
        mode: mode,
      );
    }

    if (mode == GateScanMode.exit &&
        student['gateOutDate'] == today &&
        (student['gateOutTime']?.toString().isNotEmpty ?? false)) {
      return GateScanResult(
        outcome: GateScanOutcome.alreadyScanned,
        message: 'Already Checked OUT at ${student['gateOutTime']}',
        student: Map<String, dynamic>.from(student),
        timeFormatted: student['gateOutTime']?.toString(),
        mode: mode,
      );
    }

    // 1. Update local student cache immediately (0ms UI & offline persistence)
    final updatedStudent = Map<String, dynamic>.from(student);
    if (mode == GateScanMode.entry) {
      updatedStudent['gateInTime'] = formattedTime;
      updatedStudent['gateInDate'] = today;
      updatedStudent['status'] = 'present';
      updatedStudent['lastAttendanceDate'] = today;
    } else {
      updatedStudent['gateOutTime'] = formattedTime;
      updatedStudent['gateOutDate'] = today;
    }
    _studentsById[studentId] = updatedStudent;
    await LocalDbService.saveCache(
      _studentsCacheKey(currentSchoolId),
      _studentsById.values.toList(),
    );

    final eventPayload = <String, dynamic>{
      'eventId': '${today}_${studentId}_${mode.name}',
      'schoolId': currentSchoolId,
      'classId': updatedStudent['classId']?.toString() ?? qrClassId,
      'className': updatedStudent['className']?.toString() ?? 'Class',
      'studentId': studentId,
      'studentName': updatedStudent['name']?.toString() ?? 'Student',
      'fatherName': updatedStudent['fatherName']?.toString() ?? '',
      'rollNo': updatedStudent['rollNo']?.toString() ?? '',
      'photo': updatedStudent['photo']?.toString() ?? '',
      'parentId': updatedStudent['parentId']?.toString() ?? '',
      'mode': mode.name, // 'entry' | 'exit'
      'date': today,
      'timeFormatted': formattedTime,
      'scannedAtIso': now.toIso8601String(),
      'gatekeeperId': gatekeeperId,
      'gatekeeperName': gatekeeperName,
    };

    // 2. Try live sync to Firestore + instant Parent Push Notification
    bool syncedNow = false;
    final bool online = await SyncQueueService.isOnline();
    isOnlineNotifier.value = online;

    if (online) {
      try {
        await _commitEventToFirestore(eventPayload);
        syncedNow = true;
      } catch (e) {
        debugPrint('⚠️ [Gatekeeper] Live write failed, queueing offline: $e');
        syncedNow = false;
      }
    }

    if (!syncedNow) {
      await _enqueueOfflineEvent(currentSchoolId, eventPayload);
    }

    // 3. Append to Today's Recent Scans list
    final logItem = {
      ...eventPayload,
      'synced': syncedNow,
    };
    final currentLogs = List<Map<String, dynamic>>.from(recentScansNotifier.value);
    currentLogs.insert(0, logItem);
    if (currentLogs.length > 200) {
      currentLogs.removeRange(200, currentLogs.length);
    }
    recentScansNotifier.value = currentLogs;
    await LocalDbService.saveCache(_todayLogsCacheKey(currentSchoolId), currentLogs);

    return GateScanResult(
      outcome: syncedNow ? GateScanOutcome.successOnline : GateScanOutcome.successOfflineQueued,
      message: mode == GateScanMode.entry
          ? (syncedNow ? 'Checked IN & Parent Notified' : 'Checked IN (Saved Offline)')
          : (syncedNow ? 'Checked OUT & Parent Notified' : 'Checked OUT (Saved Offline)'),
      student: updatedStudent,
      timeFormatted: formattedTime,
      mode: mode,
    );
  }

  /// Writes the gate event to student doc, daily gate_logs, and notifications (triggers FCM)
  Future<void> _commitEventToFirestore(Map<String, dynamic> ev) async {
    final schoolId = ev['schoolId']?.toString() ?? '';
    final classId = ev['classId']?.toString() ?? '';
    final studentId = ev['studentId']?.toString() ?? '';
    final studentName = ev['studentName']?.toString() ?? 'Student';
    final className = ev['className']?.toString() ?? 'Class';
    final parentId = ev['parentId']?.toString() ?? '';
    final mode = ev['mode']?.toString() ?? 'entry';
    final date = ev['date']?.toString() ?? _todayStr();
    final timeFormatted = ev['timeFormatted']?.toString() ?? _timeStr();
    final gatekeeperId = ev['gatekeeperId']?.toString() ?? '';
    final gatekeeperName = ev['gatekeeperName']?.toString() ?? 'Gatekeeper';

    if (schoolId.isEmpty || classId.isEmpty || studentId.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();

    // 1. Update Student Document (so Teacher View-Only Attendance & Parent Calendar update live!)
    final studentRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('students')
        .doc(studentId);

    if (mode == 'entry') {
      batch.update(studentRef, {
        'status': 'present',
        'lastAttendanceDate': date,
        'attendanceHistory.$date': 'present',
        'gateInTime': timeFormatted,
        'gateInDate': date,
        'gateLogs.$date.inTime': timeFormatted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(studentRef, {
        'gateOutTime': timeFormatted,
        'gateOutDate': date,
        'gateLogs.$date.outTime': timeFormatted,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 2. Write deterministic Daily Gate Log record
    final gateLogRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('gate_logs')
        .doc(date)
        .collection('entries')
        .doc(studentId);

    batch.set(
      gateLogRef,
      {
        'studentId': studentId,
        'studentName': studentName,
        'classId': classId,
        'className': className,
        'date': date,
        if (mode == 'entry') 'inTime': timeFormatted,
        if (mode == 'entry') 'inBy': gatekeeperName,
        if (mode == 'entry') 'inById': gatekeeperId,
        if (mode == 'exit') 'outTime': timeFormatted,
        if (mode == 'exit') 'outBy': gatekeeperName,
        if (mode == 'exit') 'outById': gatekeeperId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    // 3. Trigger Live Parent Push Notification via existing schools/{schoolId}/notifications pipeline
    if (parentId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('notifications')
            .add({
          'parentId': parentId,
          'studentId': studentId,
          'studentName': studentName,
          'className': className,
          'date': date,
          'time': timeFormatted,
          'type': 'attendance',
          'gateEvent': mode,
          'status': mode == 'entry' ? 'present' : 'gate_exit',
          'title': mode == 'entry' ? 'School Gate Check-In ✅' : 'School Gate Check-Out 🏠',
          'message': mode == 'entry'
              ? '$studentName has safely arrived at school at $timeFormatted.'
              : '$studentName has departed from school at $timeFormatted.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('⚠️ [Gatekeeper] Parent notification dispatch error: $e');
      }
    }
  }

  Future<void> _enqueueOfflineEvent(String schoolId, Map<String, dynamic> event) async {
    try {
      final raw = LocalDbService.getCache(_queueCacheKey(schoolId));
      final List<Map<String, dynamic>> queue = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];

      // Prevent duplicate eventId in queue
      final eventId = event['eventId']?.toString() ?? '';
      queue.removeWhere((item) => item['eventId']?.toString() == eventId);
      queue.add(event);

      await LocalDbService.saveCache(_queueCacheKey(schoolId), queue);
      pendingQueueCount.value = queue.length;
    } catch (e) {
      debugPrint('⚠️ [Gatekeeper] Enqueue offline error: $e');
    }
  }

  /// Flush all pending offline scans when internet returns
  Future<int> syncPendingQueue(String schoolId) async {
    if (_isFlushing) return 0;
    _isFlushing = true;
    int syncedCount = 0;

    try {
      final online = await SyncQueueService.isOnline();
      isOnlineNotifier.value = online;
      if (!online) return 0;

      final raw = LocalDbService.getCache(_queueCacheKey(schoolId));
      if (raw is! List || raw.isEmpty) {
        pendingQueueCount.value = 0;
        return 0;
      }

      final queue = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final List<Map<String, dynamic>> remaining = [];
      final Set<String> syncedIds = {};

      for (final ev in queue) {
        try {
          await _commitEventToFirestore(ev);
          syncedCount++;
          final id = ev['eventId']?.toString() ?? '';
          if (id.isNotEmpty) syncedIds.add(id);
        } catch (e) {
          remaining.add(ev);
        }
      }

      await LocalDbService.saveCache(_queueCacheKey(schoolId), remaining);
      pendingQueueCount.value = remaining.length;

      // Update synced status in today's recent logs UI
      if (syncedIds.isNotEmpty) {
        final updatedLogs = recentScansNotifier.value.map((log) {
          final m = Map<String, dynamic>.from(log);
          if (syncedIds.contains(m['eventId']?.toString())) {
            m['synced'] = true;
          }
          return m;
        }).toList();
        recentScansNotifier.value = updatedLogs;
        await LocalDbService.saveCache(_todayLogsCacheKey(schoolId), updatedLogs);
      }

      debugPrint('⚡ [Gatekeeper] Flushed $syncedCount pending offline scan(s). Remaining: ${remaining.length}');
    } catch (e) {
      debugPrint('⚠️ [Gatekeeper] syncPendingQueue error: $e');
    } finally {
      _isFlushing = false;
    }

    return syncedCount;
  }
}
