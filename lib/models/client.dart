import 'package:flutter/foundation.dart';

@immutable
class Client {
  final String id;
  final String name;
  final DateTime createdAt;

  const Client({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    final rawDate = map['created_at'];
    DateTime parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate = DateTime.parse(rawDate);
    } else {
      parsedDate = DateTime.now();
    }

    return Client(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  Client copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return Client(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Client(id: $id, name: $name, createdAt: $createdAt)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Client &&
        other.id == id &&
        other.name == name &&
        other.createdAt.isAtSameMomentAs(createdAt);
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt.millisecondsSinceEpoch);
}
