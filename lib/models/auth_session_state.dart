// Authentication session state stays explicit so bootstrap can route cleanly on web.

class AuthSessionState {
  const AuthSessionState({
    required this.authenticated,
    required this.loginRequired,
  });

  const AuthSessionState.desktop()
    : authenticated = true,
      loginRequired = false;

  factory AuthSessionState.fromJson(Map<String, dynamic> json) {
    return AuthSessionState(
      authenticated: json['authenticated'] == true,
      loginRequired: json['loginRequired'] == true,
    );
  }

  final bool authenticated;
  final bool loginRequired;
}
