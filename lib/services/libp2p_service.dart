import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A service that handles peer-to-peer connections using libp2p.
/// This implementation uses a lightweight server-side component to handle the
/// libp2p functionality, which the Flutter app communicates with via HTTP.
class LibP2PService {
  static final LibP2PService _instance = LibP2PService._internal();
  factory LibP2PService() => _instance;
  LibP2PService._internal();

  // Server configuration
  String _serverUrl = 'http://127.0.0.1:3000';
  bool _isConnected = false;
  String? _peerId;
  List<String>? _peerAddresses;

  // Firestore reference for user peer data
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Getters
  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;
  String? get peerId => _peerId;
  List<String>? get peerAddresses => _peerAddresses;

  /// Initialize the service
  Future<bool> initialize() async {
    try {
      // Load saved configuration
      await _loadConfig();

      // Check if the server is up
      final status = await checkServerStatus();
      return status;
    } catch (e) {
      debugPrint('Error initializing LibP2P service: $e');
      return false;
    }
  }

  /// Configure the server connection
  Future<void> configure({required String serverUrl}) async {
    _serverUrl = serverUrl;

    // Save configuration
    await _saveConfig();
  }

  /// Load saved configuration
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverUrl = prefs.getString('libp2p_server_url') ?? _serverUrl;
    } catch (e) {
      debugPrint('Error loading LibP2P config: $e');
    }
  }

  /// Save configuration
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('libp2p_server_url', _serverUrl);
    } catch (e) {
      debugPrint('Error saving LibP2P config: $e');
    }
  }

  /// Check server status
  Future<bool> checkServerStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$_serverUrl/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'online';
      }
      return false;
    } catch (e) {
      debugPrint('Error checking LibP2P server status: $e');
      return false;
    }
  }

  /// Generate a device ID that will be consistent for this device
  Future<String> _generateDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');

      if (deviceId == null) {
        // Generate a new device ID if none exists
        deviceId = const Uuid().v4();
        await prefs.setString('device_id', deviceId);
      }

      return deviceId;
    } catch (e) {
      // Fallback to a new UUID if there's an error
      debugPrint('Error generating device ID: $e');
      return const Uuid().v4();
    }
  }

  /// Initialize a libp2p node and return peer information
  Future<Map<String, dynamic>?> initNode() async {
    if (_peerId != null && _isConnected) {
      // Already initialized
      return {'peerId': _peerId, 'addresses': _peerAddresses};
    }

    try {
      final deviceId = await _generateDeviceId();

      final response = await http
          .post(
            Uri.parse('$_serverUrl/init'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'deviceId': deviceId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _peerId = data['peerId'];
        _peerAddresses = List<String>.from(data['addresses']);
        _isConnected = true;

        return data;
      }
      return null;
    } catch (e) {
      debugPrint('Error initializing libp2p node: $e');
      return null;
    }
  }

  /// Connect to a peer
  Future<bool> connectToPeer({
    required String peerId,
    required String? multiaddr,
  }) async {
    if (!_isConnected || _peerId == null) {
      await initNode();
      if (!_isConnected) return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/connect'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'targetPeerId': peerId, 'multiaddr': multiaddr}),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error connecting to peer: $e');
      return false;
    }
  }

  /// Register the current device in Firebase for discovery
  Future<bool> registerDevice() async {
    // Ensure user is logged in
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('Cannot register device: User not logged in');
      return false;
    }

    // Initialize libp2p node
    final nodeInfo = await initNode();
    if (nodeInfo == null) {
      debugPrint('Cannot register device: Failed to initialize libp2p node');
      return false;
    }

    try {
      // Get device information
      final deviceId = await _generateDeviceId();
      String deviceType = 'unknown';

      if (kIsWeb) {
        deviceType = 'web';
      } else {
        if (defaultTargetPlatform == TargetPlatform.android) {
          deviceType = 'android';
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          deviceType = 'ios';
        } else if (defaultTargetPlatform == TargetPlatform.windows) {
          deviceType = 'windows';
        } else if (defaultTargetPlatform == TargetPlatform.macOS) {
          deviceType = 'macos';
        } else if (defaultTargetPlatform == TargetPlatform.linux) {
          deviceType = 'linux';
        }
      }

      // Save device information to Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('devices')
          .doc(deviceId)
          .set({
            'deviceId': deviceId,
            'peerId': _peerId,
            'addresses': _peerAddresses,
            'platform': deviceType,
            'lastActive': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('Error registering device: $e');
      return false;
    }
  }

  /// Lookup a user's devices for P2P connection
  Future<List<Map<String, dynamic>>> lookupUserDevices(String userId) async {
    try {
      final snapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('devices')
              .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error looking up user devices: $e');
      return [];
    }
  }

  /// Send data to a peer
  Future<bool> sendData({
    required String peerId,
    required Map<String, dynamic> data,
  }) async {
    if (!_isConnected || _peerId == null) {
      await initNode();
      if (!_isConnected) return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_serverUrl/send'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'targetPeerId': peerId, 'data': data}),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error sending data to peer: $e');
      return false;
    }
  }
}
