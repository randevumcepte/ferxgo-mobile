/// Backend bazen sayısal alanları String olarak döndürür (ör. Laravel decimal cast
/// "5.00" döndürür, `year_of_manufacture` varchar olabilir). Doğrudan `as num?` cast'i
/// bu durumda "type 'String' is not a subtype of type 'num?'" hatası verir.
///
/// Bu yardımcılar String / num / null hepsini güvenle sayıya çevirir — tüm modeller
/// JSON parse'ında bunları kullanmalı ki tip uyuşmazlığı çökme yaratmasın.
library;

num? asNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

double? asDoubleOrNull(Object? v) => asNum(v)?.toDouble();

int? asIntOrNull(Object? v) => asNum(v)?.toInt();

double asDoubleOr(Object? v, double fallback) => asNum(v)?.toDouble() ?? fallback;

int asIntOr(Object? v, int fallback) => asNum(v)?.toInt() ?? fallback;
