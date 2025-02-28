# BurrowSpace libp2p Server

This is the libp2p server component for the BurrowSpace app, providing peer-to-peer connectivity and decentralized file sharing capabilities.

## Features

- libp2p node creation and management
- Peer discovery and connection
- Publish/subscribe messaging
- REST API for Flutter app integration

## Prerequisites

- Node.js 18.x or higher
- npm or yarn

## Installation

1. Clone the repository
2. Navigate to the `libp2p_server` directory
3. Install dependencies:

```bash
npm install
```

## Configuration

Create a `.env` file in the root directory with the following variables:

```
PORT=3000
LOG_LEVEL=info
```

## Running the Server

### Development Mode

```bash
npm run dev
```

### Production Mode

```bash
npm start
```

## API Endpoints

### GET /
- Returns server status

### POST /api/node/init
- Initializes a new libp2p node for a user
- Request body: `{ "userId": "user-uuid" }`
- Returns: Node information including peer ID and multiaddresses

### POST /api/peer/connect
- Connects to a peer
- Request body: `{ "userId": "user-uuid", "peerId": "peer-id", "multiaddr": "multiaddress" }`
- Returns: Connection status

### POST /api/peer/send
- Sends data to a peer via a topic
- Request body: `{ "userId": "user-uuid", "peerId": "target-peer-id", "topic": "topic-name", "data": {} }`
- Returns: Send status

### GET /api/node/status/:userId
- Gets the status of a user's node
- Returns: Node status including peer ID, addresses, and connected peers

## Integration with Flutter App

This server is designed to work with the BurrowSpace Flutter app. The app communicates with this server via the REST API to establish P2P connections and transfer files.

## License

[MIT License](LICENSE) 