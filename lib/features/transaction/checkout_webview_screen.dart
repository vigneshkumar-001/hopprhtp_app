import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/env/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/feedback/app_loaders.dart';

/// Opens the hosted web checkout (`/pay/<code>`) in an in-app browser. The web
/// page calls the `HopprApp` JS channel once payment is confirmed; on that
/// signal this screen pops with `true` so the app can continue (e.g. link the
/// transaction). Closing it manually pops `false`.
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..addJavaScriptChannel(
        'HopprApp',
        onMessageReceived: (message) {
          if (message.message.contains('paid') && mounted) {
            Navigator.of(context).pop(true);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(
        '${AppConfig.webBaseUrl}/pay/${widget.code}'
        '?theme=${widget.lime ? 'lime' : 'mono'}',
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        elevation: 0.5,
        centerTitle: true,
        title: Text('Secure checkout',
            style: AppText.bodyStrong.copyWith(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const ColoredBox(
              color: AppColors.surface,
              child: Center(child: AppCircularLoader()),
            ),
        ],
      ),
    );
  }
}
