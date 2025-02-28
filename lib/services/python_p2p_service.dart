import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:socket_io_client/socket_io_client.dart' as io;

class PythonP2PService {
  static final PythonP2PService _instance = PythonP2PService._internal();
  factory PythonP2PService() => _instance;
  PythonP2PService._internal();

  // Server configuration
  String _serverIp = '127.0.0.1'; // Default to localhost
  int _serverPort = 5000;
  String? _peerId;
  bool _isConnected = false;
  io.Socket? _socket;

  // Callback handlers
  final Map<String, Function> _eventHandlers = {};

  // Global server URL (for NAT traversal)
  String? _serverPublicUrl;

  // Getters
  bool get isConnected => _isConnected;
  String get serverUrl => _serverPublicUrl ?? 'http://$_serverIp:$_serverPort';
  String? get peerId => _peerId;

  // Configure server connection
  void configure({required String serverIp, int serverPort = 5000}) {
    _serverIp = serverIp;
    _serverPort = serverPort;
    _setupSocketIfConnected();
  }

  // Register event handlers
  void on(String event, Function(dynamic) handler) {
    _eventHandlers[event] = handler;

    // If socket is already connected, register the handler
    if (_socket != null) {
      _socket!.on(event, (data) {
        handler(data);
      });
    }
  }

