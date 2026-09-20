import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';

final resultUploadProvider = StateNotifierProvider<ResultUploadNotifier, ResultUploadState>((ref) {
  return ResultUploadNotifier(ref);
});

class ResultUploadState {
  final bool isLoading;
  final String? error;
  final bool isSuccess;
  final File? selectedFile;
  final String? fileName;

  ResultUploadState({
    this.isLoading = false,
    this.error,
    this.isSuccess = false,
    this.selectedFile,
    this.fileName,
  });

  ResultUploadState copyWith({
    bool? isLoading,
    String? error,
    bool? isSuccess,
    File? selectedFile,
    String? fileName,
  }) {
    return ResultUploadState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      selectedFile: selectedFile ?? this.selectedFile,
      fileName: fileName ?? this.fileName,
    );
  }
}

class ResultUploadNotifier extends StateNotifier<ResultUploadState> {
  final Ref ref;

  ResultUploadNotifier(this.ref) : super(ResultUploadState());

  void clearState() {
    state = ResultUploadState();
  }

  Future<void> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf'],
      );

      if (result != null && result.files.single.path != null) {
        state = state.copyWith(
          selectedFile: File(result.files.single.path!),
          fileName: result.files.single.name,
          error: null,
          isSuccess: false,
        );
      }
    } catch (e) {
      state = state.copyWith(error: "Error selecting file: $e");
    }
  }

  Future<void> uploadResult(String studentId) async {
    if (state.selectedFile == null) {
      state = state.copyWith(error: "Please select a file first");
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final user = ref.read(currentUserProvider);
      final teacherData = ref.read(teacherDataProvider).value ?? 
          (user != null ? LocalDbService.getCache('teacher_profile_${user.uid}') as Map<String, dynamic>? : null);

      if (teacherData == null) throw Exception("Teacher data not found");

      final String schoolId = teacherData['schoolId'];
      final String fileExtension = state.fileName!.split('.').last;
      final bool online = await SyncQueueService.isOnline();

      if (!online) {
        // Offline queue
        final appDir = await getApplicationDocumentsDirectory();
        final outboxDir = Directory('${appDir.path}/outbox_results');
        await outboxDir.create(recursive: true);
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${state.fileName}';
        final persistentFile = await state.selectedFile!.copy('${outboxDir.path}/$fileName');

        await SyncQueueService.enqueue(
          type: 'exam_result_upload',
          payload: {
            'schoolId': schoolId,
            'studentId': studentId,
            'fileName': state.fileName,
            'fileExtension': fileExtension,
          },
          filePath: persistentFile.path,
        );

        state = state.copyWith(isLoading: false, isSuccess: true, error: null);
        return;
      }

      // Online direct upload
      try {
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String storagePath = 'schools/$schoolId/students/$studentId/results/result_$timestamp.$fileExtension';

        final Reference storageRef = FirebaseStorage.instance.ref().child(storagePath);
        final UploadTask uploadTask = storageRef.putFile(state.selectedFile!);
        final TaskSnapshot snapshot = await uploadTask;
        final String downloadUrl = await snapshot.ref.getDownloadURL();

        final DocumentReference studentRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .doc(studentId);

        await studentRef.update({
          'uploadedResultUrl': downloadUrl,
          'uploadedResultType': fileExtension,
          'uploadedResultAt': FieldValue.serverTimestamp(),
        });

        state = state.copyWith(isLoading: false, isSuccess: true, error: null);
      } catch (uploadErr) {
        // Network fallback
        final appDir = await getApplicationDocumentsDirectory();
        final outboxDir = Directory('${appDir.path}/outbox_results');
        await outboxDir.create(recursive: true);
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${state.fileName}';
        final persistentFile = await state.selectedFile!.copy('${outboxDir.path}/$fileName');

        await SyncQueueService.enqueue(
          type: 'exam_result_upload',
          payload: {
            'schoolId': schoolId,
            'studentId': studentId,
            'fileName': state.fileName,
            'fileExtension': fileExtension,
          },
          filePath: persistentFile.path,
        );

        state = state.copyWith(isLoading: false, isSuccess: true, error: null);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: "Upload failed: $e");
    }
  }
}
