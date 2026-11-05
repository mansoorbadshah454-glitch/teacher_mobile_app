import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/app_theme.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';
import 'package:teacher_mobile_app/features/attendance/presentation/screens/attendance_screen.dart';
import 'package:teacher_mobile_app/features/contact_parents/providers/contact_parents_provider.dart';
import 'package:teacher_mobile_app/features/contact_parents/providers/parent_personal_chat_provider.dart';

class ParentPersonalChatScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  final Map<String, dynamic>? parentData;
  final String schoolId;

  const ParentPersonalChatScreen({
    super.key,
    required this.student,
    required this.parentData,
    required this.schoolId,
  });

  @override
  ConsumerState<ParentPersonalChatScreen> createState() => _ParentPersonalChatScreenState();
}

class _ParentPersonalChatScreenState extends ConsumerState<ParentPersonalChatScreen> {
  // Primary Light Sky Blue Palette
  static const Color skyBluePrimary = Color(0xFF0EA5E9); // Sky 500
  static const Color skyBlueLight = Color(0xFF38BDF8);   // Sky 400
  static const Color skyBlueDark = Color(0xFF0284C7);    // Sky 600

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Voice recording states
  bool _isRecording = false;
  late final AudioRecorder _audioRecorder;
  Timer? _recordingTimer;
  int _recordingDurationSeconds = 0;
  bool _isCanceled = false;

  // Local recorded audio preview states
  String? _recordedFilePath;
  late final AudioPlayer _previewPlayer;
  bool _isPlayingPreview = false;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;

  // Global Audio Player for playing voice notes in bubbles
  late final AudioPlayer _bubbleAudioPlayer;
  String? _currentlyPlayingBubbleUrl;
  bool _isBubblePlaying = false;
  Duration _bubblePosition = Duration.zero;
  Duration _bubbleDuration = Duration.zero;

  bool _isSendingLocal = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _previewPlayer = AudioPlayer();
    _bubbleAudioPlayer = AudioPlayer();

