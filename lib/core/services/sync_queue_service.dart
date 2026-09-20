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

  /// Add an action to the persistent queue
  static Future<String> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? filePath,
  }) async {
    final String id = const Uuid().v4();
    final item = {
      'id': id,
      'type': type,
      'payload': payload,
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
    if (await isOnline()) {
      await processQueue();
    }
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
            case 'class_broadcast':
              success = await _processClassBroadcast(payload, filePath);
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
            await _box.put(key, jsonEncode(item));
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
}
