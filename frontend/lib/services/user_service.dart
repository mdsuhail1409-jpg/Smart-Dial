import '../core/api/api_client.dart';
import '../core/models/user.dart';

/// High-level user service.
class UserService {
  UserService._();

  /// Fetch all registered users from the backend.
  ///
  /// Returns a list of [User] objects, or throws a [UserServiceException]
  /// with a human-readable message on failure.
  static Future<List<User>> getUsers() async {
    final result = await ApiClient.getUsers();
    if (!result.isSuccess) {
      throw UserServiceException(result.error ?? 'Failed to load users');
    }

    final usersJson = result.data!['users'] as List<dynamic>;
    return usersJson
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class UserServiceException implements Exception {
  final String message;
  const UserServiceException(this.message);
  @override
  String toString() => message;
}
