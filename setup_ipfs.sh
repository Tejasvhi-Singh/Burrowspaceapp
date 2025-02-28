#!/bin/bash

# BurrowSpace IPFS Setup Script
# This script helps set up IPFS for use with BurrowSpace

echo "BurrowSpace IPFS Setup"
echo "======================"
echo

# Check if IPFS is already installed
if command -v ipfs &> /dev/null; then
    echo "IPFS is already installed."
    IPFS_VERSION=$(ipfs --version | awk '{print $3}')
    echo "Current version: $IPFS_VERSION"
else
    echo "IPFS is not installed. Installing now..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo "Detected Linux OS"
        
        # Download latest IPFS
        wget https://dist.ipfs.tech/kubo/latest/kubo_latest_linux-amd64.tar.gz
        tar -xvzf kubo_latest_linux-amd64.tar.gz
        
        # Install IPFS
        cd kubo
        sudo bash install.sh
        cd ..
        
        # Clean up
        rm -rf kubo_latest_linux-amd64.tar.gz kubo
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Detected macOS"
        
        # Check if Homebrew is installed
        if command -v brew &> /dev/null; then
            echo "Installing IPFS via Homebrew..."
            brew install ipfs
        else
            echo "Homebrew not found. Please install Homebrew first or manually install IPFS."
            echo "Visit https://docs.ipfs.tech/install/command-line/ for instructions."
            exit 1
        fi
        
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        # Windows
        echo "Detected Windows OS"
        echo "Please download and install IPFS Desktop from: https://docs.ipfs.tech/install/ipfs-desktop/"
        echo "After installation, please run this script again."
        exit 1
    else
        echo "Unsupported operating system: $OSTYPE"
        echo "Please manually install IPFS from: https://docs.ipfs.tech/install/command-line/"
        exit 1
    fi
    
    echo "IPFS installed successfully!"
fi

# Initialize IPFS if not already initialized
if [ ! -d "$HOME/.ipfs" ]; then
    echo "Initializing IPFS..."
    ipfs init
else
    echo "IPFS is already initialized."
fi

# Configure IPFS for BurrowSpace
echo "Configuring IPFS for BurrowSpace..."

# Enable CORS
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'
ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["PUT", "POST", "GET"]'

# Configure Gateway
ipfs config --json Gateway.HTTPHeaders.Access-Control-Allow-Origin '["*"]'
ipfs config --json Gateway.HTTPHeaders.Access-Control-Allow-Methods '["PUT", "POST", "GET"]'

# Start IPFS daemon
echo "Starting IPFS daemon..."
echo "To start the IPFS daemon in the background, run: ipfs daemon &"
echo "To stop the IPFS daemon, find its process ID with 'ps aux | grep ipfs' and use 'kill <PID>'"
echo
echo "IPFS setup complete! Your node is ready for use with BurrowSpace."
echo "API address: http://localhost:5001/api/v0"
echo "Gateway address: http://localhost:8080/ipfs/"
echo
echo "Please configure these addresses in the BurrowSpace app settings." 