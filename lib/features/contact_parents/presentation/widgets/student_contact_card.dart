import 'package:flutter/material.dart';
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
        }
        widget.notifier.toggleStudentExpansion(widget.student['id']);
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
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
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: widget.state.isSending ? null : () {
                  widget.messageController.clear();
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
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: widget.state.isSending ? null : () async {
                  if (widget.messageController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter a message.")),
                    );
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
                        Text("Send Message", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