  // Check server status
  Future<bool> checkServerStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['public_url'] != null) {
          _serverPublicUrl = data['public_url'];
        }

        return data['status'] == 'online';
      }
      return false;
    } catch (e) {
      debugPrint('Error checking server status: $e');
      return false;
    }
  }

  // Connect to the P2P server
  Future<bool> connect(String userId) async {
    if (_isConnected) return true;

    try {
      // First try to connect via HTTP
      final response = await http
          .post(
            Uri.parse('$serverUrl/connect'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'user_id': userId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _peerId = data['peer_id'];
        _isConnected = true;

        if (data['public_url'] != null) {
          _serverPublicUrl = data['public_url'];
        }

        // Setup Socket.IO connection
        _setupSocket();

        // Start heartbeat
        _startHeartbeat();

        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error connecting to P2P server: $e');
      return false;
    }
  }

  // Setup Socket.IO connection
  void _setupSocket() {
    if (_socket != null) {
      _socket!.disconnect();
    }

    try {
      _socket = io.io(serverUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });

      _socket!.on('connect', (_) {
        debugPrint('Socket connected');

        // Register the socket with our peer ID
        if (_peerId != null) {
          _socket!.emit('register_socket', {'peer_id': _peerId});
        }

        // Trigger connected event if registered
        if (_eventHandlers.containsKey('connected')) {
          _eventHandlers['connected']!({});
        }
      });

      _socket!.on('disconnect', (_) {
        debugPrint('Socket disconnected');

        // Trigger disconnected event if registered
        if (_eventHandlers.containsKey('disconnected')) {
          _eventHandlers['disconnected']!({});
        }
      });

      _socket!.on('error', (error) {
        debugPrint('Socket error: $error');
      });

      // Register standard events
      _registerStandardEvents();

      // Register any user-defined event handlers
      _eventHandlers.forEach((event, handler) {
        _socket!.on(event, (data) {
          handler(data);
        });
      });
    } catch (e) {
      debugPrint('Error setting up socket: $e');
    }
  }

  // Re-setup socket if connected
  void _setupSocketIfConnected() {
    if (_isConnected && _peerId != null) {
      _setupSocket();
    }
  }

  // Register standard events
  void _registerStandardEvents() {
    if (_socket == null) return;

    // Transfer request event
    _socket!.on('transfer_request', (data) {
      debugPrint('Transfer request received: $data');
      if (_eventHandlers.containsKey('transfer_request')) {
        _eventHandlers['transfer_request']!(data);
      }
    });

    // Transfer approved event
    _socket!.on('transfer_approved', (data) {
      debugPrint('Transfer approved: $data');
      if (_eventHandlers.containsKey('transfer_approved')) {
        _eventHandlers['transfer_approved']!(data);
      }
    });

    // Transfer completed event
    _socket!.on('transfer_completed', (data) {
      debugPrint('Transfer completed: $data');
      if (_eventHandlers.containsKey('transfer_completed')) {
        _eventHandlers['transfer_completed']!(data);
      }
    });

    // Transfer cancelled event
    _socket!.on('transfer_cancelled', (data) {
      debugPrint('Transfer cancelled: $data');
      if (_eventHandlers.containsKey('transfer_cancelled')) {
        _eventHandlers['transfer_cancelled']!(data);
      }
    });

    // Peer signal event (for establishing P2P connection)
    _socket!.on('peer_signal', (data) {
      debugPrint('Peer signal received');
      if (_eventHandlers.containsKey('peer_signal')) {
        _eventHandlers['peer_signal']!(data);
      }
    });

    // Relay initiated event
    _socket!.on('relay_initiated', (data) {
      debugPrint('Relay initiated: $data');
      if (_eventHandlers.containsKey('relay_initiated')) {
        _eventHandlers['relay_initiated']!(data);
      }
    });

    // Relay chunk event
    _socket!.on('relay_chunk', (data) {
      // debugPrint('Relay chunk received'); // Too verbose for normal logging
      if (_eventHandlers.containsKey('relay_chunk')) {
        _eventHandlers['relay_chunk']!(data);
      }
    });
  }

  // Start heartbeat to keep connection alive
  void _startHeartbeat() {
    if (_peerId == null) return;

    Future.doWhile(() async {
      if (!_isConnected || _peerId == null) return false;

      try {
        await http
            .post(Uri.parse('$serverUrl/heartbeat/$_peerId'))
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('Heartbeat error: $e');
      }

      await Future.delayed(const Duration(seconds: 30));
      return _isConnected;
    });
  }

  // Disconnect from the P2P server
  Future<bool> disconnect() async {
    if (!_isConnected || _peerId == null) return true;

    try {
      // Disconnect socket
      if (_socket != null) {
        _socket!.disconnect();
        _socket = null;
      }

      final response = await http
          .post(Uri.parse('$serverUrl/disconnect/$_peerId'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _isConnected = false;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error disconnecting from P2P server: $e');
      return false;
    }
  }

  // Send peer signal to another peer (for establishing P2P connection)
  void sendPeerSignal({
    required String targetPeerId,
    required Map<String, dynamic> signal,
  }) {
    if (_socket == null || !_isConnected || _peerId == null) {
      debugPrint('Cannot send peer signal: not connected');
      return;
    }

    _socket!.emit('peer_signal', {
      'target_peer_id': targetPeerId,
      'sender_peer_id': _peerId,
      'signal': signal,
    });
  }

  // Send file chunk via relay
  void sendRelayChunk({
    required String sessionId,
    required String chunk,
    required int index,
    required int total,
  }) {
    if (_socket == null || !_isConnected) {
      debugPrint('Cannot send relay chunk: not connected');
      return;
    }

    _socket!.emit('relay_chunk', {
      'session_id': sessionId,
      'chunk': chunk,
      'index': index,
      'total': total,
    });
  }

  // Request a file transfer
  Future<Map<String, dynamic>?> requestFileTransfer({
    required String senderId,
    required String receiverId,
    required String fileName,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final response = await http
          .post(
            Uri.parse('$serverUrl/request-transfer'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'sender_id': senderId,
              'receiver_id': receiverId,
              'filename': fileName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error requesting file transfer: $e');
      return null;
    }
  }

  // Approve a file transfer request
  Future<Map<String, dynamic>?> approveTransfer(String requestId) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final response = await http
          .post(Uri.parse('$serverUrl/approve-transfer/$requestId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error approving transfer: $e');
      return null;
    }
  }

  // Upload a file (fallback when P2P fails)
  Future<Map<String, dynamic>?> uploadFile({
    required String transferId,
    required String filePath,
    Function(double)? onProgress,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final file = File(filePath);
      final fileName = path.basename(filePath);

      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/upload/$transferId'),
      );

      // Add the file to the request
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final multipartFile = http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: fileName,
      );

      request.files.add(multipartFile);

      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading file: $e');
      return null;
    }
  }

  // Download a file (fallback when P2P fails)
  Future<File?> downloadFile({
    required String transferId,
    required String savePath,
    Function(double)? onProgress,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final response = await http.get(
        Uri.parse('$serverUrl/download/$transferId'),
      );

      if (response.statusCode == 200) {
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading file: $e');
      return null;
    }
  }

  // Get transfer status
  Future<Map<String, dynamic>?> getTransferStatus(String transferId) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final response = await http
          .get(Uri.parse('$serverUrl/transfer-status/$transferId'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting transfer status: $e');
      return null;
    }
  }

  // Update transfer status
  Future<bool> updateTransferStatus({
    required String transferId,
    required String status,
    required double progress,
  }) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final response = await http
          .post(
            Uri.parse('$serverUrl/update-transfer-status/$transferId'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'status': status, 'progress': progress}),
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating transfer status: $e');
      return false;
    }
  }

  // Cancel a transfer
  Future<bool> cancelTransfer(String transferId) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      final response = await http
          .post(Uri.parse('$serverUrl/cancel-transfer/$transferId'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error canceling transfer: $e');
      return false;
    }
  }

  // Get online peers filtered by userId (optional)
  Future<Map<String, dynamic>?> getOnlinePeers({String? userId}) async {
    if (!_isConnected) {
      throw Exception('Not connected to P2P server');
    }

    try {
      String url = '$serverUrl/peers';
      if (userId != null) {
        url += '?user_id=$userId';
      }

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting online peers: $e');
      return null;
    }
  }
}
