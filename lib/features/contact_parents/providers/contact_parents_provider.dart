import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';

class ContactParentsState {
  final Map<String, dynamic>? assignedClass;
  final List<Map<String, dynamic>> students;
  final Map<String, dynamic> parentMap;
  final bool isLoading;
  final bool isSending;
  final String searchTerm;
  final String? expandedStudentId;
  final bool isGroupMode;

  ContactParentsState({
    this.assignedClass,
    this.students = const [],
    this.parentMap = const {},
    this.isLoading = false,
    this.isSending = false,
    this.searchTerm = '',
    this.expandedStudentId,
    this.isGroupMode = false,
  });

  ContactParentsState copyWith({
    Map<String, dynamic>? assignedClass,
    List<Map<String, dynamic>>? students,
    Map<String, dynamic>? parentMap,
    bool? isLoading,
    bool? isSending,
    String? searchTerm,
    String? expandedStudentId,
    bool clearExpanded = false,
    bool? isGroupMode,
  }) {
    return ContactParentsState(
      assignedClass: assignedClass ?? this.assignedClass,
      students: students ?? this.students,
      parentMap: parentMap ?? this.parentMap,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      searchTerm: searchTerm ?? this.searchTerm,
      expandedStudentId: clearExpanded ? null : (expandedStudentId ?? this.expandedStudentId),
      isGroupMode: isGroupMode ?? this.isGroupMode,
    );
  }
}

class ContactParentsNotifier extends StateNotifier<ContactParentsState> {
  final Ref ref;
  final AsyncValue<Map<String, dynamic>?> teacherDataAsync;

  ContactParentsNotifier(this.ref, this.teacherDataAsync) : super(ContactParentsState()) {
    _init();

    // 1. Manually pull the current state right now to prevent race conditions
    // If we've already cached the classroom in AttendanceProvider earlier, state won't be empty!
    final initialStudents = ref.read(classStudentsProvider).valueOrNull;
    final initialClass = ref.read(assignedClassProvider).valueOrNull;

    if (initialClass != null) {
      state = state.copyWith(assignedClass: initialClass);
    }
    if (initialStudents != null) {
      state = state.copyWith(students: initialStudents, isLoading: false);
    }

    // 2. Listen to the class students stream for future real-time updates
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(classStudentsProvider, (previous, next) {
      next.whenData((studentsList) {
        if (mounted) {
           state = state.copyWith(students: studentsList.toList(), isLoading: false);
        }
      });
    });

    // Listen to assigned class changes
    ref.listen<AsyncValue<Map<String, dynamic>?>>(assignedClassProvider, (previous, next) {
        next.whenData((assignedClass) {
            if (mounted) {
               state = state.copyWith(assignedClass: assignedClass);
            }
        });
    });
  }

  void _init() {
    if (teacherDataAsync.value == null) return;
    final schoolId = teacherDataAsync.value!['schoolId'];

    if (schoolId == null) return;
    
    // We only need to fetch parents map initially or listen to it, 
    // assignedClass and students are handled by ref.listen above.
    state = state.copyWith(isLoading: true);
    _fetchParentsMap(schoolId);
  }

  Future<void> _fetchParentsMap(String schoolId) async {
    try {
      final parentsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('parents')
          .get();

      final mapping = <String, dynamic>{};
      
      for (var doc in parentsSnapshot.docs) {
        final parentData = doc.data();
        parentData['id'] = doc.id;
        
        final linkedStudents = parentData['linkedStudents'];
        if (linkedStudents is List) {
          for (var link in linkedStudents) {
            if (link is Map && link['studentId'] != null) {
              mapping[link['studentId'] as String] = parentData;
            }
          }
        }
      }

      if (mounted) {
        state = state.copyWith(parentMap: mapping);
      }
    } catch (e) {
      print("ContactParents: Error fetching parents map $e");
    }
  }

  void setSearchTerm(String term) {
    state = state.copyWith(searchTerm: term);
  }

  void toggleStudentExpansion(String studentId) {
    if (state.expandedStudentId == studentId) {
      state = state.copyWith(clearExpanded: true);
    } else {
      state = state.copyWith(expandedStudentId: studentId);
    }
  }

  void collapseStudent() {
     state = state.copyWith(clearExpanded: true);
  }

