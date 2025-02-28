import os
import json
import uuid
import socket
import logging
import threading
import requests
import time
from datetime import datetime
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from werkzeug.utils import secure_filename
import socketio
import eventlet
from pyngrok import ngrok

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("server.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("BurrowSpaceP2P")

# Flask application setup
app = Flask(__name__)
CORS(app)

# Socket.IO for real-time communication
sio = socketio.Server(cors_allowed_origins='*')
app.wsgi_app = socketio.WSGIApp(sio, app.wsgi_app)

# Server configuration
UPLOAD_FOLDER = 'transfers'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024 * 1024  # 16 GB max upload

# In-memory data stores
connected_peers = {}  # Dictionary to store connected peers: {peer_id: {ip, port, user_id, status, socket_id}}
transfer_requests = {}  # Dictionary to store transfer requests: {request_id: {status, sender_id, receiver_id, filename}}
active_transfers = {}  # Dictionary to track active file transfers: {transfer_id: {progress, status, filename}}
relay_sessions = {}  # Dictionary to track relay sessions: {session_id: {sender_id, receiver_id, status}}

# Generate a server ID
SERVER_ID = str(uuid.uuid4())

# NAT traversal configuration
USE_NGROK = os.environ.get('USE_NGROK', 'False').lower() in ('true', '1', 't')
STUN_SERVERS = [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302'
]

# Global server URL (will be updated when using ngrok)
SERVER_URL = None

def get_ip():
    """Get the server's local IP address"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't even have to be reachable
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

SERVER_IP = get_ip()
SERVER_PORT = 5000

# Setup ngrok for global access if enabled
def setup_ngrok():
    global SERVER_URL
    try:
        # Open a HTTP tunnel on the specified port
        public_url = ngrok.connect(SERVER_PORT, bind_tls=True)
        logger.info(f"ngrok tunnel established at: {public_url}")
        SERVER_URL = public_url
        return public_url
    except Exception as e:
        logger.error(f"Error setting up ngrok: {str(e)}")
        return None

# Socket.IO event handlers
@sio.event
def connect(sid, environ):
    logger.info(f"Socket connected: {sid}")

@sio.event
def disconnect(sid):
    logger.info(f"Socket disconnected: {sid}")
    # Update peer status if found
    for peer_id, peer_data in list(connected_peers.items()):
        if peer_data.get('socket_id') == sid:
            connected_peers[peer_id]['status'] = 'offline'
            connected_peers[peer_id]['disconnected_at'] = datetime.now().isoformat()
            logger.info(f"Peer marked offline: {peer_id}")
            # Notify other peers about this peer disconnection
            sio.emit('peer_disconnected', {'peer_id': peer_id})

@sio.event
def register_socket(sid, data):
    try:
        peer_id = data.get('peer_id')
        if peer_id and peer_id in connected_peers:
            connected_peers[peer_id]['socket_id'] = sid
            connected_peers[peer_id]['last_seen'] = datetime.now().isoformat()
            logger.info(f"Socket registered for peer: {peer_id}")
            return {'status': 'success'}
        return {'status': 'error', 'message': 'Invalid peer ID'}
    except Exception as e:
        logger.error(f"Error registering socket: {str(e)}")
        return {'status': 'error', 'message': str(e)}

@sio.event
def peer_signal(sid, data):
    try:
        target_peer_id = data.get('target_peer_id')
        sender_peer_id = data.get('sender_peer_id')
        signal_data = data.get('signal')
        
        if target_peer_id in connected_peers and 'socket_id' in connected_peers[target_peer_id]:
            target_socket_id = connected_peers[target_peer_id]['socket_id']
            sio.emit('peer_signal', {
                'sender_peer_id': sender_peer_id,
                'signal': signal_data
            }, room=target_socket_id)
            return {'status': 'success'}
        else:
            # Target peer not connected, store signal for later delivery
            # or initiate relay if direct connection isn't possible
            initiate_relay(sender_peer_id, target_peer_id)
            return {'status': 'relay', 'message': 'Target peer unavailable, using relay'}
    except Exception as e:
        logger.error(f"Error in peer signaling: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def initiate_relay(sender_peer_id, receiver_peer_id):
    """Setup a relay session when direct P2P connection isn't possible"""
    session_id = str(uuid.uuid4())
    relay_sessions[session_id] = {
        'sender_id': sender_peer_id,
        'receiver_id': receiver_peer_id,
        'status': 'initiated',
        'created_at': datetime.now().isoformat()
    }
    
    # Notify sender that we're using relay
    if sender_peer_id in connected_peers and 'socket_id' in connected_peers[sender_peer_id]:
        sender_socket_id = connected_peers[sender_peer_id]['socket_id']
        sio.emit('relay_initiated', {
            'session_id': session_id,
            'target_peer_id': receiver_peer_id
        }, room=sender_socket_id)
    
    return session_id

@sio.event
def relay_chunk(sid, data):
    """Handle file chunk relay when direct connection isn't possible"""
    try:
        session_id = data.get('session_id')
        chunk_data = data.get('chunk')
        chunk_index = data.get('index')
        total_chunks = data.get('total')
        
        if session_id in relay_sessions:
            receiver_id = relay_sessions[session_id]['receiver_id']
            
            if receiver_id in connected_peers and 'socket_id' in connected_peers[receiver_id]:
                # Forward the chunk to receiver
                receiver_socket_id = connected_peers[receiver_id]['socket_id']
                sio.emit('relay_chunk', {
                    'session_id': session_id,
                    'chunk': chunk_data,
                    'index': chunk_index,
                    'total': total_chunks
                }, room=receiver_socket_id)
                
                # Update relay session status
                if chunk_index == total_chunks - 1:  # Last chunk
                    relay_sessions[session_id]['status'] = 'completed'
                
                return {'status': 'success'}
            else:
                # Receiver offline, store chunk for later delivery
                return {'status': 'queued', 'message': 'Receiver offline, chunk queued'}
        else:
            return {'status': 'error', 'message': 'Invalid relay session'}
    except Exception as e:
        logger.error(f"Error in relay_chunk: {str(e)}")
        return {'status': 'error', 'message': str(e)}

@app.route('/status', methods=['GET'])
def get_status():
    """Endpoint to check server status"""
    return jsonify({
        'status': 'online',
        'server_id': SERVER_ID,
        'ip': SERVER_IP,
        'port': SERVER_PORT,
        'public_url': SERVER_URL,
        'connected_peers': len(connected_peers),
        'active_transfers': len(active_transfers),
        'stun_servers': STUN_SERVERS,
    })

@app.route('/connect', methods=['POST'])
def connect_peer():
    """Endpoint for peers to connect to the server"""
    try:
        data = request.json
        if not data or 'user_id' not in data:
            return jsonify({'error': 'Missing required parameters'}), 400
        
        user_id = data['user_id']
        peer_id = str(uuid.uuid4())
        
        # Store peer information
        connected_peers[peer_id] = {
            'user_id': user_id,
            'ip': request.remote_addr,
            'connected_at': datetime.now().isoformat(),
            'status': 'online',
            'last_seen': datetime.now().isoformat()
        }
        
        logger.info(f"New peer connected: {peer_id} (User ID: {user_id})")
        
        # Return STUN servers and server information
        return jsonify({
            'status': 'connected',
            'peer_id': peer_id,
            'server_id': SERVER_ID,
            'stun_servers': STUN_SERVERS,
            'public_url': SERVER_URL
        })
    except Exception as e:
        logger.error(f"Error connecting peer: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/heartbeat/<peer_id>', methods=['POST'])
def heartbeat(peer_id):
    """Endpoint for peers to send heartbeat and maintain connection"""
    if peer_id not in connected_peers:
        return jsonify({'error': 'Peer not found'}), 404
    
    connected_peers[peer_id]['last_seen'] = datetime.now().isoformat()
    connected_peers[peer_id]['status'] = 'online'
    
    return jsonify({'status': 'ok'})

@app.route('/peers', methods=['GET'])
def get_peers():
    """Get list of connected peers"""
    # Optionally filter by user_id
    user_id = request.args.get('user_id')
    result = {}
    
    for peer_id, peer_data in connected_peers.items():
        if peer_data['status'] == 'online' and (not user_id or peer_data['user_id'] == user_id):
            result[peer_id] = peer_data
    
    return jsonify({
        'peers': result
    })

@app.route('/request-transfer', methods=['POST'])
def request_file_transfer():
    """Endpoint to request a file transfer between peers"""
    try:
        data = request.json
        if not data or 'sender_id' not in data or 'receiver_id' not in data or 'filename' not in data:
            return jsonify({'error': 'Missing required parameters'}), 400
        
        sender_id = data['sender_id']
        receiver_id = data['receiver_id']
        filename = data['filename']
        
        # Generate a unique transfer request ID
        request_id = str(uuid.uuid4())
        
        # Store the transfer request
        transfer_requests[request_id] = {
            'sender_id': sender_id,
            'receiver_id': receiver_id,
            'filename': filename,
            'status': 'pending',
            'created_at': datetime.now().isoformat()
        }
        
        logger.info(f"New transfer request: {request_id} - {sender_id} -> {receiver_id} - {filename}")
        
        # Notify receiver about transfer request via Socket.IO if they're online
        receiver_peer_id = None
        for peer_id, peer_data in connected_peers.items():
            if peer_data['user_id'] == receiver_id and peer_data['status'] == 'online':
                receiver_peer_id = peer_id
                if 'socket_id' in peer_data:
                    sio.emit('transfer_request', {
                        'request_id': request_id,
                        'sender_id': sender_id,
                        'filename': filename
                    }, room=peer_data['socket_id'])
                break
        
        return jsonify({
            'status': 'pending',
            'request_id': request_id,
            'receiver_online': receiver_peer_id is not None
        })
    except Exception as e:
        logger.error(f"Error requesting transfer: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/approve-transfer/<request_id>', methods=['POST'])
def approve_transfer(request_id):
    """Endpoint for receiver to approve a file transfer request"""
    try:
        if request_id not in transfer_requests:
            return jsonify({'error': 'Transfer request not found'}), 404
        
        # Update the transfer request status
        transfer_requests[request_id]['status'] = 'approved'
        
        # Create a transfer ID for the approved request
        transfer_id = str(uuid.uuid4())
        
        # Create an entry in active transfers
        active_transfers[transfer_id] = {
            'request_id': request_id,
            'status': 'ready',
            'progress': 0,
            'created_at': datetime.now().isoformat(),
            'sender_id': transfer_requests[request_id]['sender_id'],
            'receiver_id': transfer_requests[request_id]['receiver_id'],
            'filename': transfer_requests[request_id]['filename'],
            'transfer_mode': 'p2p'  # Default to P2P mode
        }
        
        # Notify sender via Socket.IO if they're online
        sender_id = transfer_requests[request_id]['sender_id']
        sender_peer_id = None
        for peer_id, peer_data in connected_peers.items():
            if peer_data['user_id'] == sender_id and peer_data['status'] == 'online':
                sender_peer_id = peer_id
                if 'socket_id' in peer_data:
                    sio.emit('transfer_approved', {
                        'request_id': request_id,
                        'transfer_id': transfer_id
                    }, room=peer_data['socket_id'])
                break
        
        logger.info(f"Transfer request approved: {request_id} -> Transfer ID: {transfer_id}")
        
        return jsonify({
            'status': 'approved',
            'transfer_id': transfer_id,
            'sender_online': sender_peer_id is not None
        })
    except Exception as e:
        logger.error(f"Error approving transfer: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/upload/<transfer_id>', methods=['POST'])
def upload_file(transfer_id):
    """Endpoint for sender to upload a file (fallback when P2P fails)"""
    try:
        if transfer_id not in active_transfers:
            return jsonify({'error': 'Transfer not found or not approved'}), 404
        
        if 'file' not in request.files:
            return jsonify({'error': 'No file part'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'error': 'No selected file'}), 400
        
        # Update transfer status
        active_transfers[transfer_id]['status'] = 'transferring'
        active_transfers[transfer_id]['transfer_mode'] = 'server_relay'
        
        # Secure the filename and save the file
        filename = secure_filename(file.filename)
        transfer_dir = os.path.join(app.config['UPLOAD_FOLDER'], transfer_id)
        os.makedirs(transfer_dir, exist_ok=True)
        
        file_path = os.path.join(transfer_dir, filename)
        file.save(file_path)
        
        # Update transfer status
        active_transfers[transfer_id]['status'] = 'completed'
        active_transfers[transfer_id]['progress'] = 100
        active_transfers[transfer_id]['file_path'] = file_path
        active_transfers[transfer_id]['completed_at'] = datetime.now().isoformat()
        
        # Notify receiver via Socket.IO
        receiver_id = active_transfers[transfer_id]['receiver_id']
        for peer_id, peer_data in connected_peers.items():
            if peer_data['user_id'] == receiver_id and peer_data['status'] == 'online':
                if 'socket_id' in peer_data:
                    sio.emit('transfer_completed', {
                        'transfer_id': transfer_id,
                        'filename': filename,
                        'transfer_mode': 'server_relay'
                    }, room=peer_data['socket_id'])
                break
        
        logger.info(f"File uploaded for transfer {transfer_id}: {filename}")
        
        return jsonify({
            'status': 'completed',
            'transfer_id': transfer_id,
            'filename': filename
        })
    except Exception as e:
        logger.error(f"Error uploading file: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/download/<transfer_id>', methods=['GET'])
def download_file(transfer_id):
    """Endpoint for receiver to download a file (when P2P fails)"""
    try:
        if transfer_id not in active_transfers:
            return jsonify({'error': 'Transfer not found'}), 404
        
        transfer = active_transfers[transfer_id]
        if transfer['status'] != 'completed':
            return jsonify({'error': 'File not ready for download'}), 400
        
        file_path = transfer['file_path']
        if not os.path.exists(file_path):
            return jsonify({'error': 'File not found'}), 404
        
        logger.info(f"File download initiated for transfer {transfer_id}")
        
        return send_file(file_path, as_attachment=True)
    except Exception as e:
        logger.error(f"Error downloading file: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/transfer-status/<transfer_id>', methods=['GET'])
def get_transfer_status(transfer_id):
    """Endpoint to check the status of a file transfer"""
    if transfer_id not in active_transfers:
        return jsonify({'error': 'Transfer not found'}), 404
    
    return jsonify(active_transfers[transfer_id])

@app.route('/update-transfer-status/<transfer_id>', methods=['POST'])
def update_transfer_status(transfer_id):
    """Endpoint to update transfer status from peers"""
    try:
        data = request.json
        if not data or 'status' not in data or 'progress' not in data:
            return jsonify({'error': 'Missing required parameters'}), 400
        
        if transfer_id not in active_transfers:
            return jsonify({'error': 'Transfer not found'}), 404
        
        # Update transfer status
        active_transfers[transfer_id]['status'] = data['status']
        active_transfers[transfer_id]['progress'] = data['progress']
        
        if data['status'] == 'completed':
            active_transfers[transfer_id]['completed_at'] = datetime.now().isoformat()
            
            # Notify both sender and receiver
            sender_id = active_transfers[transfer_id]['sender_id']
            receiver_id = active_transfers[transfer_id]['receiver_id']
            
            for peer_id, peer_data in connected_peers.items():
                if peer_data['user_id'] in [sender_id, receiver_id] and peer_data['status'] == 'online':
                    if 'socket_id' in peer_data:
                        sio.emit('transfer_completed', {
                            'transfer_id': transfer_id,
                            'transfer_mode': 'p2p'
                        }, room=peer_data['socket_id'])
        
        return jsonify({'status': 'updated'})
    except Exception as e:
        logger.error(f"Error updating transfer status: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/cancel-transfer/<transfer_id>', methods=['POST'])
def cancel_transfer(transfer_id):
    """Endpoint to cancel an ongoing transfer"""
    if transfer_id not in active_transfers:
        return jsonify({'error': 'Transfer not found'}), 404
    
    # Update transfer status
    active_transfers[transfer_id]['status'] = 'cancelled'
    
    # Remove the file if it exists and was using server relay
    if active_transfers[transfer_id].get('transfer_mode') == 'server_relay' and 'file_path' in active_transfers[transfer_id]:
        file_path = active_transfers[transfer_id]['file_path']
        if os.path.exists(file_path):
            os.remove(file_path)
    
    # Notify both sender and receiver
    sender_id = active_transfers[transfer_id]['sender_id']
    receiver_id = active_transfers[transfer_id]['receiver_id']
    
    for peer_id, peer_data in connected_peers.items():
        if peer_data['user_id'] in [sender_id, receiver_id] and peer_data['status'] == 'online':
            if 'socket_id' in peer_data:
                sio.emit('transfer_cancelled', {
                    'transfer_id': transfer_id
                }, room=peer_data['socket_id'])
    
    logger.info(f"Transfer cancelled: {transfer_id}")
    
    return jsonify({
        'status': 'cancelled',
        'transfer_id': transfer_id
    })

@app.route('/disconnect/<peer_id>', methods=['POST'])
def disconnect_peer(peer_id):
    """Endpoint for peers to disconnect from the server"""
    if peer_id not in connected_peers:
        return jsonify({'error': 'Peer not found'}), 404
    
    # Update peer status
    connected_peers[peer_id]['status'] = 'offline'
    connected_peers[peer_id]['disconnected_at'] = datetime.now().isoformat()
    
    logger.info(f"Peer disconnected: {peer_id}")
    
    return jsonify({
        'status': 'disconnected',
        'peer_id': peer_id
    })

# Regular cleanup task to remove inactive peers
def cleanup_inactive_peers():
    while True:
        try:
            now = datetime.now()
            for peer_id, peer_data in list(connected_peers.items()):
                if peer_data['status'] == 'online':
                    last_seen = datetime.fromisoformat(peer_data['last_seen'])
                    if (now - last_seen).total_seconds() > 60:  # 1 minute timeout
                        connected_peers[peer_id]['status'] = 'offline'
                        logger.info(f"Peer marked inactive: {peer_id}")
        except Exception as e:
            logger.error(f"Error in cleanup task: {str(e)}")
        time.sleep(30)  # Run every 30 seconds

if __name__ == '__main__':
    # Start cleanup thread
    cleanup_thread = threading.Thread(target=cleanup_inactive_peers, daemon=True)
    cleanup_thread.start()
    
    # Setup ngrok if enabled
    if USE_NGROK:
        setup_ngrok()
    
    # Log server information
    logger.info(f"Starting BurrowSpace P2P Server on {SERVER_IP}:{SERVER_PORT}")
    if SERVER_URL:
        logger.info(f"Public URL: {SERVER_URL}")
    
    # Start the server
    eventlet.wsgi.server(eventlet.listen(('0.0.0.0', SERVER_PORT)), app) 