/*
 * Copyright 2018, 2019, 2020, 2021 Dooboolab.
 *
 * This file is part of Flutter-Sound.
 *
 * Flutter-Sound is free software: you can redistribute it and/or modify
 * it under the terms of the Mozilla Public License version 2 (MPL2.0),
 * as published by the Mozilla organization.
 *
 * Flutter-Sound is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * MPL General Public License for more details.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_sound_platform_interface/flutter_sound_recorder_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:intl/date_symbol_data_local.dart';

/*
 * This is an example showing how to record to a Dart Stream.
 * It writes all the recorded data from a Stream to a File, which is completely stupid:
 * if an App wants to record something to a File, it must not use Streams.
 *
 * The real interest of recording to a Stream is for example to feed a
 * Speech-to-Text engine, or for processing the Live data in Dart in real time.
 *
 */

///
///
///
typedef _Fn = void Function();
TextEditingController _controller = new TextEditingController();
StreamSubscription? _mRecordingDataSubscription;

/* This does not work. on Android we must have the Manifest.permission.CAPTURE_AUDIO_OUTPUT permission.
 * But this permission is _is reserved for use by system components and is not available to third-party applications._
 * Pleaser look to [this](https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_UPLINK)
 *
 * I think that the problem is because it is illegal to record a communication in many countries.
 * Probably this stands also on iOS.
 * Actually I am unable to record DOWNLINK on my Xiaomi Chinese phone.
 *
 */
//const theSource = AudioSource.voiceUpLink;
//const theSource = AudioSource.voiceDownlink;

const theSource = AudioSource.microphone;

/// Example app.
class RecordPlayAudio extends StatefulWidget {
  @override
  _RecordPlayAudioState createState() => _RecordPlayAudioState();
}

class _RecordPlayAudioState extends State<RecordPlayAudio> {
  String _playerTxt= '00:00:00';
  String _recorderTxt= '00:00:00';
  StreamSubscription? _recorderSubscription;
  StreamSubscription? _playerSubscription;
  String token ="";
  double maxDuration = 1.0;
  Codec _codec = Codec.opusWebM;
  String _mPath = 'audioRecord.webm';
  FlutterSoundPlayer? _mPlayer = FlutterSoundPlayer();
  FlutterSoundRecorder? _mRecorder = FlutterSoundRecorder();
  bool _mPlayerIsInited = false;
  bool _mRecorderIsInited = false;
  bool _mplaybackReady = false;

  var uploaded =false;

  @override
  void initState() {
    _mPlayer!.openPlayer().then((value) {
      setState(() {
        _mPlayerIsInited = true;
        _mPlayer!.setSubscriptionDuration(Duration(milliseconds: 10));
      });
    });

    openTheRecorder().then((value) {
      setState(() {
        _mRecorderIsInited = true;
        _mRecorder!.setSubscriptionDuration(Duration(milliseconds: 10));
      });
    });
    initializeDateFormatting();
    super.initState();
  }

  @override
  void dispose() {
    _mPlayer!.closePlayer();
    _mPlayer = null;

    _mRecorder!.closeRecorder();
    _mRecorder = null;
    super.dispose();
  }
  void cancelRecorderSubscriptions() {
    if (_recorderSubscription != null) {
      _recorderSubscription!.cancel();
      _recorderSubscription = null;
    }
  }

  void cancelPlayerSubscriptions() {
    if (_playerSubscription != null) {
      _playerSubscription!.cancel();
      _playerSubscription = null;
    }
  }



  void _addListeners() {
    cancelPlayerSubscriptions();
    _playerSubscription = _mPlayer!.onProgress!.listen((e) {
      maxDuration = e.duration.inMilliseconds.toDouble();
      if (maxDuration <= 0) maxDuration = 0.0;

      var date = DateTime.fromMillisecondsSinceEpoch(e.position.inMilliseconds,
          isUtc: true);
      var txt = DateFormat('mm:ss:SS', 'en_GB').format(date);
      setState(() {
        _playerTxt = txt.substring(0, 8);
      });
    });
  }
  Future<void> openTheRecorder() async {
    if (!kIsWeb) {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw RecordingPermissionException('Microphone permission not granted');
      }
    }
    await _mRecorder!.openRecorder();
    if (!await _mRecorder!.isEncoderSupported(_codec) && kIsWeb) {
      _codec = Codec.opusWebM;
      _mPath = 'audioRecord.webm';
      if (!await _mRecorder!.isEncoderSupported(_codec) && kIsWeb) {
        _mRecorderIsInited = true;
        return;
      }
    }
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
      AVAudioSessionCategoryOptions.allowBluetooth |
      AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
      AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    _mRecorderIsInited = true;
  }

  // ----------------------  Here is the code for recording and playback -------

  void record() async{
    //used on mobile
   /* assert(_mRecorderIsInited && _mPlayer!.isStopped);
    var sink = await createFile();
    var recordingDataController = StreamController<Food>();
    _mRecordingDataSubscription =
        recordingDataController.stream.listen((buffer) {
          if (buffer is FoodData) {
            sink.add(buffer.data!);
          }
        });*/
    await _mRecorder!
        .startRecorder(
      toFile: _mPath,// on mobile use toStream: recordingDataController.sink,
      codec: _codec,
      audioSource: theSource,
    )
        .then((value) {
      setState(() {});
    });
    _recorderSubscription = _mRecorder!.onProgress!.listen((e) {
      var date = DateTime.fromMillisecondsSinceEpoch(
          e.duration.inMilliseconds,
          isUtc: true);
      var txt = DateFormat('mm:ss:SS', 'en_GB').format(date);

      setState(() {
        _recorderTxt = txt.substring(0, 8);

      });
    });
  }

  void stopRecorder() async {
    await _mRecorder!.stopRecorder().then((value) {

      setState(() {
        //var url = value;
        _mplaybackReady = true;

      });
    });

  }

  void play() {
    assert(_mPlayerIsInited &&
        _mplaybackReady &&
        _mRecorder!.isStopped &&
        _mPlayer!.isStopped);
    _addListeners();
    _mPlayer!
        .startPlayer(
        fromURI: _mPath,// used on mobile fromDataBuffer: getAssetData(_mPath),
        //codec: kIsWeb ? Codec.opusWebM : Codec.aacADTS,
        whenFinished: () {
          setState(() {});
        })
        .then((value) {
      setState(() {});
    });

  }

  void stopPlayer() async{
    _mPlayer!.stopPlayer().then((value) {
      setState(() {});
    });
    if (_playerSubscription != null) {
      await _playerSubscription!.cancel();
    _playerSubscription = null;
    }
  }

