import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Kết quả chọn điểm trên bản đồ.
class MapPointPickResult {
  final double latitude;
  final double longitude;

  /// Địa chỉ đọc được từ Vietmap (reverse hoặc kết quả tìm kiếm). Có thể rỗng.
  final String address;

  const MapPointPickResult({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

/// Hộp thoại chọn tọa độ trên bản đồ Vietmap.
///
/// - Chạm lên bản đồ để đặt điểm (dùng được ngay với key hiện tại).
/// - Ô tìm kiếm: gợi ý địa điểm qua Vietmap autocomplete, lấy tọa độ qua
///   Vietmap Place. Nếu key chưa được mở API Place (HTTP 423) thì báo rõ và
///   hướng dẫn chạm trực tiếp lên bản đồ. Khi key được mở, phần này tự chạy.
Future<MapPointPickResult?> showMapPointPicker(
  BuildContext context, {
  required String apiKey,
  required String title,
  double? initialLat,
  double? initialLng,
  int? radiusM,
  String initialQuery = '',
}) {
  return showDialog<MapPointPickResult>(
    context: context,
    builder: (_) => _MapPointPickerDialog(
      apiKey: apiKey,
      title: title,
      initialLat: initialLat,
      initialLng: initialLng,
      radiusM: radiusM,
      initialQuery: initialQuery,
    ),
  );
}

class _MapPointPickerDialog extends StatefulWidget {
  final String apiKey;
  final String title;
  final double? initialLat;
  final double? initialLng;
  final int? radiusM;
  final String initialQuery;

  const _MapPointPickerDialog({
    required this.apiKey,
    required this.title,
    this.initialLat,
    this.initialLng,
    this.radiusM,
    this.initialQuery = '',
  });

  @override
  State<_MapPointPickerDialog> createState() => _MapPointPickerDialogState();
}

class _MapPointPickerDialogState extends State<_MapPointPickerDialog> {
  static const _base = 'https://maps.vietmap.vn/api';
  // Trung tâm Việt Nam, dùng khi chưa có tọa độ ban đầu
  static const _defaultCenter = LatLng(16.0, 106.5);

  final _mapCtrl = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  LatLng? _point;
  String _address = '';
  bool _reverseLoading = false;
  int _reverseSeq = 0;

  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String? _searchMessage;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.initialQuery;
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    if (lat != null && lng != null) {
      _point = LatLng(lat, lng);
      _reverse(_point!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- Vietmap

  Future<dynamic> _get(String path, Map<String, String> params) async {
    final uri = Uri.parse('$_base/$path')
        .replace(queryParameters: {'apikey': widget.apiKey, ...params});
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode == 423) throw const _PlaceLimited();
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<void> _reverse(LatLng p) async {
    final seq = ++_reverseSeq;
    setState(() => _reverseLoading = true);
    String addr = '';
    try {
      final data = await _get('reverse/v3', {
        'lat': p.latitude.toString(),
        'lng': p.longitude.toString(),
      });
      if (data is List && data.isNotEmpty && data.first is Map) {
        addr = (data.first['display'] ?? data.first['address'] ?? '').toString().trim();
      }
    } catch (_) {
      addr = '';
    }
    if (!mounted || seq != _reverseSeq) return;
    setState(() {
      _address = addr;
      _reverseLoading = false;
    });
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 3) {
      setState(() {
        _results = [];
        _searchMessage = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    final params = <String, String>{'text': q};
    final c = _point ?? (widget.initialLat != null && widget.initialLng != null
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : null);
    if (c != null) params['focus'] = '${c.latitude},${c.longitude}';
    try {
      final data = await _get('autocomplete/v4', params);
      final list = (data is List ? data : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['ref_id'] ?? '').toString().isNotEmpty)
          .take(8)
          .toList();
      if (!mounted || _searchCtrl.text.trim() != q) return;
      setState(() {
        _results = list;
        _searching = false;
        _searchMessage = list.isEmpty ? 'Không tìm thấy địa điểm nào.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
        _searchMessage = 'Không tìm kiếm được, hãy chạm trực tiếp lên bản đồ.';
      });
    }
  }

  double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());

  Future<void> _selectResult(Map<String, dynamic> r) async {
    final display = (r['display'] ?? r['name'] ?? '').toString().trim();
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    try {
      var data = await _get('place/v4', {'refid': r['ref_id'].toString()});
      if (data is List && data.isNotEmpty) data = data.first;
      final lat = data is Map ? _num(data['lat']) : null;
      final lng = data is Map ? _num(data['lng']) : null;
      if (lat == null || lng == null) {
        throw Exception('Không có tọa độ');
      }
      final p = LatLng(lat, lng);
      if (!mounted) return;
      setState(() {
        _point = p;
        _address = display;
        _results = [];
        _searching = false;
      });
      _mapCtrl.move(p, 16.5);
    } on _PlaceLimited {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchMessage =
            'Key Vietmap hiện chưa được mở API Place nên chưa lấy được tọa độ từ kết quả tìm kiếm. '
            'Hãy kéo bản đồ tới "$display" rồi chạm vào đúng vị trí.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchMessage = 'Không lấy được tọa độ của địa điểm này, hãy chạm trực tiếp lên bản đồ.';
      });
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final p = _point;
    final radius = (widget.radiusM ?? 100).toDouble();
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Icon(Icons.map_outlined, color: Colors.blue.shade700, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            tooltip: 'Đóng',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: (v) {
                if (v.trim().length >= 3) _search(v.trim());
              },
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Tìm địa điểm (VD: Xi măng Bỉm Sơn)',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            if (_searchMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_searchMessage!,
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 400,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: FlutterMap(
                      mapController: _mapCtrl,
                      options: MapOptions(
                        initialCenter: p ?? _defaultCenter,
                        initialZoom: p != null ? 16 : 5.5,
                        onTap: (_, latLng) {
                          setState(() {
                            _point = latLng;
                            _results = [];
                          });
                          _reverse(latLng);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}@2x.png?apikey=${widget.apiKey}',
                        ),
                        if (p != null)
                          CircleLayer(circles: [
                            CircleMarker(
                              point: p,
                              radius: radius,
                              useRadiusInMeter: true,
                              color: Colors.blue.withValues(alpha: 0.12),
                              borderStrokeWidth: 2,
                              borderColor: Colors.blue.shade700,
                            ),
                          ]),
                        if (p != null)
                          MarkerLayer(markers: [
                            Marker(
                              point: p,
                              width: 40,
                              height: 40,
                              alignment: Alignment.topCenter,
                              child: Icon(Icons.location_on,
                                  size: 40, color: Colors.red.shade700),
                            ),
                          ]),
                      ],
                    ),
                  ),
                  if (_results.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Material(
                        elevation: 4,
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _results.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, i) {
                              final r = _results[i];
                              final name = (r['name'] ?? '').toString();
                              final addr = (r['address'] ?? '').toString();
                              return InkWell(
                                onTap: () => _selectResult(r),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(Icons.place_outlined,
                                          size: 16, color: Colors.blue.shade700),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(name,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 13)),
                                            if (addr.isNotEmpty)
                                              Text(addr,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              p == null
                  ? 'Chạm lên bản đồ để chọn đúng vị trí (cổng nhà máy, cảng, kho...).'
                  : 'Vĩ độ ${p.latitude.toStringAsFixed(6)}, Kinh độ ${p.longitude.toStringAsFixed(6)}'
                      ' – vòng tròn là bán kính ${radius.toStringAsFixed(0)} m',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
            if (p != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _reverseLoading
                      ? 'Đang đọc địa chỉ...'
                      : (_address.isEmpty ? 'Không đọc được địa chỉ' : _address),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Dùng tọa độ này'),
          onPressed: p == null
              ? null
              : () => Navigator.of(context).pop(MapPointPickResult(
                    latitude: double.parse(p.latitude.toStringAsFixed(6)),
                    longitude: double.parse(p.longitude.toStringAsFixed(6)),
                    address: _reverseLoading ? '' : _address,
                  )),
        ),
      ],
    );
  }
}

class _PlaceLimited implements Exception {
  const _PlaceLimited();
}
