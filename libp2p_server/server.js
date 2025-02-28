const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const { createLibp2p } = require('libp2p');
const { tcp } = require('@libp2p/tcp');
const { webSockets } = require('@libp2p/websockets');
const { noise } = require('@chainsafe/libp2p-noise');
const { yamux } = require('@chainsafe/libp2p-yamux');
const { mplex } = require('@libp2p/mplex');
const { bootstrap } = require('@libp2p/bootstrap');
const { mdns } = require('@libp2p/mdns');
const { kadDHT } = require('@libp2p/kad-dht');
const { gossipsub } = require('@chainsafe/libp2p-gossipsub');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

// Load environment variables
dotenv.config();

// Create Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '50mb' }));
app.use(morgan('dev'));

// Store active nodes
const nodes = new Map();
const transfers = new Map();

// Create a libp2p node
async function createNode() {
  const node = await createLibp2p({
    addresses: {
      listen: [
        '/ip4/0.0.0.0/tcp/0',
        '/ip4/0.0.0.0/tcp/0/ws',
      ]
    },
    transports: [
      tcp(),
      webSockets(),
    ],
    connectionEncryption: [
      noise()
    ],
    streamMuxers: [
      yamux(),
      mplex(),
    ],
    peerDiscovery: [
      bootstrap({
        list: [
          // Add bootstrap nodes here if needed
          '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
          '/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa',
        ]
      }),
      mdns()
    ],
    dht: kadDHT(),
    pubsub: gossipsub({ allowPublishToZeroPeers: true })
  });

  // Set up event handlers
  node.addEventListener('peer:discovery', (evt) => {
    console.log(`Discovered peer: ${evt.detail.id.toString()}`);
  });

  node.addEventListener('peer:connect', (evt) => {
    console.log(`Connected to peer: ${evt.detail.id.toString()}`);
  });

  await node.start();
  console.log(`libp2p node started with ID: ${node.peerId.toString()}`);
  
  return node;
}

// API Routes
app.get('/', (req, res) => {
  res.json({ status: 'BurrowSpace libp2p Server Running' });
});

// Initialize a new node
app.post('/api/node/init', async (req, res) => {
  try {
    const { userId } = req.body;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }
    
    // Check if node already exists for this user
    if (nodes.has(userId)) {
      const existingNode = nodes.get(userId);
      
      // Return node info
      return res.json({
        peerId: existingNode.peerId.toString(),
        addresses: existingNode.getMultiaddrs().map(addr => addr.toString()),
        status: 'existing'
      });
    }
    
    // Create a new node
    const node = await createNode();
    nodes.set(userId, node);
    
    res.json({
      peerId: node.peerId.toString(),
      addresses: node.getMultiaddrs().map(addr => addr.toString()),
      status: 'created'
    });
  } catch (error) {
    console.error('Error initializing node:', error);
    res.status(500).json({ error: error.message });
  }
});

// Connect to a peer
app.post('/api/peer/connect', async (req, res) => {
  try {
    const { userId, peerId, multiaddr } = req.body;
    
    if (!userId || !peerId || !multiaddr) {
      return res.status(400).json({ 
        error: 'User ID, peer ID, and multiaddr are required' 
      });
    }
    
    // Get the node for this user
    const node = nodes.get(userId);
    if (!node) {
      return res.status(404).json({ error: 'Node not found for this user' });
    }
    
    // Connect to the peer
    await node.dial(multiaddr);
    
    res.json({ 
      success: true, 
      message: `Connected to peer ${peerId}` 
    });
  } catch (error) {
    console.error('Error connecting to peer:', error);
    res.status(500).json({ error: error.message });
  }
});

// Send data to a peer
app.post('/api/peer/send', async (req, res) => {
  try {
    const { userId, peerId, topic, data } = req.body;
    
    if (!userId || !peerId || !topic || !data) {
      return res.status(400).json({ 
        error: 'User ID, peer ID, topic, and data are required' 
      });
    }
    
    // Get the node for this user
    const node = nodes.get(userId);
    if (!node) {
      return res.status(404).json({ error: 'Node not found for this user' });
    }
    
    // Subscribe to the topic if not already
    if (!node.pubsub.getTopics().includes(topic)) {
      await node.pubsub.subscribe(topic);
    }
    
    // Publish the data
    await node.pubsub.publish(topic, Buffer.from(JSON.stringify(data)));
    
    res.json({ 
      success: true, 
      message: `Data sent to topic ${topic}` 
    });
  } catch (error) {
    console.error('Error sending data:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get node status
app.get('/api/node/status/:userId', (req, res) => {
  try {
    const { userId } = req.params;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }
    
    // Check if node exists for this user
    if (!nodes.has(userId)) {
      return res.status(404).json({ error: 'Node not found for this user' });
    }
    
    const node = nodes.get(userId);
    
    res.json({
      peerId: node.peerId.toString(),
      addresses: node.getMultiaddrs().map(addr => addr.toString()),
      connected: node.isStarted(),
      peers: Array.from(node.getPeers()).map(peer => peer.toString())
    });
  } catch (error) {
    console.error('Error getting node status:', error);
    res.status(500).json({ error: error.message });
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
}); 