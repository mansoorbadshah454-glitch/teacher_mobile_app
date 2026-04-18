import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/contact_parents/providers/contact_parents_provider.dart';

class GroupBroadcastView extends StatefulWidget {
  final ContactParentsState state;
  final ContactParentsNotifier notifier;
  final AsyncValue<List<Map<String, dynamic>>> broadcastsAsync;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final Function(String) onSelectToggle;

  const GroupBroadcastView({
    Key? key,
    required this.state,
    required this.notifier,
    required this.broadcastsAsync,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onSelectToggle,
  }) : super(key: key);

  @override
  State<GroupBroadcastView> createState() => _GroupBroadcastViewState();
}

class _GroupBroadcastViewState extends State<GroupBroadcastView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _pendingBroadcasts = [];
  
  // Recording states
  bool _isRecording = false;
  late final AudioRecorder _audioRecorder;
  Timer? _recordingTimer;
  int _recordingDurationSeconds = 0;
  bool _isCanceled = false;

  // Audio Playback & Preview
  late final AudioPlayer _audioPlayer;
  String? _currentlyPlayingUrl;
  
  String? _recordedFilePath;
  bool _isPlayingPreview = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlayingPreview = state == PlayerState.playing);
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _currentPosition = pos);
    });
    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _totalDuration = duration);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
          _currentPosition = Duration.zero;
          _currentlyPlayingUrl = null;
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
    _audioPlayer.dispose();
    super.dispose();
  }

  // ==== Media / Attachment Logging ====
  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    
    final file = File(result.files.first.path!);
    final fileName = p.basename(file.path);
    final caption = await _showAttachmentConfirmation(file, fileName);
    if (caption != null) {
      _addPendingAndSend(caption, file, 'document', fileName);
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
      _addPendingAndSend(caption, file, 'jpg', fileName);
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
      _addPendingAndSend(caption, file, 'jpg', fileName);
    }
  }

  void _addPendingAndSend(String text, File? file, String? type, String? fileName) {
    final pendingId = "pending_${DateTime.now().millisecondsSinceEpoch}";
    setState(() {
      _pendingBroadcasts.insert(0, {
         'id': pendingId,
         'text': text,
         'attachment': file != null ? {'type': type, 'localPath': file.path, 'name': fileName} : null,
         'timestamp': Timestamp.now(),
         'isPending': true,
      });
    });

    widget.notifier.sendBroadcast(messageText: text, attachedFile: file, isVoice: type == 'audio').then((_) {
       if (mounted) setState(() => _pendingBroadcasts.removeWhere((m) => m['id'] == pendingId));
    }).catchError((_) {
       if (mounted) setState(() => _pendingBroadcasts.removeWhere((m) => m['id'] == pendingId));
    });
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
       context: context,
       backgroundColor: Colors.transparent,
       builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
             margin: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
             padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
             decoration: BoxDecoration(
               color: isDark ? AppTheme.surfaceDark : Colors.white, 
               borderRadius: BorderRadius.circular(16)
             ),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                 _buildAttachmentOption(icon: Icons.insert_drive_file, color: Colors.indigoAccent, label: "Document", onTap: _pickAndSendFile),
                 _buildAttachmentOption(icon: Icons.camera_alt, color: Colors.pinkAccent, label: "Camera", onTap: _takeAndSendPicture),
                 _buildAttachmentOption(icon: Icons.image, color: Colors.purpleAccent, label: "Gallery", onTap: _pickAndSendGallery),
               ]
             )
          );
       }
    );
  }

  Widget _buildAttachmentOption({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
     final isDark = Theme.of(context).brightness == Brightness.dark;
     return GestureDetector(
       onTap: () { Navigator.pop(context); onTap(); },
       child: Column(
         mainAxisSize: MainAxisSize.min,
         children: [
            CircleAvatar(radius: 28, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 28)),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87))
         ]
       )
     );
  }

  Future<String?> _showAttachmentConfirmation(File file, String fileName) async {
    final captionController = TextEditingController();
    final isImage = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(fileName.split('.').last.toLowerCase());

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Broadcast Attachment'),
          content: SingleChildScrollView(
            child: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                 if (isImage)
                   ConstrainedBox(constraints: const BoxConstraints(maxHeight: 200), child: Image.file(file, fit: BoxFit.contain))
                 else
                   Container(
                     padding: const EdgeInsets.all(16),
                     color: Colors.grey.withOpacity(0.1),
                     child: Text(fileName, maxLines: 2),
                   ),
                 const SizedBox(height: 16),
                 TextField(
                   controller: captionController,
                   decoration: const InputDecoration(hintText: 'Add a caption...', border: OutlineInputBorder()),
                   maxLines: 3, minLines: 1,
                 ),
               ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, captionController.text), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white), child: const Text('Send Broadcast')),
          ],
        );
      },
    );
  }

  // ==== Audio Recording Logic ====
  void _startTimer() {
    _recordingDurationSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _recordingDurationSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int rem = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rem.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    setState(() { _isRecording = true; _isCanceled = false; });
    
    if (await Permission.microphone.request().isGranted) {
      if (!_isRecording || _isCanceled) return;
      final tempDir = Directory.systemTemp;
      final path = p.join(tempDir.path, 'broadcast_msg_${DateTime.now().millisecondsSinceEpoch}.m4a');
      try {
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        if (!_isRecording || _isCanceled) {
           await _audioRecorder.stop();
           return;
        }
        _startTimer();
      } catch (e) {
        if (mounted) setState(() => _isRecording = false);
      }
    } else {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecordingSafely() async {
    _recordingTimer?.cancel();
    if (!_isRecording) return;
    
    setState(() => _isRecording = false);
    
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {}

    if (_isCanceled || path == null) {
      if (path != null && File(path).existsSync()) {
        File(path).deleteSync();
      }
      return;
    }

    // Entering Preview Mode
    setState(() => _recordedFilePath = path);
    await _audioPlayer.setSourceDeviceFile(path);
    final duration = await _audioPlayer.getDuration();
    if (duration != null && mounted) setState(() => _totalDuration = duration);
  }

  void _deletePreview({bool deleteFile = true}) {
     if (deleteFile && _recordedFilePath != null && File(_recordedFilePath!).existsSync()) {
        File(_recordedFilePath!).deleteSync();
     }
     _audioPlayer.stop();
     setState(() {
       _recordedFilePath = null;
       _isPlayingPreview = false;
       _currentPosition = Duration.zero;
       _totalDuration = Duration.zero;
     });
  }

  Future<void> _playPausePreview() async {
    if (_recordedFilePath == null) return;
    if (_isPlayingPreview) {
      await _audioPlayer.pause();
    } else {
      if (_currentPosition == _totalDuration && _totalDuration != Duration.zero) {
        await _audioPlayer.seek(Duration.zero);
      }
      await _audioPlayer.play(DeviceFileSource(_recordedFilePath!));
    }
  }

  // ==== UI Build ====

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        if (widget.isSelectionMode)
           Container(
             height: 70,
             color: AppTheme.primary.withOpacity(0.1),
             padding: const EdgeInsets.symmetric(horizontal: 16),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                  Text("${widget.selectedIds.length} Selected", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFdb2777))),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete, color: Colors.white, size: 18), 
                        label: const Text("Delete Selected", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.redAccent,
                           foregroundColor: Colors.white,
                           elevation: 0,
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                        ),
                        onPressed: widget.selectedIds.isEmpty ? null : () async {
                           final itemsToDelete = widget.broadcastsAsync.value?.where((b) => widget.selectedIds.contains(b['id'])).toList() ?? [];
                           for (var item in itemsToDelete) {
                              await widget.notifier.deleteBroadcast(item);
                           }
                           widget.onSelectToggle('CLEAR_ALL_MODE');
                        }
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey), 
                        onPressed: () => widget.onSelectToggle('CLEAR_ALL_MODE')
                      ),
                    ],
                  )
               ],
             )
           ),
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
            child: widget.broadcastsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (broadcasts) {
                if (broadcasts.isEmpty && _pendingBroadcasts.isEmpty) {
                  return _buildEmptyState();
                }
              return ListView.builder(
                controller: _scrollController,
                reverse: true, // Show bottom messages first natively
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
                itemCount: broadcasts.length + _pendingBroadcasts.length,
                itemBuilder: (context, index) {
                  final Map<String, dynamic> msg;
                  if (index < _pendingBroadcasts.length) {
                     msg = _pendingBroadcasts[index];
                  } else {
                     msg = broadcasts[index - _pendingBroadcasts.length];
                  }
                  
                  final isSelected = widget.selectedIds.contains(msg['id']);
                  
                  Widget bubble = _buildBroadcastBubble(msg);
                  
                  if (widget.isSelectionMode) {
                     return GestureDetector(
                       onTap: () => widget.onSelectToggle(msg['id']),
                       child: Container(
                         color: isSelected ? AppTheme.primary.withOpacity(0.1) : Colors.transparent,
                         padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                         margin: const EdgeInsets.only(bottom: 2),
                         child: Row(
                           children: [
                             Checkbox(
                               value: isSelected, 
                               onChanged: (_) => widget.onSelectToggle(msg['id']),
                               activeColor: const Color(0xFFdb2777),
                               shape: const CircleBorder(),
                             ),
                             Expanded(child: bubble),
                           ],
                         ),
                       ),
                     );
                  }

                  return GestureDetector(
                    onLongPress: () {
                      widget.onSelectToggle(msg['id']);
                    },
                    child: bubble,
                  );
                },
              );
            },
          ),
        ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           Container(
             padding: const EdgeInsets.all(24),
             decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle),
             child: const Icon(Icons.campaign, size: 64, color: AppTheme.primary),
           ),
           const SizedBox(height: 16),
           const Text("Start a Broadcast", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
           const SizedBox(height: 8),
           const Text("Messages sent here will be individually delivered\nto every parent in the assigned class.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ],
      )
    );
  }

  Widget _buildBroadcastBubble(Map<String, dynamic> msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    String formattedTime = '';
    if (msg['timestamp'] is Timestamp) {
      formattedTime = DateFormat('h:mm a').format((msg['timestamp'] as Timestamp).toDate());
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark.withOpacity(0.8) : Colors.white,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg['attachment'] != null) ...[
               _buildAttachment(msg['attachment']),
               const SizedBox(height: 8),
            ],
            
            if (msg['text'] != null && msg['text'].toString().trim().isNotEmpty && msg['attachment']?['type'] != 'audio')
              Text(msg['text'], style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
              
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formattedTime, style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey)),
                  const SizedBox(width: 4),
                  if (msg['isPending'] == true)
                    const SizedBox(
                       width: 10, height: 10,
                       child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)
                    )
                  else
                    const Icon(Icons.done_all, size: 14, color: Colors.blue),
                ]
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachment(Map<String, dynamic> attachment) {
    final type = attachment['type']?.toString().toLowerCase() ?? '';
    final url = attachment['url'];
    final localPath = attachment['localPath'];
    final audioSourceUrl = url ?? localPath;
    
    if (type == 'audio') {
      final isPlayingHere = _currentlyPlayingUrl != null && _currentlyPlayingUrl == audioSourceUrl;
      double fillRatio = 0.0;
      if (isPlayingHere && _totalDuration.inMilliseconds > 0) {
        fillRatio = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
      }
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        width: 220,
        child: Row(
          children: [
            GestureDetector(
              onTap: () async {
                if (audioSourceUrl == null) return;
                
                if (isPlayingHere) {
                  await _audioPlayer.pause();
                  setState(() => _currentlyPlayingUrl = null);
                } else {
                  if (url != null) {
                    await _audioPlayer.play(UrlSource(url));
                  } else if (localPath != null) {
                    await _audioPlayer.play(DeviceFileSource(localPath));
                  }
                  setState(() => _currentlyPlayingUrl = audioSourceUrl);
                }
              },
              child: Icon(isPlayingHere ? Icons.pause_circle_filled : Icons.play_circle_filled, color: const Color(0xFFdb2777), size: 40),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   LayoutBuilder(builder: (context, constraints) {
                     return Stack(
                       children: [
                         Container(
                           height: 4,
                           width: double.infinity,
                           decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                         ),
                         AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            width: constraints.maxWidth * fillRatio, 
                            height: 4, 
                            decoration: BoxDecoration(color: const Color(0xFFdb2777), borderRadius: BorderRadius.circular(2))
                         ),
                       ]
                     );
                   }),
                   const SizedBox(height: 6),
                   Text(
                     isPlayingHere ? _formatDuration(_currentPosition.inSeconds) : "Voice Broadcast", 
                     style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)
                   ),
                ]
              )
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFdb2777).withOpacity(0.1),
              backgroundImage: NetworkImage(widget.state.assignedClass?['teacherProfilePic'] ?? "https://ui-avatars.com/api/?name=${widget.state.assignedClass?['teacherName'] ?? 'T'}&background=ec4899&color=fff"),
            ),
          ],
        ),
      );
    }
    
    final bool isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(type);
    if (isImage) {
      if (localPath != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: Image.file(File(localPath), fit: BoxFit.cover, width: double.infinity),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, _) => const CircularProgressIndicator(),
            errorWidget: (context, _, __) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, color: Colors.grey),
          const SizedBox(width: 8),
          Flexible(child: Text(attachment['name'] ?? 'File attachment', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8, top: 4),
      color: Colors.transparent,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: isDark ? Border.all(color: Colors.white12) : null,
                  boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))]
                ),
                child: _buildInputContent(isDark),
              ),
            ),
            const SizedBox(width: 8),
            _buildActionIcon(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputContent(bool isDark) {
    if (_isRecording) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.mic, color: Colors.red),
            const SizedBox(width: 8),
            Text(_formatDuration(_recordingDurationSeconds), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            const Icon(Icons.chevron_left, color: Colors.grey, size: 20),
            const SizedBox(width: 4),
            const Text("Slide to cancel", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    if (_recordedFilePath != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: _deletePreview),
            GestureDetector(
              onTap: _playPausePreview,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFdb2777),
                child: Icon(_isPlayingPreview ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 18),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: RoundSliderOverlayShape(overlayRadius: 14), trackHeight: 3),
                child: Slider(
                  value: _currentPosition.inMilliseconds.toDouble(),
                  max: _totalDuration.inMilliseconds.toDouble() > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0,
                  activeColor: const Color(0xFFdb2777),
                  inactiveColor: const Color(0xFFdb2777).withOpacity(0.3),
                  onChanged: (val) => _audioPlayer.seek(Duration(milliseconds: val.toInt())),
                ),
              ),
            ),
            Text(_formatDuration(_totalDuration.inSeconds), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          icon: Icon(Icons.add, color: isDark ? Colors.white70 : Colors.black54), 
          onPressed: _showAttachmentMenu,
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: TextField(
              controller: _messageController,
              maxLines: null,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (val) => setState((){}), 
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: const InputDecoration(
                hintText: "Message...",
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        if (_messageController.text.trim().isEmpty)
          IconButton(icon: Icon(Icons.camera_alt, color: isDark ? Colors.white70 : Colors.black54), onPressed: _takeAndSendPicture),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildActionIcon() {
    final bool hasText = _messageController.text.trim().isNotEmpty;
    final bool showSend = hasText || _recordedFilePath != null;

    if (showSend) {
      return GestureDetector(
        onTap: () {
          if (_recordedFilePath != null) {
            final f = File(_recordedFilePath!);
            _deletePreview(deleteFile: false); 
            _addPendingAndSend('', f, 'audio', p.basename(f.path));
          } else {
            final text = _messageController.text;
            _messageController.clear();
            setState((){});
            _addPendingAndSend(text, null, null, null);
          }
        },
        child: const CircleAvatar(
          radius: 24,
          backgroundColor: Color(0xFFdb2777),
          child: Icon(Icons.send, color: Colors.white, size: 20),
        ),
      );
    }

    return Listener(
      onPointerDown: (_) => _startRecording(),
      onPointerMove: (event) {
        if (_isRecording && event.localPosition.dx < -50) {
           setState(() => _isCanceled = true);
           _stopRecordingSafely();
        }
      },
      onPointerUp: (_) => _stopRecordingSafely(),
      onPointerCancel: (_) => _stopRecordingSafely(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        width: _isRecording ? 64 : 48,
        height: _isRecording ? 64 : 48,
        decoration: const BoxDecoration(
          color: Color(0xFFdb2777),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: widget.state.isSending 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
              : Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: _isRecording ? 32 : 24),
        ),
      ),
    );
  }
}
