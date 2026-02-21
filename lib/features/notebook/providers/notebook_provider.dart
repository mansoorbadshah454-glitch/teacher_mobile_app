import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note_model.dart';
import '../services/notebook_storage_service.dart';
import '../services/notification_service.dart';

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
      final notes = await _storageService.getNotes();
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> saveNote(Note note) async {
    try {
      if (state.value == null) return;
      
      await _storageService.saveNote(note);
      
      if (note.reminderDateTime != null && note.reminderDateTime!.isAfter(DateTime.now())) {
        await _notificationService.scheduleNotification(
          id: note.id.hashCode,
          title: "Note Reminder: \${note.title}",
          body: note.content.length > 50 ? "\${note.content.substring(0, 50)}..." : note.content,
          scheduledDate: note.reminderDateTime!,
        );
      } else {
        await _notificationService.cancelNotification(note.id.hashCode);
      }

      final notes = await _storageService.getNotes();
      state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      print("Error saving note: \$e");
    }
  }

  Future<void> deleteNote(String id) async {
    try {
       if (state.value == null) return;
       
       await _storageService.deleteNote(id);
       await _notificationService.cancelNotification(id.hashCode);
       
       final notes = await _storageService.getNotes();
       state = AsyncValue.data(notes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      print("Error deleting note: \$e");
    }
  }
}
