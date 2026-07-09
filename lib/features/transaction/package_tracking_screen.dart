import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/tracking_dto.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/animated_refresh_icon_button.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'application/transactions_provider.dart';

/// Track Package — real backend-driven tracking (no fake movement, no
/// hardcoded route). Shows the buyer's delivery destination and the seller's
/// last self-reported position (a manual update, not a live GPS feed — see
/// [TransactionRepository.updateDeliveryLocation]), with a route drawn only
/// when the backend actually computed one (`GET /transactions/:id/tracking`).
class PackageTrackingScreen extends ConsumerStatefulWidget {
  const PackageTrackingScreen({super.key, required this.tx});

  final EscrowTransaction tx;

  @override
  ConsumerState<PackageTrackingScreen> createState() =>
      _PackageTrackingScreenState();
}

class _PackageTrackingScreenState extends ConsumerState<PackageTrackingScreen> {
  /// Raw backend status values in which the seller is actually en route —
  /// matches the backend's own `ACTIVE_DELIVERY_STATUSES` gate.
  static const _activeStatuses = {'in_transit', 'out_for_delivery'};
  static const _autoRefreshInterval = Duration(seconds: 45);

  Timer? _autoRefreshTimer;
  bool _updatingLocation = false;

  String get _id => widget.tx.id;

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  /// Starts a gentle 45s refresh only while the delivery is actually active,
  /// and only once (not re-armed every rebuild). Stops itself the moment the
  /// status leaves the active set, and always stops on dispose.
  void _scheduleAutoRefresh(TransactionTracking tracking) {
    final active = _activeStatuses.contains(tracking.status);
    if (!active) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      return;
    }
    _autoRefreshTimer ??= Timer.periodic(_autoRefreshInterval, (_) {
      if (mounted) ref.invalidate(trackingProvider(_id));
    });
  }

  void _refresh() => ref.invalidate(trackingProvider(_id));

  Future<void> _updateMyLocation() async {
    if (_updatingLocation) return;
    setState(() => _updatingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          AppSnackbar.error(
            context,
            'Turn on location services to share your delivery location.',
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          AppSnackbar.error(
            context,
            'Location permission denied. Enable it in Settings to share your delivery location.',
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await ref
          .read(transactionRepositoryProvider)
          .updateDeliveryLocation(
            _id,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
      if (!mounted) return;
      AppSnackbar.success(context, 'Delivery location updated.');
      ref.invalidate(trackingProvider(_id));
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not update your location. Please try again.',
          onRetry: _updateMyLocation,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackingAsync = ref.watch(trackingProvider(_id));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            // Keep the last map on screen while a refresh is in flight (the 45s
            // auto-refresh + manual refresh both invalidate the provider) so the
            // map, markers and cached icons never flash/reload.
            child: trackingAsync.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const _MapArea(
                child: AppCenteredLoader(
                  message: 'Preparing tracking information…',
                ),
              ),
              error: (e, _) => _MapArea(
                child: _MessageCard(
                  icon: Icons.wifi_off_rounded,
                  title: 'Could not load tracking',
                  message: 'Check your connection and try again.',
                  action: AppButton(
                    label: 'Retry',
                    variant: AppButtonVariant.outline,
                    expand: false,
                    onPressed: _refresh,
                  ),
                ),
              ),
              data: (tracking) {
                _scheduleAutoRefresh(tracking);
                if (!tracking.hasBuyerLocation) {
                  return const _MapArea(
                    child: _MessageCard(
                      icon: Icons.location_off_outlined,
                      title: 'Tracking not available',
                      message:
                          'Tracking location is not available for this transaction.',
                    ),
                  );
                }
                return _TrackingMapView(tracking: tracking);
              },
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.sm,
                AppSizes.md,
                0,
              ),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('Track package', style: AppText.title),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (trackingAsync.hasValue)
            Align(
              alignment: Alignment.bottomCenter,
              child: _StatusSheet(
                tracking: trackingAsync.value!,
                updatingLocation: _updatingLocation,
                // A refetch is in flight (manual refresh or the 45s auto-poll)
                // while the cached map/sheet stay on screen — spins the Refresh
                // location icon without blocking the whole screen.
                refreshing: trackingAsync.isLoading,
                onRefresh: _refresh,
                onUpdateMyLocation: _updateMyLocation,
              ),
            ),
        ],
      ),
    );
  }
}

