import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Sanctum bearer + user payload + opsiyonel expires_at.
@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    this.expiresAt,
  });

  final String token;
  final AuthUser user;
  final DateTime? expiresAt;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'user': user.toJson(),
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      };

  static AuthSession fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'] as String)
            : null,
      );

  String encode() => jsonEncode(toJson());
  static AuthSession decode(String raw) =>
      AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.type,
    this.avatar,
    this.rating,
    this.email,
  });

  final int id;
  final String name;
  final String? phone;
  final String type; // customer | driver
  final String? avatar;
  final double? rating; // header yıldız puanı (yeni kullanıcıda 5.0)
  final String? email;

  bool get isCustomer => type == 'customer';
  bool get isDriver   => type == 'driver';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'type': type,
        'avatar': avatar,
        'rating': rating,
        'email': email,
      };

  static AuthUser fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String?) ?? '',
        phone: json['phone'] as String?,
        type: json['type'] as String,
        avatar: json['avatar'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        email: json['email'] as String?,
      );
}
