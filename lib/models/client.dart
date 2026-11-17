import 'package:flutter/foundation.dart';
import 'sync_status.dart';

@immutable
class Client {
  final String id;
  final String name;
  final DateTime createdAt;
  final double? lat;
  final double? lng;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final SyncStatus syncStatus;
  final bool pendingDelete;
  final String? userId;
  final String status;
  final bool notified;

  const Client({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lat,
    this.lng,
    this.locationAccuracy,
    this.locationCapturedAt,
    SyncStatus? syncStatus,
    bool isSynced = true,
    this.pendingDelete = false,
    this.userId,
    this.status = 'accepted',
    this.notified = false,
  }) : syncStatus = syncStatus ?? (isSynced ? SyncStatus.synced : SyncStatus.pending);

  bool get isSynced => syncStatus == SyncStatus.synced;
  bool get hasLocation => lat != null && lng != null;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';

  String get locationText {
    if (!hasLocation) {
      return 'Location not captured';
    }
    return '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
  }

  static double? _double(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime _parseDate(dynamic rawDate) {
    if (rawDate is DateTime) return rawDate;
    if (rawDate is String) return DateTime.tryParse(rawDate) ?? DateTime.now().toUtc();
    return DateTime.now().toUtc();
  }

  static DateTime? _parseNullableDate(dynamic rawDate) {
    if (rawDate == null) return null;
    if (rawDate is DateTime) return rawDate;
    if (rawDate is String) return DateTime.tryParse(rawDate);
    return null;
  }

  static SyncStatus _parseSyncStatus(Map<String, dynamic> map) {
    final rawStatus = map['sync_status'];
    if (rawStatus is String) {
      return SyncStatus.values.firstWhere(
        (status) => status.name == rawStatus,
        orElse: () => SyncStatus.pending,
      );
    }
    if (map.containsKey('is_synced')) {
      final synced = map['is_synced'] is bool
          ? map['is_synced'] as bool
          : (map['is_synced'] as num?)?.toInt() == 1;
      return synced ? SyncStatus.synced : SyncStatus.pending;
    }
    return SyncStatus.synced;
  }

  factory Client.fromMap(Map<String, dynamic> map) => Client(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        createdAt: _parseDate(map['created_at']),
        lat: _double(map, 'lat'),
        lng: _double(map, 'lng'),
        locationAccuracy: _double(map, 'location_accuracy_m'),
        locationCapturedAt: _parseNullableDate(map['location_captured_at']),
        syncStatus: _parseSyncStatus(map),
        pendingDelete: map.containsKey('pending_delete')
            ? (map['pending_delete'] is bool
                ? map['pending_delete'] as bool
                : (map['pending_delete'] as num?)?.toInt() == 1)
            : false,
        userId: map['user_id']?.toString(),
        status: map['status']?.toString() ?? 'accepted',
        notified: map['notified'] is bool
            ? map['notified'] as bool
            : (map['notified'] as num?)?.toInt() == 1,
      );

  factory Client.fromSupabaseMap(Map<String, dynamic> map) => Client.fromMap({
        ...map,
        'sync_status': SyncStatus.synced.name,
        'pending_delete': false,
      });

  factory Client.fromLocalMap(Map<String, dynamic> map) => Client(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        createdAt: _parseDate(map['created_at']),
        lat: _double(map, 'lat'),
        lng: _double(map, 'lng'),
        locationAccuracy: _double(map, 'location_accuracy_m'),
        locationCapturedAt: _parseNullableDate(map['location_captured_at']),
        syncStatus: _parseSyncStatus(map),
        pendingDelete: (map['pending_delete'] as num?)?.toInt() == 1,
        userId: map['user_id']?.toString(),
        status: map['status']?.toString() ?? 'accepted',
        notified: (map['notified'] as num?)?.toInt() == 1,
      );

  /// Serialization for Supabase (business data only — excludes local sync metadata).
  Map<String, dynamic> toSupabaseMap({bool includeExtendedLocation = true}) => {
        'id': id,
        'name': name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        if (includeExtendedLocation) ...{
          if (locationAccuracy != null) 'location_accuracy_m': locationAccuracy,
          if (locationCapturedAt != null)
            'location_captured_at': locationCapturedAt!.toUtc().toIso8601String(),
        },
        if (userId != null) 'user_id': userId,
        'status': status,
        'notified': notified,
      };

  Map<String, dynamic> toMap() => toSupabaseMap();

  /// Serialization for SQLite (includes local synchronization metadata).
  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        'location_accuracy_m': locationAccuracy,
        'location_captured_at': locationCapturedAt?.toUtc().toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'sync_status': syncStatus.name,
        'pending_delete': pendingDelete ? 1 : 0,
        'user_id': userId,
        'status': status,
        'notified': notified ? 1 : 0,
      };

  Client copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    Object? lat = _noChange,
    Object? lng = _noChange,
    Object? locationAccuracy = _noChange,
    Object? locationCapturedAt = _noChange,
    SyncStatus? syncStatus,
    bool? isSynced,
    bool? pendingDelete,
    Object? userId = _noChange,
    String? status,
    bool? notified,
  }) =>
      Client(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        lat: identical(lat, _noChange) ? this.lat : lat as double?,
        lng: identical(lng, _noChange) ? this.lng : lng as double?,
        locationAccuracy: identical(locationAccuracy, _noChange)
            ? this.locationAccuracy
            : locationAccuracy as double?,
        locationCapturedAt: identical(locationCapturedAt, _noChange)
            ? this.locationCapturedAt
            : locationCapturedAt as DateTime?,
        syncStatus: syncStatus ??
            (isSynced != null
                ? (isSynced ? SyncStatus.synced : SyncStatus.pending)
                : this.syncStatus),
        pendingDelete: pendingDelete ?? this.pendingDelete,
        userId: identical(userId, _noChange) ? this.userId : userId as String?,
        status: status ?? this.status,
        notified: notified ?? this.notified,
      );

  @override
  String toString() =>
      'Client(id: $id, name: $name, createdAt: $createdAt, status: $status, syncStatus: ${syncStatus.name})';

  @override
  bool operator ==(Object other) =>
      other is Client &&
      other.id == id &&
      other.name == name &&
      other.createdAt.isAtSameMomentAs(createdAt) &&
      other.lat == lat &&
      other.lng == lng &&
      other.locationAccuracy == locationAccuracy &&
      ((other.locationCapturedAt == null && locationCapturedAt == null) ||
          (other.locationCapturedAt != null &&
              locationCapturedAt != null &&
              other.locationCapturedAt!.isAtSameMomentAs(locationCapturedAt!))) &&
      other.syncStatus == syncStatus &&
      other.pendingDelete == pendingDelete &&
      other.userId == userId &&
      other.status == status &&
      other.notified == notified;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        createdAt,
        lat,
        lng,
        locationAccuracy,
        locationCapturedAt,
        syncStatus,
        pendingDelete,
        userId,
        status,
        notified,
      );
}

const Object _noChange = Object();
