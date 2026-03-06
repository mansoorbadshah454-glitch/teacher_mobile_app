import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:teacher_mobile_app/features/inbox/providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> admin;

  const ChatScreen({super.key, required this.admin});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final teacherData = await ref.read(teacherDataProvider.future);
      final currentUser = ref.read(currentUserProvider);
      
      if (teacherData != null && teacherData.containsKey('schoolId') && currentUser != null) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(teacherData['schoolId'])
            .collection('messages')
            .add({
          'to': widget.admin['type'] ?? (widget.admin['role'] == 'Principal' ? 'principal' : 'admin'),
          'toId': widget.admin['id'],
          'toRole': widget.admin['role'] == 'Principal' ? 'principal' : 'school Admin',
          'from': 'teacher',
          'fromName': teacherData['name'] ?? 'Teacher',
          'fromId': currentUser.uid,
          'fromRole': 'teacher',
          'participants': [currentUser.uid, widget.admin['id']],
          'text': text,
          'type': 'teacher-reply',
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.admin['id']));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: AppTheme.primary, // Changed to AppTheme.primary
        foregroundColor: Colors.white, // Added foregroundColor
        leadingWidth: 90,
        leading: InkWell(
          onTap: () => context.pop(),
          child: Row(
            children: [
              const SizedBox(width: 8),
              const Icon(Icons.arrow_back, color: Colors.white),
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.admin['photo'].isNotEmpty
                    ? CachedNetworkImageProvider(widget.admin['photo'])
                    : null,
                child: widget.admin['photo'].isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 22)
                    : null,
              ),
            ],
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.admin['name'],
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.admin['role'],
              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clearHistory();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear History'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hi!'));
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final currentUser = ref.read(currentUserProvider);
                    final isMe = msg['fromId'] == currentUser?.uid || msg['from'] == 'teacher';
                    
                    // Mark as read if it's for me and unread
                    if (!isMe && msg['read'] == false) {
                      _markAsRead(msg['id']);
                    }

                    return _ChatBubble(msg: msg, isMe: isMe);
                  },
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: const Text('This will delete all messages and files in this chat for you and the other person.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final teacherData = await ref.read(teacherDataProvider.future);
      if (teacherData == null || teacherData['schoolId'] == null) return;

      final schoolId = teacherData['schoolId'];
      final messages = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('messages')
          .get();

      final adminId = widget.admin['id'];
      final teacherId = ref.read(currentUserProvider)?.uid;

      for (var doc in messages.docs) {
        final data = doc.data();
        final fromId = data['fromId'] ?? data['from'];
        final toId = data['toId'] ?? data['to'];

        // Check if message belongs to this conversation
        final isChatMsg = (fromId == teacherId && (toId == adminId || toId == 'principal')) ||
                         ((fromId == adminId || fromId == 'principal') && toId == teacherId);

        if (isChatMsg) {
          // 1. Delete associated storage file if exists
          if (data['attachment'] != null && data['attachment']['fullPath'] != null) {
            try {
              await FirebaseStorage.instance.ref(data['attachment']['fullPath']).delete();
            } catch (e) {
              debugPrint('Storage delete error: $e');
            }
          }
          // 2. Delete Firestore doc
          await doc.reference.delete();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat history cleared.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear: $e')));
      }
    }
  }

  Future<void> _markAsRead(String msgId) async {
    try {
      final teacherData = await ref.read(teacherDataProvider.future);
      if (teacherData != null && teacherData.containsKey('schoolId')) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(teacherData['schoolId'])
            .collection('messages')
            .doc(msgId)
            .update({'read': true});
      }
    } catch (e) {
      debugPrint('Error marking message as read: $e');
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      setState(() => _isSending = true);

      final teacherData = await ref.read(teacherDataProvider.future);
      final currentUser = ref.read(currentUserProvider);
      
      if (teacherData == null || !teacherData.containsKey('schoolId') || currentUser == null) return;

      final schoolId = teacherData['schoolId'];
      final fileName = p.basename(file.path!);
      final destination = 'schools/$schoolId/messages/attachments/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Upload to Storage
      final refStorage = FirebaseStorage.instance.ref(destination);
      await refStorage.putFile(File(file.path!));
      final downloadUrl = await refStorage.getDownloadURL();

      // Add message to Firestore
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('messages')
          .add({
        'to': widget.admin['type'] ?? (widget.admin['role'] == 'Principal' ? 'principal' : 'admin'),
        'toId': widget.admin['id'],
        'toRole': widget.admin['role'] == 'Principal' ? 'principal' : 'school Admin',
        'from': 'teacher',
        'fromName': teacherData['name'] ?? 'Teacher',
        'fromId': currentUser.uid,
        'fromRole': 'teacher',
        'participants': [currentUser.uid, widget.admin['id']],
        'text': 'Sent an attachment: $fileName',
        'attachment': {
          'url': downloadUrl,
          'fullPath': destination, // Added for easy deletion
          'name': fileName,
          'type': file.extension ?? 'file',
        },
        'type': 'teacher-reply',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildInputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(8),
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: _pickAndUploadFile,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: "Type a message",
                  hintStyle: const TextStyle(fontSize: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.secondary,
                child: _isSending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe;

  const _ChatBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    String formattedTime = '';
    if (msg['timestamp'] is Timestamp) {
      formattedTime = DateFormat('h:mm a').format((msg['timestamp'] as Timestamp).toDate());
    }

    bool isRead = msg['read'] == true;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Changed padding
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe 
            ? AppTheme.primary // Changed color for 'isMe'
            : (isDark ? AppTheme.surfaceDark : Colors.white), // Changed color for 'not isMe'
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0), // Changed radius
            bottomRight: Radius.circular(isMe ? 0 : 16), // Changed radius
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4, // Changed blurRadius
              offset: const Offset(0, 2), // Changed offset
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Changed crossAxisAlignment
          mainAxisSize: MainAxisSize.min, // Added mainAxisSize
          children: [
            if (msg['attachment'] != null) ...[
               _buildAttachment(msg['attachment']),
               const SizedBox(height: 6), // Changed height
            ],
            Text(
              msg['text'] ?? '',
              style: TextStyle(
                color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87), // Changed text color
                fontSize: 16, // Changed font size
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                if (isMe) ...[
                   const SizedBox(width: 4),
                   Icon(
                     isRead ? Icons.done_all : Icons.done_all, // Both double checks
                     size: 14,
                     color: isRead ? Colors.blue : (isDark ? Colors.white54 : Colors.black45),
                   ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachment(Map<String, dynamic> attachment) {
    final bool isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(attachment['type']?.toLowerCase());
    
    if (isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: CachedNetworkImage(
            imageUrl: attachment['url'],
            placeholder: (context, url) => Container(
              height: 150,
              width: double.infinity,
              color: Colors.black12,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.file_present, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              attachment['name'] ?? 'File',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
