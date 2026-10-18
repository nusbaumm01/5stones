import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Sfx { place, capture, win }

/// Plays the game's sound effects and remembers whether sound is on.
class SoundService extends ChangeNotifier {
  SoundService._();

  static final SoundService instance = SoundService._();

  static const _prefKey = 'sound_on';
  bool _enabled = true;
  bool _loaded = false;
  final Map<Sfx, AudioPlayer> _players = {};

  bool get enabled => _enabled;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('Could not read sound setting: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (e) {
      debugPrint('Could not save sound setting: $e');
    }
  }

  Future<void> play(Sfx sfx) async {
    if (!_enabled) return;
    try {
      final player = _players.putIfAbsent(sfx, () {
        final p = AudioPlayer();
        p.setReleaseMode(ReleaseMode.stop);
        p.setPlayerMode(PlayerMode.lowLatency);
        return p;
      });
      await player.stop();
      await player.play(AssetSource('sounds/${sfx.name}.wav'));
    } catch (e) {
      // Sound is a nice-to-have; never let it break the game.
      debugPrint('Could not play ${sfx.name}: $e');
    }
  }
}
