import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/note_model.dart';
import '../providers/notebook_provider.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note? note;
  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  Color _selectedColor = const Color(0xFF1E293B);
  DateTime? _reminderDateTime;

  final List<Color> _colors = [
    const Color(0xFF1E293B), // Dark slate
    const Color(0xFF3B82F6), // Blue
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEF4444), // Red
    const Color(0xFF8B5CF6), // Purple
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
    _selectedColor = widget.note?.color ?? _colors[0];
    _reminderDateTime = widget.note?.reminderDateTime;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _saveNote() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    
    if (title.isEmpty && content.isEmpty) {
      if (context.canPop()) {
         context.pop();
      }
      return;
    }

    final note = Note(
      id: widget.note?.id ?? const Uuid().v4(),
      title: title,
      content: content,
      color: _selectedColor,
      createdAt: widget.note?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      reminderDateTime: _reminderDateTime,
    );

    ref.read(notesProvider.notifier).saveNote(note);
    if (context.canPop()) {
       context.pop();
    }
  }

  void _deleteNote() {
    if (widget.note != null) {
      ref.read(notesProvider.notifier).deleteNote(widget.note!.id);
      if (context.canPop()) {
         context.pop();
      }
    }
  }

  Future<void> _pickReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderDateTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_reminderDateTime ?? DateTime.now().add(const Duration(minutes: 5))),
      );

      if (time != null) {
        setState(() {
          _reminderDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _saveNote();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _saveNote(),
          ),
          actions: [
            if (_reminderDateTime != null)
               Center(
                 child: Padding(
                   padding: const EdgeInsets.only(right: 8.0),
                   child: Text(
                     DateFormat('MMM d, h:mm a').format(_reminderDateTime!),
                     style: TextStyle(
                       color: _reminderDateTime!.isBefore(DateTime.now()) 
                           ? Colors.grey 
                           : const Color(0xFF3B82F6), 
                       fontSize: 12, 
                       fontWeight: FontWeight.bold,
                     ),
                   ),
                 ),
               ),
            IconButton(
              icon: Icon(
                Icons.alarm_add, 
                color: _reminderDateTime != null ? const Color(0xFF3B82F6) : Colors.grey[600],
              ),
              onPressed: _pickReminder,
              tooltip: 'Set Reminder',
            ),
            if (widget.note != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _deleteNote,
              ),
            IconButton(
              icon: const Icon(Icons.check, color: Color(0xFF10B981)),
              onPressed: _saveNote,
            ),
          ],
        ),
        body: Column(
          children: [
            // Color picker
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                itemBuilder: (context, index) {
                  final color = _colors[index];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: _selectedColor == color
                            ? Border.all(color: Colors.grey, width: 2)
                            : null,
                      ),
                      child: _selectedColor == color
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleController,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _selectedColor,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Note Title',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _contentController,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: const Color(0xFF334155),
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Start typing...',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                        ),
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
