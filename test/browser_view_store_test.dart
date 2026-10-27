import 'package:dream_player/services/browser_view_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to list', () {
    final store = BrowserViewStore.instance;
    expect(store.mode, BrowserViewMode.list);
    expect(store.isList, isTrue);
    expect(store.isGrid, isFalse);
  });

  test('persists the choice and reloads it', () async {
    await BrowserViewStore.load();
    await BrowserViewStore.instance.setMode(BrowserViewMode.grid);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dreamplayer.browserView'), 'grid');

    // A fresh load (as on the next app start) reads it back.
    await BrowserViewStore.load();
    expect(BrowserViewStore.instance.mode, BrowserViewMode.grid);
    expect(BrowserViewStore.instance.isGrid, isTrue);
  });

  test('notifies listeners when the mode changes', () async {
    await BrowserViewStore.load();
    var notified = 0;
    void listener() => notified++;
    BrowserViewStore.instance.addListener(listener);

    await BrowserViewStore.instance.setMode(BrowserViewMode.grid);
    expect(notified, 1);

    // Setting the same mode again is a no-op.
    await BrowserViewStore.instance.setMode(BrowserViewMode.grid);
    expect(notified, 1);

    BrowserViewStore.instance.removeListener(listener);
  });

  test('fromString falls back to list for anything unknown', () {
    expect(BrowserViewMode.fromString('grid'), BrowserViewMode.grid);
    expect(BrowserViewMode.fromString('list'), BrowserViewMode.list);
    expect(BrowserViewMode.fromString(null), BrowserViewMode.list);
    expect(BrowserViewMode.fromString('tiles'), BrowserViewMode.list);
  });
}