// ----------------------------- UI --------------------------------------------

  getRecorderFn() {
    if (!_mRecorderIsInited || !_mPlayer!.isStopped) {
      return null;
    }
    return _mRecorder!.isStopped ? record : stopRecorder;
  }

  getPlaybackFn() {
    if (!_mPlayerIsInited || !_mplaybackReady || !_mRecorder!.isStopped) {
      return null;
    }
    return _mPlayer!.isStopped ? play : stopPlayer;
  }

  void upload() async{
    var asset = await rootBundle.load(_mPath);
    Uint8List? uint= asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    var request = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: <String, String>{
          'Content-Type': 'application/octet-stream',
          'Authorization': 'Bearer ${token}',
          'User-Agent': 'api-explorer-client',
          'Dropbox-API-Arg': '{"path":"/$_mPath"}'
        },
        body: uint);
   print(request.body);
    print(request.statusCode);
    setState(() {
      if(request.statusCode == 200)uploaded = true;
      else uploaded =false;
    });

  }


 getUploadFn() async{
   upload();
  }

  @override
  Widget build(BuildContext context) {

    Widget makeBody() {
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(3),
            height: 80,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(0xFFFAF0E6),
              border: Border.all(
                color: Colors.indigo,
                width: 3,
              ),
            ),
            child: Row(children: [
              ElevatedButton(
                onPressed: getRecorderFn(),
                //color: Colors.white,
                //disabledColor: Colors.grey,
                child: Text(_mRecorder!.isRecording ? 'Stop' : 'Record'),
              ),
              SizedBox(
                width: 20,
              ),
              Text(
                _recorderTxt,
                style: TextStyle(
                  fontSize: 35.0,
                  color: Colors.black,
                ),
              ),
              SizedBox(
                width: 20,
              ),
              Text(_mRecorder!.isRecording
                  ? 'Recording in progress'
                  : 'Recorder is stopped'),
            ]),
          ),
          Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(3),
            height: 80,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(0xFFFAF0E6),
              border: Border.all(
                color: Colors.indigo,
                width: 3,
              ),
            ),
            child: Row(children: [
              ElevatedButton(
                onPressed: getPlaybackFn(),
                //color: Colors.white,
                //disabledColor: Colors.grey,
                child: Text(_mPlayer!.isPlaying ? 'Stop' : 'Play'),
              ),
              SizedBox(
                width: 20,
              ),
              Text(
                _playerTxt,
                style: TextStyle(
                  fontSize: 35.0,
                  color: Colors.black,
                ),
              ),
              SizedBox(
                width: 20,
              ),
              Text(_mPlayer!.isPlaying
                  ? 'Playback in progress'
                  : 'Player is stopped'),

            ]),
          ),
          Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(3),
            height: 80,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(0xFFFAF0E6),
              border: Border.all(
                color: Colors.indigo,
                width: 3,
              ),
            ),
            child: Row(children: [
              SizedBox(width:200,height:40, child:
              TextFormField(maxLines: 2,controller: _controller,onChanged: (String value){
                setState(() {
                  token = value;
                });
              },)),
              SizedBox(
                width: 20,
              ),
              ElevatedButton(
                onPressed: (){getUploadFn();},
                //color: Colors.white,
                //disabledColor: Colors.grey,
                child: Text(uploaded? 'Re-Upload to dropbox' : 'Upload to dropbox'),
              ),
              SizedBox(
                width: 20,
              ),

              Text(uploaded
                  ? 'File Uploaded Successfuly'
                  : 'File Not Uploaded'),

            ]),
          ),

        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.blue,
      appBar: AppBar(
        title: const Text('Simple Recorder'),
      ),
      body: makeBody(),
    );
  }

  Future<File> getFileFromAudio(String path) async {
    final byteData = await rootBundle.load(path);
    //File file2 = new File('assets/$path');
    //print(string);
    final file = File(path);
    //Future<File> file2 = file.copy('android/$path');
   // print(file2);
    await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

    return file;
  }
  /*
  this method is used on mobile to save record to a stream
   */
 /* Future<IOSink> createFile() async{

    var tempDir = await getTemporaryDirectory();
    _mPath = '${tempDir.path}/audioRecord.webm';
    _mPath= 'audioRecord.webm';
    print(_mPath);
    var outputFile = File(_mPath);
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    return outputFile.openWrite();
  }*/

  Future<Uint8List?> getAssetData(String path) async {
    var asset = await rootBundle.load(path);
    return asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
  }
}