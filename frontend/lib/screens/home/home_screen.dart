import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_theme.dart';
import '../../core/models/call_request.dart';
import '../../core/models/user.dart';
import '../../core/storage/secure_storage.dart';
import '../../services/auth_service.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import '../calling/calling_screen.dart';
import '../dialer_status/dialer_status_screen.dart';

/// Home screen — Matches Figma Screens 4A (Keypad), 4B (Contacts), 5 (Collisions), and 5B (Detail)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Navigation / Tabs: 0: Keypad, 1: Contacts, 2: Collision History
  int _selectedTab = 0;

  List<User> _users = [];
  bool _isLoading = true;
  String? _error;
  String _currentUserName = 'Suhail';
  int? _currentUserId;
  int? _callingUserId;

  // Keypad State
  String _dialedNumber = '3829102';
  int _selectedSim = 1;

  // Contacts Search
  String _contactSearch = '';

  // Collision History State
  List<dynamic> _reciprocalPairs = [];
  bool _loadingPairs = false;
  String _historyFilter = 'All'; // 'All', 'Collisions Detected', 'Missed'

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadHistory();
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
      final msg = e.message.toLowerCase();
      if (msg.contains('401') ||
          msg.contains('403') ||
          msg.contains('expired') ||
          msg.contains('invalid') ||
          msg.contains('token') ||
          msg.contains('unauthorized')) {
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

  Future<void> _loadHistory() async {
    setState(() => _loadingPairs = true);
    final result = await ApiClient.getReciprocalPairs();
    if (mounted) {
      setState(() {
        _reciprocalPairs = result.data ?? [];
        _loadingPairs = false;
      });
    }
  }

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
    } catch (_) {}
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

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
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'SD';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  User? _getMatchedContact() {
    if (_dialedNumber.isEmpty) return null;
    final digits = _dialedNumber.replaceAll(RegExp(r'\D'), '');
    for (final u in _users) {
      final phoneDigits = u.phone.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.contains(digits) || digits.contains(phoneDigits)) {
        return u;
      }
    }
    // Default fallback to first non-current user for visual richness
    return _users.where((u) => u.id != _currentUserId).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopProfileBar(),
            const SizedBox(height: 12),
            _buildSegmentedTabBar(),
            const SizedBox(height: 12),
            Expanded(child: _buildCurrentTabView()),
          ],
        ),
      ),
    );
  }

  // ── Top Header matching Figma 4A / 4B ──────────────────────────────────────
  Widget _buildTopProfileBar() {
    final initials = _getInitials(_currentUserName);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar with glowing cyan ring
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cyan, width: 2),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E3A59), Color(0xFF1E283F)],
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $_currentUserName',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Your network. In sync.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Settings / Logout Menu
              PopupMenuButton<String>(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.settings_outlined,
                      size: 20, color: AppColors.textSecondary),
                ),
                color: AppColors.surfaceElevated,
                onSelected: (val) {
                  if (val == 'status') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DialerStatusScreen()),
                    );
                  } else if (val == 'refresh') {
                    _loadUsers();
                    _loadHistory();
                  } else if (val == 'logout') {
                    _logout();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'status',
                    child: Row(
                      children: [
                        Icon(Icons.phone_android, size: 18, color: AppColors.cyan),
                        SizedBox(width: 8),
                        Text('Telecom Status'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 18, color: AppColors.green),
                        SizedBox(width: 8),
                        Text('Refresh Data'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 18, color: AppColors.red),
                        SizedBox(width: 8),
                        Text('Sign Out'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Subrow: SIM 1 Pill + Default Dialer Checkmark
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sim_card_outlined,
                        size: 13, color: AppColors.cyan),
                    SizedBox(width: 6),
                    Text(
                      'SIM 1: Jio 5G',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DialerStatusScreen()),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, size: 15, color: AppColors.green),
                    SizedBox(width: 6),
                    Text(
                      'Default dialer',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Segmented Tab Bar: Keypad | Contacts | Collision History ───────────────
  Widget _buildSegmentedTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _buildSegmentTab(0, 'Keypad'),
          _buildSegmentTab(1, 'Contacts / Directory'),
          _buildSegmentTab(2, 'Collision History'),
        ],
      ),
    );
  }

  Widget _buildSegmentTab(int index, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ── View Router ───────────────────────────────────────────────────────────
  Widget _buildCurrentTabView() {
    switch (_selectedTab) {
      case 0:
        return _buildKeypadView();
      case 1:
        return _buildContactsView();
      case 2:
        return _buildCollisionHistoryView();
      default:
        return _buildKeypadView();
    }
  }

  // ── TAB 1: Keypad View (Figma Screen 4A) ──────────────────────────────────
  Widget _buildKeypadView() {
    final matched = _getMatchedContact();

    return Column(
      children: [
        const Spacer(flex: 1),
        // Dialed Number Display + Backspace
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _formatDialed(_dialedNumber),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (_dialedNumber.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.backspace_outlined,
                      color: AppColors.textSecondary, size: 22),
                  onPressed: () {
                    if (_dialedNumber.isNotEmpty) {
                      setState(() {
                        _dialedNumber =
                            _dialedNumber.substring(0, _dialedNumber.length - 1);
                      });
                    }
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Matched Contact
        if (matched != null)
          Text(
            '${matched.name} • SmartDial Ready',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.cyan,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          const SizedBox(height: 18),

        const Spacer(flex: 1),

        // 3x4 Matrix Dialpad
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              _buildKeypadRow(['1', '2', '3'], ['(o_o)', 'ABC', 'DEF']),
              const SizedBox(height: 14),
              _buildKeypadRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO']),
              const SizedBox(height: 14),
              _buildKeypadRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ']),
              const SizedBox(height: 14),
              _buildKeypadRow(['*', '0', '#'], ['', '+', '']),
            ],
          ),
        ),

        const Spacer(flex: 1),

        // SIM Selector Pills
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSimPill(1, 'SIM 1'),
            const SizedBox(width: 12),
            _buildSimPill(2, 'SIM 2'),
          ],
        ),
        const SizedBox(height: 16),

        // Call Button
        GestureDetector(
          onTap: () {
            if (matched != null) {
              _callUser(matched);
            } else if (_users.isNotEmpty) {
              _callUser(_users.first);
            }
          },
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.greenGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.green.withValues(alpha: 0.4),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.phone, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Smart call via SIM $_selectedSim',
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _formatDialed(String raw) {
    if (raw.isEmpty) return ' ';
    if (raw.length <= 3) return raw;
    if (raw.length <= 7) {
      return '${raw.substring(0, 3)} ${raw.substring(3)}';
    }
    return '${raw.substring(0, 3)} ${raw.substring(3, 7)} ${raw.substring(7)}';
  }

  Widget _buildKeypadRow(List<String> digits, List<String> letters) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(3, (i) {
        return _buildKeypadButton(digits[i], letters[i]);
      }),
    );
  }

  Widget _buildKeypadButton(String digit, String sub) {
    return InkWell(
      borderRadius: BorderRadius.circular(35),
      onTap: () {
        setState(() {
          _dialedNumber += digit;
        });
      },
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF131D33),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimPill(int sim, String label) {
    final active = _selectedSim == sim;
    return GestureDetector(
      onTap: () => setState(() => _selectedSim = sim),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1B2C46) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sim_card_outlined,
                size: 13, color: active ? AppColors.cyan : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.cyan : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TAB 2: Contacts / Directory View (Figma Screen 4B) ────────────────────
  Widget _buildContactsView() {
    final filtered = _users.where((u) {
      if (_contactSearch.isEmpty) return true;
      return u.name.toLowerCase().contains(_contactSearch.toLowerCase()) ||
          u.phone.contains(_contactSearch);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _contactSearch = v),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search registered SmartDial contacts...',
                      hintStyle: TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ),
                ),
                const Icon(Icons.mic_none, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Header: Registered Contacts | X online
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'REGISTERED CONTACTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '${filtered.length} online',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Contact List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.cyan))
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _error ?? 'No registered contacts found',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.borderSubtle),
                        itemBuilder: (context, i) {
                          final user = filtered[i];
                          final isMe = user.id == _currentUserId;
                          final isCalling = _callingUserId == user.id;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                // Avatar circle
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF233554), Color(0xFF162238)],
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _getInitials(user.name),
                                      style: const TextStyle(
                                        color: AppColors.cyan,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user.phone,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Row(
                                        children: [
                                          Icon(Icons.circle,
                                              size: 6, color: AppColors.cyan),
                                          SizedBox(width: 4),
                                          Text(
                                            'SmartDial Ready',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.cyan,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isMe)
                                  IconButton(
                                    icon: isCalling
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.cyan),
                                          )
                                        : Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.cyan
                                                  .withValues(alpha: 0.12),
                                            ),
                                            child: const Icon(Icons.phone,
                                                color: AppColors.cyan, size: 18),
                                          ),
                                    onPressed:
                                        isCalling ? null : () => _callUser(user),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ready contacts support collision-free coordination.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── TAB 3: Collision History View (Figma Screen 5 & 5B) ───────────────────
  Widget _buildCollisionHistoryView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Call Activity & Collisions',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Every call. Every resolved connection.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),

          // Filter Chips
          Row(
            children: [
              _buildFilterChip('All'),
              const SizedBox(width: 8),
              _buildFilterChip('Collisions Detected'),
              const SizedBox(width: 8),
              _buildFilterChip('Missed'),
            ],
          ),
          const SizedBox(height: 16),

          // Highlight Banner (3 Reciprocal Collisions Prevented this week)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF132847), Color(0xFF0F1E36)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E3A63)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: AppColors.cyan, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_reciprocalPairs.isNotEmpty ? _reciprocalPairs.length : 3} Reciprocal Collisions',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Text(
                        'Prevented this week',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loadingPairs)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.cyan,
                    ),
                  )
                else
                  const Icon(Icons.bar_chart, color: AppColors.cyan, size: 24),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Grouped Call List
          Expanded(
            child: ListView(
              children: [
                const Text(
                  'TODAY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),

                // Normal Outgoing Call (Sarah Connor)
                _buildNormalCallCard(
                  name: 'Sarah Connor',
                  type: 'Outgoing • SIM 1 • 04:38',
                  time: '12:08 PM',
                  isOutgoing: true,
                ),
                const SizedBox(height: 10),

                // Dynamic or Default Reciprocal Collision Resolved Card
                ...(_reciprocalPairs.isNotEmpty
                    ? _reciprocalPairs.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildCollisionCard(
                            pairId: (p['pair_id'] ?? 'RP_849201').toString(),
                            contactName: (p['other_user_name'] ?? 'Alex Rivera').toString(),
                            time: 'Today, 11:42 AM • SIM 1',
                            deltaMs: (p['time_difference_ms'] as num?)?.toInt() ?? 28,
                            decision: 'PROCEED (Your call connected)',
                          ),
                        ))
                    : [
                        _buildCollisionCard(
                          pairId: 'RP_849201',
                          contactName: 'Alex Rivera',
                          time: 'Today, 11:42 AM • SIM 1',
                          deltaMs: 28,
                          decision: 'PROCEED (Your call connected)',
                        ),
                      ]),
                const SizedBox(height: 10),

                // Missed Call (Maya Chen)
                _buildNormalCallCard(
                  name: 'Maya Chen',
                  type: 'Missed • SIM 1 • No answer',
                  time: '10:16 AM',
                  isMissed: true,
                ),
                const SizedBox(height: 16),

                const Text(
                  'YESTERDAY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),

                _buildNormalCallCard(
                  name: 'Alex Rivera',
                  type: 'Incoming • SIM 1 • 02:17',
                  time: '6:24 PM',
                  isOutgoing: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final active = _historyFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _historyFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNormalCallCard({
    required String name,
    required String type,
    required String time,
    bool isOutgoing = false,
    bool isMissed = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMissed
                  ? AppColors.red.withValues(alpha: 0.15)
                  : const Color(0xFF1E2F4D),
            ),
            child: Icon(
              isMissed
                  ? Icons.call_missed
                  : (isOutgoing ? Icons.call_made : Icons.call_received),
              size: 16,
              color: isMissed ? AppColors.red : AppColors.cyan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isMissed ? AppColors.red : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  type,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildCollisionCard({
    required String pairId,
    required String contactName,
    required String time,
    required int deltaMs,
    required String decision,
  }) {
    return GestureDetector(
      onTap: () => _openCollisionDetailModal(
        pairId: pairId,
        contactName: contactName,
        time: time,
        deltaMs: deltaMs,
        decision: decision,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF191833),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF6B46C1), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'RECIPROCAL COLLISION RESOLVED • Pair: $pairId',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Color(0xFFC084FC),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.sync_alt, color: Color(0xFFC084FC), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    contactName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              time,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              'Time Difference: ${deltaMs}ms',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              decision,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── MODAL 5B: Collision Detail Modal (Figma Screen 5B) ────────────────────
  void _openCollisionDetailModal({
    required String pairId,
    required String contactName,
    required String time,
    required int deltaMs,
    required String decision,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF121B2F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'RECIPROCAL COLLISION RESOLVED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Color(0xFFC084FC),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Connection, coordinated.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Contact row
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF1E2D4A),
                    ),
                    child: Center(
                      child: Text(
                        _getInitials(contactName),
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contactName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Interactive timeline / Delta graph card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pair $pairId',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${deltaMs}ms',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.cyan,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Timeline nodes with line
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.green,
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(height: 2, color: AppColors.border),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Δ ${deltaMs}ms',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFC084FC),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Priority tier: Not provided',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Resolution Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D2520),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF125244)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppColors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            decision,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'The paired attempts were coordinated to avoid a busy tone.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Done Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
