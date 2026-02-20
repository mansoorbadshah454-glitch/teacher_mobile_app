import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/widgets/news_post_card.dart';
import 'package:teacher_mobile_app/features/news_feed/presentation/screens/create_post_screen.dart';

class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  String? schoolId;
  String? schoolName;
  String? schoolLogo;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSchoolInfo();
  }

  Future<void> _fetchSchoolInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = "User not logged in";
          _isLoading = false;
        });
        return;
      }

      print("🔍 [NewsFeed] Fetching school info for user: ${user.uid}");

      // Naive search: Get first school
      final schoolsSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      if (schoolsSnapshot.docs.isNotEmpty) {
        final doc = schoolsSnapshot.docs.first;
        setState(() {
          schoolId = doc.id;
          schoolName = doc.data()['name'];
          schoolLogo = doc.data()['logo'] ?? doc.data()['profileImage'];
          _errorMessage = null;
        });
        print("✅ [NewsFeed] Found school: ${doc.id}");
      } else {
        setState(() {
          _errorMessage = "No schools found";
        });
        print("⚠️ [NewsFeed] No schools collection found");
      }
    } catch (e) {
      print("💥 [NewsFeed] Error: $e");
      setState(() {
        _errorMessage = "Failed to load school info: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              backgroundColor: AppTheme.backgroundDark,
              // expandedHeight: 120.0,
              floating: true,
              pinned: true,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.pop(),
              ),
              title: Row(
                children: [
                  if (schoolLogo != null)
                    CircleAvatar(
                      backgroundImage: NetworkImage(schoolLogo!),
                      radius: 16,
                    )
                  else
                    const Icon(Icons.shield, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schoolName ?? "School Feed",
                      style: AppTheme.titleLarge.copyWith(fontSize: 20),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              centerTitle: false,
            ),
          ];
        },
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.orange, size: 48),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchSchoolInfo,
                          child: const Text("Retry"),
                        )
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('schools')
                    .doc(schoolId)
                    .collection('posts')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.feed_outlined, size: 64, color: Colors.white.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            "No posts yet",
                            style: AppTheme.bodyMedium.copyWith(color: Colors.white54),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: docs.length + 1, // +1 for Create Post
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildCreatePostTrigger(context);
                      }
                      final data = docs[index - 1].data() as Map<String, dynamic>;
                      final id = docs[index - 1].id;
                      return NewsPostCard(
                        id: id,
                        data: data,
                        schoolId: schoolId!,
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _buildCreatePostTrigger(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      color: AppTheme.surfaceDark,
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage: FirebaseAuth.instance.currentUser?.photoURL != null 
                ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!) 
                : null,
            radius: 20,
            child: FirebaseAuth.instance.currentUser?.photoURL == null 
                ? const Icon(Icons.person) 
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (schoolId != null) {
                   Navigator.push(
                     context,
                     MaterialPageRoute(builder: (_) => CreatePostScreen(schoolId: schoolId!)),
                   );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  "Write a post...",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.image, color: Colors.green),
            onPressed: () {
                 if (schoolId != null) {
                   Navigator.push(
                     context,
                     MaterialPageRoute(builder: (_) => CreatePostScreen(schoolId: schoolId!)),
                   );
                }
            },
          ),
        ],
      ),
    );
  }
}
