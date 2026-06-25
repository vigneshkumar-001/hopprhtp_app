import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dto/transaction_dto.dart';
import 'dto/user_dto.dart';
import 'models/models.dart';

/// App-wide state — a [ChangeNotifier] shared through [AppScope] (an
/// [InheritedNotifier]). Rebuild listeners with `ListenableBuilder` or by
/// reading `AppScope.of(context)`.
///
/// An optional [SharedPreferences] handle is used to persist lightweight
/// preferences (currently the selected theme) across app restarts.
class AppState extends ChangeNotifier {
  AppState({SharedPreferences? prefs}) : _prefs = prefs {
    _limeTheme = _prefs?.getBool(_kLimeTheme) ?? false;
  }

  final SharedPreferences? _prefs;
  static const String _kLimeTheme = 'hoppr.limeTheme';

  HopprUser? _user;
  HopprUser? get user => _user;
  bool get isAuthenticated => _user != null;

  // ---- Theme -------------------------------------------------------------
  late bool _limeTheme;
  bool get limeTheme => _limeTheme;

  void setLimeTheme(bool value) {
    if (_limeTheme == value) return;
    _limeTheme = value;
    _prefs?.setBool(_kLimeTheme, value); // persisted for next launch
    notifyListeners();
  }

  void toggleTheme() => setLimeTheme(!_limeTheme);

  final List<EscrowTransaction> _transactions = _seedTransactions();
  List<EscrowTransaction> get transactions => List.unmodifiable(_transactions);

  List<EscrowTransaction> byStage(TxStage stage) =>
      _transactions.where((t) => t.stage == stage).toList(growable: false);

  int get activeCount => byStage(TxStage.active).length;
  int get coolingCount => byStage(TxStage.cooling).length;

  // ---- Auth --------------------------------------------------------------
  void signUp({
    required String fullName,
    required String phone,
    String? email,
  }) {
    _user = HopprUser(
      fullName: fullName.trim(),
      phone: phone.trim(),
      email: (email != null && email.trim().isNotEmpty) ? email.trim() : null,
      deals: 0,
      verified: false,
      escrowBalance: 0,
    );
    notifyListeners();
  }

  /// Bridges the authenticated [ApiUser] (from the backend) into the legacy
  /// dashboard state. Lets existing screens keep reading `AppScope.of(context)`
  /// while features migrate to Riverpod providers one at a time.
  void hydrateFromApi(ApiUser u) {
    _user = HopprUser(
      fullName: u.fullName,
      phone: u.phone,
      email: u.email,
      trustScore: u.trustGrade,
      deals: u.deals,
      disputes: u.disputes,
      verified: u.verified,
      escrowBalance: u.escrowBalanceKobo / 100,
    );
    notifyListeners();
  }

  /// Demo sign-in — accepts any identifier/PIN and loads the seeded profile.
  void signIn({required String identifier}) {
    _user = HopprUser(
      fullName: 'Amara Okafor',
      phone: identifier.trim(),
      email: identifier.contains('@') ? identifier.trim() : null,
    );
    notifyListeners();
  }

  void signOut() {
    _user = null;
    notifyListeners();
  }

  void updateProfile({String? fullName, String? phone, String? email}) {
    final u = _user;
    if (u == null) return;
    if (fullName != null) u.fullName = fullName;
    if (phone != null) u.phone = phone;
    if (email != null) u.email = email;
    notifyListeners();
  }

  void markVerified() {
    _user?.verified = true;
    notifyListeners();
  }

  // ---- Transactions ------------------------------------------------------
  void addTransaction(EscrowTransaction tx) {
    _transactions.insert(0, tx);
    final u = _user;
    if (u != null) u.escrowBalance += tx.amount;
    notifyListeners();
  }

  /// Inserts a backend-created transaction onto the demo dashboard list — a
  /// bridge until the list screens move to the transactions provider.
  void addFromApi(ApiTransaction t) {
    _transactions.insert(
      0,
      EscrowTransaction(
        id: t.id,
        code: t.code,
        merchantName: t.merchantName,
        productName: t.productName,
        variant: t.variant,
        amount: t.grandTotalNaira,
        stage: _stageFromApi(t.stage),
        status: _statusFromApi(t.status),
      ),
    );
    notifyListeners();
  }

  static TxStage _stageFromApi(ApiTxStage s) => switch (s) {
        ApiTxStage.cooling => TxStage.cooling,
        ApiTxStage.done => TxStage.done,
        ApiTxStage.active => TxStage.active,
      };

  static TxStatus _statusFromApi(ApiTxStatus s) => switch (s) {
        ApiTxStatus.outForDelivery => TxStatus.outForDelivery,
        ApiTxStatus.inTransit => TxStatus.inTransit,
        ApiTxStatus.delivered => TxStatus.delivered,
        ApiTxStatus.released || ApiTxStatus.completed => TxStatus.released,
        ApiTxStatus.disputed => TxStatus.disputed,
        _ => TxStatus.awaitingDispatch,
      };

  EscrowTransaction? findByCode(String code) {
    final normalized = code.trim().toUpperCase();
    for (final t in _transactions) {
      if (t.code.toUpperCase() == normalized) return t;
    }
    return null;
  }

  static List<EscrowTransaction> _seedTransactions() => [
        EscrowTransaction(
          id: 't1',
          code: 'HTP-7Q2K',
          merchantName: 'Mira Atelier',
          productName: 'Linen Two-Piece Set',
          variant: 'Size M · Sand beige',
          amount: 51220,
          stage: TxStage.active,
          status: TxStatus.outForDelivery,
        ),
        EscrowTransaction(
          id: 't2',
          code: 'HTP-3M8X',
          merchantName: 'TechHub NG',
          productName: 'Anker 737 Power Bank',
          variant: '24,000mAh · Black',
          amount: 86208,
          stage: TxStage.active,
          status: TxStatus.inTransit,
        ),
        EscrowTransaction(
          id: 't3',
          code: 'HTP-9K4P',
          merchantName: 'Lagos Kicks',
          productName: 'Retro Hi-Top Sneakers',
          variant: 'Size 43 · Off-white',
          amount: 42500,
          stage: TxStage.cooling,
          status: TxStatus.delivered,
        ),
        EscrowTransaction(
          id: 't4',
          code: 'HTP-1A0Z',
          merchantName: 'Bloom & Co',
          productName: 'Ceramic Vase Bundle',
          amount: 18900,
          stage: TxStage.done,
          status: TxStatus.released,
        ),
        EscrowTransaction(
          id: 't5',
          code: 'HTP-6T5R',
          merchantName: 'Gadget Plug',
          productName: 'AirPods Pro (2nd gen)',
          variant: 'USB-C',
          amount: 168000,
          stage: TxStage.done,
          status: TxStatus.released,
        ),
      ];
}

/// Shares [AppState] down the tree and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope was not found in the tree');
    return scope!.notifier!;
  }

  /// Read without subscribing to rebuilds (for event handlers).
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope was not found in the tree');
    return scope!.notifier!;
  }
}
