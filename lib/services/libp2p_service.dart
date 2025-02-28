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
  String _serverUrl = 'https://burrowspaceapp-libp2p.onrender.com';
  bool _isConnected = false;
  String? _peerId;
  List<String>? _peerAddresses;
  bool _isWakingServer = false;

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

      // If server is not responding, try to wake it up
      if (!status && !_isWakingServer) {
        // Only attempt wake-up once
        _isWakingServer = true;
        debugPrint('Server might be sleeping. Attempting to wake it up...');
        // Ping the server to wake it up - Render spins down free tier after inactivity
        await http.get(Uri.parse(_serverUrl));
        // Wait a bit for server to start
        await Future.delayed(const Duration(seconds: 5));
        // Retry status check
        final retryStatus = await checkServerStatus();
        _isWakingServer = false;
        return retryStatus;
      }

      return status;
    } catch (e) {
      debugPrint('Error initializing LibP2P service: $e');
      _isWakingServer = false;
      return false;
    }
  }

  /// Configure the server connection
  Future<void> configure({required String serverUrl}) async {
    _serverUrl = serverUrl;

    // Save configuration
    await _saveConfig();

    // Reset connection state
    _isConnected = false;
    _peerId = null;
    _peerAddresses = null;

    // Check connection to new server
    await checkServerStatus();
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
          .get(Uri.parse('$_serverUrl/'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _isConnected = data['status'] == 'BurrowSpace libp2p Server Running';
        return _isConnected;
      }
      _isConnected = false;
      return false;
    } catch (e) {
      debugPrint('Error checking LibP2P server status: $e');
      _isConnected = false;
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
      // Make sure server is awake
      if (!_isConnected) {
        final isAwake = await initialize();
        if (!isAwake) {
          debugPrint('Cannot initialize node: Server not connected');
          return null;
        }
      }

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('Cannot initialize node: User not logged in');
        return null;
      }

      final userId = currentUser.uid;
      final deviceId = await _generateDeviceId();

      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/node/init'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'userId': userId, 'deviceId': deviceId}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _peerId = data['peerId'];
        _peerAddresses = List<String>.from(data['addresses']);
        _isConnected = true;

        debugPrint('Successfully initialized libp2p node with ID: $_peerId');
        return data;
      }

      debugPrint(
        'Error initializing node: ${response.statusCode} - ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Error initializing libp2p node: $e');
      return null;
    }
  }

  /// Connect to a peer
  Future<bool> connectToPeer({
    required String peerId,
    String? multiaddr,
  }) async {
    if (!_isConnected || _peerId == null) {
      final nodeInit = await initNode();
      if (nodeInit == null) return false;
    }

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final userId = currentUser.uid;

      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/peer/connect'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userId': userId,
              'peerId': peerId,
              'multiaddr': multiaddr,
            }),
          )
          .timeout(const Duration(seconds: 15));

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

      debugPrint('Successfully registered device with ID: $deviceId');
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
              .orderBy('lastActive', descending: true)
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
      final nodeInit = await initNode();
      if (nodeInit == null) return false;
    }

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final userId = currentUser.uid;
      const topic = 'p2p-transfer'; // Default topic for file transfers

      final response = await http
          .post(
            Uri.parse('$_serverUrl/api/peer/send'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userId': userId,
              'peerId': peerId,
              'topic': topic,
              'data': data,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          'Error sending data: ${response.statusCode} - ${response.body}',
        );
      }

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error sending data to peer: $e');
      return false;
    }
  }
}
