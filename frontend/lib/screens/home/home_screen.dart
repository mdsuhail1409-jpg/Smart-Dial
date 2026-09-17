import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/models/call_request.dart';
import '../../core/models/user.dart';
import '../../core/storage/secure_storage.dart';
import '../../services/auth_service.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import '../calling/calling_screen.dart';
import '../dialer_status/dialer_status_screen.dart';

/// Home screen — displayed after successful login.
///
/// Shows "Welcome, [user name]" and lists ALL registered users
/// fetched live from GET /api/users.
/// Each user other than the authenticated user has a CALL button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<User> _users = [];
  bool _isLoading = true;
  String? _error;
  String _currentUserName = '';
  int? _currentUserId;

  // Track which user ID is currently being called (loading state per row)
  int? _callingUserId;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await UserService.getUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
      await _resolveCurrentUser();
    } on UserServiceException catch (e) {
      if (!mounted) return;
      // A 401/403 means the stored JWT is expired or invalid.
      // Clear it and send the user back to Login.
      final msg = e.message.toLowerCase();
      if (msg.contains('401') || msg.contains('403') ||
          msg.contains('expired') || msg.contains('invalid') ||
          msg.contains('token') || msg.contains('unauthorized')) {
        await AuthService.logout();
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  /// Decode the JWT locally to extract user ID, then match to the loaded list.
  Future<void> _resolveCurrentUser() async {
    try {
      final token = await SecureStorage.getToken();
      if (token == null) return;

      final parts = token.split('.');
      if (parts.length != 3) return;

      String padded = parts[1];
      padded += '=' * ((4 - padded.length % 4) % 4);
      padded = padded.replaceAll('-', '+').replaceAll('_', '/');

      final payloadJson = utf8.decode(base64Decode(padded));
      final payloadMap = jsonDecode(payloadJson) as Map<String, dynamic>;

      final sub = payloadMap['sub'];
      if (sub == null) return;
      final userId = int.tryParse(sub.toString());
      if (userId == null) return;

      final match = _users.where((u) => u.id == userId).firstOrNull;
      if (match != null && mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserName = match.name;
        });
      }
    } catch (_) {
      // Non-critical
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  /// Called when the CALL button is pressed for [user].
  Future<void> _callUser(User user) async {
    setState(() => _callingUserId = user.id);

    try {
      final CallRequest request = await CallService.createCallRequest(user.id);
      if (!mounted) return;
      setState(() => _callingUserId = null);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallingScreen(
            initialRequest: request,
            receiver: user,
          ),
        ),
      );
    } on CallServiceException catch (e) {
      if (!mounted) return;
      setState(() => _callingUserId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartDial'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_android),
            tooltip: 'Telecom status',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DialerStatusScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh users',
            onPressed: _isLoading ? null : _loadUsers,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentUserName.isNotEmpty
                  ? 'Welcome, $_currentUserName'
                  : 'Welcome',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Registered Users',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _loadUsers,
            ),
          ],
        ),
      );
    }

    if (_users.isEmpty) {
      return const Center(child: Text('No users registered yet.'));
    }

    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = _users[index];
        final isMe = user.id == _currentUserId;
        final isCalling = _callingUserId == user.id;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isMe
                ? Colors.green.shade100
                : Colors.blue.shade100,
            child: Text(
              user.name[0].toUpperCase(),
              style: TextStyle(
                color: isMe
                    ? Colors.green.shade800
                    : Colors.blue.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            isMe ? '${user.name} (You)' : user.name,
            style: isMe
                ? TextStyle(color: Colors.grey.shade600)
                : null,
          ),
          subtitle: Text(user.phone),
          trailing: isMe
              ? null // No CALL button for yourself
              : SizedBox(
                  width: 80,
                  height: 34,
                  child: ElevatedButton(
                    onPressed: (_callingUserId != null) ? null : () => _callUser(user),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isCalling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phone, size: 14),
                              SizedBox(width: 4),
                              Text('CALL', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                  ),
                ),
        );
      },
    );
  }
}
