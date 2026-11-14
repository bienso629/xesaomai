import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressSuggestion {
  final String name;
  final String address;
  final String display;
  final String refId;

  const AddressSuggestion({
    required this.name,
    required this.address,
    required this.display,
    required this.refId,
  });
}

class GeocodedLocation {
  final double latitude;
  final double longitude;
  final String matchedAddress;
  final String precisionType;

  const GeocodedLocation({
    required this.latitude,
    required this.longitude,
    required this.matchedAddress,
    this.precisionType = '',
  });
}

/// Dịch vụ tự động chuyển đổi Địa chỉ sang Vĩ độ / Kinh độ (Geocoding)
/// tối ưu cho địa chỉ Việt Nam:
/// - Nhận diện tức thì chuỗi tọa độ "lat, lng" hoặc liên kết Google Maps.
/// - Gợi ý địa chỉ tiếng Việt qua Vietmap Autocomplete v4.
/// - Kết hợp Vietmap Place v4 (nếu mở khóa) và ArcGIS World Geocoder (VNM)
///   với chấm điểm độ chi tiết (PointAddress / StreetAddress / POI / Locality).
class AddressGeocoderService {
  static const String defaultVietmapKey =
      'edfac336d2c0462850d93fd5859878b1ad84b769ddfed745';
  static const String _vietmapBase = 'https://maps.vietmap.vn/api';
  static const String _arcgisUrl =
      'https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates';

  static const Set<String> _vnStopWords = {
    'duong',
    'so',
    'to',
    'kp',
    'khu',
    'pho',
    'phuong',
    'xa',
    'thi',
    'tran',
    'quan',
    'huyen',
    'thanh',
    'tinh',
    'tp',
    'vn',
    'viet',
    'nam',
    'ap',
    'thon',
  };

  /// Thử trích xuất trực tiếp tọa độ nếu người dùng dán "10.896916, 107.242164"
  /// hoặc đường dẫn Google Maps (@10.896916,107.242164 / !3d10.8969!4d107.2421).
  static GeocodedLocation? tryParseRawCoordinates(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Dạng !3d<lat>!4d<lng> trong link Google Maps chi tiết
    final bangMatch = RegExp(
      r'!3d(-?\d{1,2}\.\d{3,})!4d(-?\d{2,3}\.\d{3,})',
    ).firstMatch(text);
    if (bangMatch != null) {
      final lat = double.tryParse(bangMatch.group(1)!);
      final lng = double.tryParse(bangMatch.group(2)!);
      if (_isValidCoord(lat, lng)) {
        return GeocodedLocation(
          latitude: lat!,
          longitude: lng!,
          matchedAddress: 'Trích xuất từ liên kết bản đồ',
          precisionType: 'ExactLink',
        );
      }
    }

    // 2. Dạng @lat,lng hoặc chuỗi "lat, lng" thuần túy
    final pairMatch = RegExp(
      r'(?:@|^|\?q=|ll=)\s*(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{2,3}\.\d{3,})(?:\s|$|,|&|/)',
    ).firstMatch(text);
    if (pairMatch != null) {
      final lat = double.tryParse(pairMatch.group(1)!);
      final lng = double.tryParse(pairMatch.group(2)!);
      if (_isValidCoord(lat, lng)) {
        return GeocodedLocation(
          latitude: lat!,
          longitude: lng!,
          matchedAddress: 'Tọa độ trực tiếp',
          precisionType: 'ExactCoord',
        );
      }
    }
    return null;
  }

