import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StudentScoreCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  final bool isTestMode;
  
  // Normal Mode Params
  final int? academicScore;
  final int? homeworkScore;
  final bool hasActiveHomework;
  final Function(String, String, int)? onScoreChanged;

  // Test Mode Params
  final int? testScore;
  final Function(String, int)? onTestScoreChanged;

  const StudentScoreCard({
    Key? key,
    required this.student,
    this.isTestMode = false,
    this.academicScore,
    this.homeworkScore,
    this.hasActiveHomework = false,
    this.onScoreChanged,
    this.testScore,
    this.onTestScoreChanged,
  }) : super(key: key);

  @override
  ConsumerState<StudentScoreCard> createState() => _StudentScoreCardState();
}

class _StudentScoreCardState extends ConsumerState<StudentScoreCard> {
  Color _getScoreColor(int score) {
    if (score >= 80) return const Color(0xFF10B981); // emerald-500
    if (score >= 50) return const Color(0xFFF59E0B); // amber-500
    return const Color(0xFFEF4444); // red-500
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final name = student['name'] ?? 'Unknown';
    final rollNo = student['rollNo']?.toString() ?? 'N/A';
    final profilePic = student['profilePic'];

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
        boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))] : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, Roll No
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF334155) : Colors.indigo[50]!, // slate-700 or light indigo
                ),
                clipBehavior: Clip.hardEdge,
                child: profilePic != null && profilePic.isNotEmpty
                    ? Image.network(profilePic, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.person, color: isDark ? Colors.white : Colors.indigo[200]))
                    : Icon(Icons.person, color: isDark ? Colors.white : Colors.indigo[200]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.indigo[900],
                      ),
                    ),
                    Text(
                      "Roll No: $rollNo",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sliders based on mode
          if (widget.isTestMode)
            _buildSlider(
              context: context,
              label: "Test Score",
              value: widget.testScore ?? 0,
              onChanged: (val) {
                if (widget.onTestScoreChanged != null) {
                  widget.onTestScoreChanged!(student['id'], val.toInt());
                }
              },
            )
          else ...[
            _buildSlider(
              context: context,
              label: "Subject Performance",
              value: widget.academicScore ?? 0,
              onChanged: (val) {
                if (widget.onScoreChanged != null) {
                  widget.onScoreChanged!(student['id'], 'academic', val.toInt());
                }
              },
            ),
            const SizedBox(height: 10),
            _buildHomeworkButtons(context),
          ],
          
        ],
      ),
    );
  }

  Widget _buildHomeworkButtons(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!widget.hasActiveHomework) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.assignment_late_outlined, size: 15, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "No Homework Assigned",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "Inactive",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hwScore = widget.homeworkScore;
    final bool hasMark = hwScore != null;
    final isDone = hasMark && hwScore >= 75;
    final isIncomplete = hasMark && hwScore >= 25 && hwScore < 75;
    final isNotDone = hasMark && hwScore < 25;

    String statusText = "Unmarked";
    Color statusColor = Colors.grey;
    if (isDone) {
      statusText = "Done (100%)";
      statusColor = const Color(0xFF10B981);
    } else if (isIncomplete) {
      statusText = "Incomplete (50%)";
      statusColor = const Color(0xFFF59E0B);
    } else if (isNotDone) {
      statusText = "Not Done (0%)";
      statusColor = const Color(0xFFEF4444);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Homework",
              style: TextStyle(
                color: isDark ? Colors.grey : Colors.grey[600],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildHomeworkPill(
                title: "Done",
                icon: Icons.check_circle_outline,
                isSelected: isDone,
                selectedColor: const Color(0xFF10B981),
                isDark: isDark,
                onTap: () {
                  if (widget.onScoreChanged != null) {
                    widget.onScoreChanged!(widget.student['id'], 'homework', 100);
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildHomeworkPill(
                title: "Incomplete",
                icon: Icons.timelapse_outlined,
                isSelected: isIncomplete,
                selectedColor: const Color(0xFFF59E0B),
                isDark: isDark,
                onTap: () {
                  if (widget.onScoreChanged != null) {
                    widget.onScoreChanged!(widget.student['id'], 'homework', 50);
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildHomeworkPill(
                title: "Not Done",
                icon: Icons.cancel_outlined,
                isSelected: isNotDone,
                selectedColor: const Color(0xFFEF4444),
                isDark: isDark,
                onTap: () {
                  if (widget.onScoreChanged != null) {
                    widget.onScoreChanged!(widget.student['id'], 'homework', 0);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHomeworkPill({
    required String title,
    required IconData icon,
    required bool isSelected,
    required Color selectedColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor
              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? selectedColor
                : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[700]),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required BuildContext context,
    required String label,
    required int value,
    required ValueChanged<double> onChanged,
  }) {
    final activeColor = _getScoreColor(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey[600],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            Text(
              "$value%",
              style: TextStyle(
                color: activeColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: activeColor,
            inactiveTrackColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
            thumbColor: activeColor,
            trackHeight: 4.0,
            overlayColor: activeColor.withOpacity(0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
