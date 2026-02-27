import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  ContactParentsState({
    this.assignedClass,
    this.students = const [],
    this.parentMap = const {},
    this.isLoading = false,
    this.isSending = false,
    this.searchTerm = '',
    this.expandedStudentId,
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
  }) {
    return ContactParentsState(
      assignedClass: assignedClass ?? this.assignedClass,
      students: students ?? this.students,
      parentMap: parentMap ?? this.parentMap,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      searchTerm: searchTerm ?? this.searchTerm,
      expandedStudentId: clearExpanded ? null : (expandedStudentId ?? this.expandedStudentId),
    );
  }
}

class ContactParentsNotifier extends StateNotifier<ContactParentsState> {
  final Ref ref;
  final AsyncValue<Map<String, dynamic>?> teacherDataAsync;

  ContactParentsNotifier(this.ref, this.teacherDataAsync) : super(ContactParentsState()) {
    _init();

    // Listen to the class students stream for real-time updates
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

  Future<void> sendMessage({
    required Map<String, dynamic> student,
    required Map<String, dynamic> parent,
    required String messageText,
  }) async {
    if (messageText.trim().isEmpty) return;
    
    final teacherData = teacherDataAsync.value;
    if (teacherData == null) return;

    final schoolId = teacherData['schoolId'] as String?;
    final teacherId = teacherData['uid'] as String? ?? teacherData['id'] as String?; // Handle different auth models
    final teacherName = teacherData['name'] as String? ?? 'Teacher';

    if (schoolId == null || teacherId == null) return;

    state = state.copyWith(isSending: true);

    try {
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
        'message': messageText.trim(),
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
        'message': messageText.trim(),
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
}

final contactParentsProvider = StateNotifierProvider<ContactParentsNotifier, ContactParentsState>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  return ContactParentsNotifier(ref, teacherDataAsync);
});