/// Neutral background behind the loading/error/empty placeholders, so nothing
/// ever reads as a broken or blank map. Centers within the safe (non-notch/
/// status-bar) area — this sits behind `Positioned.fill` in a `Stack` whose
/// full bounds include the area under the status bar, so centering on the
/// raw bounds instead of the safe area visually skews the content upward.
class _MapArea extends StatelessWidget {
  const _MapArea({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceMuted,
      child: SafeArea(child: Center(child: child)),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppColors.textTertiary),
            const SizedBox(height: AppSizes.md),
            Text(title, style: AppText.bodyStrong, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(message, style: AppText.caption, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSizes.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The real map: buyer destination always shown, seller marker only if
/// reported, route polyline only when the backend actually returned one.
/// Fits the camera to whatever markers exist exactly once per data change
/// (not on every rebuild) so it never flickers/re-animates needlessly.
class _TrackingMapView extends ConsumerStatefulWidget {
  const _TrackingMapView({required this.tracking});

  final TransactionTracking tracking;

  @override
  ConsumerState<_TrackingMapView> createState() => _TrackingMapViewState();
}

class _TrackingMapViewState extends ConsumerState<_TrackingMapView>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _map;

  // Custom marker icons — seller = delivery/driver asset (its opaque white
  // background is stripped so only the pin shows), buyer = destination pin.
  // Loaded once and cached; null until loaded, or if an asset fails, in which
  // case we fall back to a default hued marker so the map never breaks.
  BitmapDescriptor? _sellerIcon;
  BitmapDescriptor? _buyerIcon;
  bool _iconsRequested = false;

  // Lightweight, vsync-throttled pulse for the seller's live position. Drives
  // ONLY the pulse Circle (via AnimatedBuilder below) — never the marker icons
  // or polyline — so it never causes marker flicker or a full map rebuild.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  // Route polyline state. We prefer the backend route, else fetch a route-wise
  // path from Google Directions client-side, cached by coordinate key so it's
  // fetched only when the seller/buyer point actually changes — not per build,
  // and not on a refresh unless the location moved.
  final Dio _dio = Dio();
  List<LatLng> _routePoints = const [];
  String? _routeKey;
  bool _routeFailed = false;

  @override
  void initState() {
    super.initState();
    _ensureRoute();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _dio.close();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iconsRequested) return; // load exactly once
    _iconsRequested = true;
    _loadMarkerIcons();
  }

  Future<void> _loadMarkerIcons() async {
    final config = createLocalImageConfiguration(context);
    // Seller: strip the asset's opaque white square so only the clean pin shows.
    final seller = await _loadTransparentPinMarker(
      'assets/images/tracking.png',
      logicalWidth: 58,
    );
    if (seller != null && mounted) setState(() => _sellerIcon = seller);
    // Buyer: pin.png already ships transparent → use it directly.
    try {
      final icon = await BitmapDescriptor.asset(
        config,
        'assets/images/pin.png',
        width: 44,
      );
      if (mounted) setState(() => _buyerIcon = icon);
    } catch (_) {
      // Keep null → default marker fallback.
    }
  }

  String _keyFor(TransactionTracking t) =>
      '${t.buyerLocation?.latitude},${t.buyerLocation?.longitude},'
      '${t.sellerCurrentLocation?.latitude},${t.sellerCurrentLocation?.longitude}';

  @override
  void didUpdateWidget(covariant _TrackingMapView old) {
    super.didUpdateWidget(old);
    if (_keyFor(widget.tracking) != _keyFor(old.tracking)) {
      _fitCamera();
      _ensureRoute();
    }
  }

  /// Builds the route polyline for the current seller→buyer points. Prefers a
  /// backend-provided route; otherwise fetches a route-wise path from Google
  /// Directions client-side. Cached by coordinate key → no repeat/per-build
  /// calls; only re-fetches when the location actually changes.
  Future<void> _ensureRoute() async {
    final buyer = widget.tracking.buyerLocation;
    final seller = widget.tracking.sellerCurrentLocation;
    if (buyer == null || seller == null) {
      _routeKey = null;
      if (_routePoints.isNotEmpty || _routeFailed) {
        setState(() {
          _routePoints = const [];
          _routeFailed = false;
        });
      }
      return;
    }
    final key =
        '${seller.latitude},${seller.longitude}>'
        '${buyer.latitude},${buyer.longitude}';
    if (key == _routeKey) return; // already have (or are fetching) this route
    _routeKey = key;

    // Prefer a backend-provided route polyline when present.
    final backend = widget.tracking.route;
    if (backend != null && backend.polyline.isNotEmpty) {
      final pts = _decodePolyline(backend.polyline);
      if (mounted) {
        setState(() {
          _routePoints = pts;
          _routeFailed = false;
        });
      }
      return;
    }

    // Otherwise fetch a route-wise polyline from Google Directions client-side.
    try {
      final apiKey = await ref.read(googleApiKeyProvider.future);
      if (apiKey == null || apiKey.isEmpty) throw StateError('no key');
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${seller.latitude},${seller.longitude}',
          'destination': '${buyer.latitude},${buyer.longitude}',
          'mode': 'driving',
          'key': apiKey,
        },
      );
      final data = res.data;
      final routes = data is Map ? data['routes'] : null;
      String? poly;
      if (routes is List && routes.isNotEmpty) {
        final first = routes.first;
        final overview = first is Map ? first['overview_polyline'] : null;
        final points = overview is Map ? overview['points'] : null;
        if (points is String) poly = points;
      }
      if (poly == null || poly.isEmpty) throw StateError('no route');
      final pts = _decodePolyline(poly);
      if (!mounted || key != _routeKey) return; // stale result
      setState(() {
        _routePoints = pts;
        _routeFailed = false;
      });
    } catch (_) {
      if (!mounted || key != _routeKey) return;
      // Do not fake a straight line — show markers only, plus a small note.
      setState(() {
        _routePoints = const [];
        _routeFailed = true;
      });
    }
  }

