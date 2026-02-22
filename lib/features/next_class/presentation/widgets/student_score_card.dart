import 'package:flutter/material.dart';

class StudentScoreCard extends StatelessWidget {
  final Map<String, dynamic> student;
  final bool isTestMode;
  
  // Normal Mode Params
  final int? academicScore;
  final int? homeworkScore;
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
    this.onScoreChanged,
    this.testScore,
    this.onTestScoreChanged,
  }) : super(key: key);

  Color _getScoreColor(int score) {
    if (score >= 80) return const Color(0xFF10B981); // emerald-500
    if (score >= 50) return const Color(0xFFF59E0B); // amber-500
    return const Color(0xFFEF4444); // red-500
  }

  @override
  Widget build(BuildContext context) {
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
          if (isTestMode)
            _buildSlider(
              context: context,
              label: "Test Score",
              value: testScore ?? 0,
              onChanged: (val) {
                if (onTestScoreChanged != null) {
                  onTestScoreChanged!(student['id'], val.toInt());
                }
              },
            )
          else ...[
            _buildSlider(
              context: context,
              label: "Subject Score",
              value: academicScore ?? 0,
              onChanged: (val) {
                if (onScoreChanged != null) {
                  onScoreChanged!(student['id'], 'academic', val.toInt());
                }
              },
            ),
            const SizedBox(height: 12),
            _buildSlider(
              context: context,
              label: "Homework Score",
              value: homeworkScore ?? 0,
              onChanged: (val) {
                if (onScoreChanged != null) {
                  onScoreChanged!(student['id'], 'homework', val.toInt());
                }
              },
            ),
          ],
        ],
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
