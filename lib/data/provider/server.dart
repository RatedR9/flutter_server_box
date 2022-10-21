import 'dart:async';

import 'package:logging/logging.dart';
import 'package:toolbox/core/provider_base.dart';
import 'package:toolbox/data/model/server/server_connection_state.dart';
import 'package:toolbox/data/model/server/server.dart';
import 'package:toolbox/data/model/server/server_private_info.dart';
import 'package:toolbox/data/model/server/server_status.dart';
import 'package:toolbox/data/model/server/server_worker.dart';
import 'package:toolbox/data/model/server/snippet.dart';
import 'package:toolbox/data/store/private_key.dart';
import 'package:toolbox/data/store/server.dart';
import 'package:toolbox/data/store/setting.dart';
import 'package:toolbox/locator.dart';

class ServerProvider extends BusyProvider {
  List<ServerInfo> _servers = [];
  List<ServerInfo> get servers => _servers;
  final Map<String, ServerWorker> _workers = {};
  final Map<String, String?> _snippetResults = {};

  Timer? _timer;

  final logger = Logger('ServerProvider');

  Future<void> loadLocalData() async {
    setBusyState(true);
    final infos = locator<ServerStore>().fetch();
    _servers = List.generate(infos.length, (index) => genInfo(infos[index]));
    setBusyState(false);
    notifyListeners();
  }

  ServerInfo genInfo(ServerPrivateInfo spi) {
    return ServerInfo(spi, emptyStatus, ServerConnectionState.disconnected);
  }

  Future<void> refreshData({ServerPrivateInfo? spi}) async {
    if (spi != null) {
      _getData(spi);
      return;
    }
    await Future.wait(_servers.map((s) async {
      await _getData(s.info);
    }));
  }

  Future<void> startAutoRefresh() async {
    final duration =
        locator<SettingStore>().serverStatusUpdateInterval.fetch()!;
    if (duration == 0) return;
    stopAutoRefresh();
    _timer = Timer.periodic(Duration(seconds: duration), (_) async {
      await refreshData();
    });
  }

  void stopAutoRefresh() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void setDisconnected() {
    for (var i = 0; i < _servers.length; i++) {
      _servers[i].connectionState = ServerConnectionState.disconnected;
    }
  }

  void addServer(ServerPrivateInfo spi) {
    _servers.add(genInfo(spi));
    locator<ServerStore>().put(spi);
    notifyListeners();
    refreshData(spi: spi);
  }

  void delServer(ServerPrivateInfo info) {
    _workers[info.id]?.dispose();
    _workers.remove(info.id);
    final idx = _servers.indexWhere((s) => s.info == info);
    _servers.removeAt(idx);
    notifyListeners();
    locator<ServerStore>().delete(info);
  }

  Future<void> updateServer(
      ServerPrivateInfo old, ServerPrivateInfo newSpi) async {
    final idx = _servers.indexWhere((e) => e.info == old);
    if (idx < 0) {
      throw RangeError.index(idx, _servers);
    }
    _servers[idx].info = newSpi;
    locator<ServerStore>().update(old, newSpi);
    notifyListeners();
    refreshData(spi: newSpi);
  }

  Future<void> _getData(ServerPrivateInfo spi) async {
    final spiId = spi.id;
    if (!_workers.containsKey(spiId)) {
      final keyId = spi.pubKeyId;
      final privateKey =
          keyId == null ? null : locator<PrivateKeyStore>().get(keyId);
      _workers[spiId] = ServerWorker(
          onNotify: (event) => onNotify(event, spiId),
          spi: spi,
          privateKey: privateKey?.privateKey);
      _workers[spiId]?.init();
    }

    _workers[spiId]?.update();
  }

  Future<String?> runSnippet(ServerPrivateInfo spi, Snippet snippet) async {
    final spiId = spi.id;
    if (!_workers.containsKey(spiId)) {
      final keyId = spi.pubKeyId;
      final privateKey =
          keyId == null ? null : locator<PrivateKeyStore>().get(keyId);
      _workers[spiId] = ServerWorker(
          onNotify: (event) => onNotify(event, spiId),
          spi: spi,
          privateKey: privateKey?.privateKey);
      _workers[spiId]?.init();
    }

    final result = await _workers[spiId]?.runSnippet(snippet);
    if (result != null) {
      _snippetResults[spiId] = result;
    }
    return result;
  }

  void onNotify(dynamic event, String id) {
    final idx = _servers.indexWhere((s) => s.info.id == id);
    if (idx < 0) {
      throw RangeError.index(idx, _servers);
    }
    switch (event.runtimeType) {
      case ServerStatus:
        _servers[idx].status = event;
        break;
      case ServerConnectionState:
        _servers[idx].connectionState = event;
        break;
      case String:
        _servers[idx].status.failedInfo = event;
        break;
      case Exception:
        _servers[idx].status.failedInfo = event.toString();
        break;
      case Duration:
        logger.info('Connected to [$id] in $event');
        break;
      case SnippetResult:
        _snippetResults[id] = event.result;
        break;
    }
    notifyListeners();
  }
}
