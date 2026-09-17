import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/telecom_service.dart';

/// Dialer Status Screen
///
/// Shows:
///  - Whether SmartDial is the default phone app
///  - Button to request the default dialer role (via Android system UI)
///  - Available SIM / PhoneAccounts
///
/// This is a development/settings screen. In production it can be embedded
/// in a Settings flow.
class DialerStatusScreen extends StatefulWidget {
  const DialerStatusScreen({super.key});

  @override
  State<DialerStatusScreen> createState() => _DialerStatusScreenState();
}

class _DialerStatusScreenState extends State<DialerStatusScreen> {
  bool _telecomSupported = false;
  bool _isDefaultDialer = false;
  List<PhoneAccountInfo> _accounts = [];
  bool _loading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);

    // Request READ_PHONE_STATE so we can list SIM accounts
    await Permission.phone.request();

    final supported = await TelecomService.isTelecomSupported();
    final isDefault = await TelecomService.isDefaultDialer();
    final accounts  = await TelecomService.getAvailablePhoneAccounts();

    if (!mounted) return;
    setState(() {
      _telecomSupported = supported;
      _isDefaultDialer  = isDefault;
      _accounts         = accounts;
      _loading          = false;
    });
  }

  Future<void> _requestRole() async {
    setState(() => _statusMessage = 'Launching system dialog…');
    final result = await TelecomService.requestDefaultDialerRole();
    if (!mounted) return;

    setState(() {
      _statusMessage = switch (result) {
        'already_default' => 'SmartDial is already the default phone app.',
        'requested'       => 'Role dialog shown. Please confirm on the next screen.',
        _                 => result,
      };
    });

    // Re-query after user may have confirmed in the system dialog
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telecom Status'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── Telecom support ─────────────────────────────────────────
                _SectionHeader('Android Telecom'),
                _StatusTile(
                  label: 'Telecom framework',
                  ok: _telecomSupported,
                  okText: 'Available',
                  failText: 'Not available on this device',
                ),
                const SizedBox(height: 8),

                // ── Default dialer ──────────────────────────────────────────
                _SectionHeader('Default Phone App'),
                _StatusTile(
                  label: 'SmartDial is default dialer',
                  ok: _isDefaultDialer,
                  okText: 'Yes ✓',
                  failText: 'Not set as default',
                ),
                const SizedBox(height: 12),

                if (!_isDefaultDialer)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _requestRole,
                      icon: const Icon(Icons.phone_android),
                      label: const Text('Make SmartDial Default Phone App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                if (_isDefaultDialer)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'SmartDial is the Default Phone App',
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ],
                    ),
                  ),

                // Status message
                if (_statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── SIM Accounts ────────────────────────────────────────────
                _SectionHeader('Available SIM / PhoneAccounts'),
                if (_accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No call-capable PhoneAccounts found.\n'
                      'READ_PHONE_STATE permission may be needed, or '
                      'SmartDial may not yet be the default dialer.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._accounts.map((acc) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              'S${acc.index + 1}',
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(acc.label),
                          subtitle: Text('ID: ${acc.id}'),
                          trailing: Icon(
                            acc.enabled ? Icons.signal_cellular_alt : Icons.signal_cellular_off,
                            color: acc.enabled ? Colors.green : Colors.grey,
                          ),
                        ),
                      )),

                const SizedBox(height: 24),

                // ── Architecture note ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Architecture Note',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'SmartDial voice calls travel through:\n'
                        'Android Telecom → SIM → Cellular Operator → Phone B\n\n'
                        'WebRTC is NOT used for voice communication.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String label;
  final bool ok;
  final String okText;
  final String failText;

  const _StatusTile({
    required this.label,
    required this.ok,
    required this.okText,
    required this.failText,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: ok ? Colors.green.shade600 : Colors.red.shade400,
      ),
      title: Text(label),
      trailing: Text(
        ok ? okText : failText,
        style: TextStyle(
          color: ok ? Colors.green.shade700 : Colors.red.shade600,
          fontSize: 12,
        ),
      ),
    );
  }
}
