import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  final String schoolId;
  final String? postId;
  final Map<String, dynamic>? initialData;

  const CreatePostScreen({
    super.key, 
    required this.schoolId,
    this.postId,
    this.initialData,
  });

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _isPosting = false;
  
  List<Map<String, dynamic>> _selectedMediaList = [];
  List<Map<String, dynamic>> _existingMediaList = [];
  
  // Background selection
  int _selectedBackgroundIndex = 0;
  final List<List<Color>> _backgroundGradients = [
    [], // Default
    [const Color(0xFFFF5F6D), const Color(0xFFFFC371)], // Sunset
    [const Color(0xFF2193b0), const Color(0xFF6dd5ed)], // Ocean
    [const Color(0xFFcc2b5e), const Color(0xFF753a88)], // Purple Love
    [const Color(0xFF00B4DB), const Color(0xFF0083B0)], // Blue Raspberry
    [const Color(0xFFf12711), const Color(0xFFf5af19)], // Flare
    [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)], // Frost
  ];

  void _onBackgroundSelected(int index) {
    if (index != 0 && _textController.text.length > 130) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Backgrounds can only be used for posts under 130 characters.")),
      );
      return;
    }
    setState(() {
      _selectedBackgroundIndex = index;
      if (index != 0) {
        // Selecting a background clears media
        _selectedMediaList.clear();
        _existingMediaList.clear();
      }
    });
  }
  
  // Audience Selection
  String _selectedAudience = 'all'; // 'all' or classId
  String? _selectedClassName;
  List<Map<String, dynamic>> _classes = [];
  bool _isLoadingClasses = true;

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _initializeEditMode();
  }

  void _initializeEditMode() {
    if (widget.postId != null && widget.initialData != null) {
      final data = widget.initialData!;
      _textController.text = data['text'] ?? '';
      
      // Initialize media state if exists
      if (data['media'] != null) {
          _existingMediaList = List<Map<String, dynamic>>.from(data['media']);
      } else if (data['mediaUrl'] != null || data['imageUrl'] != null) {
          _existingMediaList = [
              {
                  'url': data['mediaUrl'] ?? data['imageUrl'],
                  'type': data['mediaType'] ?? (data['imageUrl'] != null ? 'image' : 'none')
              }
          ];
      }

      // Initialize Audience
      if (data['targetAudience'] == 'class') {
         _selectedAudience = data['targetClassId'] ?? 'all';
         _selectedClassName = data['targetClassName'];
      }
      _selectedBackgroundIndex = data['backgroundIndex'] ?? 0;
    }
  }

  Future<void> _fetchClasses() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('classes')
          .get();
      
      final classes = snapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc.data()['name'] ?? 'Unknown Class',
      }).toList();

      setState(() {
        _classes = classes;
        _isLoadingClasses = false;
      });
    } catch (e) {
      print("Error fetching classes: $e");
      setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false, bool isMultiple = false}) async {
    final picker = ImagePicker();
    
    try {
      if (isVideo) {
        final XFile? file = await picker.pickVideo(source: source);
        if (file != null) {
          setState(() {
            _selectedBackgroundIndex = 0;
            _selectedMediaList.add({'file': File(file.path), 'type': 'video'});
          });
        }
      } else if (isMultiple) {
        final List<XFile> files = await picker.pickMultiImage();
        if (files.isNotEmpty) {
          setState(() {
            _selectedBackgroundIndex = 0;
            _selectedMediaList.addAll(files.map((f) => {'file': File(f.path), 'type': 'image'}));
          });
        }
      } else {
        final XFile? file = await picker.pickImage(source: source);
        if (file != null) {
          setState(() {
            _selectedBackgroundIndex = 0;
            _selectedMediaList.add({'file': File(file.path), 'type': 'image'});
          });
        }
      }
    } catch (e) {
      print("Error picking media: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking media: $e")),
      );
    }
  }

  Future<void> _createPost() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedMediaList.isEmpty && _existingMediaList.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception("User not logged in");

      // 1. Upload Media (if any)
      List<Map<String, dynamic>> finalMediaList = List.from(_existingMediaList);
      
      if (_selectedMediaList.isNotEmpty) {
        final uploadedMedia = await Future.wait(_selectedMediaList.map((media) async {
            final file = media['file'] as File;
            final type = media['type'] as String;
            final ref = FirebaseStorage.instance
                .ref()
                .child('schools/${widget.schoolId}/posts/${DateTime.now().millisecondsSinceEpoch}_${user.uid}_${file.path.split('/').last}');
            
            await ref.putFile(file);
            final url = await ref.getDownloadURL();
            return {'url': url, 'type': type};
        }));
        finalMediaList.addAll(uploadedMedia);
      }

      // 2. Prepare Post Data
      final Map<String, dynamic> postData = {
        'text': text,
        'authorId': user.uid,
        'authorName': user.displayName ?? "Teacher",
        'authorImage': user.photoURL ?? "",
        'role': 'Teacher',
        'timestamp': FieldValue.serverTimestamp(),
        'likes': [],
        'comments': [],
        'schoolId': widget.schoolId,
        'targetAudience': _selectedAudience == 'all' ? 'all' : 'class',
      };

      if (finalMediaList.isNotEmpty) {
         postData['media'] = finalMediaList;
         // legacy attributes for backward compatibility
         postData['mediaUrl'] = finalMediaList.first['url'];
         postData['mediaType'] = finalMediaList.first['type'];
         if (finalMediaList.first['type'] == 'image') postData['imageUrl'] = finalMediaList.first['url'];
      }

      if (_selectedAudience != 'all') {
        postData['targetClassId'] = _selectedAudience;
        postData['targetClassName'] = _selectedClassName; 
      }
      postData['backgroundIndex'] = _selectedBackgroundIndex;

      // 3. Save to Firestore
      final collectionRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('posts');

      if (widget.postId != null) {
         // Update existing
         await collectionRef.doc(widget.postId).update(postData);
      } else {
         // Create new
         await collectionRef.add(postData);
      }

      if (mounted) context.pop(); // Close screen

    } catch (e) {
      print("Error creating post: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to post: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Widget _buildMediaPreviewItem({required BuildContext context, required bool isLocal, File? file, String? url, required String type, required VoidCallback onRemove}) {
      return Stack(
          children: [
              Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
                  ),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isLocal 
                          ? (type == 'image' ? Image.file(file!, fit: BoxFit.cover) : Container(color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_fill, size: 32, color: Colors.white))))
                          : (type == 'image' ? Image.network(url!, fit: BoxFit.cover) : Container(color: Colors.black87, child: const Center(child: Icon(Icons.play_circle_fill, size: 32, color: Colors.white))))
                  ),
              ),
              Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                  ),
              )
          ]
      );
  }

  @override
  Widget build(BuildContext context) {
    bool hasMedia = _selectedMediaList.isNotEmpty || _existingMediaList.isNotEmpty;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.primaryGradient,
          ),
        ),
        title: Text(
          widget.postId != null ? "Edit Post" : "Create Post", 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: (_textController.text.isNotEmpty || hasMedia) && !_isPosting
                ? _createPost
                : null,
            child: _isPosting 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.postId != null ? "UPDATE" : "POST", 
                    style: TextStyle(
                      color: (_textController.text.isNotEmpty || hasMedia) 
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: FontWeight.bold
                    )),
          )
        ],
      ),
      body: Column(
        children: [
          // Audience Selector
          if (!_isLoadingClasses)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Text("To: ", style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                )),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedAudience,
                      dropdownColor: Theme.of(context).colorScheme.surface,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text("All Classes (Public)"),
                        ),
                        ..._classes.map((cls) {
                          return DropdownMenuItem(
                            value: cls['id'] as String,
                            child: Text(cls['name'] as String),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedAudience = val!;
                          if (val != 'all') {
                             final selectedClass = _classes.firstWhere(
                                 (c) => c['id'] == val,
                                 orElse: () => <String, dynamic>{},
                             );
                             _selectedClassName = selectedClass['name'];
                          } else {
                            _selectedClassName = null;
                          }
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.1)),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Input Area
                  Container(
                    height: _selectedBackgroundIndex != 0 ? 300 : null,
                    decoration: _selectedBackgroundIndex != 0 
                        ? BoxDecoration(
                            gradient: LinearGradient(colors: _backgroundGradients[_selectedBackgroundIndex]),
                          )
                        : null,
                    padding: const EdgeInsets.all(16.0),
                    alignment: _selectedBackgroundIndex != 0 ? Alignment.center : Alignment.topLeft,
                    child: TextField(
                      controller: _textController,
                      style: TextStyle(
                          color: _selectedBackgroundIndex != 0 ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color, 
                          fontSize: _selectedBackgroundIndex != 0 ? (_textController.text.length < 85 ? 28 : 22) : 15,
                          height: _selectedBackgroundIndex != 0 ? null : 1.4,
                          fontWeight: _selectedBackgroundIndex != 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: _selectedBackgroundIndex != 0 ? TextAlign.center : TextAlign.start,
                      minLines: _selectedBackgroundIndex != 0 ? 1 : 5,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: "What's on your mind?",
                        hintStyle: TextStyle(
                            color: _selectedBackgroundIndex != 0 
                                ? Colors.white70 
                                : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.4),
                        ),
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val.length > 130 && _selectedBackgroundIndex != 0) {
                             _selectedBackgroundIndex = 0;
                          }
                        });
                      },
                    ),
                  ),

                  // Background Selection Row
                  if (!hasMedia)
                    SizedBox(
                      height: 50,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _backgroundGradients.length,
                        itemBuilder: (context, index) {
                          final isSelected = _selectedBackgroundIndex == index;
                          return GestureDetector(
                            onTap: () => _onBackgroundSelected(index),
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: isSelected ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
                                color: index == 0 ? Theme.of(context).dividerColor.withOpacity(0.1) : null,
                                gradient: index != 0 ? LinearGradient(colors: _backgroundGradients[index]) : null,
                              ),
                              child: index == 0 
                                  ? Icon(Icons.block, color: Theme.of(context).disabledColor, size: 20) 
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),

                  // Bottom Actions
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Text("Add to your post", style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                        )),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.image, color: Colors.green),
                          onPressed: () => _pickMedia(ImageSource.gallery, isMultiple: true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.videocam, color: Colors.red),
                          onPressed: () => _pickMedia(ImageSource.gallery, isVideo: true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt, color: Colors.blue),
                          onPressed: () => _pickMedia(ImageSource.camera),
                        ),
                      ],
                    ),
                  ),

                  // Media Preview
                  if (hasMedia)
                     Container(
                       width: double.infinity,
                       margin: const EdgeInsets.all(16),
                       child: Wrap(
                         spacing: 8,
                         runSpacing: 8,
                         children: [
                           ..._existingMediaList.asMap().entries.map((entry) {
                               int idx = entry.key;
                               var m = entry.value;
                               return _buildMediaPreviewItem(
                                   context: context,
                                   isLocal: false, 
                                   url: m['url'], 
                                   type: m['type'], 
                                   onRemove: () {
                                       setState(() => _existingMediaList.removeAt(idx));
                                   }
                               );
                           }),
                           ..._selectedMediaList.asMap().entries.map((entry) {
                               int idx = entry.key;
                               var m = entry.value;
                               return _buildMediaPreviewItem(
                                   context: context,
                                   isLocal: true, 
                                   file: m['file'], 
                                   type: m['type'], 
                                   onRemove: () {
                                       setState(() => _selectedMediaList.removeAt(idx));
                                   }
                               );
                           })
                         ],
                       )
                     ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
