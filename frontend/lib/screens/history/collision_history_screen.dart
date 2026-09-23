import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

/// Screen displaying collision detection history and resolution telemetry.
class CollisionHistoryScreen extends StatefulWidget {
  const CollisionHistoryScreen({super.key});

  @override
  State<CollisionHistoryScreen> createState() => _CollisionHistoryScreenState();
}

class _CollisionHistoryScreenState extends State<CollisionHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _pairs = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiClient.getReciprocalPairs();
    if (mounted) {
      if (result.isSuccess) {
        setState(() {
          _pairs = result.data ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = result.error ?? 'Failed to load collision history';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        title: const Text(
          'Collision History & Telemetry',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_pairs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_split, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No Collision Events Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When two parties call each other simultaneously,\nSmartDial coordinates and logs the event here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: Colors.blue,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pairs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final pair = _pairs[index] as Map<String, dynamic>;
          return _buildPairCard(pair);
        },
      ),
    );
  }

  Widget _buildPairCard(Map<String, dynamic> pair) {
    final pairId = pair['pair_id'] ?? 'RP_UNKNOWN';
    final diffMs = pair['time_difference_ms'] ?? 0;
    final decisionType = pair['decision_type'];
    final reasonCode = pair['reason_code'];
    final reqA = pair['request_a'] as Map<String, dynamic>? ?? {};
    final reqB = pair['request_b'] as Map<String, dynamic>? ?? {};
    final callerA = reqA['caller']?['name'] ?? 'User A';
    final callerB = reqB['caller']?['name'] ?? 'User B';

    Color badgeColor = Colors.blue;
    String verdictText = 'Simultaneous Dialing';
    if (decisionType == 'ALLOW_A_TO_B') {
      badgeColor = Colors.green.shade700;
      verdictText = 'Allowed: $callerA → $callerB';
    } else if (decisionType == 'ALLOW_B_TO_A') {
      badgeColor = Colors.green.shade700;
      verdictText = 'Allowed: $callerB → $callerA';
    } else if (decisionType == 'BLOCK') {
      badgeColor = Colors.red.shade700;
      verdictText = 'Blocked';
    } else if (decisionType == 'ASK_USER') {
      badgeColor = Colors.orange.shade800;
      verdictText = 'Prompted User';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.blue, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    pairId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withAlpha(120)),
                ),
                child: Text(
                  verdictText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      callerA,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Called $callerB',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.compare_arrows, color: Colors.grey.shade400, size: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      callerB,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Called $callerA',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 24, color: Colors.grey.shade200),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Δ $diffMs ms',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              if (reasonCode != null)
                Text(
                  'Reason: $reasonCode',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
