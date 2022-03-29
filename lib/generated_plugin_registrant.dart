//
// Generated file. Do not edit.
//

// ignore_for_file: lines_longer_than_80_chars

import 'package:assets_audio_player_web/web/assets_audio_player_web.dart';
import 'package:audio_session/audio_session_web.dart';
import 'package:flutter_sound_web/flutter_sound_web.dart';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

// ignore: public_member_api_docs
void registerPlugins(Registrar registrar) {
  AssetsAudioPlayerWebPlugin.registerWith(registrar);
  AudioSessionWeb.registerWith(registrar);
  FlutterSoundPlugin.registerWith(registrar);
  registrar.registerMessageHandler();
}
