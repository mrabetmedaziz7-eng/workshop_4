import 'package:flutter/foundation.dart';

@immutable
class Client {
  final String id;
  final String name;
  final DateTime createdAt;
  final double? lat;
  final double? lng;
  final bool isSynced;
  final bool pendingDelete;

  const Client({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lat,
    this.lng,
    this.isSynced = true,
    this.pendingDelete = false,
  });

  static double? _double(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  factory Client.fromMap(Map<String, dynamic> map) {
    final rawDate = map['created_at'];
    final parsedDate = rawDate is DateTime
        ? rawDate
        : rawDate is String
            ? DateTime.tryParse(rawDate) ?? DateTime.now().toUtc()
            : DateTime.now().toUtc();
    return Client(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      createdAt: parsedDate,
      lat: _double(map, 'lat'),
      lng: _double(map, 'lng'),
      isSynced: map.containsKey('is_synced')
          ? (map['is_synced'] is bool
              ? map['is_synced'] as bool
              : (map['is_synced'] as num?)?.toInt() == 1)
          : true,
      pendingDelete: map.containsKey('pending_delete')
          ? (map['pending_delete'] is bool
              ? map['pending_delete'] as bool
              : (map['pending_delete'] as num?)?.toInt() == 1)
          : false,
    );
  }

  factory Client.fromLocalMap(Map<String, dynamic> map) {
    final rawDate = map['created_at'] as String?;
    return Client(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      createdAt: rawDate == null
          ? DateTime.now().toUtc()
          : (DateTime.tryParse(rawDate) ?? DateTime.now().toUtc()),
      lat: _double(map, 'lat'),
      lng: _double(map, 'lng'),
      isSynced: (map['is_synced'] as num?)?.toInt() == 1,
      pendingDelete: (map['pending_delete'] as num?)?.toInt() == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
      };

  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        'is_synced': isSynced ? 1 : 0,
        'pending_delete': pendingDelete ? 1 : 0,
      };

  Client copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    Object? lat = _noChange,
    Object? lng = _noChange,
    bool? isSynced,
    bool? pendingDelete,
  }) => Client(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        lat: identical(lat, _noChange) ? this.lat : lat as double?,
        lng: identical(lng, _noChange) ? this.lng : lng as double?,
        isSynced: isSynced ?? this.isSynced,
        pendingDelete: pendingDelete ?? this.pendingDelete,
      );

  @override
  String toString() => 'Client(id: $id, name: $name, createdAt: $createdAt, lat: $lat, lng: $lng)';

  @override
  bool operator ==(Object other) => other is Client &&
      other.id == id &&
      other.name == name &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      other.lat == lat &&
      other.lng == lng &&
      other.isSynced == isSynced &&
      other.pendingDelete == pendingDelete;

  @override
  int get hashCode => Object.hash(id, name, createdAt, lat, lng, isSynced, pendingDelete);
}

const Object _noChange = Object();
