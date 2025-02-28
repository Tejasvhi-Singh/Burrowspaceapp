# BurrowSpace Global P2P Server

A Python-based peer-to-peer file sharing server for the BurrowSpace Flutter application, with global access capabilities.

## Features

- Global P2P file sharing across networks with NAT traversal
- Signaling server for establishing direct peer connections
- Automatic relay fallback when direct P2P connections aren't possible
- Real-time communication with Socket.IO
- Support for large file transfers (up to 16GB)
- Transfer status monitoring and progress tracking
- RESTful API for peer connections and file transfers

## Prerequisites

- Python 3.8 or higher
- pip (Python package manager)

## Installation

1. Clone the repository or navigate to the `python_server` directory
2. Create a virtual environment (optional but recommended):
   ```
   python -m venv venv
   ```
3. Activate the virtual environment:
   - Windows:
     ```
     venv\Scripts\activate
     ```
   - macOS/Linux:
     ```
     source venv/bin/activate
     ```
4. Install dependencies:
   ```
   pip install -r requirements.txt
   ```

## Running the Server

### Local Network Mode

1. Make sure you're in the `python_server` directory
2. Run the server:
   ```
   python server.py
   ```
3. The server will start on port 5000 by default
4. Make note of your server's IP address (shown in the console)

### Global Access Mode (with ngrok)

To make your server accessible from anywhere (necessary when peers are on different networks):

1. Set the environment variable:
   - Windows: `set USE_NGROK=True`
   - macOS/Linux: `export USE_NGROK=True`
2. Run the server:
   ```
   python server.py
   ```
3. The server will generate a public URL using ngrok
4. The ngrok URL will be displayed in the console and available via the status endpoint

## API Endpoints

### Server Status
- `GET /status` - Check if the server is running, get STUN servers and public URL

### Peer Connection
- `POST /connect` - Connect a new peer to the server
- `POST /heartbeat/<peer_id>` - Send heartbeat to maintain connection
- `POST /disconnect/<peer_id>` - Disconnect a peer
- `GET /peers` - Get a list of connected peers

### File Transfers
- `POST /request-transfer` - Request a file transfer
- `POST /approve-transfer/<request_id>` - Approve a transfer request
- `POST /update-transfer-status/<transfer_id>` - Update transfer status for P2P transfers
- `POST /upload/<transfer_id>` - Upload a file (fallback when P2P fails)
- `GET /download/<transfer_id>` - Download a file (fallback when P2P fails)
- `GET /transfer-status/<transfer_id>` - Check transfer status
- `POST /cancel-transfer/<transfer_id>` - Cancel a transfer

## Socket.IO Events

### Client to Server
- `register_socket` - Register a socket connection with a peer ID
- `peer_signal` - Forward signaling data to another peer
- `relay_chunk` - Relay a file chunk when direct P2P isn't possible

### Server to Client
- `peer_signal` - Receive signaling data from another peer
- `relay_initiated` - Notifies a client that relay mode is being used
- `relay_chunk` - Receive a file chunk via relay
- `transfer_request` - Notification of a new transfer request
- `transfer_approved` - Notification that a transfer was approved
- `transfer_completed` - Notification that a transfer was completed
- `transfer_cancelled` - Notification that a transfer was cancelled
- `peer_disconnected` - Notification that a peer has disconnected

## P2P Communication Modes

The server supports three modes of file transfer:

1. **Direct P2P** - Peers establish a direct connection and transfer files without server involvement (preferred)
2. **Server Relay** - When direct connection isn't possible, files are relayed through the server in chunks
3. **Server Storage** - As a last resort, files can be uploaded to the server and downloaded by the recipient

## NAT Traversal

The server uses STUN servers to help peers establish direct connections even when behind NATs:

- Google STUN servers are used by default
- The server can be made globally accessible via ngrok

## Integration with Flutter App

The Flutter app communicates with this server through:
1. HTTP requests for API endpoints
2. Socket.IO for real-time events
3. P2P connections for direct file transfer

Make sure the server IP address/URL and port are correctly configured in your Flutter application settings.

## Security Considerations

This is a basic implementation with limited security features. For production use, consider implementing:

- Authentication and user verification
- HTTPS for all API endpoints
- End-to-end encryption for file transfers
- Rate limiting and DoS protection
- Data validation and sanitization

## Troubleshooting

If you have issues connecting:
1. Check that the server is running
2. Verify firewall settings are allowing connections on port 5000
3. For global access, make sure ngrok is working properly
4. Check the server logs for error messages
5. Ensure peers are using the correct server URL (local IP or ngrok URL)
6. If direct P2P fails, the system will automatically fall back to relay mode 