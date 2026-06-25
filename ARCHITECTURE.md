# Hoppr app — architecture (state + networking)

State management is **Riverpod** (no codegen). Networking is **Dio** behind a
repository layer. Tokens live in **flutter_secure_storage**. Money is kept in
**kobo (int)** end-to-end to match the backend — divide by 100 only at display.

## Layers

```
Screen (ConsumerWidget)
  └─ watches a Provider ............ features/<feature>/application/*.dart
       └─ calls a Repository ....... data/repositories/*.dart
            └─ Dio (apiCall) ....... core/network/ (envelope unwrap + errors)
                 └─ Backend ........ /api/v1/...
DTOs (data/dto/*) parse the JSON; never leak Dio/Response above the repository.
```

| Concern | File |
|---|---|
| Base URL (per-platform, `--dart-define` override) | `core/env/app_config.dart` |
| Secure JWT storage | `core/storage/token_store.dart` |
| `{success,data}` unwrap + error mapping | `core/network/api_client.dart`, `api_exception.dart` |
| Bearer attach + 401 refresh/retry | `core/network/auth_interceptor.dart` |
| DI (dio, repos, token store) | `core/providers.dart` |
| Auth session state | `features/auth/application/auth_controller.dart` |
| Transaction list/detail state | `features/transaction/application/transactions_provider.dart` |

## Running against the backend

1. Start the backend: in `backend/`, `npm run dev` (listens on `:4000`).
2. Android emulator → `10.0.2.2`, iOS sim/desktop → `localhost` are automatic.
   Physical device / staging:
   `flutter run --dart-define=API_BASE_URL=https://your-host/api/v1`

## Consuming state in a screen

Turn a `StatelessWidget`/`StatefulWidget` into a `ConsumerWidget`/`ConsumerStatefulWidget`
and `ref.watch` the slice you need — only that widget rebuilds.

```dart
class ActiveDealsView extends ConsumerWidget {
  const ActiveDealsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(transactionsByStageProvider(ApiTxStage.active));
    return deals.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text((e as ApiException).message),
      data: (list) => ListView.builder(            // lazy, not .toList()
        itemCount: list.length,
        itemBuilder: (_, i) => TransactionCard(tx: list[i]),
      ),
    );
  }
}
```

Sign in, then refresh the list:
```dart
await ref.read(authControllerProvider.notifier)
    .login(identifier: phone, pin: pin);
ref.invalidate(transactionsProvider); // refetch for the new session
```

## What's wired vs. next

- **Wired:** auth (request-otp → confirm → login → refresh/auto-retry → logout,
  session restore on launch), transactions (list, by-stage, detail, and the
  lifecycle actions: agree/fund/ship/out-for-delivery/confirm-delivery/release/cancel).
- **Next:** `TransactionRepository.create` (needs the consignment + payout request
  shape); migrate the seed-driven screens (`home_screen`, `transactions_tab`,
  `transaction_detail_screen`) off `AppState`/`AppScope` onto these providers;
  add wallet + dispute repositories following the same pattern.

> `data/app_state.dart` (the demo `ChangeNotifier`) still drives the existing
> screens. It can be retired feature-by-feature as each screen moves to a provider.
