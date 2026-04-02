import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/contact_parents/providers/contact_parents_provider.dart';

class StudentContactCard extends StatefulWidget {
  final Map<String, dynamic> student;
  final bool isExpanded;
  final Map<String, dynamic>? parentData;
  final ContactParentsState state;
  final ContactParentsNotifier notifier;
  final TextEditingController messageController;

  const StudentContactCard({
    Key? key,
    required this.student,
    required this.isExpanded,
    this.parentData,
    required this.state,
    required this.notifier,
    required this.messageController,
  }) : super(key: key);

  @override
  State<StudentContactCard> createState() => _StudentContactCardState();
}

class _StudentContactCardState extends State<StudentContactCard> {
  bool _isPressed = false;
  
  // Recording states
  bool _isRecording = false;
  late final AudioRecorder _audioRecorder;
  Timer? _recordingTimer;
  int _recordingDurationSeconds = 0;
  bool _isCanceled = false;

  // Preview / Playback states
  String? _recordedFilePath;
  late final AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
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
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _startTimer() {
    _recordingDurationSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _recordingDurationSeconds++);
      }
    });
  }

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
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
          await _audioPlayer.setSourceDeviceFile(path);
          final duration = await _audioPlayer.getDuration();
          if (duration != null && mounted) {
            setState(() => _totalDuration = duration);
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
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _audioPlayer.stop();
    setState(() {
      _recordedFilePath = null;
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    });
  }

  Future<void> _playPauseAudio() async {
    if (_recordedFilePath == null) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_currentPosition == _totalDuration && _totalDuration != Duration.zero) {
        await _audioPlayer.seek(Duration.zero);
      }
      await _audioPlayer.play(DeviceFileSource(_recordedFilePath!));
    }
  }

  Future<void> _sendRecordedNote() async {
    if (_recordedFilePath == null) return;
    try {
      if (mounted) {
        await widget.notifier.sendVoiceMessage(
          student: widget.student,
          parent: widget.parentData!,
          audioFile: File(_recordedFilePath!),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Voice message sent successfully!")),
          );
          await _deletePreview();
          widget.messageController.clear();
          widget.notifier.collapseStudent();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send voice message: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        if (!widget.isExpanded) {
          widget.messageController.clear();
          _deletePreview();
        }
        widget.notifier.toggleStudentExpansion(widget.student['id']);
      },
      child: AnimatedScale(
        scale: (_isPressed && !widget.isExpanded) ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: widget.isExpanded 
              ? const Color(0xFFec4899).withOpacity(0.05) 
              : (isDark ? AppTheme.surfaceDark : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isExpanded ? const Color(0xFFec4899) : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            ),
            boxShadow: isLight && !widget.isExpanded
              ? [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
              : [],
          ),
          child: Column(
            children: [
              // Header / Summary Card
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(14),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (widget.student['profilePic'] != null && widget.student['profilePic'].toString().isNotEmpty)
                          ? Image.network(widget.student['profilePic'], fit: BoxFit.cover)
                          : Image.network("https://api.dicebear.com/7.x/avataaars/svg?seed=${widget.student['id']}", fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.student['name'] ?? "Unknown",
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.indigo[900],
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "#${widget.student['rollNo'] ?? '-'}",
                                  style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700], fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "• Tap to Message",
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.isExpanded ? const Color(0xFFec4899) : const Color(0xFFec4899).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.message, 
                        color: widget.isExpanded ? Colors.white : const Color(0xFFec4899), 
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),

              // Expanded Message Area
              if (widget.isExpanded)
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
                    color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: widget.parentData != null 
                    ? _buildMessageComposer(context)
                    : _buildNoParentMessage(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFFec4899),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
            Text(
              "To: ${widget.parentData!['name'] ?? 'Unknown'} (Parent)",
              style: const TextStyle(
                color: Color(0xFFec4899),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isRecording)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                  child: CircularProgressIndicator(
                    color: Colors.red,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDuration(_recordingDurationSeconds),
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Text(
                  "< Slide left to cancel",
                  style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          )
        else if (_recordedFilePath != null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFFec4899).withOpacity(0.1) : Colors.pink.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFec4899).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _deletePreview,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(isDark ? 0.1 : 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _playPauseAudio,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFec4899),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _currentPosition.inMilliseconds.toDouble(),
                      max: _totalDuration.inMilliseconds.toDouble() > 0 ? _totalDuration.inMilliseconds.toDouble() : 1.0,
                      activeColor: const Color(0xFFec4899),
                      inactiveColor: const Color(0xFFec4899).withOpacity(0.3),
                      onChanged: (val) {
                        _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                ),
                Text(
                  _formatDuration(_totalDuration.inSeconds),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFec4899)),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.backgroundDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            ),
            child: TextField(
              controller: widget.messageController,
              maxLines: 4,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "Write a specific message about ${(widget.student['name'] ?? '').split(' ').first}...",
                hintStyle: const TextStyle(color: Colors.grey),
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
              ),
              onChanged: (text) => setState(() {}),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: widget.state.isSending || _isRecording ? null : () {
                  widget.messageController.clear();
                  _deletePreview();
                  widget.notifier.collapseStudent();
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            if (_recordedFilePath != null)
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.state.isSending ? null : _sendRecordedNote,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFFec4899),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: widget.state.isSending
                    ? const SizedBox(
                        height: 20, 
                        width: 20, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.send, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text("Send Voice Note", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                ),
              )
            else if (widget.messageController.text.trim().isEmpty)
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressMoveUpdate: (details) {
                    if (_isRecording && details.localOffsetFromOrigin.dx < -50) {
                      _cancelRecording();
                    }
                  },
                  onLongPressEnd: (_) => _stopRecordingSafely(),
                  child: ElevatedButton(
                    onPressed: widget.state.isSending ? null : () {},
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: _isRecording ? Colors.red : const Color(0xFFec4899),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: widget.state.isSending
                      ? const SizedBox(
                          height: 20, 
                          width: 20, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isRecording ? Icons.mic : Icons.mic_none, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _isRecording ? "Release to Finish" : "Hold to Record", 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                            ),
                          ],
                        ),
                  ),
                ),
              )
            else
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.state.isSending ? null : () async {
                    if (widget.messageController.text.trim().isEmpty) {
                      return;
                    }
                    
                    try {
                      await widget.notifier.sendMessage(
                        student: widget.student, 
                        parent: widget.parentData!, 
                        messageText: widget.messageController.text,
                      );
                      if (mounted) {
                        widget.messageController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Message sent successfully!")),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to send: $e")),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFFec4899),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: widget.state.isSending
                    ? const SizedBox(
                        height: 20, 
                        width: 20, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.send, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text("Send Text", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                ),
              ),
          ],
        )
      ],
    );
  }

  Widget _buildNoParentMessage(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: const [
            Icon(Icons.link_off, color: Colors.grey, size: 32),
            SizedBox(height: 12),
            Text(
              "No parent account linked to this student.",
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 4),
            Text(
              "Please contact admin to link a parent.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
