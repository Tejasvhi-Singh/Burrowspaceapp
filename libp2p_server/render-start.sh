#!/bin/bash

# Log information about the environment
echo "Node version: $(node -v)"
echo "NPM version: $(npm -v)"
echo "Working directory: $(pwd)"

# Try to use the temporary server first to ensure something works
if [ -f server.js.tmp ]; then
  echo "Using temporary server for startup..."
  cp server.js.tmp server.js
fi

# Start the server
node server.js 