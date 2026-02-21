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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF334155), // slate-700
                ),
                clipBehavior: Clip.hardEdge,
                child: profilePic != null && profilePic.isNotEmpty
                    ? Image.network(profilePic, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white))
                    : const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Roll No: $rollNo",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
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
              style: const TextStyle(
                color: Colors.grey,
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
            inactiveTrackColor: Colors.white.withOpacity(0.1),
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
