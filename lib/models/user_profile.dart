import 'package:flutter/foundation.dart';

@immutable
class UserProfile {
  final String id;
  final String name;
  final String role;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isClient => role == 'client';

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      role: map['role']?.toString() ?? 'client',
      createdAt: map['created_at'] != null
          ? (map['created_at'] is DateTime
              ? map['created_at'] as DateTime
              : DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now().toUtc())
          : DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'role': role,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  UserProfile copyWith({
    String? id,
    String? name,
    String? role,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          role == other.role &&
          createdAt.isAtSameMomentAs(other.createdAt);

  @override
  int get hashCode => Object.hash(id, name, role, createdAt);

  @override
  String toString() => 'UserProfile(id: $id, name: $name, role: $role)';
}
