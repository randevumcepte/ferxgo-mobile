import 'package:flutter/foundation.dart';

import '../../core/util/json_num.dart';

/// Fiyat pazarlığı bloğu (inDrive tarzı) — backend `NegotiationPayload` trait'inin
/// Flutter karşılığı. Hem müşteri (RideStatus) hem sürücü (offer) payload'ında
/// aynı `negotiation` anahtarı altında gelir. Pazarlıksız eski talepte null olur.
@immutable
class Negotiation {
  const Negotiation({
    required this.state,
    required this.round,
    required this.maxRounds,
    required this.roundsLeft,
    required this.suggestedFare,
    required this.customerOfferFare,
    required this.driverCounterFare,
    required this.agreedFare,
    required this.currentPrice,
    required this.minFare,
    required this.maxFare,
    required this.awaiting,
    required this.currency,
  });

  /// null | customer_offered | driver_countered | agreed | rejected
  final String? state;
  final int round;
  final int maxRounds;
  final int roundsLeft;
  final double? suggestedFare;
  final double? customerOfferFare;
  final double? driverCounterFare;
  final double? agreedFare;
  final double? currentPrice;
  final double? minFare;
  final double? maxFare;

  /// Sıra kimde: 'customer' → yolcu karar verecek, 'driver' → sürücü karar verecek
  final String? awaiting;
  final String currency;

  bool get isDriverCountered => state == 'driver_countered';
  bool get isCustomerOffered => state == 'customer_offered';
  bool get isAgreed => state == 'agreed';
  bool get awaitingCustomer => awaiting == 'customer';
  bool get awaitingDriver => awaiting == 'driver';
  bool get hasRoundsLeft => roundsLeft > 0;

  static Negotiation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return Negotiation(
      state: json['state'] as String?,
      round: asIntOr(json['round'], 0),
      maxRounds: asIntOr(json['max_rounds'], 4),
      roundsLeft: asIntOr(json['rounds_left'], 0),
      suggestedFare: asDoubleOrNull(json['suggested_fare']),
      customerOfferFare: asDoubleOrNull(json['customer_offer_fare']),
      driverCounterFare: asDoubleOrNull(json['driver_counter_fare']),
      agreedFare: asDoubleOrNull(json['agreed_fare']),
      currentPrice: asDoubleOrNull(json['current_price']),
      minFare: asDoubleOrNull(json['min_fare']),
      maxFare: asDoubleOrNull(json['max_fare']),
      awaiting: json['awaiting'] as String?,
      currency: (json['currency'] as String?) ?? 'TRY',
    );
  }
}