  void _onMapCreated(GoogleMapController c) {
    _map = c;
    _fitCamera();
  }

  Future<void> _fitCamera() async {
    // Let the map finish its first frame before we ask it for a camera move.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final map = _map;
    if (map == null || !mounted) return;

    final buyer = widget.tracking.buyerLocation;
    final seller = widget.tracking.sellerCurrentLocation;
    if (buyer == null) return;

    if (seller != null) {
      final swLat = buyer.latitude < seller.latitude
          ? buyer.latitude
          : seller.latitude;
      final swLng = buyer.longitude < seller.longitude
          ? buyer.longitude
          : seller.longitude;
      final neLat = buyer.latitude > seller.latitude
          ? buyer.latitude
          : seller.latitude;
      final neLng = buyer.longitude > seller.longitude
          ? buyer.longitude
          : seller.longitude;
      await map.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(swLat, swLng),
            northeast: LatLng(neLat, neLng),
          ),
          72,
        ),
      );
    } else {
      await map.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(buyer.latitude, buyer.longitude), 15),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final buyer = widget.tracking.buyerLocation!;
    final seller = widget.tracking.sellerCurrentLocation;

    final buyerLatLng = LatLng(buyer.latitude, buyer.longitude);
    final sellerLatLng = seller == null
        ? null
        : LatLng(seller.latitude, seller.longitude);

    // Markers + polyline depend only on the tracking data (stable across pulse
    // ticks), so they're built once here — the AnimatedBuilder below rebuilds
    // only the pulse Circle, so the marker icons never re-diff or flicker.
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('buyer'),
        position: buyerLatLng,
        icon:
            _buyerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 1.0), // pin tip on the point
        infoWindow: const InfoWindow(title: 'Delivery destination'),
      ),
      if (sellerLatLng != null)
        Marker(
          markerId: const MarkerId('seller'),
          position: sellerLatLng,
          icon:
              _sellerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 1.0), // pin tip on the point
          infoWindow: const InfoWindow(title: "Seller's current location"),
        ),
    };

    // Route-wise polyline from _ensureRoute (backend route or Google Directions,
    // cached). No straight-line fallback — if the route API fails we show
    // markers only (plus the _routeFailed note) rather than a fake straight line.
    final polylines = <Polyline>{
      if (_routePoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: AppColors.ink,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    };

    // No seller yet → no pulse, so skip the AnimatedBuilder (map builds once).
    if (sellerLatLng == null) {
      return _buildMap(buyerLatLng, markers, const <Circle>{}, polylines);
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return _buildMap(
          buyerLatLng,
          markers,
          _pulseCircles(sellerLatLng, _pulse.value),
          polylines,
        );
      },
    );
  }

  /// A smooth, premium double-ripple pulse around the seller: two eased,
  /// staggered rings that expand and fade. Only the Circle set is rebuilt each
  /// frame (via the AnimatedBuilder) — never the markers or polyline.
  Set<Circle> _pulseCircles(LatLng center, double t) {
    Circle ripple(int i, double phase) {
      final p = (t + phase) % 1.0;
      final eased = Curves.easeOut.transform(p);
      return Circle(
        circleId: CircleId('seller-pulse-$i'),
        center: center,
        radius: 14 + 54 * eased, // metres
        fillColor: AppColors.ink.withValues(alpha: 0.13 * (1 - p)),
        strokeColor: AppColors.ink.withValues(alpha: 0.22 * (1 - p)),
        strokeWidth: 1,
      );
    }

    return {ripple(0, 0.0), ripple(1, 0.5)};
  }

  Widget _buildMap(
    LatLng target,
    Set<Marker> markers,
    Set<Circle> circles,
    Set<Polyline> polylines,
  ) {
    final map = GoogleMap(
      initialCameraPosition: CameraPosition(target: target, zoom: 14),
      onMapCreated: _onMapCreated,
      padding: const EdgeInsets.only(top: 120, bottom: 260),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      markers: markers,
      circles: circles,
      polylines: polylines,
    );
    if (!_routeFailed) return map;
    // Route API failed → markers only + a small safe note (never a fake route).
    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 66,
          left: AppSizes.md,
          right: AppSizes.md,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.85),
                borderRadius: AppRadii.pill,
              ),
              child: Text(
                'Route preview unavailable — showing markers only.',
                style: AppText.caption.copyWith(color: AppColors.textOnDark),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({
    required this.tracking,
    required this.updatingLocation,
    required this.refreshing,
    required this.onRefresh,
    required this.onUpdateMyLocation,
  });

  final TransactionTracking tracking;
  final bool updatingLocation;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onUpdateMyLocation;

  /// Role- and status-aware guidance line. The buyer sees seller-focused
  /// wording ("the seller is on the way"); the seller sees own-action wording
  /// ("you are on the way", "update your location", "verify with the code").
  String _stageNote(ApiTxStatus s, bool isSeller, bool hasSellerLocation) {
    switch (s) {
      case ApiTxStatus.disputed:
        return isSeller
            ? 'Payout is on hold due to dispute.'
            : 'This transaction is under dispute.';
      case ApiTxStatus.delivered:
      case ApiTxStatus.cooling:
      case ApiTxStatus.released:
      case ApiTxStatus.completed:
        return isSeller
            ? 'Delivery confirmed. Payout unlocks after cooling period.'
            : 'Delivery has been confirmed. Cooling period is active.';
      case ApiTxStatus.cancelled:
      case ApiTxStatus.refunded:
      case ApiTxStatus.returned:
      case ApiTxStatus.undeliverable:
        return 'This order is no longer active.';
      case ApiTxStatus.inTransit:
      case ApiTxStatus.outForDelivery:
        if (isSeller) {
          return hasSellerLocation
              ? 'You are on the way to the buyer location.'
              : 'Update your delivery location so the buyer can track the order.';
        }
        return hasSellerLocation
            ? 'The seller is on the way with your order.'
            : 'Seller location is not updated yet.';
      case ApiTxStatus.awaitingDispatch:
        return isSeller
            ? 'Start delivery so the buyer can track this order.'
            : 'Waiting for the seller to dispatch this order.';
      default:
        return 'Tracking this order.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ApiTxStatus.fromApi(tracking.status);
    final route = tracking.route;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSizes.rXl),
          topRight: Radius.circular(AppSizes.rXl),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadii.pill,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delivery status', style: AppText.caption),
                    const SizedBox(height: 2),
                    Text(status.label, style: AppText.h2),
                  ],
                ),
              ),
              StatusPill(
                label: status.label,
                icon: Icons.local_shipping_outlined,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            _stageNote(status, tracking.isSeller, tracking.hasSellerLocation),
            style: AppText.body,
          ),
          if (route != null) ...[
            const SizedBox(height: AppSizes.md),
            Row(
              children: [
                if (route.distanceText.isNotEmpty)
                  _MetricChip(
                    icon: Icons.route_outlined,
                    label: route.distanceText,
                  ),
                if (route.distanceText.isNotEmpty &&
                    route.durationText.isNotEmpty)
                  const SizedBox(width: AppSizes.sm),
                if (route.durationText.isNotEmpty)
                  _MetricChip(
                    icon: Icons.schedule_rounded,
                    label: route.durationText,
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                tracking.lastUpdatedAt != null
                    ? 'Last updated ${Dates.relative(tracking.lastUpdatedAt!)}'
                    : 'Not updated yet',
                style: AppText.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          _RefreshLocationButton(refreshing: refreshing, onTap: onRefresh),
          if (tracking.isSeller) ...[
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Update my delivery location',
              icon: Icons.my_location_rounded,
              accentInLime: true,
              loading: updatingLocation,
              enabled: !updatingLocation,
              onPressed: onUpdateMyLocation,
            ),
          ],
        ],
      ),
    );
  }
}

