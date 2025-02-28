# BurrowSpace libp2p Server

This is the libp2p server component for the BurrowSpace app, which enables peer-to-peer connections and decentralized file sharing.

## Local Development

### Prerequisites
- Node.js (v18 or later)
- npm

### Setup

1. Install dependencies:
```
npm install
```

2. Create a `.env` file:
```
PORT=3000
```

3. Start the server:
```
npm start
```

For development with auto-reload:
```
npm run dev
```

## Deploying to Render.com

### Option 1: Manual Deployment

1. Sign up for a Render account: https://render.com/
2. Create a new Web Service
3. Connect to your GitHub repository
4. Use the following settings:
   - **Build Command**: `cd libp2p_server && npm install`
   - **Start Command**: `cd libp2p_server && npm start`
   - **Environment Variables**: Add `PORT`, set to `3000`

### Option 2: Using render.yaml (Blueprint)

This repository includes a `render.yaml` file that automatically configures your deployment.

1. Fork or clone this repository
2. In Render dashboard, go to "Blueprints"
3. Connect to your repository
4. Render will automatically detect the configuration and set up your service

### Fixing Common Deployment Issues

If you encounter errors related to libp2p exports on Render:

1. Make sure package.json has `"type": "commonjs"` specified
2. Ensure you're using a compatible version of libp2p (≤ 0.45.0)
3. Check that your Node.js version is set to v18 in Render

## API Endpoints

- `GET /` - Check server status
- `POST /api/node/init` - Initialize a new libp2p node
- `POST /api/peer/connect` - Connect to a peer
- `POST /api/peer/send` - Send data to a peer
- `GET /api/node/status/:userId` - Get node status

## Troubleshooting

- If you see `ERR_PACKAGE_PATH_NOT_EXPORTED` errors, check your libp2p version
- For connection issues, ensure your firewall allows the necessary ports
- For peer discovery problems, verify that your libp2p configuration is correct

## Features

- libp2p node creation and management
- Peer discovery and connection
- Publish/subscribe messaging
- REST API for Flutter app integration

## Prerequisites

- Node.js 18.x or higher
- npm or yarn

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

## Integration with Flutter App

This server is designed to work with the BurrowSpace Flutter app. The app communicates with this server via the REST API to establish P2P connections and transfer files.

## License

[MIT License](LICENSE) 