# BurrowSpace App

A decentralized file sharing application built with Flutter, Firebase, IPFS, and libp2p.

## Architecture

BurrowSpace uses a hybrid decentralized architecture:

- **IPFS** for decentralized file storage
- **libp2p** for peer-to-peer connections
- **Firebase** for user authentication and discovery

### Key Components

1. **Flutter App**: The main mobile application
2. **IPFS Node**: For content-addressed file storage
3. **libp2p Server**: For peer-to-peer connections
4. **Firebase**: For authentication and user discovery

## Getting Started

### Prerequisites

- Flutter SDK 3.7.0 or higher
- Node.js 18.x or higher (for libp2p server)
- IPFS node (local or remote)
- Firebase project

### Setup

1. Clone the repository
2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```
3. Set up the libp2p server:
   ```bash
   cd libp2p_server
   npm install
   ```
4. Configure your IPFS node (local or remote)
5. Update the settings in the app with your IPFS and libp2p server URLs

## Running the App

1. Start the libp2p server:
   ```bash
   cd libp2p_server
   npm start
   ```
2. Run the Flutter app:
   ```bash
   flutter run
   ```

## Features

- Decentralized file storage with IPFS
- Direct peer-to-peer file transfers
- User discovery via Firebase
- End-to-end data integrity through content addressing
- Works across different networks with relay options

## Architecture Details

### File Storage

Files are stored using IPFS, which provides content-addressed storage. This means files are identified by their content rather than location, ensuring data integrity.

### Peer-to-Peer Connections

The app uses libp2p for direct peer-to-peer connections, allowing for efficient file transfers without relying on central servers.

### User Discovery

Firebase is used for user authentication and discovery, making it easy to find and connect with other users while maintaining the decentralized nature of file transfers.

## License

[MIT License](LICENSE)
