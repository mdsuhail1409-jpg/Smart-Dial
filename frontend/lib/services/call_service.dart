import '../core/api/api_client.dart';
import '../core/models/call_request.dart';

/// High-level call request service.
///
/// Wraps [ApiClient] call-related methods.
/// Reuses the existing JWT storage — no second auth mechanism.
class CallService {
  CallService._();

  /// Create a call request to [receiverId].
  /// Returns the [CallRequest] on success, throws [CallServiceException] on failure.
  static Future<CallRequest> createCallRequest(int receiverId) async {
    final result = await ApiClient.createCallRequest(receiverId: receiverId);
    if (!result.isSuccess) {
      throw CallServiceException(result.error ?? 'Failed to create call request');
    }
    return CallRequest.fromJson(result.data!);
  }

  /// Fetch a single call request by [requestId].
  static Future<CallRequest> getCallRequest(String requestId) async {
    final result = await ApiClient.getCallRequest(requestId);
    if (!result.isSuccess) {
      throw CallServiceException(result.error ?? 'Failed to fetch call request');
    }
    return CallRequest.fromJson(result.data!);
  }

  /// Fetch all call requests for the authenticated user.
  static Future<List<CallRequest>> getMyCallRequests({String? status}) async {
    final result = await ApiClient.getMyCallRequests(status: status);
    if (!result.isSuccess) {
      throw CallServiceException(result.error ?? 'Failed to fetch call requests');
    }
    final list = result.data!['requests'] as List<dynamic>;
    return list.map((e) => CallRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Cancel a PENDING call request.
  static Future<CallRequest> cancelCallRequest(String requestId) async {
    final result = await ApiClient.cancelCallRequest(requestId);
    if (!result.isSuccess) {
      throw CallServiceException(result.error ?? 'Failed to cancel call request');
    }
    return CallRequest.fromJson(result.data!);
  }
}

class CallServiceException implements Exception {
  final String message;
  const CallServiceException(this.message);
  @override
  String toString() => message;
}
