import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:teacher_mobile_app/features/syllabus/providers/syllabus_provider.dart';

class SyllabusDetailScreen extends ConsumerWidget {
  final SyllabusAssignment assignment;

  const SyllabusDetailScreen({super.key, required this.assignment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10b981), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.subject,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "${assignment.className} • Syllabus & Chapters",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.85),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Reusable Paper & Overview Content
          Expanded(
            child: SyllabusPaperView(assignment: assignment),
          ),
        ],
      ),
    );
  }
}

class SyllabusPaperView extends ConsumerWidget {
  final SyllabusAssignment assignment;

  const SyllabusPaperView({super.key, required this.assignment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(syllabusChaptersProvider(assignment));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return chaptersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF10b981)),
      ),
      error: (e, st) => Center(
        child: Text(
          "Error: $e",
          style: const TextStyle(color: Colors.red),
        ),
      ),
      data: (chapters) {
        final totalChapters = chapters.length;
        final pendingChapters = chapters
            .where((c) => (c['status'] ?? 'Pending') == 'Pending')
            .length;

        // Find all "In Progress" chapter numbers (1-based index)
        final inProgressNumbers = <int>[];
        for (int i = 0; i < chapters.length; i++) {
          if (chapters[i]['status'] == 'In Progress') {
            inProgressNumbers.add(i + 1);
          }
        }

        final String currentlyOnText = inProgressNumbers.isEmpty
            ? "-"
            : inProgressNumbers.map((n) => "#$n").join(", ");

        return Column(
          children: [
            // --- 1. Top 3 Overview Cards ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildOverviewCard(
                      title: "Total Chapters",
                      value: "$totalChapters",
                      icon: Icons.menu_book_rounded,
                      accentColor: const Color(0xFF6366F1), // Indigo
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildOverviewCard(
                      title: "Currently On No:",
                      value: currentlyOnText,
                      icon: Icons.edit_note_rounded,
                      accentColor: const Color(0xFFF59E0B), // Amber/Orange
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildOverviewCard(
                      title: "Pending Chapters",
                      value: "$pendingChapters",
                      icon: Icons.pending_actions_rounded,
                      accentColor: const Color(0xFFEF4444), // Red/Rose
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),

            // --- 2. Notebook Paper Sheet with Pencil Handwriting ---
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF7), // Warm notebook paper tone
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFE5DEC9),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Ruled Notebook Lines + Red Margin Line Painter
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _NotebookPaperPainter(),
                        ),
                      ),

                      // Top Binder Holes Decoration
                      Positioned(
                        top: 10,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            6,
                            (_) => Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFE2E8F0),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFFCBD5E1),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Content inside the notebook page
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: chapters.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    "No syllabus chapters written yet for this subject.",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.caveat(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                color: const Color(0xFF10b981),
                                onRefresh: () async {
                                  ref.invalidate(
                                      syllabusChaptersProvider(assignment));
                                },
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 32,
                                  ),
                                  itemCount: chapters.length,
                                  itemBuilder: (context, index) {
                                    final chapter = chapters[index];
                                    return _buildHandwrittenChapterRow(
                                      context: context,
                                      ref: ref,
                                      chapter: chapter,
                                      chapterNumber: index + 1,
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withOpacity(isDark ? 0.3 : 0.2),
          width: 1.2,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHandwrittenChapterRow({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> chapter,
    required int chapterNumber,
  }) {
    final String status = (chapter['status'] ?? 'Pending').toString();
    final bool isCompleted = status == 'Completed';
    final bool isInProgress = status == 'In Progress';

    // Status button visual configuration
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (isCompleted) {
      statusColor = const Color(0xFF16A34A); // Green
      statusIcon = Icons.check_circle_rounded;
      statusLabel = "Done";
    } else if (isInProgress) {
      statusColor = const Color(0xFFD97706); // Amber/Orange
      statusIcon = Icons.timelapse_rounded;
      statusLabel = "Active";
    } else {
      statusColor = const Color(0xFF64748B); // Slate Grey
      statusIcon = Icons.radio_button_unchecked_rounded;
      statusLabel = "Pending";
    }

    final topics = (chapter['topics'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        [];

    // Graphite pencil color
    final Color pencilColor = isCompleted
        ? const Color(0xFF6B7280)
        : const Color(0xFF27272A);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left side of red margin line: Chapter Number in pencil
              SizedBox(
                width: 48,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Text(
                    "$chapterNumber.",
                    style: GoogleFonts.caveat(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isInProgress
                          ? const Color(0xFFD97706)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Chapter Name in Pencil Handwriting Style + Strikethrough when Completed
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapter['title']?.toString() ?? 'Untitled Chapter',
                      style: GoogleFonts.caveat(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: pencilColor,
                        height: 1.15,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: const Color(0xFF374151),
                        decorationThickness: 2.4,
                      ),
                    ),
                    if ((chapter['time'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          "Est. Time: ${chapter['time']}",
                          style: GoogleFonts.patrickHand(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Interactive Status Cycle Button (Pending -> In Progress -> Completed)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    ref.read(syllabusServiceProvider).toggleChapterStatus(
                          assignment,
                          chapter['id'].toString(),
                          status,
                        );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withOpacity(0.45),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: GoogleFonts.patrickHand(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Sub-topics written in smaller pencil handwriting below the chapter
          if (topics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 64, right: 16, top: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 2,
                children: topics.map((topic) {
                  return Text(
                    "• $topic",
                    style: GoogleFonts.patrickHand(
                      fontSize: 15,
                      color: isCompleted
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF4B5563),
                      decoration: isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      decorationColor: const Color(0xFF6B7280),
                      decorationThickness: 1.5,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotebookPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final horizontalLinePaint = Paint()
      ..color = const Color(0xFFBFDBFE).withOpacity(0.65) // Soft notebook blue lines
      ..strokeWidth = 1.0;

    // Draw horizontal ruled lines every 36 pixels starting below the binder holes
    const double startY = 44.0;
    const double lineSpacing = 36.0;
    for (double y = startY; y < size.height; y += lineSpacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        horizontalLinePaint,
      );
    }

    // Draw double vertical red/pink margin line on the left
    final marginLinePaint = Paint()
      ..color = const Color(0xFFFCA5A5).withOpacity(0.85)
      ..strokeWidth = 1.4;

    canvas.drawLine(
      const Offset(48, 0),
      Offset(48, size.height),
      marginLinePaint,
    );
    canvas.drawLine(
      const Offset(51, 0),
      Offset(51, size.height),
      marginLinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
