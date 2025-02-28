import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'login_screen.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'chat_screen.dart';
import 'device_screen.dart';
import 'settings_screen.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final Set<String> _selectedFiles = {};
  String _currentSort = 'Name';
  bool _isGridView = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  Future<void> _addFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        dialogTitle:
            Platform.isAndroid || Platform.isIOS
                ? 'Select files'
                : 'Browse files',
      );

      if (result != null && result.files.isNotEmpty) {
        final existingFiles =
            await _firestore
                .collection('users')
                .doc(_auth.currentUser!.uid)
                .collection('files')
                .get();

        final existingPaths =
            existingFiles.docs.map((doc) {
              final data = doc.data();
              return data['path'] as String;
            }).toSet();

        final newFiles =
            result.files.where((file) {
              if (file.path == null) {
                _logDebug('File path is null for ${file.name}');
                return false;
              }
              final isDuplicate = existingPaths.contains(file.path);
              if (isDuplicate) {
                _logDebug('Duplicate found: ${file.path}');
              }
              return !isDuplicate;
            }).toList();

        if (newFiles.isEmpty) {
          _showMessage('These files already exist', isError: true);
          return;
        }

        // Add new files
        for (final file in newFiles) {
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('files')
              .add({
                'addedAt': FieldValue.serverTimestamp(),
                'name': file.name,
                'path': file.path,
                'size': file.size,
                'extension': file.extension,
              });
        }

        _showMessage(
          result.files.length == newFiles.length
              ? 'Added ${newFiles.length} file(s) successfully'
              : 'Added ${newFiles.length} file(s), skipped ${result.files.length - newFiles.length} duplicate(s)',
        );
      }
    } catch (e) {
      _showMessage('Error adding files: $e', isError: true);
    }
  }

  Future<void> _openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final result = await OpenFile.open(filePath);
        if (result.type != ResultType.done) {
          _showMessage('Cannot open file: ${result.message}', isError: true);
        }
      } else {
        _showMessage('File not found', isError: true);
      }
    } catch (e) {
      _showMessage('Error opening file: $e', isError: true);
    }
  }

  Future<void> _deleteFile(String documentId) async {
    try {
      final fileDoc =
          await _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('files')
              .doc(documentId)
              .get();

      final filePath = fileDoc.data()?['path'] as String?;

      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('files')
          .doc(documentId)
          .delete();

      if (filePath != null) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          _logDebug('Error deleting file from storage: $e');
        }
      }

      _showMessage('File deleted');
    } catch (e) {
      _showMessage('Error deleting file: $e', isError: true);
    }
  }

  void _toggleFileSelection(String documentId) {
    setState(() {
      if (_selectedFiles.contains(documentId)) {
        _selectedFiles.remove(documentId);
      } else {
        _selectedFiles.add(documentId);
      }
    });
  }

  Future<void> _deleteSelectedFiles() async {
    try {
      for (final documentId in _selectedFiles) {
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .collection('files')
            .doc(documentId)
            .delete();
      }

      setState(() {
        _selectedFiles.clear();
      });

      _showMessage('Selected files deleted');
    } catch (e) {
      _showMessage('Error deleting files: $e', isError: true);
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Burrow Space'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Badge(label: Text('85%'), child: Icon(Icons.storage)),
            onPressed: () {
              // Show storage details
            },
          ),
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DeviceScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: _signOut,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort files',
            onSelected: (value) {
              setState(() {
                _currentSort = value;
              });
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'Name',
                    child: Text('Sort by name'),
                  ),
                  const PopupMenuItem(
                    value: 'Date',
                    child: Text('Sort by date'),
                  ),
                  const PopupMenuItem(
                    value: 'Size',
                    child: Text('Sort by size'),
                  ),
                  const PopupMenuItem(
                    value: 'Type',
                    child: Text('Sort by type'),
                  ),
                ],
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: _isGridView ? 'List view' : 'Grid view',
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'logout':
                  _signOut();
                  break;
                case 'devices':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DeviceScreen(),
                    ),
                  );
                  break;
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'devices',
                    child: Text('Manage devices'),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                  const PopupMenuItem(value: 'logout', child: Text('Logout')),
                ],
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud,
                    size: 48,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream:
                        _firestore
                            .collection('users')
                            .doc(_auth.currentUser!.uid)
                            .collection('files')
                            .snapshots(),
                    builder: (context, snapshot) {
                      final fileCount = snapshot.data?.docs.length ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Files',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '$fileCount files stored',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _isGridView ? _buildGridView() : _buildListView()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFiles,
        icon: const Icon(Icons.add),
        label: const Text('Add Files'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar:
          _selectedFiles.isNotEmpty
              ? BottomAppBar(
                height: 60,
                padding: EdgeInsets.zero,
                child: Container(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.delete),
                        label: Text('Delete (${_selectedFiles.length})'),
                        onPressed: _deleteSelectedFiles,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.share),
                        label: Text('Share (${_selectedFiles.length})'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ChatScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              )
              : null,
    );
  }

  Widget _buildGridView() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('files')
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        // Sort documents based on _currentSort
        _sortDocuments(documents);

        if (documents.isEmpty) {
          return const Center(child: Text('No files yet'));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            final doc = documents[index];
            final file = doc.data() as Map<String, dynamic>;
            final isSelected = _selectedFiles.contains(doc.id);
            final extension = file['extension'] as String? ?? '';

            // Choose background color based on file type
            Color cardColor;
            switch (extension.toLowerCase()) {
              case 'pdf':
                cardColor = Colors.red.shade100;
                break;
              case 'doc':
              case 'docx':
                cardColor = Colors.blue.shade100;
                break;
              case 'jpg':
              case 'png':
                cardColor = Colors.green.shade100;
                break;
              default:
                cardColor = Colors.grey.shade100;
            }

            return Dismissible(
              key: Key(doc.id),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _deleteFile(doc.id),
              child: Card(
                color:
                    isSelected
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                        : cardColor,
                child: InkWell(
                  onTap: () => _openFile(file['path'] as String),
                  onLongPress: () => _toggleFileSelection(doc.id),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Icon(
                              _getFileIcon(file['extension'] as String),
                              size: 48,
                            ),
                            Checkbox(
                              value: isSelected,
                              onChanged:
                                  (bool? value) => _toggleFileSelection(doc.id),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          file['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatFileSize(file['size'] as int),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildListView() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          _firestore
              .collection('users')
              .doc(_auth.currentUser!.uid)
              .collection('files')
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        // Sort documents based on _currentSort
        _sortDocuments(documents);

        if (documents.isEmpty) {
          return const Center(child: Text('No files yet'));
        }

        return ListView.builder(
          itemCount: documents.length,
          itemBuilder: (context, index) {
            final doc = documents[index];
            final file = doc.data() as Map<String, dynamic>;
            final isSelected = _selectedFiles.contains(doc.id);

            return Dismissible(
              key: Key(doc.id),
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) => _deleteFile(doc.id),
              child: ListTile(
                leading: Icon(_getFileIcon(file['extension'] as String)),
                title: Text(file['name'] as String),
                subtitle: Text('Size: ${_formatFileSize(file['size'] as int)}'),
                trailing: Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) => _toggleFileSelection(doc.id),
                ),
                onTap: () => _openFile(file['path'] as String),
                onLongPress: () => _toggleFileSelection(doc.id),
                selected: isSelected,
              ),
            );
          },
        );
      },
    );
  }

  IconData _getFileIcon(String? extension) {
    if (extension == null) return Icons.insert_drive_file;

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

  // Helper method to sort documents based on current sort option
  void _sortDocuments(List<QueryDocumentSnapshot> documents) {
    switch (_currentSort) {
      case 'Name':
        documents.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          return (aData['name'] as String).compareTo(bData['name'] as String);
        });
        break;
      case 'Size':
        documents.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          return (aData['size'] as int).compareTo(bData['size'] as int);
        });
        break;
      case 'Date':
        documents.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = aData['addedAt'] as Timestamp?;
          final bDate = bData['addedAt'] as Timestamp?;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate); // Newest first
        });
        break;
      case 'Type':
        documents.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          return (aData['extension'] as String? ?? '').compareTo(
            bData['extension'] as String? ?? '',
          );
        });
        break;
    }
  }
}
