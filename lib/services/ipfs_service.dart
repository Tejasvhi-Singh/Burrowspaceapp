import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

/// A service that interfaces with IPFS for decentralized file storage.
class IPFSService {
  static final IPFSService _instance = IPFSService._internal();
  factory IPFSService() => _instance;
  IPFSService._internal();

  // Configuration
  String _ipfsApiUrl = 'http://127.0.0.1:5001/api/v0';
  String _ipfsGatewayUrl = 'http://127.0.0.1:8080/ipfs';
  String? _publicGatewayUrl = 'https://ipfs.io/ipfs';
  bool _isInitialized = false;

  // Getters
  bool get isInitialized => _isInitialized;
  String get ipfsApiUrl => _ipfsApiUrl;
  String get ipfsGatewayUrl => _ipfsGatewayUrl;
  String? get publicGatewayUrl => _publicGatewayUrl;

  /// Initialize the IPFS service
  Future<bool> initialize() async {
    try {
      // Load saved configuration
      await _loadConfig();

      // Check if IPFS node is running
      final status = await checkNodeStatus();
      _isInitialized = status;
      return status;
    } catch (e) {
      debugPrint('Error initializing IPFS service: $e');
      return false;
    }
  }

  /// Configure the IPFS service
  Future<void> configure({
    required String ipfsApiUrl,
    required String ipfsGatewayUrl,
    String? publicGatewayUrl,
  }) async {
    _ipfsApiUrl = ipfsApiUrl;
    _ipfsGatewayUrl = ipfsGatewayUrl;
    _publicGatewayUrl = publicGatewayUrl;

    // Save configuration
    await _saveConfig();
  }

  /// Load saved configuration
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ipfsApiUrl = prefs.getString('ipfs_api_url') ?? _ipfsApiUrl;
      _ipfsGatewayUrl = prefs.getString('ipfs_gateway_url') ?? _ipfsGatewayUrl;
      _publicGatewayUrl =
          prefs.getString('ipfs_public_gateway_url') ?? _publicGatewayUrl;
    } catch (e) {
      debugPrint('Error loading IPFS config: $e');
    }
  }

  /// Save configuration
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ipfs_api_url', _ipfsApiUrl);
      await prefs.setString('ipfs_gateway_url', _ipfsGatewayUrl);
      if (_publicGatewayUrl != null) {
        await prefs.setString('ipfs_public_gateway_url', _publicGatewayUrl!);
      }
    } catch (e) {
      debugPrint('Error saving IPFS config: $e');
    }
  }

  /// Check if IPFS node is running
  Future<bool> checkNodeStatus() async {
    try {
      final response = await http
          .post(Uri.parse('$_ipfsApiUrl/id'))
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error checking IPFS node status: $e');
      return false;
    }
  }

  /// Add a file to IPFS
  /// Returns the Content Identifier (CID) of the added file
  Future<String?> addFile(File file, {Function(double)? onProgress}) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final fileBytes = await file.readAsBytes();
      final fileName = path.basename(file.path);

      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_ipfsApiUrl/add'),
      );

      // Add the file to the request
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      );

      request.files.add(multipartFile);

      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Hash'] as String;
      }
      return null;
    } catch (e) {
      debugPrint('Error adding file to IPFS: $e');
      return null;
    }
  }

  /// Get a file from IPFS by its CID
  Future<File?> getFile(
    String cid, {
    String? fileName,
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Create a temp file to store the downloaded content
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(tempDir.path, fileName ?? cid);
      final file = File(filePath);

      // Download the file
      final response = await http.get(Uri.parse('$_ipfsGatewayUrl/$cid'));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting file from IPFS: $e');
      return null;
    }
  }

  /// Pin a file to ensure it stays in the network
  Future<bool> pinFile(String cid) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final response = await http.post(
        Uri.parse('$_ipfsApiUrl/pin/add?arg=$cid'),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error pinning file: $e');
      return false;
    }
  }

  /// Unpin a file
  Future<bool> unpinFile(String cid) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final response = await http.post(
        Uri.parse('$_ipfsApiUrl/pin/rm?arg=$cid'),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error unpinning file: $e');
      return false;
    }
  }

  /// Get a shareable URL for a file
  String getShareableUrl(String cid, {bool usePublicGateway = true}) {
    final gatewayUrl =
        usePublicGateway && _publicGatewayUrl != null
            ? _publicGatewayUrl!
            : _ipfsGatewayUrl;

    return '$gatewayUrl/$cid';
  }
}
