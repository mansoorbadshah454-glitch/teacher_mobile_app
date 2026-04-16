import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/contact_parents/providers/contact_parents_provider.dart';
import 'package:teacher_mobile_app/features/contact_parents/presentation/widgets/student_contact_card.dart';
import 'package:teacher_mobile_app/features/contact_parents/presentation/screens/group_broadcast_view.dart';

class ContactParentsScreen extends ConsumerStatefulWidget {
  const ContactParentsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ContactParentsScreen> createState() => _ContactParentsScreenState();
}

class _ContactParentsScreenState extends ConsumerState<ContactParentsScreen> {
  final TextEditingController _messageController = TextEditingController();
  
  // Selection State for Group View Deletion
  bool _isSelectionMode = false;
  final Set<String> _selectedBroadcastIds = {};

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactParentsProvider);
    final notifier = ref.read(contactParentsProvider.notifier);
    final schoolId = ref.watch(teacherDataProvider).value?['schoolId'] ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(context, state, notifier),
          
          if (!state.isGroupMode)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildSearchBar(context, state, notifier),
            ),
          
          Expanded(
            child: state.isGroupMode
              ? GroupBroadcastView(
                  state: state,
                  notifier: notifier,
                  broadcastsAsync: ref.watch(classBroadcastsProvider),
                  isSelectionMode: _isSelectionMode,
                  selectedIds: _selectedBroadcastIds,
                  onSelectToggle: (id) {
                    setState(() {
                       if (id == 'CLEAR_ALL_MODE') {
                          _isSelectionMode = false;
                          _selectedBroadcastIds.clear();
                       } else {
                          if (!_isSelectionMode) _isSelectionMode = true;
                          if (_selectedBroadcastIds.contains(id)) {
                             _selectedBroadcastIds.remove(id);
                             if (_selectedBroadcastIds.isEmpty) _isSelectionMode = false;
                          } else {
                             _selectedBroadcastIds.add(id);
                          }
               }
                    });
                  },
                )
              : _buildStudentList(context, state, notifier, schoolId),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ContactParentsState state, ContactParentsNotifier notifier) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFec4899), Color(0xFFdb2777)],
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
      child: Column(
        children: [
          Row(
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
                        ? (state.isGroupMode ? "${state.parentMap.length} Total Parents" : "${state.assignedClass!['name']} • ${state.students.length} Students")
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
              if (state.isGroupMode)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'select') {
                      setState(() => _isSelectionMode = true);
                    } else if (value == 'clear') {
                       final broadcasts = ref.read(classBroadcastsProvider).valueOrNull;
                       if (broadcasts != null) {
                          await notifier.clearHistory(broadcasts);
                       }
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(
                      value: 'select',
                      child: Text('Select to delete'),
                    ),
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear history'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Toggle Segmented Control
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.toggleGroupMode(false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: !state.isGroupMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "List",
                        style: TextStyle(
                          color: !state.isGroupMode ? const Color(0xFFdb2777) : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.toggleGroupMode(true),
                    child: Container(
                      decoration: BoxDecoration(
                        color: state.isGroupMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "Group",
                        style: TextStyle(
                          color: state.isGroupMode ? const Color(0xFFdb2777) : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ContactParentsState state, ContactParentsNotifier notifier) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        boxShadow: isLight 
          ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] 
          : [],
      ),
      child: TextField(
        onChanged: notifier.setSearchTerm,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
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

  Widget _buildStudentList(BuildContext context, ContactParentsState state, ContactParentsNotifier notifier, String schoolId) {
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

        return StudentContactCard(
          student: student,
          isExpanded: isExpanded,
          parentData: parentData,
          state: state,
          notifier: notifier,
          messageController: _messageController,
          schoolId: schoolId,
        );
      },
    );
  }
}