    // Preview Player listeners
    _previewPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlayingPreview = state == PlayerState.playing);
    });
    _previewPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _previewPosition = pos);
    });
    _previewPlayer.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _previewDuration = duration);
    });
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
          _previewPosition = Duration.zero;
        });
      }
    });

    // Bubble Audio Player listeners
    _bubbleAudioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isBubblePlaying = state == PlayerState.playing);
    });
    _bubbleAudioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _bubblePosition = pos);
    });
    _bubbleAudioPlayer.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _bubbleDuration = duration);
    });
    _bubbleAudioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isBubblePlaying = false;
          _bubblePosition = Duration.zero;
          _currentlyPlayingBubbleUrl = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _previewPlayer.dispose();
    _bubbleAudioPlayer.dispose();
    super.dispose();
  }

  DateTime? _parseTimestamp(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // --- Voice Recording Flow ---
  void _startTimer() {
    _recordingDurationSeconds = 0;
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingDurationSeconds++);
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final directory = await getTemporaryDirectory();
        final path = p.join(directory.path, 'voice_msg_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

        setState(() {
          _isRecording = true;
          _isCanceled = false;
        });
        _startTimer();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Microphone permission denied.")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<void> _stopRecordingSafely() async {
    _recordingTimer?.cancel();
    if (!_isRecording) return;
    try {
      final path = await _audioRecorder.stop();
      if (_isCanceled) {
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        if (mounted) setState(() {
          _isRecording = false;
          _recordedFilePath = null;
        });
        return;
      }

      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordedFilePath = path;
        });

        if (path != null) {
          await _previewPlayer.setSourceDeviceFile(path);
          final duration = await _previewPlayer.getDuration();
          if (duration != null && mounted) {
            setState(() => _previewDuration = duration);
          }
        }
      }
    } catch (e) {
      debugPrint("Error stopping recording: $e");
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isCanceled) {
      _isCanceled = true;
      await _stopRecordingSafely();
    }
  }

  Future<void> _deletePreview() async {
    if (_recordedFilePath != null) {
      final file = File(_recordedFilePath!);
      if (await file.exists()) await file.delete();
    }
    await _previewPlayer.stop();
    setState(() {
      _recordedFilePath = null;
      _isPlayingPreview = false;
      _previewPosition = Duration.zero;
      _previewDuration = Duration.zero;
    });
  }

  Future<void> _playPausePreview() async {
    if (_recordedFilePath == null) return;
    if (_isPlayingPreview) {
      await _previewPlayer.pause();
    } else {
      if (_previewPosition == _previewDuration && _previewDuration != Duration.zero) {
        await _previewPlayer.seek(Duration.zero);
      }
      await _previewPlayer.play(DeviceFileSource(_recordedFilePath!));
    }
  }

  Future<void> _sendVoiceNote() async {
    if (_recordedFilePath == null || widget.parentData == null) return;
    final file = File(_recordedFilePath!);
    setState(() => _isSendingLocal = true);

    try {
      final notifier = ref.read(contactParentsProvider.notifier);
      await notifier.sendVoiceMessage(
        student: widget.student,
        parent: widget.parentData!,
        audioFile: file,
      );
      await _deletePreview();
      // Instant local echo in chat stream
      ref.read(parentChatRefreshTriggerProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Voice note sent successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error sending voice note: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingLocal = false);
    }
  }

  // --- Attachments Flow ---
  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;

    final file = File(result.files.first.path!);
    final fileName = p.basename(file.path);
    final caption = await _showAttachmentConfirmation(file, fileName);
    if (caption != null) {
      await _sendAttachment(caption, file);
    }
  }

  Future<void> _takeAndSendPicture() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image == null) return;

    final file = File(image.path);
    final fileName = p.basename(image.path);
    final caption = await _showAttachmentConfirmation(file, fileName);
    if (caption != null) {
      await _sendAttachment(caption, file);
    }
  }

  Future<void> _pickAndSendGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    final file = File(image.path);
    final fileName = p.basename(image.path);
    final caption = await _showAttachmentConfirmation(file, fileName);
    if (caption != null) {
      await _sendAttachment(caption, file);
    }
  }

  Future<String?> _showAttachmentConfirmation(File file, String fileName) async {
    final captionController = TextEditingController();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(fileName.split('.').last.toLowerCase());

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Send Attachment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isImage)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file, fit: BoxFit.contain),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file, color: skyBluePrimary, size: 32),
                        const SizedBox(width: 12),
                        Expanded(child: Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: captionController,
                  decoration: InputDecoration(
                    hintText: 'Add a caption...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  maxLines: 3,
                  minLines: 1,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, captionController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: skyBluePrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  void _showAttachmentMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAttachmentOption(
              icon: Icons.insert_drive_file_rounded,
              color: skyBlueDark,
              label: "Document",
              onTap: _pickAndSendFile,
            ),
            _buildAttachmentOption(
              icon: Icons.camera_alt_rounded,
              color: skyBluePrimary,
              label: "Camera",
              onTap: _takeAndSendPicture,
            ),
            _buildAttachmentOption(
              icon: Icons.image_rounded,
              color: Colors.indigoAccent,
              label: "Gallery",
              onTap: _pickAndSendGallery,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
        ],
      ),
    );
  }

  Future<void> _sendAttachment(String caption, File file) async {
    if (widget.parentData == null) return;
    setState(() => _isSendingLocal = true);
    try {
      final notifier = ref.read(contactParentsProvider.notifier);
      await notifier.sendMessage(
        student: widget.student,
        parent: widget.parentData!,
        messageText: caption,
        attachedFile: file,
      );
      // Instant local echo in chat stream
      ref.read(parentChatRefreshTriggerProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Attachment sent successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send attachment: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingLocal = false);
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || widget.parentData == null) return;

    _messageController.clear();
    setState(() => _isSendingLocal = true);

    try {
      final notifier = ref.read(contactParentsProvider.notifier);
      await notifier.sendMessage(
        student: widget.student,
        parent: widget.parentData!,
        messageText: text,
      );
      // Instant local echo in chat stream
      ref.read(parentChatRefreshTriggerProvider.notifier).state++;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingLocal = false);
    }
  }

  // --- Voice Bubble Audio Playback ---
  Future<void> _toggleBubbleAudio(String audioSource) async {
    if (_currentlyPlayingBubbleUrl == audioSource && _isBubblePlaying) {
      await _bubbleAudioPlayer.pause();
    } else if (_currentlyPlayingBubbleUrl == audioSource && !_isBubblePlaying) {
      await _bubbleAudioPlayer.resume();
    } else {
      await _bubbleAudioPlayer.stop();
      setState(() {
        _currentlyPlayingBubbleUrl = audioSource;
        _bubblePosition = Duration.zero;
      });

      if (audioSource.startsWith('http://') || audioSource.startsWith('https://')) {
        await _bubbleAudioPlayer.play(UrlSource(audioSource));
      } else {
        await _bubbleAudioPlayer.play(DeviceFileSource(audioSource));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parentId = widget.parentData?['id'] as String? ?? '';
    final studentId = widget.student['id'] as String? ?? '';

    // Watch personal chat messages stream
    final chatParams = ParentPersonalChatParams(
      schoolId: widget.schoolId,
      parentId: parentId,
      studentId: studentId,
    );

    final chatAsync = parentId.isNotEmpty
        ? ref.watch(parentPersonalChatMessagesProvider(chatParams))
        : const AsyncValue.data(<Map<String, dynamic>>[]);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.backgroundDark : const Color(0xFFF0F2F5),
                image: DecorationImage(
                  image: const AssetImage('assets/images/chat_bg.png'),
                  fit: BoxFit.cover,
                  colorFilter: isDark
                      ? ColorFilter.mode(Colors.black.withOpacity(0.85), BlendMode.darken)
                      : ColorFilter.mode(Colors.white.withOpacity(0.2), BlendMode.lighten),
                ),
              ),
              child: widget.parentData == null
                  ? _buildUnlinkedState()
                  : _buildChatList(chatAsync, isDark),
            ),
          ),
          if (widget.parentData != null) _buildMessageComposer(isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final parentName = widget.parentData?['name'] as String?;
    final isLinked = widget.parentData != null;
    final studentName = widget.student['name'] ?? 'Student';
    final rollNo = widget.student['rollNo'] ?? '-';

    return Container(
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [skyBlueLight, skyBlueDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          StudentAvatar(
            studentId: widget.student['id'] ?? '',
            schoolId: widget.schoolId,
            profilePic: widget.student['profilePic'] ?? "https://api.dicebear.com/7.x/avataaars/svg?seed=${widget.student['id']}",
            size: 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "#$rollNo",
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isLinked ? "Parent: $parentName" : "No Parent Linked",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: SyncQueueService.pendingCountNotifier,
            builder: (context, pendingCount, _) {
              final studentId = widget.student['id'] as String? ?? '';
              final parentId = widget.parentData?['id'] as String? ?? '';
              final chatPending = SyncQueueService.getPendingMessagesFor(
                schoolId: widget.schoolId,
                parentId: parentId,
                studentId: studentId,
              ).length;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chatPending > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, color: Colors.white, size: 11),
                          const SizedBox(width: 3),
                          Text(
                            "$chatPending queued",
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLinked ? Colors.green.shade600 : Colors.red.shade400,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLinked ? Icons.link : Icons.link_off,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLinked ? "Linked" : "Unlinked",
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }


  Widget _buildUnlinkedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link_off_rounded, size: 48, color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text(
              "Parent Not Linked",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "No parent account is currently linked to ${widget.student['name'] ?? 'this student'}. Please ask the parent to enter the student's Roll Number (#${widget.student['rollNo'] ?? '-'}) in the Parent App to link.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(AsyncValue<List<Map<String, dynamic>>> chatAsync, bool isDark) {
    return chatAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: skyBluePrimary),
      ),
      error: (err, stack) => Center(
        child: Text("Error loading chat: $err", style: const TextStyle(color: Colors.red)),
      ),
      data: (messages) {
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
                const SizedBox(height: 12),
                const Text(
                  "No recent messages",
                  style: TextStyle(color: Colors.grey, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Send a direct message or voice note to begin.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return _buildMessageBubble(message, isDark);
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isDark) {
    final bool isOutgoing = (message['senderRole'] != 'parent' && message['type'] != 'parent-reply');
    final String text = message['message'] ?? message['messageText'] ?? '';
    final String? attachmentUrl = message['attachmentUrl'] as String?;
    final String? attachmentType = message['attachmentType'] as String?;
    final String? attachmentName = message['attachmentName'] as String?;
    final String? localFilePath = message['localFilePath'] as String?;
    final bool isPending = message['isPending'] == true;
    final bool isRead = message['read'] == true;
    final DateTime? timestamp = _parseTimestamp(message['timestamp']);

    final timeString = timestamp != null ? DateFormat('h:mm a').format(timestamp) : '';

    final audioSource = localFilePath ?? attachmentUrl;
    final isVoice = attachmentType == 'audio' || (audioSource != null && audioSource.endsWith('.m4a'));

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOutgoing
              ? skyBlueDark
              : (isDark ? AppTheme.surfaceDark : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
            bottomRight: Radius.circular(isOutgoing ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isOutgoing ? 0.08 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: isOutgoing
              ? null
              : Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Voice Note Layout
            if (isVoice && audioSource != null)
              _buildVoiceBubblePlayer(audioSource, isOutgoing, isDark)
            // Image Attachment
            else if (attachmentUrl != null && ['jpg', 'jpeg', 'png', 'webp'].contains(attachmentType?.toLowerCase()))
              _buildImageAttachment(attachmentUrl, isOutgoing)
            // Document / File Attachment
            else if (attachmentUrl != null)
              _buildDocumentAttachment(attachmentUrl, attachmentName ?? 'Document', isOutgoing),

            // Text content (if not generic voice placeholder)
            if (text.isNotEmpty && text != 'Sent a voice message' && text != 'Sent an attachment') ...[
              if (attachmentUrl != null || isVoice) const SizedBox(height: 6),
              Text(
                text,
                style: TextStyle(
                  color: isOutgoing ? Colors.white : (isDark ? Colors.white : Colors.black87),
                  fontSize: 14.5,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 4),

            // Metadata row: Time & Seen Status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeString,
                  style: TextStyle(
                    color: isOutgoing ? Colors.white70 : Colors.grey,
                    fontSize: 10.5,
                  ),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  if (isPending)
                    const Icon(Icons.access_time, size: 12, color: Colors.white70)
                  else if (isRead)
                    const Icon(Icons.done_all, size: 14, color: Color(0xFFE0F2FE)) // Bright cyan double tick
                  else
                    const Icon(Icons.done_all, size: 14, color: Colors.white70), // Grey double tick
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceBubblePlayer(String audioSource, bool isOutgoing, bool isDark) {
    final isThisPlaying = _currentlyPlayingBubbleUrl == audioSource && _isBubblePlaying;
    final position = _currentlyPlayingBubbleUrl == audioSource ? _bubblePosition : Duration.zero;
    final duration = _currentlyPlayingBubbleUrl == audioSource ? _bubbleDuration : Duration.zero;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _toggleBubbleAudio(audioSource),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOutgoing ? Colors.white : skyBluePrimary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isThisPlaying ? Icons.pause : Icons.play_arrow,
              color: isOutgoing ? skyBlueDark : Colors.white,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: SliderTheme(
                  data: SliderThemeData(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    trackHeight: 3,
                    thumbColor: isOutgoing ? Colors.white : skyBluePrimary,
                    activeTrackColor: isOutgoing ? Colors.white : skyBluePrimary,
                    inactiveTrackColor: isOutgoing ? Colors.white38 : Colors.grey.shade300,
                  ),
                  child: Slider(
                    value: position.inMilliseconds.toDouble(),
                    max: duration.inMilliseconds.toDouble() > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                    onChanged: (val) {
                      if (_currentlyPlayingBubbleUrl == audioSource) {
                        _bubbleAudioPlayer.seek(Duration(milliseconds: val.toInt()));
                      }
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  _formatDuration(position.inSeconds),
                  style: TextStyle(
                    fontSize: 10,
                    color: isOutgoing ? Colors.white70 : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageAttachment(String imageUrl, bool isOutgoing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            height: 140,
            width: double.infinity,
            color: Colors.grey.withOpacity(0.15),
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2, color: skyBluePrimary),
          ),
          errorWidget: (context, url, error) => Container(
            height: 100,
            color: Colors.grey.withOpacity(0.2),
            child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentAttachment(String url, String fileName, bool isOutgoing) {
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isOutgoing ? Colors.white.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, color: isOutgoing ? Colors.white : skyBluePrimary, size: 24),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isOutgoing ? Colors.white : Colors.black87,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Live Recording Banner
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDuration(_recordingDurationSeconds),
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  const Text(
                    "< Slide left to cancel",
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          // 2. Audio Preview Player
          else if (_recordedFilePath != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isDark ? skyBluePrimary.withOpacity(0.12) : Colors.lightBlue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: skyBluePrimary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _deletePreview,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(isDark ? 0.1 : 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _playPausePreview,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: skyBluePrimary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_isPlayingPreview ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _previewPosition.inMilliseconds.toDouble(),
                        max: _previewDuration.inMilliseconds.toDouble() > 0 ? _previewDuration.inMilliseconds.toDouble() : 1.0,
                        activeColor: skyBluePrimary,
                        inactiveColor: skyBluePrimary.withOpacity(0.3),
                        onChanged: (val) {
                          _previewPlayer.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(_previewDuration.inSeconds),
                    style: const TextStyle(fontSize: 11, color: skyBlueDark, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSendingLocal ? null : _sendVoiceNote,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: skyBlueDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSendingLocal
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Send", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ),

          // 3. Main Input Bar (Text + Voice + Attachment)
          if (_recordedFilePath == null)
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 26),
                  onPressed: _isSendingLocal ? null : _showAttachmentMenu,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.backgroundDark : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: 4,
                      minLines: 1,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: "Message ${widget.parentData?['name'] ?? 'Parent'}...",
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_messageController.text.trim().isNotEmpty)
                  GestureDetector(
                    onTap: _isSendingLocal ? null : _sendTextMessage,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: skyBluePrimary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: _isSendingLocal
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  )
                else
                  GestureDetector(
                    onTapDown: (_) {
                      if (!_isSendingLocal) _startRecording();
                    },
                    onTapUp: (_) => _stopRecordingSafely(),
                    onTapCancel: () => _cancelRecording(),
                    onPanUpdate: (details) {
                      if (_isRecording && details.delta.dx < -2) {
                        _cancelRecording();
                      }
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : skyBluePrimary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