  void toggleGroupMode(bool isGroup) {
     state = state.copyWith(isGroupMode: isGroup);
  }
  Future<void> sendMessage({
    required Map<String, dynamic> student,
    required Map<String, dynamic> parent,
    String? messageText,
    File? attachedFile,
  }) async {
    if ((messageText == null || messageText.trim().isEmpty) && attachedFile == null) return;
    
    final teacherData = teacherDataAsync.value;
    if (teacherData == null) return;

    final schoolId = teacherData['schoolId'] as String?;
    final teacherId = teacherData['uid'] as String? ?? teacherData['id'] as String?; // Handle different auth models
    final teacherName = teacherData['name'] as String? ?? 'Teacher';

    if (schoolId == null || teacherId == null) return;

    state = state.copyWith(isSending: true);

    try {
      String? attachmentUrl;
      String? attachmentName;
      String? attachmentType;

      if (attachedFile != null) {
        final pathStr = attachedFile.path;
        attachmentName = pathStr.split('/').last;
        attachmentType = pathStr.split('.').last.toLowerCase();
        
        final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_$attachmentName';
        final refStorage = FirebaseStorage.instance.ref(destination);
        await refStorage.putFile(attachedFile);
        attachmentUrl = await refStorage.getDownloadURL();
      }

      final textToSave = (messageText != null && messageText.isNotEmpty)
          ? messageText.trim()
          : 'Sent an attachment';

      final batch = FirebaseFirestore.instance.batch();

      // 1. Create Message Record
      final messageRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('messages')
          .doc();

      batch.set(messageRef, {
        'teacherId': teacherId,
        'teacherName': teacherName,
        'parentId': parent['id'],
        'parentName': parent['name'] ?? 'Parent',
        'studentId': student['id'],
        'studentName': student['name'] ?? 'Student',
        'message': textToSave,
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (attachmentType != null) 'attachmentType': attachmentType,
        if (attachmentName != null) 'attachmentName': attachmentName,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'schoolId': schoolId,
        'type': 'direct'
      });

      // 2. Send Notification to Parent
      final notificationRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('notifications')
          .doc();

      batch.set(notificationRef, {
        'parentId': parent['id'],
        'studentId': student['id'],
        'studentName': student['name'] ?? 'Student',
        'title': "New Message from Teacher",
        'message': textToSave,
        'type': "message",
        'read': false,
        'createdAt': FieldValue.serverTimestamp()
      });

      await batch.commit();

      if (mounted) {
        state = state.copyWith(isSending: false, clearExpanded: true);
      }
    } catch (e) {
      print("ContactParents: Error sending message $e");
      if (mounted) {
        state = state.copyWith(isSending: false);
      }
      rethrow;
    }
  }

  Future<void> sendVoiceMessage({
    required Map<String, dynamic> student,
    required Map<String, dynamic> parent,
    required File audioFile,
  }) async {
    final teacherData = teacherDataAsync.value;
    if (teacherData == null) return;

    final schoolId = teacherData['schoolId'] as String?;
    final teacherId = teacherData['uid'] as String? ?? teacherData['id'] as String?; // Handle different auth models
    final teacherName = teacherData['name'] as String? ?? 'Teacher';

    if (schoolId == null || teacherId == null) return;

    state = state.copyWith(isSending: true);

    try {
      final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_voice.m4a';
      final refStorage = FirebaseStorage.instance.ref(destination);
      await refStorage.putFile(audioFile);
      final audioUrl = await refStorage.getDownloadURL();

      final batch = FirebaseFirestore.instance.batch();

      // 1. Create Message Record
      final messageRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('messages')
          .doc();

      batch.set(messageRef, {
        'teacherId': teacherId,
        'teacherName': teacherName,
        'parentId': parent['id'],
        'parentName': parent['name'] ?? 'Parent',
        'studentId': student['id'],
        'studentName': student['name'] ?? 'Student',
        'message': 'Sent a voice message',
        'attachmentUrl': audioUrl,
        'attachmentType': 'audio',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'schoolId': schoolId,
        'type': 'direct'
      });

      // 2. Send Notification to Parent
      final notificationRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('notifications')
          .doc();

      batch.set(notificationRef, {
        'parentId': parent['id'],
        'studentId': student['id'],
        'studentName': student['name'] ?? 'Student',
        'title': "New Voice Message from Teacher",
        'message': "Audio message received",
        'type': "message",
        'read': false,
        'createdAt': FieldValue.serverTimestamp()
      });

      await batch.commit();

      if (mounted) {
        state = state.copyWith(isSending: false, clearExpanded: true);
      }
    } catch (e) {
      print("ContactParents: Error sending voice message $e");
      if (mounted) {
        state = state.copyWith(isSending: false);
      }
      rethrow;
    }
  }

