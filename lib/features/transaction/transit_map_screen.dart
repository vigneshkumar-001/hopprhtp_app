import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import 'application/transactions_provider.dart';
import 'confirm_delivery_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Transit — the "Package on the way" tracking screen with a REAL Google Map.
/// Keeps the existing layout (dispatcher card on top, ETA + OTP sheet at the
/// bottom); only the map area is the live Google Maps view. The courier marker
/// is animated along a route (no live GPS feed yet); the OTP note + "receiving"
/// flow tie to the user's real in-transit transaction when one is loaded.
class TransitMapScreen extends ConsumerStatefulWidget {
  const TransitMapScreen({super.key});

  @override
  ConsumerState<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends ConsumerState<TransitMapScreen> {
  // A believable delivery route across Lagos (Lekki → Ikoyi).
  static const _waypoints = <LatLng>[
    LatLng(6.4281, 3.4216),
    LatLng(6.4402, 3.4448),
    LatLng(6.4525, 3.4561),
    LatLng(6.4623, 3.4344),
    LatLng(6.4698, 3.4106),
    LatLng(6.4584, 3.3982),
  ];

  late final List<LatLng> _path = _densify(_waypoints, 28);
  GoogleMapController? _map;
  Timer? _timer;
  int _i = 0;

  LatLng get _courier => _path[_i];
  LatLng get _dest => _waypoints.last;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 550), (t) {
      if (_i >= _path.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map?.dispose();
    super.dispose();
  }

  static List<LatLng> _densify(List<LatLng> pts, int perSeg) {
    final out = <LatLng>[];
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      for (int s = 0; s < perSeg; s++) {
        final t = s / perSeg;
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
      }
    }
    out.add(pts.last);
    return out;
  }

  void _onMapCreated(GoogleMapController c) {
    _map = c;
    var swLat = _waypoints.first.latitude, swLng = _waypoints.first.longitude;
    var neLat = swLat, neLng = swLng;
    for (final p in _waypoints) {
      swLat = p.latitude < swLat ? p.latitude : swLat;
      swLng = p.longitude < swLng ? p.longitude : swLng;
      neLat = p.latitude > neLat ? p.latitude : neLat;
      neLng = p.longitude > neLng ? p.longitude : neLng;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(swLat, swLng),
      northeast: LatLng(neLat, neLng),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      _map?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
    });
  }

  void _receive(ApiTransaction? tx) {
    final draft = PaymentDraft(
      productName: tx?.productName ?? 'Your delivery',
      sellerName: tx?.merchantName ?? 'Seller',
      sellerCode: tx?.code ?? 'HTP-LGS-8881',
      itemSubtotal: tx?.itemSubtotalNaira ?? 1230087,
    );
    AppNav.push(context, ConfirmDeliveryScreen(draft: draft));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final tx = ref.watch(transactionsProvider).maybeWhen(
          data: (list) {
            final moving = list
                .where((t) =>
                    t.status == ApiTxStatus.inTransit ||
                    t.status == ApiTxStatus.outForDelivery)
                .toList();
            if (moving.isNotEmpty) return moving.first;
            return list.isNotEmpty ? list.first : null;
          },
          orElse: () => null,
        );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ── The live Google Map fills the screen behind the cards ──────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(6.4498, 3.4300),
                zoom: 12.5,
              ),
              onMapCreated: _onMapCreated,
              // Inset the camera so the route isn't hidden behind the cards.
              padding: const EdgeInsets.only(top: 150, bottom: 300),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: {
                Marker(
                  markerId: const MarkerId('destination'),
                  position: _dest,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed),
                  infoWindow: const InfoWindow(title: 'Delivery address'),
                ),
                Marker(
                  markerId: const MarkerId('courier'),
                  position: _courier,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                  infoWindow: const InfoWindow(title: 'Tunde Bello'),
                ),
              },
              polylines: {
                const Polyline(
                  polylineId: PolylineId('route'),
                  points: _waypoints,
                  color: AppColors.ink,
                  width: 4,
                ),
              },
            ),
          ),

          // ── Top: title bar + dispatcher card ───────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.sm),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text('Package on the way', style: AppText.title),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            background:
                                accent.isLime ? const Color(0xFFE6E7DD) : null,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSizes.screenPad),
                  child: AppCard(
                    shadow: true,
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Row(
                      children: [
                        InitialsAvatar(
                          initials: 'TB',
                          size: 38,
                          background:
                              accent.isLime ? const Color(0xFFF7EBB0) : null,
                        ),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tunde Bello', style: AppText.bodyStrong),
                              const SizedBox(height: 2),
                              Text('Dispatcher · holds your code',
                                  style: AppText.caption),
                            ],
                          ),
                        ),
                        const _CallButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom: ETA + OTP sheet ────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: _ArrivalSheet(onReceive: () => _receive(tx)),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton();
  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final bg = accent.isLime ? const Color(0xFFCBF24A) : AppColors.ink;
    final fg = accent.isLime ? accent.onAccent : AppColors.textOnDark;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(Icons.call_rounded, size: 18, color: fg),
    );
  }
}

class _ArrivalSheet extends StatelessWidget {
  const _ArrivalSheet({required this.onReceive});
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
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
              color: AppColors.shadow, blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(AppSizes.xl, AppSizes.md, AppSizes.xl,
          AppSizes.lg + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border, borderRadius: AppRadii.pill),
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
                    Text('Estimated arrival', style: AppText.caption),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('10:00', style: AppText.h1),
                        const SizedBox(width: 6),
                        Text('Today', style: AppText.body),
                      ],
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: 'Out for delivery',
                icon: Icons.local_shipping_outlined,
                background: accent.isLime ? const Color(0xFFFBF2C6) : null,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          NoteBanner(
            icon: Icons.info_outline_rounded,
            color: accent.isLime ? const Color(0xFFEAF7C2) : null,
            textColor: accent.isLime ? const Color(0xFF181A12) : null,
            highlight: 'Tunde Bello',
            highlightColor: AppColors.textPrimary,
            text:
                'The 6-digit code was sent to Tunde Bello — not to you. Get it from them at the door.',
          ),
          const SizedBox(height: AppSizes.md),
          AppButton(
            label: 'I\'m receiving it now',
            trailingIcon: Icons.arrow_forward_rounded,
            variant: AppButtonVariant.outline,
            accentInLime: true,
            onPressed: onReceive,
          ),
        ],
      ),
    );
  }
}
