import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/ipfs_service.dart';
import 'services/libp2p_service.dart';
import 'services/file_transfer_service.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ipfsApiUrlController = TextEditingController();
  final _ipfsGatewayUrlController = TextEditingController();
  final _publicGatewayUrlController = TextEditingController();
  final _libp2pServerUrlController = TextEditingController();

  bool _isCheckingIpfs = false;
  bool _isCheckingLibp2p = false;
  bool _isIpfsConnected = false;
  bool _isLibp2pConnected = false;
  bool _isWakingServer = false;
  String _ipfsStatus = 'Not connected';
  String _libp2pStatus = 'Not connected';

  final _ipfsService = IPFSService();
  final _libp2pService = LibP2PService();
  final _transferService = FileTransferService();

  bool _usePublicGateway = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkConnections();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipfsApiUrlController.text =
          prefs.getString('ipfs_api_url') ?? 'http://127.0.0.1:5001/api/v0';
      _ipfsGatewayUrlController.text =
          prefs.getString('ipfs_gateway_url') ?? 'http://127.0.0.1:8080/ipfs';
      _publicGatewayUrlController.text =
          prefs.getString('ipfs_public_gateway_url') ?? 'https://ipfs.io/ipfs';
      _libp2pServerUrlController.text =
          prefs.getString('libp2p_server_url') ??
          'https://burrowspaceapp-libp2p.onrender.com';
      _usePublicGateway = prefs.getBool('use_public_gateway') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ipfs_api_url', _ipfsApiUrlController.text);
    await prefs.setString('ipfs_gateway_url', _ipfsGatewayUrlController.text);
    await prefs.setString(
      'ipfs_public_gateway_url',
      _publicGatewayUrlController.text,
    );
    await prefs.setString('libp2p_server_url', _libp2pServerUrlController.text);
    await prefs.setBool('use_public_gateway', _usePublicGateway);

    // Update the services configuration
    await _ipfsService.configure(
      ipfsApiUrl: _ipfsApiUrlController.text,
      ipfsGatewayUrl: _ipfsGatewayUrlController.text,
      publicGatewayUrl: _publicGatewayUrlController.text,
    );

    await _libp2pService.configure(serverUrl: _libp2pServerUrlController.text);

    // Re-initialize the transfer service
    await _transferService.initialize();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _checkConnections() async {
    await _checkIpfsConnection();
    await _checkLibp2pConnection();
  }

  Future<void> _checkIpfsConnection() async {
    setState(() {
      _isCheckingIpfs = true;
      _ipfsStatus = 'Checking connection...';
    });

    try {
      final isConnected = await _ipfsService.checkNodeStatus();

      setState(() {
        _isIpfsConnected = isConnected;
        _ipfsStatus =
            isConnected
                ? 'Connected to IPFS node'
                : 'Failed to connect to IPFS node';
      });
    } catch (e) {
      setState(() {
        _isIpfsConnected = false;
        _ipfsStatus = 'Error: $e';
      });
    } finally {
      setState(() {
        _isCheckingIpfs = false;
      });
    }
  }

  Future<void> _checkLibp2pConnection() async {
    setState(() {
      _isCheckingLibp2p = true;
      _libp2pStatus = 'Checking connection...';
    });

    try {
      final isConnected = await _libp2pService.checkServerStatus();

      if (!isConnected &&
          _libp2pServerUrlController.text.contains('render.com')) {
        // If using Render and not connected, it might be sleeping
        setState(() {
          _isLibp2pConnected = false;
          _isWakingServer = true;
          _libp2pStatus =
              'Server might be sleeping. Attempting to wake it up...';
        });

        // Try to wake up the server
        try {
          await http.get(Uri.parse(_libp2pServerUrlController.text));
          // Wait for server to wake up
          await Future.delayed(const Duration(seconds: 5));
          // Check again
          final retryConnected = await _libp2pService.checkServerStatus();
          setState(() {
            _isLibp2pConnected = retryConnected;
            _isWakingServer = !retryConnected;
            _libp2pStatus =
                retryConnected
                    ? 'Connected to libp2p server'
                    : 'Server is still waking up. This may take up to 30 seconds on the free tier.';
          });

          // If still not connected, schedule another check in 10 seconds
          if (!retryConnected) {
            _scheduleRetryCheck();
          }
        } catch (e) {
          setState(() {
            _isLibp2pConnected = false;
            _isWakingServer = false;
            _libp2pStatus = 'Failed to wake up server: $e';
          });
        }
      } else {
        setState(() {
          _isLibp2pConnected = isConnected;
          _isWakingServer = false;
          _libp2pStatus =
              isConnected
                  ? 'Connected to libp2p server'
                  : 'Failed to connect to libp2p server';
        });
      }
    } catch (e) {
      setState(() {
        _isLibp2pConnected = false;
        _isWakingServer = false;
        _libp2pStatus = 'Error: $e';
      });
    } finally {
      setState(() {
        _isCheckingLibp2p = false;
      });
    }
  }

  void _scheduleRetryCheck() {
    if (!mounted) return;

    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted || !_isWakingServer) return;

      setState(() {
        _libp2pStatus = 'Retrying connection to server...';
      });

      _libp2pService.checkServerStatus().then((isConnected) {
        if (!mounted) return;

        setState(() {
          _isLibp2pConnected = isConnected;
          _isWakingServer = !isConnected;
          _libp2pStatus =
              isConnected
                  ? 'Connected to libp2p server'
                  : 'Server is still waking up. This may take longer than expected.';
        });

        // If still not connected, schedule one more check
        if (!isConnected) {
          Future.delayed(const Duration(seconds: 15), () {
            if (!mounted || !_isWakingServer) return;
            _checkLibp2pConnection();
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IPFS Settings Card
            Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'IPFS Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _isIpfsConnected
                                    ? Colors.green.withAlpha(20)
                                    : Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isIpfsConnected
                                    ? Icons.check_circle
                                    : Icons.error_outline,
                                size: 16,
                                color:
                                    _isIpfsConnected
                                        ? Colors.green
                                        : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isIpfsConnected ? 'Connected' : 'Disconnected',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      _isIpfsConnected
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ipfsStatus,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ipfsApiUrlController,
                      decoration: const InputDecoration(
                        labelText: 'IPFS API URL',
                        hintText: 'e.g. http://127.0.0.1:5001/api/v0',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _ipfsGatewayUrlController,
                      decoration: const InputDecoration(
                        labelText: 'IPFS Gateway URL',
                        hintText: 'e.g. http://127.0.0.1:8080/ipfs',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _publicGatewayUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Public Gateway URL',
                        hintText: 'e.g. https://ipfs.io/ipfs',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Use Public Gateway'),
                      subtitle: const Text(
                        'For sharing content with users without IPFS',
                      ),
                      value: _usePublicGateway,
                      onChanged: (value) {
                        setState(() {
                          _usePublicGateway = value;
                        });
                      },
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _isCheckingIpfs ? null : _checkIpfsConnection,
                          icon:
                              _isCheckingIpfs
                                  ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.refresh),
                          label: const Text('Test Connection'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // libp2p Settings Card
            Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'libp2p Configuration',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _isWakingServer
                                    ? Colors.orange.withAlpha(20)
                                    : _isLibp2pConnected
                                    ? Colors.green.withAlpha(20)
                                    : Colors.red.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isWakingServer
                                    ? Icons.hourglass_empty
                                    : _isLibp2pConnected
                                    ? Icons.check_circle
                                    : Icons.error_outline,
                                size: 16,
                                color:
                                    _isWakingServer
                                        ? Colors.orange
                                        : _isLibp2pConnected
                                        ? Colors.green
                                        : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isWakingServer
                                    ? 'Waking up'
                                    : _isLibp2pConnected
                                    ? 'Connected'
                                    : 'Disconnected',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      _isWakingServer
                                          ? Colors.orange
                                          : _isLibp2pConnected
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _libp2pStatus,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _libp2pServerUrlController,
                      decoration: const InputDecoration(
                        labelText: 'libp2p Server URL',
                        hintText:
                            'e.g. https://burrowspaceapp-libp2p.onrender.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _libp2pServerUrlController.text =
                                  'https://burrowspaceapp-libp2p.onrender.com';
                            });
                          },
                          icon: const Icon(Icons.restore),
                          label: const Text('Reset to Default'),
                        ),
                        _isWakingServer
                            ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.orange,
                                ),
                              ),
                              label: const Text('Waking Server...'),
                            )
                            : OutlinedButton.icon(
                              onPressed:
                                  _isCheckingLibp2p
                                      ? null
                                      : _checkLibp2pConnection,
                              icon:
                                  _isCheckingLibp2p
                                      ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.refresh),
                              label: const Text('Test Connection'),
                            ),
                      ],
                    ),
                    if (_isWakingServer) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        backgroundColor: Colors.orange.withAlpha(30),
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The Render.com free tier server is waking up. This may take up to 30 seconds.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Save buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Save All Settings'),
                  ),
                ],
              ),
            ),

            // Instructions Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Setup Instructions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // IPFS Setup instructions
                    ExpansionTile(
                      title: const Text('IPFS Setup'),
                      initiallyExpanded: true,
                      childrenPadding: const EdgeInsets.all(16.0),
                      children: [
                        _buildInstructionStep(
                          1,
                          'Download and install IPFS Desktop from https://ipfs.tech',
                          Icons.download,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          2,
                          'Launch IPFS Desktop and wait for the node to start',
                          Icons.play_arrow,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          3,
                          'By default, the API is available at http://127.0.0.1:5001/api/v0',
                          Icons.api,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          4,
                          'The local gateway is available at http://127.0.0.1:8080/ipfs',
                          Icons.link,
                        ),
                      ],
                    ),

                    // libp2p Setup instructions
                    ExpansionTile(
                      title: const Text('libp2p Server Setup'),
                      initiallyExpanded: true,
                      childrenPadding: const EdgeInsets.all(16.0),
                      children: [
                        _buildInstructionStep(
                          1,
                          'You can use our hosted server at https://burrowspaceapp-libp2p.onrender.com',
                          Icons.cloud,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withAlpha(50),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'About the Render.com Server',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '• The server is hosted on Render.com\'s free tier',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '• It may go to sleep after 15 minutes of inactivity',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '• The app will attempt to wake it automatically when needed',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '• Wake-up can take 30+ seconds on the free tier',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInstructionStep(
                          2,
                          'Or run your own server by downloading from github.com/burrowspace/server',
                          Icons.download,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          3,
                          'Install Node.js and npm if you haven\'t already',
                          Icons.system_update,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          4,
                          'Run "npm install" in the server directory',
                          Icons.terminal,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          5,
                          'Start the server with "npm start"',
                          Icons.play_arrow,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          6,
                          'The local server will be available at http://127.0.0.1:3000',
                          Icons.public,
                        ),
                        const SizedBox(height: 8),
                        _buildInstructionStep(
                          7,
                          'Note: The Render.com free tier may sleep after inactivity. The app will attempt to wake it automatically.',
                          Icons.info_outline,
                        ),
                      ],
                    ),

                    // Global Access
                    ExpansionTile(
                      title: const Text('Enabling Global Access'),
                      initiallyExpanded: false,
                      childrenPadding: const EdgeInsets.all(16.0),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.indigo.withAlpha(50),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.public,
                                    color: Colors.indigo.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Global Access Setup',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '1. For the libp2p server, you can use our hosted server:',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(8),
                                color: Colors.black87,
                                child: const Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'https://burrowspaceapp-libp2p.onrender.com',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '2. Or use a service like ngrok for your local server:',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.all(8),
                                color: Colors.black87,
                                child: const Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'ngrok http 3000',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '3. Use a public IPFS gateway if you don\'t have your own:',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                '• https://ipfs.io/ipfs/\n• https://dweb.link/ipfs/\n• https://cloudflare-ipfs.com/ipfs/',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '4. Enable "Use Public Gateway" option above',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Note: The Render.com free tier may sleep after inactivity periods. The app will attempt to wake it automatically when needed.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(int step, String text, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ipfsApiUrlController.dispose();
    _ipfsGatewayUrlController.dispose();
    _publicGatewayUrlController.dispose();
    _libp2pServerUrlController.dispose();
    super.dispose();
  }
}
