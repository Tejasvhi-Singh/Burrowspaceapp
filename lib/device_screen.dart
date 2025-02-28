import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _deviceNameController = TextEditingController();
  bool _isAddingDevice = false;

  @override
  void initState() {
    super.initState();
    _deviceNameController.text = _getDefaultDeviceName();
  }

  String _getDefaultDeviceName() {
    if (kIsWeb) {
      return 'Web Browser';
    } else if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isIOS) {
      return 'iOS Device';
    } else if (Platform.isWindows) {
      return 'Windows PC';
    } else if (Platform.isMacOS) {
      return 'Mac';
    } else if (Platform.isLinux) {
      return 'Linux Device';
    } else {
      return 'Unknown Device';
    }
  }

  String _getPlatformType() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  IconData _getDeviceIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'windows':
        return Icons.laptop_windows;
      case 'macos':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      case 'web':
        return Icons.web;
      default:
        return Icons.devices_other;
    }
  }

  Future<void> _addDevice() async {
    if (_deviceNameController.text.isEmpty) {
      _showMessage('Device name cannot be empty');
      return;
    }

    setState(() {
      _isAddingDevice = true;
    });

    try {
      // Add device to Firestore
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('devices')
          .add({
        'deviceName': _deviceNameController.text.trim(),
        'platform': _getPlatformType(),
        'lastActive': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _isAddingDevice = false;
        _deviceNameController.text = '';
      });

      _showMessage('Device added successfully');
    } catch (e) {
      setState(() {
        _isAddingDevice = false;
      });
      _showMessage('Error adding device: $e', isError: true);
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    try {
      await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .collection('devices')
          .doc(deviceId)
          .delete();

      _showMessage('Device removed');
    } catch (e) {
      _showMessage('Error removing device: $e', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Add New Device'),
                  content: TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Device Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _isAddingDevice
                          ? null
                          : () {
                              _addDevice();
                              Navigator.pop(context);
                            },
                      child: _isAddingDevice
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Add Device'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Device summary card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.devices,
                      size: 48, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(_auth.currentUser!.uid)
                        .collection('devices')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final deviceCount = snapshot.data?.docs.length ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your Devices',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text('$deviceCount active devices',
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Device list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(_auth.currentUser!.uid)
                  .collection('devices')
                  .orderBy('lastActive', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final devices = snapshot.data!.docs;

                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.devices_other,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No devices added yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add your first device',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device =
                        devices[index].data() as Map<String, dynamic>;
                    final deviceId = devices[index].id;
                    final platform = device['platform'] as String? ?? 'unknown';
                    final isThisDevice = platform == _getPlatformType();

                    return Dismissible(
                      key: Key(deviceId),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        if (isThisDevice) {
                          _showMessage('Cannot remove the current device',
                              isError: true);
                          return false;
                        }
                        return await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Confirm'),
                            content: Text(
                                'Remove device "${device['deviceName']}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) => _removeDevice(deviceId),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: isThisDevice
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.blue.withValues(alpha: 0.2),
                              child: Icon(
                                _getDeviceIcon(platform),
                                color:
                                    isThisDevice ? Colors.green : Colors.blue,
                              ),
                            ),
                            if (isThisDevice)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Text(device['deviceName'] as String? ?? 'Unknown'),
                            if (isThisDevice)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Current',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.green),
                                ),
                              ),
                          ],
                        ),
                        subtitle: device['lastActive'] != null
                            ? Text(
                                'Last active: ${_formatTimestamp(device['lastActive'] as Timestamp)}',
                              )
                            : const Text('Recently added'),
                        trailing: isThisDevice
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeDevice(deviceId),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _deviceNameController.text = _getDefaultDeviceName();
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Add This Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.blue.withValues(alpha: 0.2),
                    child: Icon(
                      _getDeviceIcon(_getPlatformType()),
                      color: Colors.blue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Device Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isAddingDevice
                      ? null
                      : () {
                          _addDevice();
                          Navigator.pop(context);
                        },
                  child: _isAddingDevice
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add Device'),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }
}
