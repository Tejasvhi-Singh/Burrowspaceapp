#!/bin/bash

# BurrowSpace libp2p Server - Render Deployment Helper
# This script helps prepare the server for deployment to Render.com

echo "Preparing libp2p server for Render deployment..."

# Ensure we're using the right Node version
NODE_VERSION=$(node -v)
echo "Current Node version: $NODE_VERSION"

if [[ $NODE_VERSION != *"v18"* ]]; then
  echo "Warning: We recommend using Node.js v18 for Render deployment"
  echo "You can install it with: nvm install 18"
fi

# Install dependencies
echo "Installing dependencies..."
npm install

# Check for render.yaml
if [ -f "render.yaml" ]; then
  echo "render.yaml found, your Blueprint configuration is ready"
else
  echo "Creating render.yaml for Blueprint deployment..."
  cat > render.yaml << EOL
services:
  - type: web
    name: burrowspace-libp2p-server
    env: node
    buildCommand: cd libp2p_server && npm install
    startCommand: cd libp2p_server && npm start
    envVars:
      - key: NODE_VERSION
        value: 18
      - key: PORT
        value: 3000
    healthCheckPath: /
EOL
  echo "render.yaml created"
fi

# Check for .env file
if [ -f ".env" ]; then
  echo ".env file found"
else
  echo "Creating sample .env file..."
  cat > .env << EOL
PORT=3000
NODE_ENV=production
LOG_LEVEL=info
EOL
  echo ".env file created"
fi

echo ""
echo "====== DEPLOYMENT INSTRUCTIONS ======"
echo "1. Push your code to GitHub"
echo "2. Create a new Web Service on Render.com"
echo "3. Connect your GitHub repository"
echo "4. Configure with these settings:"
echo "   - Build Command: cd libp2p_server && npm install"
echo "   - Start Command: cd libp2p_server && npm start"
echo "5. Add environment variables if needed"
echo "======================================"
echo ""
echo "Preparation complete! Your server is ready for Render deployment." 