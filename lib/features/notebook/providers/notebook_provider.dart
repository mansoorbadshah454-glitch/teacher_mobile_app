import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note_model.dart';
import '../services/notebook_storage_service.dart';
import '../services/notification_service.dart';

import 'package:firebase_auth/firebase_auth.dart';

final notebookStorageServiceProvider = Provider((ref) => NotebookStorageService());
final notificationServiceProvider = Provider((ref) => NotificationService());

final notesProvider = StateNotifierProvider<NotesNotifier, AsyncValue<List<Note>>>((ref) {
  return NotesNotifier(
    ref.read(notebookStorageServiceProvider),
    ref.read(notificationServiceProvider),
  );
});

class NotesNotifier extends StateNotifier<AsyncValue<List<Note>>> {
  final NotebookStorageService _storageService;
  final NotificationService _notificationService;

  NotesNotifier(this._storageService, this._notificationService) : super(const AsyncValue.loading()) {
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        state = const AsyncValue.data([]);
        return;
      }
      final notes = await _storageService.getNotes(uid);
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveNote(Note note) async {
    try {
      if (state.value == null) return;
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final updatedNote = note.teacherId == null ? note.copyWith(teacherId: uid) : note;
      
      await _storageService.saveNote(updatedNote);
      
      if (updatedNote.reminderDateTime != null && updatedNote.reminderDateTime!.isAfter(DateTime.now())) {
        await _notificationService.scheduleNotification(
          id: updatedNote.id.hashCode,
          title: "Note Reminder: \${updatedNote.title}",
          body: updatedNote.content.length > 50 ? "\${updatedNote.content.substring(0, 50)}..." : updatedNote.content,
          scheduledDate: updatedNote.reminderDateTime!,
        );
      } else {
        await _notificationService.cancelNotification(updatedNote.id.hashCode);
      }

      final notes = await _storageService.getNotes(uid);
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      print("Error saving note: \$e");
    }
  }

  Future<void> deleteNote(String id) async {
    try {
       if (state.value == null) return;
       
       final uid = FirebaseAuth.instance.currentUser?.uid;
       if (uid == null) return;

       await _storageService.deleteNote(id);
       await _notificationService.cancelNotification(id.hashCode);
       
       final notes = await _storageService.getNotes(uid);
       state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      print("Error deleting note: \$e");
    }
  }
}
