import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// WebRTC sesli görüşme API katmanı — `/calls/{publicId}/*`.
/// Web CallController ile aynı protokol (start/accept/end/state/signal/signals).
class CallRepository {
  CallRepository(this._api);
  final ApiClient _api;

  Future<Map<String, dynamic>> start(String publicId) =>
      _api.postJson('/calls/$publicId/start');

  Future<Map<String, dynamic>> accept(String publicId) =>
      _api.postJson('/calls/$publicId/accept');

  Future<Map<String, dynamic>> end(String publicId) =>
      _api.postJson('/calls/$publicId/end');

  Future<Map<String, dynamic>> state(String publicId) =>
      _api.getJson('/calls/$publicId/state');

  Future<void> pushSignal(String publicId, String type, Map<String, dynamic> payload) =>
      _api.postJson('/calls/$publicId/signal', body: {'type': type, 'payload': payload});

  Future<List<Map<String, dynamic>>> pullSignals(String publicId, int sinceId) async {
    final res = await _api.getJson('/calls/$publicId/signals', query: {'since_id': sinceId});
    return (res['signals'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }
}

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(ref.watch(apiClientProvider));
});
