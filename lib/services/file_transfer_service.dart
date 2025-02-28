import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ipfs_service.dart';
import 'libp2p_service.dart';

/// Status of a file transfer
enum TransferStatus {
  pending,
  approved,
  inProgress,
  completed,
  failed,
  cancelled,
}

/// A service that combines IPFS and libp2p for decentralized file transfers.
class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  factory FileTransferService() => _instance;
  FileTransferService._internal();

  // Services
  final _ipfsService = IPFSService();
  final _p2pService = LibP2PService();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Event handlers
  final Map<String, Function> _eventHandlers = {};

  // Initialize the service
  Future<bool> initialize() async {
    try {
      // Initialize IPFS and libp2p
      final ipfsInitialized = await _ipfsService.initialize();
      final p2pInitialized = await _p2pService.initialize();

      // Register the device for discovery
      if (p2pInitialized && _auth.currentUser != null) {
        await _p2pService.registerDevice();
      }

      return ipfsInitialized && p2pInitialized;
    } catch (e) {
      debugPrint('Error initializing FileTransferService: $e');
      return false;
    }
  }

  // Register event handlers
  void on(String event, Function(dynamic) handler) {
    _eventHandlers[event] = handler;
  }

  /// Request a file transfer to another user
  Future<Map<String, dynamic>?> requestFileTransfer({
    required String receiverId,
    required String filePath,
    required String fileName,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not logged in');
    }

    try {
      // Generate a transfer ID
      final transferId = const Uuid().v4();

      // Create transfer record in Firestore
      final transferRef = _firestore
          .collection('file_transfers')
          .doc(transferId);

      await transferRef.set({
        'transferId': transferId,
        'senderId': currentUser.uid,
        'receiverId': receiverId,
        'fileName': fileName,
        'fileSize': File(filePath).lengthSync(),
        'status': TransferStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create notification
      await _firestore.collection('notifications').add({
        'userId': receiverId,
        'type': 'transfer_request',
        'transferId': transferId,
        'senderId': currentUser.uid,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {'transferId': transferId, 'status': TransferStatus.pending.name};
    } catch (e) {
      debugPrint('Error requesting file transfer: $e');
      return null;
    }
  }

  /// Approve a file transfer request
  Future<bool> approveTransfer(String transferId) async {
    try {
      await _firestore.collection('file_transfers').doc(transferId).update({
        'status': TransferStatus.approved.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Error approving transfer: $e');
      return false;
    }
  }

  /// Cancel a file transfer
  Future<bool> cancelTransfer(String transferId) async {
    try {
      await _firestore.collection('file_transfers').doc(transferId).update({
        'status': TransferStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Error canceling transfer: $e');
      return false;
    }
  }

  /// Share a file with another user using IPFS and libp2p
  Future<Map<String, dynamic>?> shareFile({
    required String receiverId,
    required String filePath,
    Function(double)? onProgress,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not logged in');
    }

    try {
      final file = File(filePath);
      final fileName = path.basename(filePath);

      // Create initial transfer record
      final transfer = await requestFileTransfer(
        receiverId: receiverId,
        filePath: filePath,
        fileName: fileName,
      );

      if (transfer == null) {
        return null;
      }

      final transferId = transfer['transferId'];

      // Add file to IPFS
      if (onProgress != null) onProgress(0.1);
      final cid = await _ipfsService.addFile(
        file,
        onProgress: (progress) {
          // Scale progress from 0.1 to 0.7
          if (onProgress != null) onProgress(0.1 + progress * 0.6);
        },
      );

      if (cid == null) {
        await _firestore.collection('file_transfers').doc(transferId).update({
          'status': TransferStatus.failed.name,
          'error': 'Failed to add file to IPFS',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return null;
      }

      // Pin the file to ensure it stays available
      await _ipfsService.pinFile(cid);
      if (onProgress != null) onProgress(0.8);

      // Update the transfer record with IPFS details
      await _firestore.collection('file_transfers').doc(transferId).update({
        'cid': cid,
        'status': TransferStatus.inProgress.name,
        'ipfsUrl': _ipfsService.getShareableUrl(cid, usePublicGateway: true),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Look up the user's devices from Firebase
      final receiverDevices = await _p2pService.lookupUserDevices(receiverId);
      if (onProgress != null) onProgress(0.9);

      if (receiverDevices.isNotEmpty) {
        // Try to connect to each device
        for (final device in receiverDevices) {
          if (device['peerId'] != null) {
            final connected = await _p2pService.connectToPeer(
              peerId: device['peerId'],
              multiaddr:
                  device['addresses']?.isNotEmpty == true
                      ? device['addresses'][0]
                      : null,
            );

            if (connected) {
              // Send the transfer notification via libp2p
              await _p2pService.sendData(
                peerId: device['peerId'],
                data: {
                  'type': 'file_transfer',
                  'transferId': transferId,
                  'cid': cid,
                  'fileName': fileName,
                },
              );
              break;
            }
          }
        }
      }

      // Mark as completed
      await _firestore.collection('file_transfers').doc(transferId).update({
        'status': TransferStatus.completed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create notification
      await _firestore.collection('notifications').add({
        'userId': receiverId,
        'type': 'transfer_completed',
        'transferId': transferId,
        'senderId': currentUser.uid,
        'read': false,
        'cid': cid,
        'fileName': fileName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (onProgress != null) onProgress(1.0);

      return {
        'transferId': transferId,
        'cid': cid,
        'status': TransferStatus.completed.name,
      };
    } catch (e) {
      debugPrint('Error sharing file: $e');
      return null;
    }
  }

  /// Download a file from IPFS
  Future<File?> downloadFile({
    required String cid,
    required String savePath,
    String? fileName,
    Function(double)? onProgress,
  }) async {
    try {
      // Get the file from IPFS
      final file = await _ipfsService.getFile(
        cid,
        fileName: fileName ?? cid,
        onProgress: onProgress,
      );

      if (file == null) {
        return null;
      }

      // If a save path is specified, copy the file
      if (savePath != file.path) {
        final saveFile = File(savePath);
        await file.copy(savePath);
        return saveFile;
      }

      return file;
    } catch (e) {
      debugPrint('Error downloading file: $e');
      return null;
    }
  }

  /// Get all transfers for a user
  Stream<QuerySnapshot<Map<String, dynamic>>> getTransfers({
    bool isSender = true,
  }) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not logged in');
    }

    final field = isSender ? 'senderId' : 'receiverId';

    return _firestore
        .collection('file_transfers')
        .where(field, isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get a specific transfer
  Stream<DocumentSnapshot<Map<String, dynamic>>> getTransfer(
    String transferId,
  ) {
    return _firestore.collection('file_transfers').doc(transferId).snapshots();
  }
}