/// Outline "Refresh location" button whose icon spins while a tracking refetch
/// is in flight. Disabled during the fetch so repeated taps can't queue
/// duplicate calls; the label switches to "Refreshing…". The spin stops the
/// moment the fetch completes or fails (never left spinning).
class _RefreshLocationButton extends StatelessWidget {
  const _RefreshLocationButton({required this.refreshing, required this.onTap});
  final bool refreshing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: refreshing ? null : onTap,
        child: Container(
          height: AppSizes.buttonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadii.md,
            border: Border.all(color: AppColors.border, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedRefreshIcon(
                isLoading: refreshing,
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                refreshing ? 'Refreshing…' : 'Refresh location',
                style: AppText.bodyStrong,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(label, style: AppText.caption),
        ],
      ),
    );
  }
}

/// Loads a pin asset and strips its opaque (near-white) background so only the
/// pin graphic renders on the map — the driver asset ships on a solid white
/// square that would otherwise show as a rectangle behind the marker. The
/// background is removed with a flood-fill from the image borders, so enclosed
/// light regions inside the pin (e.g. the white circle behind the truck) are
/// preserved. Returns null on any failure so the caller falls back to a default
/// marker.
Future<BitmapDescriptor?> _loadTransparentPinMarker(
  String assetPath, {
  int decodeWidth = 132,
  double? logicalWidth,
}) async {
  try {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: decodeWidth,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (byteData == null) return null;
    final pixels = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    _stripBorderBackground(pixels, w, h);
    final out = await _imageFromPixels(pixels, w, h);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    if (png == null) return null;
    return BitmapDescriptor.bytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      width: logicalWidth,
    );
  } catch (_) {
    return null; // fall back to the default marker
  }
}

/// Flood-fills near-white pixels connected to the image border to fully
/// transparent, leaving enclosed light regions untouched.
void _stripBorderBackground(Uint8List px, int w, int h, {int threshold = 232}) {
  bool nearWhite(int i) =>
      px[i] >= threshold &&
      px[i + 1] >= threshold &&
      px[i + 2] >= threshold &&
      px[i + 3] != 0;
  final visited = Uint8List(w * h);
  final stack = <int>[];
  void seed(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    stack.add(y * w + x);
  }

  for (int x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (int y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    if (visited[p] == 1) continue;
    visited[p] = 1;
    final i = p * 4;
    if (!nearWhite(i)) continue;
    px[i + 3] = 0; // fully transparent
    final x = p % w;
    final y = p ~/ w;
    seed(x + 1, y);
    seed(x - 1, y);
    seed(x, y + 1);
    seed(x, y - 1);
  }
}

/// Rebuilds a [ui.Image] from raw RGBA pixels.
Future<ui.Image> _imageFromPixels(Uint8List px, int w, int h) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    px,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Decodes a Google "encoded polyline" (backend route or Directions
/// overview_polyline) into map points. Standard public-domain algorithm.
List<LatLng> _decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
