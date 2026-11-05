// ignore_for_file: use_null_aware_elements
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class SyncQueueService {
  static const String boxName = 'sync_queue';
  static bool _isInitialized = false;
  static bool _isProcessing = false;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static StreamSubscription<List<ConnectivityResult>>? get connectivitySubscription => _connectivitySubscription;

  /// Dispose and cancel connectivity listeners
  static void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isInitialized = false;
  }

  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  static Box get _box => Hive.box(boxName);

  /// Initialize Hive box and connectivity listener
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      _updatePendingCount();

      // Listen for connectivity transitions
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
        final bool hasConnection = results.any((r) => r != ConnectivityResult.none);
        if (hasConnection) {
          debugPrint('🌐 [SyncQueue] Network detected, triggering auto-sync...');
          processQueue();
        }
      });

      _isInitialized = true;
      debugPrint('⚡ [SyncQueue] Service initialized. Pending items: ${pendingCountNotifier.value}');

      // Initial check on boot
      checkAndSync();
    } catch (e) {
      debugPrint('⚠️ [SyncQueue] Init error: $e');
    }
  }

  static void _updatePendingCount() {
    try {
      if (Hive.isBoxOpen(boxName)) {
        pendingCountNotifier.value = _box.length;
      }
    } catch (_) {}
  }

  /// Retrieve any offline-queued messages destined for a specific student and parent
  static List<Map<String, dynamic>> getPendingMessagesFor({
    required String schoolId,
    required String parentId,
    required String studentId,
  }) {
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return [];
    final list = <Map<String, dynamic>>[];
    try {
      for (var key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(jsonDecode(raw));
        final type = item['type'] as String?;
        if (type == 'parent_text_message' || type == 'parent_voice_message' || type == 'parent_media_message') {
          final payload = Map<String, dynamic>.from(item['payload'] ?? {});
          if (payload['schoolId'] == schoolId &&
              payload['parentId'] == parentId &&
              payload['studentId'] == studentId) {
            list.add({
              'id': 'pending_$key',
              'teacherId': payload['teacherId'],
              'teacherName': payload['teacherName'],
              'parentId': parentId,
              'parentName': payload['parentName'],
              'studentId': studentId,
              'studentName': payload['studentName'],
              'message': payload['messageText'] ?? (type == 'parent_voice_message' ? 'Sent a voice message' : 'Sent an attachment'),
              'attachmentUrl': null,
              'attachmentType': type == 'parent_voice_message' ? 'audio' : null,
              'localFilePath': item['filePath'],
              'timestamp': DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now(),
              'read': false,
              'isPending': true,
              'schoolId': schoolId,
              'type': 'direct',
            });
          }
        }
      }
    } catch (_) {}
    return list;
  }

  /// Retrieve pending offline marks for a class, exam, and subject
  static Map<String, dynamic>? getPendingMarksFor({
    required String schoolId,
    required String classId,
    required String examId,
    required String subject,
  }) {
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return null;
    try {
      for (var key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(jsonDecode(raw));
        if (item['type'] == 'exam_marks_save') {
          final payload = Map<String, dynamic>.from(item['payload'] ?? {});
          if (payload['schoolId'] == schoolId &&
              payload['classId'] == classId &&
              payload['examId'] == examId &&
              payload['subject'] == subject) {
            return payload;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Retrieve pending offline homework for a class and subject
  static List<Map<String, dynamic>> getPendingHomeworkFor({
    required String schoolId,
    required String classId,
    required String subject,
  }) {
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return [];
    final list = <Map<String, dynamic>>[];
    try {
      for (var key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(jsonDecode(raw));
        if (item['type'] == 'homework_save') {
          final payload = Map<String, dynamic>.from(item['payload'] ?? {});
          if (payload['schoolId'] == schoolId && payload['classId'] == classId) {
            final hwData = Map<String, dynamic>.from(payload['homeworkData'] ?? {});
            if (hwData['subject'] == subject) {
              hwData['isPendingSync'] = true;
              list.add(hwData);
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  /// Retrieve pending offline scheduled test for a class and subject
  static Map<String, dynamic>? getPendingScheduledTestFor({
    required String schoolId,
    required String classId,
    required String subject,
  }) {
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return null;
    try {
      for (var key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(jsonDecode(raw));
        if (item['type'] == 'test_schedule') {
          final payload = Map<String, dynamic>.from(item['payload'] ?? {});
          if (payload['schoolId'] == schoolId && payload['classId'] == classId) {
            final testData = Map<String, dynamic>.from(payload['testData'] ?? {});
            if (testData['subject'] == subject && testData['status'] == 'scheduled') {
              testData['isPendingSync'] = true;
              return testData;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Remove or cancel a pending homework item directly from SyncQueue
  static Future<void> removePendingHomework(String homeworkId) async {
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return;
    try {
      final keysToDelete = <dynamic>[];
      for (var key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(jsonDecode(raw));
        if (item['type'] == 'homework_save') {
          final payload = Map<String, dynamic>.from(item['payload'] ?? {});
          if (payload['homeworkId'] == homeworkId) {
            keysToDelete.add(key);
          }
        }
      }
      for (var k in keysToDelete) {
        await _box.delete(k);
      }
      _updatePendingCount();
    } catch (_) {}
  }

  /// Remove or cancel a pending test item directly from SyncQueue
  static Future<void> removePendingScheduledTest(String testId) async {
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return;
    try {
      final keysToDelete = <dynamic>[];
      for (var key in _box.keys) {
        final raw = _box.get(key);
        if (raw == null) continue;
        final item = Map<String, dynamic>.from(jsonDecode(raw));
        if (item['type'] == 'test_schedule') {
          final payload = Map<String, dynamic>.from(item['payload'] ?? {});
          if (payload['testId'] == testId) {
            keysToDelete.add(key);
          }
        }
      }
      for (var k in keysToDelete) {
        await _box.delete(k);
      }
      _updatePendingCount();
    } catch (_) {}
  }

  /// Check internet reachability
  static Future<bool> isOnline() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.any((r) => r != ConnectivityResult.none)) {
        return false;
      }
      // Actual DNS probe to verify live gateway
      final probe = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return probe.isNotEmpty && probe[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static dynamic _sanitize(dynamic data) {
    if (data == null) return null;
    if (data is Timestamp) return data.toDate().toIso8601String();
    if (data is DateTime) return data.toIso8601String();
    if (data is FieldValue) return null;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), _sanitize(value)));
    }
    if (data is List) {
      return data.map((e) => _sanitize(e)).toList();
    }
    return data;
  }

  /// Add an action to the persistent queue
  static Future<String> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? filePath,
  }) async {
    final String id = const Uuid().v4();
    final sanitizedPayload = Map<String, dynamic>.from(_sanitize(payload) as Map);
    final item = {
      'id': id,
      'type': type,
      'payload': sanitizedPayload,
      'filePath': filePath,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    };

    await _box.put(id, jsonEncode(item));
    _updatePendingCount();
    debugPrint('📥 [SyncQueue] Enqueued "$type" (Task ID: $id). Total pending: ${pendingCountNotifier.value}');

    // If online, immediately try to sync
    checkAndSync();

    return id;
  }

  /// Trigger sync if online
  static Future<void> checkAndSync() async {
    await processQueue();
  }

  /// Sequentially process all pending items in the queue
  static Future<void> processQueue() async {
    if (_isProcessing) return;
    if (!Hive.isBoxOpen(boxName) || _box.isEmpty) return;

    _isProcessing = true;
    debugPrint('🔄 [SyncQueue] Processing queue (${_box.length} items)...');

    try {
      final keys = List<dynamic>.from(_box.keys);

      for (var key in keys) {
        final rawData = _box.get(key);
        if (rawData == null) continue;

        Map<String, dynamic> item;
        try {
          item = Map<String, dynamic>.from(jsonDecode(rawData));
        } catch (e) {
          await _box.delete(key);
          continue;
        }

        final String type = item['type'] ?? '';
        final Map<String, dynamic> payload = Map<String, dynamic>.from(item['payload'] ?? {});
        final String? filePath = item['filePath'];

        bool success = false;

        try {
          switch (type) {
            case 'attendance_confirm':
              success = await _processAttendanceConfirm(payload);
              break;
            case 'attendance_late_update':
              success = await _processAttendanceLateUpdate(payload);
              break;
            case 'parent_voice_message':
              success = await _processParentVoiceMessage(payload, filePath);
              break;
            case 'parent_media_message':
              success = await _processParentMediaMessage(payload, filePath);
              break;
            case 'parent_text_message':
              success = await _processParentTextMessage(payload);
              break;
            case 'teacher_checkin':
              success = await _processTeacherCheckin(payload);
              break;
            case 'teacher_checkout':
              success = await _processTeacherCheckout(payload);
              break;
            case 'exam_result_upload':
              success = await _processExamResultUpload(payload, filePath);
              break;
            case 'exam_marks_save':
              success = await _processExamMarksSave(payload);
              break;
            case 'class_broadcast':
              success = await _processClassBroadcast(payload, filePath);
              break;
            case 'homework_save':
              success = await _processHomeworkSave(payload);
              break;
            case 'homework_delete':
              success = await _processHomeworkDelete(payload);
              break;
            case 'test_schedule':
              success = await _processTestSchedule(payload);
              break;
            case 'test_cancel':
              success = await _processTestCancel(payload);
              break;
            case 'test_complete':
              success = await _processTestComplete(payload);
              break;
            case 'test_scores_save':
              success = await _processTestScoresSave(payload);
              break;
            case 'daily_scores_save':
              success = await _processDailyScoresSave(payload);
              break;
            default:
              debugPrint('⚠️ [SyncQueue] Unknown task type: $type, discarding.');
              success = true; // Drop unknown task
          }
        } catch (e) {
          debugPrint('❌ [SyncQueue] Error processing $type ($key): $e');
          success = false;
        }

        if (success) {
          await _box.delete(key);
          debugPrint('✅ [SyncQueue] Task $type ($key) synced and removed.');
        } else {
          int retries = (item['retryCount'] as int? ?? 0) + 1;
          if (retries > 5) {
            debugPrint('⚠️ [SyncQueue] Max retries exceeded for task $key. Discarding.');
            await _box.delete(key);
          } else {
            item['retryCount'] = retries;
            item['status'] = 'failed';
            await _box.put(key, jsonEncode(_sanitize(item)));
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SyncQueue] Queue processing loop error: $e');
    } finally {
      _isProcessing = false;
      _updatePendingCount();
    }
  }

  // -------------------------------------------------------------
  // HANDLERS
  // -------------------------------------------------------------

  static Future<bool> _processAttendanceConfirm(Map<String, dynamic> payload) async {
    final schoolId = payload['schoolId'] as String;
    final classId = payload['classId'] as String;
    final className = payload['className'] as String;
    final teacherId = payload['teacherId'] as String;
    final teacherName = payload['teacherName'] as String;
    final date = payload['date'] as String;
    final Map<String, dynamic> attendanceMap = Map<String, dynamic>.from(payload['attendanceMap'] ?? {});
    final List<dynamic> studentsRaw = payload['students'] ?? [];

    final batch = FirebaseFirestore.instance.batch();

    // 1. Attendance History Document
    final historyRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('attendance')
        .doc('${classId}_$date'); // Deterministic doc ID prevents duplicate records on re-sync!

    final records = attendanceMap.entries.map((entry) {
      final sId = entry.key;
      final status = entry.value.toString();
      final student = studentsRaw.firstWhere(
        (s) => s['id'] == sId,
        orElse: () => <String, dynamic>{'name': 'Unknown'},
      );
      return {
        'id': sId,
        'name': student['name'] ?? 'Unknown',
        'status': status,
      };
    }).toList();

    batch.set(historyRef, {
      'teacherId': teacherId,
      'teacherName': teacherName,
      'classId': classId,
      'className': className,
      'date': date,
      'timestamp': FieldValue.serverTimestamp(),
      'records': records,
      'totalPresent': records.where((r) => r['status'] == 'present').length,
      'totalAbsent': records.where((r) => r['status'] == 'absent').length,
    }, SetOptions(merge: true));

    // 2. Loop students & batch update
    for (var sRaw in studentsRaw) {
      final s = Map<String, dynamic>.from(sRaw);
      final sId = s['id'] as String;
      final status = attendanceMap[sId] ?? 'absent';

      final studentRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(sId);

      batch.update(studentRef, {
        'status': status,
        'lastAttendanceDate': date,
        'attendanceHistory.$date': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // 3. Dispatch Parent Notifications in non-blocking try/catch
    for (var sRaw in studentsRaw) {
      final s = Map<String, dynamic>.from(sRaw);
      final sId = s['id'] as String;
      final sName = s['name'] as String? ?? 'Student';
      final status = attendanceMap[sId] ?? 'absent';

      String? parentId;
      if (s['parentDetails'] != null && s['parentDetails']['parentId'] != null) {
        parentId = s['parentDetails']['parentId']?.toString();
      }

      if (parentId != null && parentId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('notifications')
              .add({
            'parentId': parentId,
            'studentId': sId,
            'studentName': sName,
            'title': 'Attendance Update',
            'type': 'attendance',
            'status': status,
            'className': className,
            'date': date,
            'message': status == 'leave_granted'
                ? '$sName is on leave today, $date.'
                : '$sName is marked $status in School today, $date.',
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    }

    return true;
  }

  static Future<bool> _processAttendanceLateUpdate(Map<String, dynamic> payload) async {
    final schoolId = payload['schoolId'] as String;
    final classId = payload['classId'] as String;
    final studentId = payload['studentId'] as String;
    final studentName = payload['studentName'] as String? ?? 'Student';
    final newStatus = payload['newStatus'] as String;
    final date = payload['date'] as String;
    final parentId = payload['parentId'] as String?;

    final batch = FirebaseFirestore.instance.batch();

    // 1. Update Student Subcollection
    final studentRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('students')
        .doc(studentId);

    batch.update(studentRef, {
      'status': newStatus,
      'lastAttendanceDate': date,
      'attendanceHistory.$date': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Update today's attendance document if exists
    final historyRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('attendance')
        .doc('${classId}_$date');

    final historySnap = await historyRef.get();
    if (historySnap.exists && historySnap.data() != null) {
      final records = List<Map<String, dynamic>>.from(
        (historySnap.data()!['records'] as List? ?? []).map((r) => Map<String, dynamic>.from(r)),
      );
      bool found = false;
      for (var r in records) {
        if (r['id'] == studentId) {
          r['status'] = newStatus;
          found = true;
          break;
        }
      }
      if (!found) {
        records.add({'id': studentId, 'name': studentName, 'status': newStatus});
      }

      batch.update(historyRef, {
        'records': records,
        'totalPresent': records.where((r) => r['status'] == 'present').length,
        'totalAbsent': records.where((r) => r['status'] == 'absent').length,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // 3. Send Single Notification to That Late Student's Parent Only!
    if (parentId != null && parentId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('notifications')
            .add({
          'parentId': parentId,
          'studentId': studentId,
          'studentName': studentName,
          'title': 'Attendance Update (Late Arrival)',
          'type': 'attendance',
          'status': newStatus,
          'date': date,
          'message': '$studentName has arrived and status was updated to $newStatus on $date.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    return true;
  }

  static Future<bool> _processParentVoiceMessage(Map<String, dynamic> payload, String? filePath) async {
    final schoolId = payload['schoolId'] as String;
    final teacherId = payload['teacherId'] as String;
    final teacherName = payload['teacherName'] as String;
    final parentId = payload['parentId'] as String;
    final parentName = payload['parentName'] as String? ?? 'Parent';
    final studentId = payload['studentId'] as String;
    final studentName = payload['studentName'] as String? ?? 'Student';

    if (filePath == null || !File(filePath).existsSync()) {
      debugPrint('⚠️ [SyncQueue] Voice file does not exist locally: $filePath');
      return true; // Discard invalid file
    }

    final file = File(filePath);
    final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_voice.m4a';
    final refStorage = FirebaseStorage.instance.ref(destination);
    await refStorage.putFile(file);
    final audioUrl = await refStorage.getDownloadURL();

    final batch = FirebaseFirestore.instance.batch();

    final messageRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('messages')
        .doc();

    batch.set(messageRef, {
      'teacherId': teacherId,
      'teacherName': teacherName,
      'parentId': parentId,
      'parentName': parentName,
      'studentId': studentId,
      'studentName': studentName,
      'message': 'Sent a voice message',
      'attachmentUrl': audioUrl,
      'attachmentType': 'audio',
      'timestamp': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 14))),
      'read': false,
      'schoolId': schoolId,
      'type': 'direct',
    });

    final notificationRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('notifications')
        .doc();

    batch.set(notificationRef, {
      'parentId': parentId,
      'studentId': studentId,
      'studentName': studentName,
      'title': 'New Voice Message from Teacher',
      'message': 'Audio message received',
      'type': 'message',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Clean up local temp voice file once uploaded safely
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    return true;
  }

  static Future<bool> _processParentMediaMessage(Map<String, dynamic> payload, String? filePath) async {
    final schoolId = payload['schoolId'] as String;
    final teacherId = payload['teacherId'] as String;
    final teacherName = payload['teacherName'] as String;
    final parentId = payload['parentId'] as String;
    final parentName = payload['parentName'] as String? ?? 'Parent';
    final studentId = payload['studentId'] as String;
    final studentName = payload['studentName'] as String? ?? 'Student';
    final messageText = payload['messageText'] as String? ?? 'Sent an attachment';

    String? attachmentUrl;
    String? attachmentName;
    String? attachmentType;

    if (filePath != null && File(filePath).existsSync()) {
      final file = File(filePath);
      attachmentName = filePath.split(Platform.pathSeparator).last;
      attachmentType = attachmentName.split('.').last.toLowerCase();

      final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_$attachmentName';
      final refStorage = FirebaseStorage.instance.ref(destination);
      await refStorage.putFile(file);
      attachmentUrl = await refStorage.getDownloadURL();

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    final batch = FirebaseFirestore.instance.batch();

    final messageRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('messages')
        .doc();

    batch.set(messageRef, {
      'teacherId': teacherId,
      'teacherName': teacherName,
      'parentId': parentId,
      'parentName': parentName,
      'studentId': studentId,
      'studentName': studentName,
      'message': messageText,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
      if (attachmentType != null) 'attachmentType': attachmentType,
      if (attachmentName != null) 'attachmentName': attachmentName,
      'timestamp': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 14))),
      'read': false,
      'schoolId': schoolId,
      'type': 'direct',
    });

    final notificationRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('notifications')
        .doc();

    batch.set(notificationRef, {
      'parentId': parentId,
      'studentId': studentId,
      'studentName': studentName,
      'title': 'New Message from Teacher',
      'message': messageText,
      'type': 'message',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return true;
  }

  static Future<bool> _processParentTextMessage(Map<String, dynamic> payload) async {
    return _processParentMediaMessage(payload, null);
  }

  static Future<bool> _processTeacherCheckin(Map<String, dynamic> payload) async {
    final schoolId = payload['schoolId'] as String;
    final teacherId = payload['teacherId'] as String;
    final date = payload['date'] as String;
    final checkInTimeStr = payload['checkInTime'] as String;
    final status = payload['status'] as String? ?? 'Present';

    final checkInDateTime = DateTime.parse(checkInTimeStr);
    final checkInTimestamp = Timestamp.fromDate(checkInDateTime);

    final attendanceRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(teacherId)
        .collection('attendance_logs')
        .doc(date);

    await attendanceRef.set({
      'date': date,
      'checkIn': checkInTimestamp,
      'status': status,
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(teacherId)
        .set({
      'lastAttendanceDate': date,
    }, SetOptions(merge: true));

    return true;
  }

  static Future<bool> _processTeacherCheckout(Map<String, dynamic> payload) async {
    final schoolId = payload['schoolId'] as String;
    final teacherId = payload['teacherId'] as String;
    final date = payload['date'] as String;
    final checkOutTimeStr = payload['checkOutTime'] as String;
    final status = payload['status'] as String? ?? 'Present';

    final checkOutDateTime = DateTime.parse(checkOutTimeStr);
    final checkOutTimestamp = Timestamp.fromDate(checkOutDateTime);

    final attendanceRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(teacherId)
        .collection('attendance_logs')
        .doc(date);

    await attendanceRef.update({
      'checkOut': checkOutTimestamp,
      'status': status,
    });

    return true;
  }

  static Future<bool> _processExamResultUpload(Map<String, dynamic> payload, String? filePath) async {
    final schoolId = payload['schoolId'] as String;
    final studentId = payload['studentId'] as String;
    final fileExtension = payload['fileExtension'] as String? ?? 'pdf';

    if (filePath == null || !File(filePath).existsSync()) {
      debugPrint('⚠️ [SyncQueue] Result file does not exist locally: $filePath');
      return true; // Drop invalid task
    }

    final file = File(filePath);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final storagePath = 'schools/$schoolId/students/$studentId/results/result_$timestamp.$fileExtension';

    final refStorage = FirebaseStorage.instance.ref().child(storagePath);
    await refStorage.putFile(file);
    final downloadUrl = await refStorage.getDownloadURL();

    final studentRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId);

    await studentRef.update({
      'uploadedResultUrl': downloadUrl,
      'uploadedResultType': fileExtension,
      'uploadedResultAt': FieldValue.serverTimestamp(),
    });

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    return true;
  }

  static Future<bool> _processExamMarksSave(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final className = (payload['className'] ?? '').toString();
    final examId = (payload['examId'] ?? '').toString();
    final examTitle = (payload['examTitle'] ?? '').toString();
    final subject = (payload['subject'] ?? '').toString();
    final teacherId = (payload['teacherId'] ?? '').toString();
    final teacherName = (payload['teacherName'] ?? '').toString();
    final totalMarks = (payload['totalMarks'] as num?)?.toInt() ?? 100;
    final passingMarks = (payload['passingMarks'] as num?)?.toInt() ?? 33;
    final Map<String, dynamic> marksData = Map<String, dynamic>.from(payload['marksData'] ?? {});

    if (schoolId.isEmpty || classId.isEmpty || examId.isEmpty || subject.isEmpty) {
      debugPrint('⚠️ [SyncQueue] Invalid exam marks payload, discarding.');
      return true;
    }

    final marksDocId = '${examId}_$subject'.replaceAll('/', '_').replaceAll(' ', '_');
    final batch = FirebaseFirestore.instance.batch();

    // 1. Save to Class Exam Marks Collection
    final classMarksRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('exam_marks')
        .doc(marksDocId);

    batch.set(
      classMarksRef,
      {
        'examId': examId,
        'examTitle': examTitle,
        'classId': classId,
        'className': className,
        'subject': subject,
        'teacherId': teacherId,
        'teacherName': teacherName,
        'totalMarks': totalMarks,
        'passingMarks': passingMarks,
        'updatedAt': FieldValue.serverTimestamp(),
        'marks': marksData,
      },
      SetOptions(merge: true),
    );

    // 2. Also merge into each student's exam_results subcollection
    for (final entry in marksData.entries) {
      final studentId = entry.key;
      if (entry.value is! Map) continue;
      final sData = Map<String, dynamic>.from(entry.value as Map);

      final studentResultRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentId)
          .collection('exam_results')
          .doc(examId);

      batch.set(
        studentResultRef,
        {
          'examId': examId,
          'examTitle': examTitle,
          'updatedAt': FieldValue.serverTimestamp(),
          'subjects': {
            subject: {
              'subject': subject,
              'totalMarks': totalMarks,
              'obtainedMarks': sData['isAbsent'] == true ? null : sData['obtainedMarks'],
              'isAbsent': sData['isAbsent'] == true,
              'grade': sData['grade'] ?? 'N/A',
              'remarks': sData['remarks'] ?? '',
            }
          }
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    debugPrint('✅ [SyncQueue] Successfully synced exam marks for $className - $subject ($examTitle)');
    return true;
  }

  static Future<bool> _processClassBroadcast(Map<String, dynamic> payload, String? filePath) async {
    final schoolId = payload['schoolId'] as String;
    final classId = payload['classId'] as String;
    final teacherId = payload['teacherId'] as String;
    final teacherName = payload['teacherName'] as String;
    final messageText = payload['messageText'] as String? ?? 'New Broadcast';
    final bool isVoice = payload['isVoice'] as bool? ?? false;
    final attachmentName = payload['attachmentName'] as String?;
    final attachmentType = payload['attachmentType'] as String?;
    final Map<String, dynamic> parentMap = Map<String, dynamic>.from(payload['parentMap'] ?? {});
    final List<dynamic> students = payload['students'] ?? [];

    String? attachmentUrl;

    if (filePath != null && File(filePath).existsSync()) {
      final file = File(filePath);
      final destName = attachmentName ?? (isVoice ? 'voice.m4a' : 'attachment');
      final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_$destName';
      final refStorage = FirebaseStorage.instance.ref(destination);
      await refStorage.putFile(file);
      attachmentUrl = await refStorage.getDownloadURL();
    }

    final broadcastRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('broadcasts')
        .doc();

    final broadcastId = broadcastRef.id;
    final timestamp = FieldValue.serverTimestamp();

    final broadcastData = {
      'id': broadcastId,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'text': messageText,
      'attachment': attachmentUrl != null ? {
        'url': attachmentUrl,
        'name': attachmentName ?? 'file',
        'type': attachmentType ?? (isVoice ? 'audio' : 'file'),
        'fullPath': FirebaseStorage.instance.refFromURL(attachmentUrl).fullPath,
      } : null,
      'timestamp': timestamp,
    };

    final uniqueParents = parentMap.values.map((p) => p['id']).toSet();
    var batch = FirebaseFirestore.instance.batch();
    batch.set(broadcastRef, broadcastData);

    for (var parentId in uniqueParents) {
      final studentDocEntry = parentMap.entries.firstWhere(
        (e) => e.value['id'] == parentId,
        orElse: () => const MapEntry<String, dynamic>('', {}),
      );
      if (studentDocEntry.key.isEmpty) continue;
      final studentDoc = studentDocEntry.key;
      final studentInfo = students.firstWhere(
        (s) => s['id'] == studentDoc,
        orElse: () => <String, dynamic>{'name': 'Student', 'id': studentDoc},
      );

      final msgRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('messages')
          .doc();

      batch.set(msgRef, {
        'teacherId': teacherId,
        'teacherName': teacherName,
        'parentId': parentId,
        'parentName': parentMap[studentDoc]?['name'] ?? 'Parent',
        'studentId': studentInfo['id'],
        'studentName': studentInfo['name'] ?? 'Student',
        'message': messageText,
        'attachmentUrl': attachmentUrl,
        'attachmentType': attachmentType,
        'timestamp': timestamp,
        'read': false,
        'schoolId': schoolId,
        'type': 'class-broadcast',
        'broadcastId': broadcastId,
      });

      final notifRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('notifications')
          .doc();

      batch.set(notifRef, {
        'parentId': parentId,
        'studentId': studentInfo['id'],
        'studentName': studentInfo['name'] ?? 'Student',
        'title': isVoice ? "New Voice Message from Teacher" : "New Broadcast Message",
        'message': messageText,
        'type': "message",
        'read': false,
        'createdAt': timestamp,
      });
    }

    await batch.commit();

    // Clean up local temp file once uploaded if applicable
    if (filePath != null) {
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    return true;
  }

  static Future<bool> _processHomeworkSave(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final homeworkId = (payload['homeworkId'] ?? '').toString();
    final Map<String, dynamic> hwData = Map<String, dynamic>.from(payload['homeworkData'] ?? {});

    if (schoolId.isEmpty || classId.isEmpty || homeworkId.isEmpty) {
      debugPrint('⚠️ [SyncQueue] Invalid homework payload, discarding.');
      return true;
    }

    hwData.remove('isPendingSync');

    if (hwData['dueDateTime'] is String) {
      final dt = DateTime.tryParse(hwData['dueDateTime'] as String);
      if (dt != null) {
        hwData['dueDateTime'] = Timestamp.fromDate(dt);
      }
    }
    hwData['updatedAt'] = FieldValue.serverTimestamp();
    if (!hwData.containsKey('createdAt') || hwData['createdAt'] == null) {
      hwData['createdAt'] = FieldValue.serverTimestamp();
    }

    final hwRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('homework')
        .doc(homeworkId);

    await hwRef.set(hwData, SetOptions(merge: true));
    debugPrint('✅ [SyncQueue] Successfully synced homework ($homeworkId) for class $classId');
    return true;
  }

  static Future<bool> _processHomeworkDelete(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final homeworkId = (payload['homeworkId'] ?? '').toString();

    if (schoolId.isEmpty || classId.isEmpty || homeworkId.isEmpty) return true;

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('homework')
        .doc(homeworkId)
        .delete();

    debugPrint('✅ [SyncQueue] Successfully synced homework deletion ($homeworkId)');
    return true;
  }

  static Future<bool> _processTestSchedule(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final className = (payload['className'] ?? '').toString();
    final testId = (payload['testId'] ?? '').toString();
    final Map<String, dynamic> testData = Map<String, dynamic>.from(payload['testData'] ?? {});
    final List<dynamic> students = payload['students'] ?? [];
    final String testMessage = (payload['testMessage'] ?? '').toString();

    if (schoolId.isEmpty || classId.isEmpty || testId.isEmpty) {
      debugPrint('⚠️ [SyncQueue] Invalid test schedule payload, discarding.');
      return true;
    }

    testData.remove('isPendingSync');
    testData['createdAt'] = FieldValue.serverTimestamp();

    final testRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('scheduled_tests')
        .doc(testId);

    await testRef.set(testData, SetOptions(merge: true));

    // Send Parent Notifications safely
    if (students.isNotEmpty && testMessage.isNotEmpty) {
      try {
        final processedParents = <String>{};
        var batch = FirebaseFirestore.instance.batch();
        int batchCount = 0;

        for (var sRaw in students) {
          if (sRaw is! Map) continue;
          final student = Map<String, dynamic>.from(sRaw);
          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId']?.toString();
          }
          if (parentId != null && parentId.isNotEmpty && !processedParents.contains(parentId)) {
            processedParents.add(parentId);
            final alertRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .doc();

            batch.set(alertRef, {
              'parentId': parentId,
              'studentId': student['id'] ?? '',
              'studentName': student['name'] ?? 'Student',
              'title': 'Test Scheduled: ${testData['subject'] ?? 'Test'}',
              'message': testMessage,
              'type': 'academic',
              'read': false,
              'className': className,
              'createdAt': FieldValue.serverTimestamp(),
            });
            batchCount++;

            if (batchCount >= 400) {
              await batch.commit();
              batch = FirebaseFirestore.instance.batch();
              batchCount = 0;
            }
          }
        }
        if (batchCount > 0) {
          await batch.commit();
        }
      } catch (e) {
        debugPrint('⚠️ [SyncQueue] Error dispatching scheduled test parent alerts: $e');
      }
    }

    debugPrint('✅ [SyncQueue] Successfully synced scheduled test ($testId) and alerted parents');
    return true;
  }

  static Future<bool> _processTestCancel(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final className = (payload['className'] ?? '').toString();
    final testId = (payload['testId'] ?? '').toString();
    final subject = (payload['subject'] ?? '').toString();
    final List<dynamic> students = payload['students'] ?? [];
    final String cancelMessage = (payload['cancelMessage'] ?? '').toString();

    if (schoolId.isEmpty || classId.isEmpty || testId.isEmpty) return true;

    final testRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('scheduled_tests')
        .doc(testId);

    await testRef.delete();

    if (students.isNotEmpty && cancelMessage.isNotEmpty) {
      try {
        final processedParents = <String>{};
        var batch = FirebaseFirestore.instance.batch();
        int batchCount = 0;

        for (var sRaw in students) {
          if (sRaw is! Map) continue;
          final student = Map<String, dynamic>.from(sRaw);
          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId']?.toString();
          }
          if (parentId != null && parentId.isNotEmpty && !processedParents.contains(parentId)) {
            processedParents.add(parentId);
            final alertRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .doc();

            batch.set(alertRef, {
              'parentId': parentId,
              'studentId': student['id'] ?? '',
              'studentName': student['name'] ?? 'Student',
              'title': 'Test Cancelled: $subject',
              'message': cancelMessage,
              'type': 'academic',
              'read': false,
              'className': className,
              'createdAt': FieldValue.serverTimestamp(),
            });
            batchCount++;

            if (batchCount >= 400) {
              await batch.commit();
              batch = FirebaseFirestore.instance.batch();
              batchCount = 0;
            }
          }
        }
        if (batchCount > 0) {
          await batch.commit();
        }
      } catch (e) {
        debugPrint('⚠️ [SyncQueue] Error sending cancel test alerts: $e');
      }
    }

    debugPrint('✅ [SyncQueue] Successfully synced cancelled test ($testId)');
    return true;
  }

  static Future<bool> _processTestComplete(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final testId = (payload['testId'] ?? '').toString();

    if (schoolId.isEmpty || classId.isEmpty || testId.isEmpty) return true;

    final testRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('scheduled_tests')
        .doc(testId);

    await testRef.update({'status': 'completed'});
    debugPrint('✅ [SyncQueue] Successfully synced test completion ($testId)');
    return true;
  }

  static Future<bool> _processTestScoresSave(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final className = (payload['className'] ?? '').toString();
    final testId = (payload['testId'] ?? '').toString();
    final subject = (payload['subject'] ?? '').toString();
    final testType = (payload['testType'] ?? 'Written').toString();
    final maxMarks = (payload['maxMarks'] as num?)?.toInt() ?? 10;
    final dateStr = (payload['dateStr'] ?? '').toString();
    final String testMessage = (payload['testMessage'] ?? '').toString();
    final Map<String, dynamic> testScores = Map<String, dynamic>.from(payload['testScores'] ?? {});
    final List<dynamic> absentStudentsRaw = payload['absentStudents'] ?? [];
    final Set<String> absentStudents = absentStudentsRaw.map((e) => e.toString()).toSet();
    final List<dynamic> students = payload['students'] ?? [];

    if (schoolId.isEmpty || classId.isEmpty || testId.isEmpty) return true;

    var batch = FirebaseFirestore.instance.batch();
    int batchCount = 0;
    final processedParents = <String>{};

    for (var sRaw in students) {
      if (sRaw is! Map) continue;
      final student = Map<String, dynamic>.from(sRaw);
      final studentId = student['id']?.toString() ?? '';
      if (studentId.isEmpty) continue;
      final bool isAbsent = absentStudents.contains(studentId);

      String? parentId;
      if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
        parentId = student['parentDetails']['parentId']?.toString();
      }

      if (parentId != null && parentId.isNotEmpty && !processedParents.contains(parentId)) {
        processedParents.add(parentId);
        final alertRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('notifications')
            .doc();

        final sName = student['name'] ?? 'Student';
        final notifTitle = isAbsent ? 'Test Absence: $subject' : 'Test Results: $subject';
        final notifMsg = isAbsent
            ? '$sName was marked ABSENT for the $testType test in $subject on $dateStr.'
            : testMessage;

        batch.set(alertRef, {
          'parentId': parentId,
          'studentId': studentId,
          'studentName': sName,
          'title': notifTitle,
          'message': notifMsg,
          'type': 'academic',
          'read': false,
          'className': className,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batchCount++;
      }

      if (testScores.containsKey(studentId) || isAbsent) {
        final score = isAbsent ? null : (int.tryParse(testScores[studentId]?.toString() ?? '') ?? 0);
        final studentRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .doc(studentId);

        final scoreRef = studentRef.collection('testScores').doc(testId);
        batch.set(scoreRef, {
          'subject': subject,
          'testType': testType,
          'score': score,
          'isAbsent': isAbsent,
          'maxMarks': maxMarks,
          'date': dateStr,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batchCount++;
      }

      if (batchCount >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        batchCount = 0;
      }
    }

    final testDocRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('scheduled_tests')
        .doc(testId);

    batch.update(testDocRef, {
      'status': 'completed',
      'scores': testScores,
      'absentStudents': absentStudents.toList(),
      'completedAt': FieldValue.serverTimestamp(),
      'presentCount': testScores.length,
      'absentCount': absentStudents.length,
    });

    await batch.commit();

    debugPrint('✅ [SyncQueue] Successfully synced test scores and report for $testId');
    return true;
  }

  static Future<bool> _processDailyScoresSave(Map<String, dynamic> payload) async {
    final schoolId = (payload['schoolId'] ?? '').toString();
    final classId = (payload['classId'] ?? '').toString();
    final subject = (payload['subject'] ?? '').toString();
    final Map<String, dynamic> scoreUpdates = Map<String, dynamic>.from(payload['scoreUpdates'] ?? {});
    final List<dynamic> students = payload['students'] ?? [];

    if (schoolId.isEmpty || classId.isEmpty || scoreUpdates.isEmpty) return true;

    var batch = FirebaseFirestore.instance.batch();
    int batchCount = 0;

    for (var entry in scoreUpdates.entries) {
      final studentId = entry.key;
      if (entry.value is! Map) continue;
      final updates = Map<String, dynamic>.from(entry.value as Map);

      final studentRaw = students.firstWhere(
        (s) => s is Map && s['id'] == studentId,
        orElse: () => <String, dynamic>{},
      );
      if (studentRaw is! Map || studentRaw.isEmpty) continue;
      final student = Map<String, dynamic>.from(studentRaw);

      final studentRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentId);

      List<dynamic> newAcademicScores = List<dynamic>.from(student['academicScores'] ?? []);
      List<dynamic> newHomeworkScores = List<dynamic>.from(student['homeworkScores'] ?? []);

      if (updates.containsKey('academic')) {
        final scoreVal = int.tryParse(updates['academic']?.toString() ?? '') ?? 0;
        final idx = newAcademicScores.indexWhere((s) => s is Map && s['subject'] == subject);
        if (idx >= 0) {
          newAcademicScores[idx] = { ...Map<String, dynamic>.from(newAcademicScores[idx] as Map), 'score': scoreVal };
        } else {
          newAcademicScores.add({ 'subject': subject, 'score': scoreVal });
        }
      }

      if (updates.containsKey('homework')) {
        final scoreVal = int.tryParse(updates['homework']?.toString() ?? '') ?? 0;
        final idx = newHomeworkScores.indexWhere((s) => s is Map && s['subject'] == subject);
        if (idx >= 0) {
          newHomeworkScores[idx] = { ...Map<String, dynamic>.from(newHomeworkScores[idx] as Map), 'score': scoreVal };
        } else {
          newHomeworkScores.add({ 'subject': subject, 'score': scoreVal });
        }
      }

      batch.update(studentRef, {
        'academicScores': newAcademicScores,
        'homeworkScores': newHomeworkScores,
      });
      batchCount++;

      if (batchCount >= 400) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    debugPrint('✅ [SyncQueue] Successfully synced daily scores for class $classId ($subject)');
    return true;
  }
}
