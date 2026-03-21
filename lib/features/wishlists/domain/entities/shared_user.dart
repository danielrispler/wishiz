class SharedUser {
  const SharedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String role;

  SharedUser copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
  }) {
    return SharedUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
    );
  }
}
