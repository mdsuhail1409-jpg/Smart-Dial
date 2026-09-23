/// Mirrors the backend CallRequestResponse schema.
///
/// Day 2 fields: requestId, caller, receiver, status, reciprocalFlag, pairId,
/// requestTime, expiresAt.
/// reciprocalFlag and pairId are present but unused until Day 3.
class CallRequest {
  final String requestId;
  final UserSummary caller;
  final UserSummary receiver;
  final String status;
  final bool reciprocalFlag;
  final String? pairId;
  final DateTime requestTime;
  final DateTime expiresAt;

  const CallRequest({
    required this.requestId,
    required this.caller,
    required this.receiver,
    required this.status,
    required this.reciprocalFlag,
    required this.pairId,
    required this.requestTime,
    required this.expiresAt,
  });

  factory CallRequest.fromJson(Map<String, dynamic> json) {
    return CallRequest(
      requestId: json['request_id'] as String,
      caller: UserSummary.fromJson(json['caller'] as Map<String, dynamic>),
      receiver: UserSummary.fromJson(json['receiver'] as Map<String, dynamic>),
      status: json['status'] as String,
      reciprocalFlag: json['reciprocal_flag'] as bool,
      pairId: json['pair_id'] as String?,
      requestTime: DateTime.parse(json['request_time'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  bool get isPending => status == 'PENDING';
  bool get isCancelled => status == 'CANCELLED';
  bool get isExpired => status == 'EXPIRED';

  CallRequest copyWith({
    String? requestId,
    UserSummary? caller,
    UserSummary? receiver,
    String? status,
    bool? reciprocalFlag,
    String? pairId,
    DateTime? requestTime,
    DateTime? expiresAt,
  }) {
    return CallRequest(
      requestId: requestId ?? this.requestId,
      caller: caller ?? this.caller,
      receiver: receiver ?? this.receiver,
      status: status ?? this.status,
      reciprocalFlag: reciprocalFlag ?? this.reciprocalFlag,
      pairId: pairId ?? this.pairId,
      requestTime: requestTime ?? this.requestTime,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

/// Minimal user summary embedded in call request responses.
class UserSummary {
  final int id;
  final String name;

  const UserSummary({required this.id, required this.name});

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}
