import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/features/syllabus/providers/syllabus_provider.dart';

class SyllabusDetailScreen extends ConsumerWidget {
  final SyllabusAssignment assignment;
  
  const SyllabusDetailScreen({super.key, required this.assignment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(syllabusChaptersProvider(assignment));
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    // Calculate progress locally based on chapters
    double progressPercent = 0.0;
    if (chaptersAsync.value != null && chaptersAsync.value!.isNotEmpty) {
      final chapters = chaptersAsync.value!;
      final completed = chapters.where((c) => c['status'] == 'Completed').length;
      progressPercent = completed / chapters.length;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 24,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.chevron_left, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.subject,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          Text(
                            assignment.className,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Progress UI
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 100,
                          height: 100,
                          child: CircularProgressIndicator(
                            value: progressPercent,
                            strokeWidth: 8,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        Text(
                          "${(progressPercent * 100).toInt()}%",
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Subject Progress", style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          progressPercent == 1.0 ? "Completed!" : progressPercent > 0.5 ? "On Track" : "Just Started", 
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
                        ),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),

          // Chapters List
          Expanded(
            child: chaptersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.indigo)),
              error: (e, st) => Center(child: Text("Error: $e")),
              data: (chapters) {
                if (chapters.isEmpty) {
                  return const Center(
                    child: Text(
                      "No syllabus chapters found for this subject.",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(syllabusChaptersProvider(assignment));
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    Color statusColor;
                    IconData statusIcon;
                    if (chapter['status'] == 'Completed') {
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                    } else if (chapter['status'] == 'In Progress') {
                      statusColor = Colors.orange;
                      statusIcon = Icons.timelapse;
                    } else {
                      statusColor = Colors.grey;
                      statusIcon = Icons.radio_button_unchecked;
                    }

                    final topics = (chapter['topics'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                        boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))] : [],
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: GestureDetector(
                            onTap: () {
                              ref.read(syllabusServiceProvider).toggleChapterStatus(
                                assignment, 
                                chapter['id'], 
                                chapter['status'] ?? 'Pending'
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(statusIcon, color: statusColor, size: 28),
                            ),
                          ),
                          title: Text(
                            chapter['title'] ?? 'Untitled Chapter',
                            style: TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold, 
                              color: isDark ? Colors.white : Colors.indigo[900],
                              decoration: chapter['status'] == 'Completed' ? TextDecoration.lineThrough : null,
                            )
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  chapter['time'] ?? 'N/A', 
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)
                                ),
                              ],
                            ),
                          ),
                          children: [
                            if (topics.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 64, right: 16, bottom: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Topics:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    ...topics.map((topic) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("• ", style: TextStyle(color: Colors.grey)),
                                          Expanded(child: Text(topic, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87))),
                                        ],
                                      ),
                                    )),
                                  ],
                                ),
                              )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            ),
          ),
        ],
      ),
    );
  }
}
