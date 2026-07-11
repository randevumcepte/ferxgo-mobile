import 'package:flutter/foundation.dart';

import '../../../shared/models/negotiation.dart';
import 'nearby_driver.dart';

/// `/customer/ride-requests/{publicId}` polling response'unun parse hali.
@immutable
class RideStatus {
  const RideStatus({
    required this.status,
    required this.rejectionCount,
    required this.currentIndex,
    required this.totalCandidates,
    required this.secondsRemaining,
    required this.offeredDriver,
    required this.acceptedDriver,
    required this.ridePublicId,
    required this.arrivedAt,
    required this.customerConfirmedAt,
    required this.noShowAt,
    required this.negotiation,
    required this.isFavoriteWave,
    required this.reconfirmRequiredAt,
    required this.customerReconfirmedAt,
  });

  /// pending | pool_expanded | awaiting_customer_reconfirm | accepted | expired | cancelled | exhausted
  final String status;
  final int rejectionCount;
  final int currentIndex;
  final int totalCandidates;
  final int secondsRemaining;
  final NearbyDriver? offeredDriver;
  final NearbyDriver? acceptedDriver;
  final String? ridePublicId;
  final DateTime? arrivedAt;
  final DateTime? customerConfirmedAt;
  final DateTime? noShowAt;
  final Negotiation? negotiation;

  /// Auto ("Hadi Gidelim") dağıtımı — favori dalgası mı, yakın havuz mu
  final bool isFavoriteWave;
  final DateTime? reconfirmRequiredAt;
  final DateTime? customerReconfirmedAt;

  bool get isPending   => status == 'pending';
  bool get isAccepted  => status == 'accepted';
  bool get isExpired   => status == 'expired';
  bool get isCancelled => status == 'cancelled';
  bool get isExhausted => status == 'exhausted';
  bool get isTerminal  => isExpired || isCancelled || isExhausted;

  /// Auto/havuz: teklif online favori/yakın sürücülere yayıldı, cevap bekleniyor
  bool get isPoolExpanded => status == 'pool_expanded';

  /// Eşleşen üye sürücü bulundu, yolcunun onayı/reddi bekleniyor
  bool get isAwaitingReconfirm => status == 'awaiting_customer_reconfirm';

  /// "Sürücü aranıyor" ekranı gösterilecek durumlar
  bool get isSearching => isPending || isPoolExpanded;

  /// Sürücü vardı, müşteri henüz "gördüm" demedi
  bool get awaitingCustomerConfirm =>
      isAccepted && arrivedAt != null && customerConfirmedAt == null;

  /// Sürücü karşı teklif verdi, yolcunun kabul/karşı-teklif/vazgeç kararı bekleniyor
  bool get awaitingCustomerPriceDecision =>
      isPending && (negotiation?.awaitingCustomer ?? false);

  static RideStatus fromJson(Map<String, dynamic> json, {required dynamic fallbackPosition}) {
    NearbyDriver? parseDriver(Object? raw) {
      if (raw is! Map) return null;
      return NearbyDriver.fromJson(Map<String, dynamic>.from(raw), fallback: fallbackPosition);
    }

    return RideStatus(
      status: json['status'] as String? ?? 'pending',
      rejectionCount: ((json['rejection_count'] as num?) ?? 0).toInt(),
      currentIndex: ((json['current_index'] as num?) ?? 0).toInt(),
      totalCandidates: ((json['total_candidates'] as num?) ?? 0).toInt(),
      secondsRemaining: ((json['seconds_remaining'] as num?) ?? 0).toInt(),
      offeredDriver: parseDriver(json['offered_driver']),
      acceptedDriver: parseDriver(json['accepted_driver']),
      ridePublicId: json['ride_public_id'] as String?,
      arrivedAt: _parseDate(json['arrived_at']),
      customerConfirmedAt: _parseDate(json['customer_confirmed_at']),
      noShowAt: _parseDate(json['no_show_at']),
      negotiation: Negotiation.fromJson(json['negotiation']),
      isFavoriteWave: (json['is_favorite_wave'] as bool?) ?? false,
      reconfirmRequiredAt: _parseDate(json['reconfirm_required_at']),
      customerReconfirmedAt: _parseDate(json['customer_reconfirmed_at']),
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }
}

@immutable
class RideMessage {
  const RideMessage({
    required this.id,
    required this.sender, // customer | driver | system
    required this.body,
    required this.createdAt,
  });

  final int id;
  final String sender;
  final String body;
  final DateTime createdAt;

  bool get isCustomer => sender == 'customer';
  bool get isDriver   => sender == 'driver';
  bool get isSystem   => sender == 'system';

  static RideMessage fromJson(Map<String, dynamic> json) => RideMessage(
        id: (json['id'] as num).toInt(),
        sender: json['sender'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
