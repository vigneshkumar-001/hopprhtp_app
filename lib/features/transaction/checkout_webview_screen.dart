import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/env/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/feedback/app_loaders.dart';

/// How the checkout screen was left. [failed] and [pending] both carry an
/// optional [CheckoutResult.message] with the real reason, when known.
enum PaymentOutcome {
  /// The web page confirmed the payment (`{event:'paid'}`).
  success,

  /// The buyer closed the screen manually before paying.
  cancelled,

  /// The web page reported a payment error, or the checkout page itself
  /// couldn't be loaded (network/server unreachable).
  failed,

  /// Reserved for an asynchronous/awaiting-confirmation payment state. The
  /// current checkout page always resolves synchronously (paid or failed), so
  /// nothing produces this today — kept for a future gateway that does.
  pending,
}

/// The result [CheckoutWebViewScreen] pops with.
class CheckoutResult {
  const CheckoutResult(this.outcome, {this.message});
  final PaymentOutcome outcome;
  final String? message;
}

/// Opens the hosted web checkout (`/pay/<code>`) in an in-app browser. The web
/// page calls the `HopprApp` JS channel on `paid` (success) or `failed`
/// (payment declined/errored — additive signal, the page's own inline retry
/// is unchanged); closing the screen manually pops [PaymentOutcome.cancelled].
/// If the page itself can't load at all (offline/server down), an in-screen
/// retry is shown instead of a blank/broken WebView.
class CheckoutWebViewScreen extends StatefulWidget {
  const CheckoutWebViewScreen({
    super.key,
    required this.code,
    this.lime = false,
  });

  final String code;

  /// Renders the web page in the app's lime theme (otherwise Mono / B&W).
  final bool lime;

  @override
  State<CheckoutWebViewScreen> createState() => _CheckoutWebViewScreenState();
}

class _CheckoutWebViewScreenState extends State<CheckoutWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _loadError = false;

  Uri get _url => Uri.parse(
    '${AppConfig.webBaseUrl}/pay/${widget.code}'
    '?theme=${widget.lime ? 'lime' : 'mono'}',
  );

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..addJavaScriptChannel('HopprApp', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loadError = false);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Only a main-frame failure means the checkout page itself never
            // loaded — a missing sub-resource (an icon, a font) shouldn't
            // block the whole screen behind a retry wall.
            if (!mounted || error.isForMainFrame == false) return;
            setState(() {
              _loading = false;
              _loadError = true;
            });
          },
        ),
      )
      ..loadRequest(_url);
  }

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {
      // Fall through to the raw-string checks below.
    }
    final event = data?['event'] as String? ?? message.message;
    if (event == 'paid' || event.contains('paid')) {
      Navigator.of(context).pop(const CheckoutResult(PaymentOutcome.success));
      return;
    }
    if (event == 'failed') {
      final reason = data?['message'] as String?;
      Navigator.of(
        context,
      ).pop(CheckoutResult(PaymentOutcome.failed, message: reason));
    }
  }

  void _retryLoad() {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    _controller.loadRequest(_url);
  }

  void _close() =>
      Navigator.of(context).pop(const CheckoutResult(PaymentOutcome.cancelled));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          'Secure checkout',
          style: AppText.bodyStrong.copyWith(fontSize: 15),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: _close,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading && !_loadError)
            const ColoredBox(
              color: AppColors.surface,
              child: Center(child: AppCircularLoader()),
            ),
          if (_loadError)
            ColoredBox(
              color: AppColors.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        size: 40,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(height: AppSizes.md),
                      Text(
                        'Could not load secure checkout',
                        style: AppText.bodyStrong,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Check your connection and try again.',
                        style: AppText.caption,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSizes.lg),
                      AppButton(
                        label: 'Retry',
                        expand: false,
                        variant: AppButtonVariant.outline,
                        onPressed: _retryLoad,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
