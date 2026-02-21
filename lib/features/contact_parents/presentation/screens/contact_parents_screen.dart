import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/contact_parents/providers/contact_parents_provider.dart';

class ContactParentsScreen extends ConsumerStatefulWidget {
  const ContactParentsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ContactParentsScreen> createState() => _ContactParentsScreenState();
}

class _ContactParentsScreenState extends ConsumerState<ContactParentsScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactParentsProvider);
    final notifier = ref.read(contactParentsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, state),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildSearchBar(state, notifier),
            ),
            
            Expanded(
              child: _buildStudentList(context, state, notifier),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ContactParentsState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFec4899), Color(0xFFdb2777)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33ec4899),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chevron_left, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Contact Parents",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  state.assignedClass != null 
                    ? "${state.assignedClass!['name']} • ${state.students.length} Students" 
                    : "Fetching class...",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ContactParentsState state, ContactParentsNotifier notifier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: TextField(
        onChanged: notifier.setSearchTerm,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: Colors.grey, size: 20),
          suffixIcon: state.searchTerm.isNotEmpty 
            ? GestureDetector(
                onTap: () => notifier.setSearchTerm(''),
                child: const Icon(Icons.close, color: Colors.grey, size: 18),
              )
            : null,
          border: InputBorder.none,
          hintText: "Search by name or roll no...",
          hintStyle: const TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildStudentList(BuildContext context, ContactParentsState state, ContactParentsNotifier notifier) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFec4899)));
    }

    if (state.assignedClass == null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              const Text(
                "No Class Assigned",
                style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "You need an assigned class to contact parents.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text("Go Back", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }

    final filteredStudents = state.students.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final roll = (s['rollNo'] ?? '').toString().toLowerCase();
      final query = state.searchTerm.toLowerCase();
      return name.contains(query) || roll.contains(query);
    }).toList();

    if (filteredStudents.isEmpty) {
      return const Center(
        child: Text("No students found matching your search.", style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final student = filteredStudents[index];
        final isExpanded = state.expandedStudentId == student['id'];
        final parentData = state.parentMap[student['id']];

        return _buildStudentCard(student, isExpanded, parentData, state, notifier);
      },
    );
  }

  Widget _buildStudentCard(
    Map<String, dynamic> student, 
    bool isExpanded, 
    Map<String, dynamic>? parentData,
    ContactParentsState state,
    ContactParentsNotifier notifier,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isExpanded ? const Color(0xFFec4899).withOpacity(0.05) : AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded ? const Color(0xFFec4899) : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          // Header / Summary Card
          InkWell(
            onTap: () {
              if (!isExpanded) {
                // Clear the message box when opening a new student
                _messageController.clear();
              }
              notifier.toggleStudentExpansion(student['id']);
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (student['profilePic'] != null && student['profilePic'].toString().isNotEmpty)
                        ? Image.network(student['profilePic'], fit: BoxFit.cover)
                        : Image.network("https://api.dicebear.com/7.x/avataaars/svg?seed=${student['id']}", fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['name'] ?? "Unknown",
                          style: const TextStyle(
                            color: Colors.white,
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
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "#${student['rollNo'] ?? '-'}",
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                      color: isExpanded ? const Color(0xFFec4899) : const Color(0xFFec4899).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.message, 
                      color: isExpanded ? Colors.white : const Color(0xFFec4899), 
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded Message Area
          if (isExpanded)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                color: Colors.black.withOpacity(0.2),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: parentData != null 
                ? _buildMessageComposer(student, parentData, state, notifier)
                : _buildNoParentMessage(),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageComposer(
    Map<String, dynamic> student, 
    Map<String, dynamic> parentData,
    ContactParentsState state,
    ContactParentsNotifier notifier,
  ) {
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
              "To: ${parentData['name'] ?? 'Unknown'} (Parent)",
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
            color: AppTheme.backgroundDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TextField(
            controller: _messageController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Write a specific message about ${(student['name'] ?? '').split(' ').first}...",
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
                onPressed: state.isSending ? null : () {
                  _messageController.clear();
                  notifier.collapseStudent();
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
                onPressed: state.isSending ? null : () async {
                  if (_messageController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter a message.")),
                    );
                    return;
                  }
                  
                  try {
                    await notifier.sendMessage(
                      student: student, 
                      parent: parentData, 
                      messageText: _messageController.text,
                    );
                    if (mounted) {
                      _messageController.clear();
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
                child: state.isSending
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

  Widget _buildNoParentMessage() {
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
