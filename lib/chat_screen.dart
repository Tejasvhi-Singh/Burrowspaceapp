import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'services/file_transfer_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  List<String> selectedFiles = [];
  final _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  String? _selectedUserId;

  // Transfer progress tracking
  final Map<String, double> _transferProgress = {};

  // Decentralized services status
  bool _isTransferServiceInitialized = false;
  final _transferService = FileTransferService();

  @override
  void initState() {
    super.initState();
    _checkForSharedFiles();
    _initializeTransferService();
    _setupTransferListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Initialize the decentralized file transfer service
  Future<void> _initializeTransferService() async {
    try {
      final isInitialized = await _transferService.initialize();

      if (mounted) {
        setState(() {
          _isTransferServiceInitialized = isInitialized;
        });
      }

      if (isInitialized) {
        _showNotification('Decentralized file transfer service initialized');
      } else {
        _showNotification('Failed to initialize file transfer service');
      }
    } catch (e) {
      _showError('Error initializing transfer service: $e');
    }
  }

  // Show error message
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // Show notification message
  void _showNotification(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // Check for shared files
  Future<void> _checkForSharedFiles() async {
    if (!mounted) return;

    try {
      // Listen for files shared with current user
      _firestore
          .collection('file_transfers')
          .where('receiverId', isEqualTo: _auth.currentUser!.uid)
          .where('status', isEqualTo: TransferStatus.completed.name)
          .snapshots()
          .listen((snapshot) async {
            for (var doc in snapshot.docs) {
              final data = doc.data();

              // Check if this is a new transfer we haven't processed
              if (data['processed'] != true) {
                // Mark as processed
                await doc.reference.update({'processed': true});

                // If there's a CID, download and save the file
                if (data['cid'] != null) {
                  _showNotification(
                    'New file shared with you: ${data['fileName']}',
                  );

                  // Show download dialog
                  if (mounted) {
                    showDialog(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('New File Available'),
                            content: Text(
                              '${data['fileName']} is ready to download',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Later'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _downloadSharedFile(
                                    data['cid'],
                                    data['fileName'],
                                  );
                                },
                                child: const Text('Download'),
                              ),
                            ],
                          ),
                    );
                  }
                }
              }
            }
          });
    } catch (e) {
      _showError('Error checking shared files: $e');
    }
  }

  // Download a shared file from IPFS
  Future<void> _downloadSharedFile(String cid, String fileName) async {
    try {
      // Get directory to save file
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      // Show progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => StatefulBuilder(
                builder: (context, setState) {
                  return AlertDialog(
                    title: const Text('Downloading File'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Downloading $fileName'),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: _transferProgress[cid] ?? 0.0,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${((_transferProgress[cid] ?? 0.0) * 100).toStringAsFixed(0)}%',
                        ),
                      ],
                    ),
                  );
                },
              ),
        );
      }

      // Download file
      final file = await _transferService.downloadFile(
        cid: cid,
        savePath: filePath,
        fileName: fileName,
        onProgress: (progress) {
          setState(() {
            _transferProgress[cid] = progress;
          });

          // Update dialog
          if (mounted) {
            setState(() {});
          }
        },
      );

      // Close dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (file != null) {
        _showNotification('File downloaded successfully');

        // Save file info to user's collection
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('files')
            .add({
              'name': fileName,
              'path': filePath,
              'size': file.lengthSync(),
              'extension': fileName.split('.').last,
              'cid': cid,
              'addedAt': FieldValue.serverTimestamp(),
            });
      } else {
        _showError('Failed to download file');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      _showError('Error downloading file: $e');
    }
  }

  // Request file transfer
  Future<void> _requestFileTransfer(
    String targetUserId,
    String filePath,
  ) async {
    if (!_isTransferServiceInitialized) {
      await _initializeTransferService();
      if (!_isTransferServiceInitialized) {
        _showError(
          'Could not initialize transfer service. Please check settings.',
        );
        return;
      }
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showError('File not found: $filePath');
        return;
      }

      // Get filename from path
      final fileName = filePath.split('/').last.split('\\').last;

      // Log the file being shared
      debugPrint('Sharing file: $fileName');

      // Start file transfer
      _showNotification('Starting file transfer for $fileName...');

      setState(() {
        _transferProgress[filePath] = 0.0;
      });

      // Share the file
      final result = await _transferService.shareFile(
        receiverId: targetUserId,
        filePath: filePath,
        onProgress: (progress) {
          setState(() {
            _transferProgress[filePath] = progress;
          });
        },
      );

      if (result == null) {
        _showError('Failed to share file');
        setState(() {
          _transferProgress.remove(filePath);
        });
        return;
      }

      _showNotification('File shared successfully');

      // Update the UI
      setState(() {
        _transferProgress.remove(filePath);
      });
    } catch (e) {
      _showError('Failed to send file: $e');
      setState(() {
        _transferProgress.remove(filePath);
      });
    }
  }

  // Setup listeners for file transfer events
  void _setupTransferListeners() {
    // Listen for transfer events
    _transferService.on('transfer_request', (data) {
      _showNotification('New file transfer request from ${data['senderId']}');
    });

    _transferService.on('transfer_completed', (data) {
      _showNotification('File transfer completed: ${data['fileName']}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Files'),
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Icon(
              _isTransferServiceInitialized ? Icons.wifi : Icons.wifi_off,
              color: _isTransferServiceInitialized ? Colors.green : Colors.grey,
            ),
          ),
          if (selectedFiles.isNotEmpty && _selectedUserId != null)
            IconButton(icon: const Icon(Icons.send), onPressed: _shareFiles),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search users by email...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _searchUsers,
            ),
          ),

          // Search results
          if (_searchResults.isNotEmpty)
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user =
                      _searchResults[index].data() as Map<String, dynamic>;
                  final isSelected =
                      _selectedUserId == _searchResults[index].id;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? Colors.blue : null,
                      child: Text(user['email'][0].toUpperCase()),
                    ),
                    title: Text(
                      user['email'] as String,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(user['fullName'] as String? ?? ''),
                    selected: isSelected,
                    trailing: Radio<String>(
                      value: _searchResults[index].id,
                      groupValue: _selectedUserId,
                      onChanged: (value) {
                        setState(() {
                          _selectedUserId = value;
                        });
                        if (value != null) {
                          _requestFileTransfer(value, '');
                        }
                      },
                    ),
                  );
                },
              ),
            ),

          // Transfer Progress Indicators
          if (_transferProgress.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[200],
              child: Column(
                children:
                    _transferProgress.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: entry.value,
                                backgroundColor: Colors.grey[300],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  entry.value < 1 ? Colors.blue : Colors.green,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${(entry.value * 100).toInt()}%'),
                          ],
                        ),
                      );
                    }).toList(),
              ),
            ),

          // File list
          Expanded(
            flex: 2,
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _firestore
                      .collection('users')
                      .doc(_auth.currentUser!.uid)
                      .collection('files')
                      .orderBy('addedAt', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final documents = snapshot.data!.docs;

                if (documents.isEmpty) {
                  return const Center(child: Text('No files to share'));
                }

                return ListView.builder(
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final file =
                        documents[index].data() as Map<String, dynamic>;
                    final isSelected = selectedFiles.contains(
                      file['path'] as String?,
                    );

                    return ListTile(
                      leading: Icon(
                        _getFileIcon(file['extension'] as String? ?? ''),
                      ),
                      title: Text(file['name'] as String),
                      subtitle: Text(
                        'Size: ${_formatFileSize(file['size'] as int)}',
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        onChanged: (bool? value) {
                          setState(() {
                            if (value == true) {
                              selectedFiles.add(file['path'] as String? ?? '');
                            } else {
                              selectedFiles.remove(
                                file['path'] as String? ?? '',
                              );
                            }
                          });
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await FilePicker.platform.pickFiles();
          if (result != null && result.files.isNotEmpty) {
            final file = result.files.first;
            if (file.path != null) {
              // Save to local directory
              final directory = await getApplicationDocumentsDirectory();
              final fileName = file.name;
              final targetPath = '${directory.path}/$fileName';

              // Copy file to app directory if needed
              final sourceFile = File(file.path!);
              final targetFile = File(targetPath);

              if (!await targetFile.exists()) {
                await sourceFile.copy(targetPath);
              }

              // Store in Firestore
              await _firestore
                  .collection('users')
                  .doc(_auth.currentUser!.uid)
                  .collection('files')
                  .add({
                    'name': fileName,
                    'path': targetPath,
                    'size': file.size,
                    'type': file.extension,
                    'extension': file.extension,
                    'addedAt': FieldValue.serverTimestamp(),
                  });
            }
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'm4a':
        return Icons.audio_file;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      final results =
          await _firestore
              .collection('users')
              .where('email', isGreaterThanOrEqualTo: query)
              .where('email', isLessThan: '${query}z')
              .get();

      setState(() {
        _searchResults =
            results.docs
                .where((doc) => doc.id != _auth.currentUser!.uid)
                .toList();
      });
    } catch (e) {
      _showError('Error searching users: $e');
    }
  }

  Future<void> _shareFiles() async {
    if (!mounted || _selectedUserId == null || selectedFiles.isEmpty) {
      _showError('Please select recipient and files');
      return;
    }

    try {
      // Send files via decentralized transfer service
      for (final filePath in selectedFiles) {
        await _requestFileTransfer(_selectedUserId!, filePath);
      }

      // Clear selection
      setState(() {
        selectedFiles.clear();
      });

      _showNotification('File sharing initiated');
    } catch (e) {
      _showError('Error sharing files: $e');
    }
  }
}