  Future<void> sendBroadcast({
    String? messageText,
    File? attachedFile,
    bool isVoice = false, 
  }) async {
    final teacherData = teacherDataAsync.value;
    final assignedClass = state.assignedClass;
    if (teacherData == null || assignedClass == null) return;

    final schoolId = teacherData['schoolId'] as String?;
    final teacherId = teacherData['uid'] as String? ?? teacherData['id'] as String?;
    final teacherName = teacherData['name'] as String? ?? 'Teacher';
    final classId = assignedClass['id'] as String?;

    if (schoolId == null || classId == null || teacherId == null) return;
    if (state.parentMap.isEmpty) return; // No parents to email

    state = state.copyWith(isSending: true);

    try {
      String? attachmentUrl;
      String? attachmentName;
      String? attachmentType;

      if (attachedFile != null) {
        final pathStr = attachedFile.path;
        attachmentName = pathStr.split('/').last;
        attachmentType = isVoice ? 'audio' : pathStr.split('.').last.toLowerCase();
        
        final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_$attachmentName';
        final refStorage = FirebaseStorage.instance.ref(destination);
        await refStorage.putFile(attachedFile);
        attachmentUrl = await refStorage.getDownloadURL();
      }

      final textToSave = (messageText != null && messageText.isNotEmpty)
          ? messageText.trim()
          : (isVoice ? 'Sent a voice message' : 'Sent an attachment');

      // 1. Create Master Broadcast Document
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
        'text': textToSave,
        'attachment': attachmentUrl != null ? {
          'url': attachmentUrl,
          'name': attachmentName,
          'type': attachmentType,
          'fullPath': FirebaseStorage.instance.refFromURL(attachmentUrl).fullPath,
        } : null,
        'timestamp': timestamp,
      };

      // Ensure batches don't exceed 500 limits by doing multiple batches if necessary
      // For a typical classroom (< 50 students), 1 batch is fine.
      final uniqueParents = state.parentMap.values.map((p) => p['id']).toSet(); // Ensure unique
      var batch = FirebaseFirestore.instance.batch();
      
      batch.set(broadcastRef, broadcastData);

      for (var parentId in uniqueParents) {
        // Find one student doc to associate (for notification consistency)
        final studentDocEntry = state.parentMap.entries.firstWhere(
            (e) => e.value['id'] == parentId,
            orElse: () => const MapEntry<String, dynamic>('', {}),
        );
        if (studentDocEntry.key.isEmpty) continue;
        final studentDoc = studentDocEntry.key;
        final studentInfo = state.students.firstWhere((s) => s['id'] == studentDoc, orElse: () { return <String, dynamic>{'name': 'Student', 'id': studentDoc}; });

        // Add Direct Message to Parent
        final msgRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('messages')
            .doc();

        batch.set(msgRef, {
          'teacherId': teacherId,
          'teacherName': teacherName,
          'parentId': parentId,
          'parentName': state.parentMap[studentDoc]?['name'] ?? 'Parent',
          'studentId': studentInfo['id'],
          'studentName': studentInfo['name'] ?? 'Student',
          'message': textToSave,
          'attachmentUrl': attachmentUrl,
          'attachmentType': attachmentType,
          'timestamp': timestamp,
          'read': false,
          'schoolId': schoolId,
          'type': 'class-broadcast', // Tag it
          'broadcastId': broadcastId,
        });

        // Add Notification
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
          'message': textToSave,
          'type': "message",
          'read': false,
          'createdAt': timestamp,
        });
      }

      await batch.commit();

      if (mounted) {
        state = state.copyWith(isSending: false);
      }
    } catch (e) {
      print("ContactParents: Error broadcasting $e");
      if (mounted) state = state.copyWith(isSending: false);
      rethrow;
    }
  }

  Future<void> deleteBroadcast(Map<String, dynamic> broadcast) async {
    final teacherData = teacherDataAsync.value;
    final assignedClass = state.assignedClass;
    if (teacherData == null || assignedClass == null) return;
    
    final schoolId = teacherData['schoolId'] as String?;
    final classId = assignedClass['id'] as String?;
    if (schoolId == null || classId == null) return;

    try {
      // Delete Master Broadcast Doc (Teacher UI view)
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('broadcasts')
          .doc(broadcast['id'])
          .delete();
          
    } catch (e) {
      print("Error deleting broadcast $e");
      rethrow;
    }
  }

  Future<void> clearHistory(List<Map<String, dynamic>> allBroadcasts) async {
    for (var broadcast in allBroadcasts) {
      await deleteBroadcast(broadcast);
    }
  }
}

final contactParentsProvider = StateNotifierProvider.autoDispose<ContactParentsNotifier, ContactParentsState>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  return ContactParentsNotifier(ref, teacherDataAsync);
});

final classBroadcastsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final assignedClassAsync = ref.watch(assignedClassProvider);

  if (teacherDataAsync.value == null || assignedClassAsync.value == null) {
     return Stream.value([]);
  }

  final schoolId = teacherDataAsync.value!['schoolId'];
  final classId = assignedClassAsync.value!['id'];

  return FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .doc(classId)
      .collection('broadcasts')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList());
});
