import 'dart:io';

import 'package:escrow/features/profile/identity_verification_screen.dart';
import 'package:escrow/features/profile/kyc_draft_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

XFile _xf(String path) => XFile(path);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('kyc_draft_storage_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File realFile(String name) {
    final f = File('${tmp.path}/$name');
    f.writeAsBytesSync([1, 2, 3]);
    return f;
  }

  KycDraft draftWith({
    required List<int> docIndexes,
    File? doc0Front,
    File? doc0Back,
    File? selfie,
  }) {
    final d = KycDraft()..selectedDocIndexes = docIndexes;
    d.docs = docIndexes.map(KycDocSlot.new).toList();
    if (doc0Front != null) d.docs[0].front = _xf(doc0Front.path);
    if (doc0Back != null) d.docs[0].back = _xf(doc0Back.path);
    if (selfie != null) d.selfie = _xf(selfie.path);
    return d;
  }

  group('KycDraftStorage', () {
    test('load() returns null when nothing has ever been saved', () async {
      expect(await KycDraftStorage.load(), isNull);
    });

    test(
      'round-trips a draft whose files genuinely still exist on disk',
      () async {
        final front = realFile('front.jpg');
        final back = realFile('back.jpg');
        final selfie = realFile('selfie.jpg');
        final draft = draftWith(
          docIndexes: [0, 1],
          doc0Front: front,
          doc0Back: back,
          selfie: selfie,
        );

        await KycDraftStorage.save(draft);
        final loaded = await KycDraftStorage.load();

        expect(loaded, isNotNull);
        expect(loaded!.selectedDocIndexes, [0, 1]);
        expect(loaded.docs[0].front?.path, front.path);
        expect(loaded.docs[0].back?.path, back.path);
        expect(loaded.selfie?.path, selfie.path);
      },
    );

    test(
      'drops a file reference whose path no longer exists, without losing the rest',
      () async {
        final front = realFile('front.jpg');
        final draft = draftWith(docIndexes: [0], doc0Front: front);
        draft.docs[0].back = _xf(
          '${tmp.path}/never_written.jpg',
        ); // never created on disk

        await KycDraftStorage.save(draft);
        final loaded = await KycDraftStorage.load();

        expect(loaded, isNotNull);
        expect(loaded!.docs[0].front?.path, front.path); // survives
        expect(loaded.docs[0].back, isNull); // dropped, not a dangling path
      },
    );

    test(
      'resuming reflects exactly which step is actually still incomplete',
      () async {
        final front = realFile('front.jpg');
        final back = realFile('back.jpg');

        final onlyFirstDocDone = draftWith(
          docIndexes: [0, 1],
          doc0Front: front,
          doc0Back: back,
        );
        expect(onlyFirstDocDone.documentsReady, isFalse);

        final bothDocsDone = KycDraft()..selectedDocIndexes = [0, 1];
        bothDocsDone.docs = [
          KycDocSlot(0)
            ..front = _xf(front.path)
            ..back = _xf(back.path),
          KycDocSlot(1)
            ..front = _xf(front.path)
            ..back = _xf(back.path),
        ];
        expect(bothDocsDone.documentsReady, isTrue);
        expect(bothDocsDone.selfie, isNull);
      },
    );

    test('clear() removes the saved draft', () async {
      final draft = draftWith(docIndexes: [0, 1]);
      await KycDraftStorage.save(draft);
      expect(await KycDraftStorage.load(), isNotNull);

      await KycDraftStorage.clear();
      expect(await KycDraftStorage.load(), isNull);
    });

    test(
      'saving a draft with no chosen document types clears any prior save',
      () async {
        final draft = draftWith(docIndexes: [0, 1]);
        await KycDraftStorage.save(draft);
        expect(await KycDraftStorage.load(), isNotNull);

        await KycDraftStorage.save(KycDraft());
        expect(await KycDraftStorage.load(), isNull);
      },
    );

    test(
      'malformed saved data is treated as no draft, never a crash',
      () async {
        SharedPreferences.setMockInitialValues({
          'hoppr.kycDraft.v1': 'not valid json',
        });
        expect(await KycDraftStorage.load(), isNull);
      },
    );
  });
}
