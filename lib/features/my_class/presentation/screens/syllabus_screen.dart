import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  // Mock data for the syllabus
  final double progressPercent = 0.65;
  
  final List<Map<String, dynamic>> syllabusData = [
    {
      'subject': 'Mathematics',
      'icon': Icons.calculate,
      'color': const Color(0xFF6366f1), // Indigo
      'chapters': [
        {'title': 'Algebraic Expressions', 'status': 'Completed', 'time': '2 weeks'},
        {'title': 'Linear Equations', 'status': 'Completed', 'time': '1 week'},
        {'title': 'Geometry & Shapes', 'status': 'In Progress', 'time': '3 weeks'},
        {'title': 'Trigonometry', 'status': 'Pending', 'time': '4 weeks'},
      ],
    },
    {
      'subject': 'Science',
      'icon': Icons.science,
      'color': const Color(0xFF10b981), // Emerald
      'chapters': [
        {'title': 'Cell Structure', 'status': 'Completed', 'time': '2 weeks'},
        {'title': 'Human Anatomy', 'status': 'In Progress', 'time': '3 weeks'},
        {'title': 'Chemical Reactions', 'status': 'Pending', 'time': '2 weeks'},
      ],
    },
    {
      'subject': 'English',
      'icon': Icons.menu_book,
      'color': const Color(0xFFeab308), // Yellow
      'chapters': [
        {'title': 'Grammar Basics', 'status': 'Completed', 'time': '1 week'},
        {'title': 'Creative Writing', 'status': 'Completed', 'time': '2 weeks'},
        {'title': 'Literature: Shakespeare', 'status': 'Pending', 'time': '3 weeks'},
      ],
    }
  ];

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

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
                colors: [Color(0xFF6366f1), Color(0xFF4f46e5)], // Indigo Gradient
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
                    const Text(
                      "Syllabus",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Progress Ring UI
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
                        const Text("Overall Progress", style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text("On Track", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text("Mid-term upcoming", style: TextStyle(color: Colors.white, fontSize: 10)),
                        )
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: syllabusData.length,
              itemBuilder: (context, index) {
                final subject = syllabusData[index];
                final chapters = subject['chapters'] as List<Map<String, dynamic>>;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                    boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))] : [],
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (subject['color'] as Color).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(subject['icon'] as IconData, color: subject['color'] as Color),
                      ),
                      title: Text(subject['subject'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.indigo[900])),
                      children: chapters.map((chapter) {
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

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: Icon(statusIcon, color: statusColor, size: 20),
                          title: Text(chapter['title'], style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600)),
                          subtitle: Text("Est. Time: ${chapter['time']}", style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black45)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              chapter['status'],
                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
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
