import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

class AddressPickResult {
  const AddressPickResult({
    required this.address,
    required this.location,
  });

  final String address;
  final LatLng location;
}

class AddressPickerScreen extends ConsumerStatefulWidget {
  const AddressPickerScreen({super.key, this.initialAddress});

  final String? initialAddress;

  @override
  ConsumerState<AddressPickerScreen> createState() =>
      _AddressPickerScreenState();
}

class _AddressPickerScreenState extends ConsumerState<AddressPickerScreen> {
  final _search = TextEditingController();
  final _dio = Dio();
  Timer? _debounce;
  GoogleMapController? _map;
  LatLng _mapCenter = const LatLng(6.5244, 3.3792);
  LatLng _selected = const LatLng(6.5244, 3.3792);
  String _selectedAddress = '';
  bool _loading = false;
  bool _searching = false;
  bool _ready = false;
  bool _locationPermissionGranted = false;
  bool _updatingFromCamera = false;
  Timer? _cameraDebounce;
  List<_PlaceResult> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _cameraDebounce?.cancel();
    _search.dispose();
    _map?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _searchPlaces(value);
    });
  }

  Future<void> _loadCurrentLocation() async {
    try {
      debugPrint('📍 Address picker: checking device location...');
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        debugPrint('📍 Address picker: location services are disabled.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('📍 Address picker: location permission denied.');
        return;
      }

      if (mounted) {
        setState(() => _locationPermissionGranted = true);
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      final pos = lastKnown ?? await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final current = LatLng(pos.latitude, pos.longitude);
      debugPrint(
        '📍 Address picker: current location = ${current.latitude}, ${current.longitude}',
      );
      setState(() {
        _selected = current;
        _mapCenter = current;
      });
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(current, 16));
      final address = await _reverseGeocode(current);
      if (mounted) setState(() => _selectedAddress = address);
    } catch (_) {
      // Silently fall back to the default Lagos camera if location fails.
      debugPrint('📍 Address picker: failed to load current location.');
    }
  }

  Future<void> _searchPlaces([String? query]) async {
    final text = (query ?? _search.text).trim();
    final key = await ref.read(googleApiKeyProvider.future);
    if (text.isEmpty || key == null || key.isEmpty) return;
    setState(() => _searching = true);
    try {
      final nearbyBias = '${_mapCenter.latitude},${_mapCenter.longitude}';
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
        queryParameters: {
          'query': text,
          'location': nearbyBias,
          'radius': 8000,
          'key': key,
        },
      );
      final items = (res.data['results'] as List<dynamic>? ?? const [])
          .map((e) => _PlaceResult.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => _results = items);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<String> _reverseGeocode(LatLng latLng) async {
    final key = await ref.read(googleApiKeyProvider.future);
    if (key == null || key.isEmpty) {
      return '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
    }
    final res = await _dio.get(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'latlng': '${latLng.latitude},${latLng.longitude}',
        'key': key,
      },
    );
    final results = res.data['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty) {
      return '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
    }
    return (results.first as Map<String, dynamic>)['formatted_address'] as String? ??
        '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
  }

  Future<void> _selectPlace(_PlaceResult place) async {
    final pos = LatLng(place.lat, place.lng);
    final address = place.address;
    debugPrint(
      '📍 Address picker: selected search result "${place.name}" -> ${pos.latitude}, ${pos.longitude}',
    );
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = pos;
      _selectedAddress = address;
      _search.text = place.name;
      _results = const [];
    });
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  Future<void> _pickFromMap(LatLng latLng) async {
    setState(() => _loading = true);
    try {
      final address = await _reverseGeocode(latLng);
      setState(() {
        _selected = latLng;
        _selectedAddress = address;
      });
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateFromCamera() async {
    if (_updatingFromCamera) return;

    final center = _mapCenter;
    final movedMeters = Geolocator.distanceBetween(
      _selected.latitude,
      _selected.longitude,
      center.latitude,
      center.longitude,
    );
    if (movedMeters < 25) return;

    _updatingFromCamera = true;
    try {
      final address = await _reverseGeocode(center);
      if (!mounted) return;
      setState(() {
        _selected = center;
        _selectedAddress = address;
      });
    } finally {
      _updatingFromCamera = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(6.5244, 3.3792),
                  zoom: 12.5,
                ),
                onMapCreated: (c) {
                  _map = c;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _map?.animateCamera(
                      CameraUpdate.newLatLngZoom(_selected, 16),
                    );
                  });
                },
                onCameraMove: (position) {
                  _mapCenter = position.target;
                },
                onCameraIdle: () {
                  _cameraDebounce?.cancel();
                  _cameraDebounce = Timer(
                    const Duration(milliseconds: 250),
                    _updateFromCamera,
                  );
                },
                onTap: _pickFromMap,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
                myLocationEnabled: _locationPermissionGranted,
                markers: const {},
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: Image(
                      image: AssetImage('assets/images/pin.png'),
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSizes.md,
              left: AppSizes.md,
              right: AppSizes.md,
              child: AnimatedSlide(
                offset: _ready ? Offset.zero : const Offset(0, -0.06),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _ready ? 1 : 0,
                  duration: const Duration(milliseconds: 320),
                  child: AppCard(
                    shadow: true,
                      onTap: _selectedAddress.isEmpty
                          ? null
                          : () async {
                              final current = _selected;
                              await _map?.animateCamera(
                                CameraUpdate.newLatLngZoom(current, 16),
                              );
                            },
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _search,
                                textInputAction: TextInputAction.search,
                                style: AppText.bodyStrong,
                                decoration: InputDecoration(
                                  hintText: 'Search address or landmark',
                                  // helperText:
                                  //     'Search first, then tap a result or drag the map',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _searching
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : IconButton(
                                          onPressed: () => _searchPlaces(),
                                          icon: const Icon(
                                              Icons.arrow_forward_rounded),
                                        ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onTap: () {
                                  _search.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: _search.text.length,
                                  );
                                },
                                onChanged: _onSearchChanged,
                                onSubmitted: (_) => _searchPlaces(),
                              ),
                            ),
                            const SizedBox(width: AppSizes.sm),
                            IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _results = const []);
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _results.isNotEmpty
                              ? Padding(
                                  key: const ValueKey('results'),
                                  padding: const EdgeInsets.only(
                                      top: AppSizes.sm),
                                  child: SizedBox(
                                    height: 180,
                                    child: ListView.separated(
                                      itemCount: _results.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: AppSizes.sm),
                                      itemBuilder: (context, index) {
                                        final place = _results[index];
                                        return TweenAnimationBuilder<double>(
                                          key: ValueKey(place.name),
                                          tween: Tween(begin: 0.96, end: 1),
                                          duration: Duration(
                                              milliseconds: 220 + index * 18),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, scale, child) =>
                                              Transform.scale(
                                            scale: scale,
                                            child: child,
                                          ),
                                          child: AppCard(
                                            onTap: () async {
                                              await _selectPlace(place);
                                            },
                                            padding: const EdgeInsets.all(
                                                AppSizes.md),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                    Icons.place_outlined),
                                                const SizedBox(
                                                    width: AppSizes.md),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(place.name,
                                                          style: AppText
                                                              .bodyStrong),
                                                      const SizedBox(height: 4),
                                                      Text(place.address,
                                                          style:
                                                              AppText.caption),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        'Tap to place pin here',
                                                        style: AppText.caption.copyWith(
                                                          color: AppColors.textTertiary,
                                                        ),
                                                      ),
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
                                )
                              : const SizedBox(key: ValueKey('empty')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppSizes.md,
              right: AppSizes.md,
              bottom: AppSizes.md,
              child: AnimatedOpacity(
                opacity: _ready ? 1 : 0,
                duration: const Duration(milliseconds: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppCard(
                      shadow: true,
                      onTap: _selectedAddress.isEmpty
                          ? null
                          : () async {
                              final current = _selected;
                              await _map?.animateCamera(
                                CameraUpdate.newLatLngZoom(current, 16),
                              );
                            },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final fade = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOut,
                          );
                          return FadeTransition(
                            opacity: fade,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: _selectedAddress.isNotEmpty
                            ? Column(
                                key: ValueKey(_selectedAddress),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.my_location_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _loading ? "Updating address..." : "Selected address",
                                          style: AppText.label,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _selectedAddress,
                                    style: AppText.bodyStrong,
                                  ),
                                ],
                              )
                            : Column(
                                key: const ValueKey('empty-address'),
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.place_outlined, color: AppColors.textTertiary, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "Tap a result or drag the map to choose an address",
                                          style: AppText.bodyStrong.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSizes.sm),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    const SizedBox(height: AppSizes.sm),
                    AppButton(
                      label: "Continue",
                      onPressed: _selectedAddress.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                                AddressPickResult(
                                  address: _selectedAddress,
                                  location: _selected,
                                ),
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),)
    );
  }
}

class _PlaceResult {
  const _PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String name;
  final String address;
  final double lat;
  final double lng;

  static _PlaceResult fromJson(Map<String, dynamic> json) => _PlaceResult(
        name: json['name'] as String? ?? 'Selected place',
        address: json['formatted_address'] as String? ??
            json['vicinity'] as String? ??
            '',
        lat: (((json['geometry'] as Map<String, dynamic>)['location']
                    as Map<String, dynamic>)['lat'] as num? ??
                0)
            .toDouble(),
        lng: (((json['geometry'] as Map<String, dynamic>)['location']
                    as Map<String, dynamic>)['lng'] as num? ??
                0)
            .toDouble(),
  );
}








