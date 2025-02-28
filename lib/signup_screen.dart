import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class SignupScreen extends StatefulWidget {
  final String? initialEmail;
  final String? initialName;
  final String? provider;

  const SignupScreen({
    super.key,
    this.initialEmail,
    this.initialName,
    this.provider,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
    _fullNameController.text = widget.initialName ?? '';
    _deviceNameController.text = _getDefaultDeviceName();
  }

  String _getDefaultDeviceName() {
    if (kIsWeb) {
      return 'Web Browser';
    } else {
      try {
        return '${Platform.operatingSystem} Device';
      } catch (e) {
        return 'Unknown Device';
      }
    }
  }

  bool _validatePassword(String password) {
    if (password.length < 8) {
      setState(() {
        _passwordError = 'Password must contain a minimum of 8 characters';
      });
      return false;
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      setState(() {
        _passwordError = 'Password must contain at least one symbol e.g @,!';
      });
      return false;
    }
    setState(() {
      _passwordError = null;
    });
    return true;
  }

  bool _validateConfirmPassword() {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _confirmPasswordError = 'Password does not match';
      });
      return false;
    }
    setState(() {
      _confirmPasswordError = null;
    });
    return true;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _signUp() async {
    if (_fullNameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showMessage('Please fill in all fields');
      return;
    }

    if (!_validatePassword(_passwordController.text) ||
        !_validateConfirmPassword()) {
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      UserCredential? userCredential;

      if (widget.provider == null) {
        // Email/password signup
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      if (!mounted) return;

      final user = userCredential?.user ?? _auth.currentUser;
      if (user != null) {
        // Update user profile
        await user.updateDisplayName(_fullNameController.text);

        // Create user document in Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'userId': user.uid,
          'fullName': _fullNameController.text,
          'email': _emailController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
          'provider': widget.provider ?? 'email',
        });

        // Add device information
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('devices')
            .add({
          'deviceName': _deviceNameController.text,
          'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          'lastActive': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        // Remove loading dialog first
        Navigator.of(context).pop();
        // Then navigate to home screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
        return;
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // Remove loading dialog
      Navigator.of(context).pop();

      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Email is already registered';
          break;
        case 'invalid-email':
          message = 'Invalid email format';
          break;
        case 'weak-password':
          message = 'Password is too weak';
          break;
        default:
          message = 'Error: ${e.message}';
          break;
      }

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;
      // Remove loading dialog
      Navigator.of(context).pop();
      _showMessage('Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Let's get you started"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Create password',
                    border: const OutlineInputBorder(),
                    errorText: _passwordError,
                  ),
                  onChanged: _validatePassword,
                ),
                if (_passwordError == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Password must contain a minimum of 8 characters',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: const OutlineInputBorder(),
                    errorText: _confirmPasswordError,
                  ),
                  onChanged: (value) => _validateConfirmPassword(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _deviceNameController,
                  decoration: const InputDecoration(
                    labelText: 'Device Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Sign up'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already a user?'),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text('Login'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }
}