  static bool _isValidCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  /// Lấy danh sách gợi ý địa chỉ chuẩn từ Vietmap Autocomplete v4.
  static Future<List<AddressSuggestion>> fetchSuggestions(
    String query, {
    String apiKey = defaultVietmapKey,
    double? focusLat,
    double? focusLng,
  }) async {
    final q = query.trim();
    if (q.length < 3 || tryParseRawCoordinates(q) != null) {
      return const [];
    }
    final params = <String, String>{'apikey': apiKey, 'text': q};
    if (focusLat != null && focusLng != null) {
      params['focus'] = '$focusLat,$focusLng';
    }
    try {
      final uri = Uri.parse(
        '$_vietmapBase/autocomplete/v4',
      ).replace(queryParameters: params);
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List) return const [];
      final out = <AddressSuggestion>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final display = (item['display'] ?? '').toString().trim();
        final name = (item['name'] ?? '').toString().trim();
        final addr = (item['address'] ?? '').toString().trim();
        final refId = (item['ref_id'] ?? '').toString().trim();
        if (display.isEmpty && name.isEmpty) continue;
        out.add(
          AddressSuggestion(
            name: name.isNotEmpty ? name : display,
            address: addr,
            display: display.isNotEmpty ? display : name,
            refId: refId,
          ),
        );
        if (out.length >= 5) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Tra cứu tự động Vĩ độ & Kinh độ từ chuỗi địa chỉ tiếng Việt.
  static Future<GeocodedLocation?> geocodeAddress(
    String query, {
    String? vietmapRefId,
    String apiKey = defaultVietmapKey,
  }) async {
    final q = query.trim();
    if (q.length < 3) return null;

    // 1. Kiểm tra tọa độ trực tiếp hoặc link Google Maps
    final direct = tryParseRawCoordinates(q);
    if (direct != null) return direct;

    // 2. Nếu có refId Vietmap và key mở khóa API Place v4, ưu tiên lấy trực tiếp
    if (vietmapRefId != null && vietmapRefId.isNotEmpty) {
      final vmLoc = await _tryVietmapPlace(vietmapRefId, apiKey: apiKey);
      if (vmLoc != null) return vmLoc;
    }

    // 3. Tra cứu kết hợp ArcGIS World Geocoder (VNM) trên chuỗi gốc
    //    và chuỗi chuẩn hóa từ Vietmap Autocomplete v4.
    final ranked = <_RankedCandidate>[];

    final rawCandidates = await _queryArcGis(q);
    for (final c in rawCandidates) {
      ranked.add(_rankCandidate(c, q));
    }
    ranked.sort((a, b) => b.rankScore.compareTo(a.rankScore));

    final hasHighConfidenceExact =
        ranked.isNotEmpty &&
        ranked.first.rawScore >= 90 &&
        const {
          'PointAddress',
          'Subaddress',
          'BuildingName',
          'StreetAddress',
        }.contains(ranked.first.location.precisionType);

    if (!hasHighConfidenceExact) {
      final suggestions = await fetchSuggestions(q, apiKey: apiKey);
      if (suggestions.isNotEmpty) {
        final top = suggestions.first;
        // Nếu chưa thử Place v4 ở trên thì thử nhanh
        if ((vietmapRefId == null || vietmapRefId.isEmpty) &&
            top.refId.isNotEmpty) {
          final vmLoc = await _tryVietmapPlace(top.refId, apiKey: apiKey);
          if (vmLoc != null) return vmLoc;
        }
        if (top.display.isNotEmpty &&
            top.display.toLowerCase() != q.toLowerCase()) {
          final normCandidates = await _queryArcGis(top.display);
          for (final c in normCandidates) {
            ranked.add(_rankCandidate(c, q));
          }
          ranked.sort((a, b) => b.rankScore.compareTo(a.rankScore));
        }
      }
    }

    if (ranked.isEmpty) return null;
    return ranked.first.location;
  }

  static Future<GeocodedLocation?> _tryVietmapPlace(
    String refId, {
    required String apiKey,
  }) async {
    try {
      final uri = Uri.parse(
        '$_vietmapBase/place/v4',
      ).replace(queryParameters: {'apikey': apiKey, 'refid': refId});
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      dynamic data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is List && data.isNotEmpty) data = data.first;
      if (data is! Map) return null;
      final lat = double.tryParse('${data['lat'] ?? ''}');
      final lng = double.tryParse('${data['lng'] ?? ''}');
      if (!_isValidCoord(lat, lng)) return null;
      final disp = (data['display'] ?? data['name'] ?? '').toString().trim();
      return GeocodedLocation(
        latitude: lat!,
        longitude: lng!,
        matchedAddress: disp,
        precisionType: 'VietmapPlace',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _queryArcGis(String text) async {
    try {
      final uri = Uri.parse(_arcgisUrl).replace(
        queryParameters: {
          'SingleLine': text,
          'f': 'json',
          'countryCode': 'VNM',
          'maxLocations': '5',
          'outFields': 'Match_addr,Addr_type',
        },
      );
      final res = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return const [];
      final cands = decoded['candidates'];
      if (cands is! List) return const [];
      return cands
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static _RankedCandidate _rankCandidate(
    Map<String, dynamic> c,
    String userQuery,
  ) {
    final locMap = c['location'] is Map ? c['location'] as Map : const {};
    final lat = double.tryParse('${locMap['y'] ?? ''}');
    final lng = double.tryParse('${locMap['x'] ?? ''}');
    final rawScore = double.tryParse('${c['score'] ?? 0}') ?? 0.0;
    final attrs = c['attributes'] is Map ? c['attributes'] as Map : const {};
    final addrType = (attrs['Addr_type'] ?? '').toString();
    final matchedAddr = (c['address'] ?? attrs['Match_addr'] ?? '')
        .toString()
        .trim();

    if (!_isValidCoord(lat, lng)) {
      return _RankedCandidate(
        location: const GeocodedLocation(
          latitude: 0,
          longitude: 0,
          matchedAddress: '',
        ),
        rawScore: -1,
        rankScore: -999,
      );
    }

    final uTokens = _normalizeTokens(userQuery);
    final aTokens = _normalizeTokens(matchedAddr);
    final overlapCount = uTokens.intersection(aTokens).length;
    final overlapRatio = uTokens.isEmpty ? 0.0 : overlapCount / uTokens.length;

    double bonus = 0.0;
    switch (addrType) {
      case 'PointAddress':
      case 'Subaddress':
      case 'BuildingName':
        bonus = 18.0;
        break;
      case 'StreetAddress':
      case 'StreetInt':
      case 'StreetName':
      case 'DistanceMarker':
        bonus = 12.0;
        break;
      case 'POI':
        bonus = overlapRatio >= 0.4 ? 16.0 : -5.0;
        break;
      case 'Neighborhood':
      case 'District':
        bonus = 5.0;
        break;
      default:
        bonus = 0.0;
    }

    return _RankedCandidate(
      location: GeocodedLocation(
        latitude: lat!,
        longitude: lng!,
        matchedAddress: matchedAddr,
        precisionType: addrType,
      ),
      rawScore: rawScore,
      rankScore: rawScore + bonus + (overlapRatio * 6.0),
    );
  }

  static Set<String> _normalizeTokens(String input) {
    final lower = _removeVietnameseDiacritics(input.toLowerCase());
    final matches = RegExp(r'[a-z0-9]+').allMatches(lower);
    final out = <String>{};
    for (final m in matches) {
      final w = m.group(0)!;
      if (w.length >= 2 && !_vnStopWords.contains(w)) {
        out.add(w);
      }
    }
    return out;
  }

  static String _removeVietnameseDiacritics(String str) {
    const withDia =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const withoutDia =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      final ch = str[i];
      final idx = withDia.indexOf(ch);
      buf.write(idx >= 0 ? withoutDia[idx] : ch);
    }
    return buf.toString();
  }
}

class _RankedCandidate {
  final GeocodedLocation location;
  final double rawScore;
  final double rankScore;

  const _RankedCandidate({
    required this.location,
    required this.rawScore,
    required this.rankScore,
  });
}
