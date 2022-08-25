import 'dart:isolate';

import 'package:dartssh2/dartssh2.dart';
import 'package:easy_isolate/easy_isolate.dart';
import 'package:toolbox/core/extension/stringx.dart';
import 'package:toolbox/core/extension/uint8list.dart';
import 'package:toolbox/data/model/server/cpu_2_status.dart';
import 'package:toolbox/data/model/server/cpu_status.dart';
import 'package:toolbox/data/model/server/disk_info.dart';
import 'package:toolbox/data/model/server/memory.dart';
import 'package:toolbox/data/model/server/net_speed.dart';
import 'package:toolbox/data/model/server/server_connection_state.dart';
import 'package:toolbox/data/model/server/server_private_info.dart';
import 'package:toolbox/data/model/server/server_status.dart';
import 'package:toolbox/data/model/server/snippet.dart';
import 'package:toolbox/data/model/server/tcp_status.dart';

const seperator = 'A====A';
const shellCmd = "export LANG=en_US.utf-8 \necho '$seperator' \n"
    "cat /proc/net/dev && date +%s \necho $seperator \n "
    "cat /etc/os-release | grep PRETTY_NAME \necho $seperator \n"
    "cat /proc/stat | grep cpu \necho $seperator \n"
    "uptime \necho $seperator \n"
    "cat /proc/net/snmp \necho $seperator \n"
    "df -h \necho $seperator \n"
    "cat /proc/meminfo \necho $seperator \n"
    "cat /sys/class/thermal/thermal_zone*/type \necho $seperator \n"
    "cat /sys/class/thermal/thermal_zone*/temp";
const shellPath = '.serverbox.sh';
final cpuTempReg = RegExp(r'(x86_pkg_temp|cpu_thermal)');
final numReg = RegExp(r'\s{1,}');
final memItemReg = RegExp(r'([A-Z].+:)\s+([0-9]+) kB');

final emptyMemory = Memory(total: 1, used: 0, free: 1, cache: 0, avail: 1);
final emptyNetSpeedPart = NetSpeedPart('', 0, 0, 0);
final emptyTcpStatus = TcpStatus(0, 0, 0, 0);
final emptyNetSpeed = NetSpeed([emptyNetSpeedPart], [emptyNetSpeedPart]);
final emptyCpuStatus = CpuStatus('cpu', 0, 0, 0, 0, 0, 0, 0);
final emptyCpu2Status = Cpu2Status([emptyCpuStatus], [emptyCpuStatus], '');
final emptyStatus = ServerStatus(
    emptyCpu2Status,
    emptyMemory,
    'Loading...',
    '',
    [DiskInfo('/', '/', 0, '0', '0', '0')],
    TcpStatus(0, 0, 0, 0),
    emptyNetSpeed);

enum ServerWorkerRequest {
  update,
}

class ServerWorker {
  ServerWorker({required this.onNotify, required this.spi, this.privateKey});

  final Function(Object event) onNotify;
  final ServerPrivateInfo spi;
  final String? privateKey;
  final worker = Worker();
  SSHClient? client;
  ServerStatus status = emptyStatus;

  void dispose() {
    worker.dispose();
  }

  /// Initiate the worker (new thread) and start listen from messages between
  /// the threads
  Future<void> init() async {
    if (worker.isInitialized) worker.dispose();
    await worker.init(
      mainMessageHandler,
      isolateMessageHandler,
      errorHandler: print,
    );
  }

  void update() {
    worker.sendMessage(ServerWorkerRequest.update);
  }

  /// Handle the messages coming from the isolate
  void mainMessageHandler(dynamic data, SendPort isolateSendPort) {
    onNotify(data);
  }

  /// Handle the messages coming from the main
  Future<void> isolateMessageHandler(
      dynamic data, SendPort mainSendPort, SendErrorFunction sendError) async {
    switch (data) {
      case Snippet:
        if (client == null) {
          mainSendPort.send('no client');
        }
        mainSendPort.send(SnippetResult(await runSnippet(data)));
        break;
      case ServerWorkerRequest.update:
        if (client == null) {
          mainSendPort.send(ServerConnectionState.connecting);
          final watch = Stopwatch()..start();
          try {
            final socket = await SSHSocket.connect(spi.ip, spi.port);
            if (spi.pubKeyId == null) {
              client = SSHClient(socket,
                  username: spi.user, onPasswordRequest: () => spi.pwd);
            } else {
              if (privateKey == null) {
                mainSendPort.send('No private key');
                return mainSendPort.send(ServerConnectionState.failed);
              }
              client = SSHClient(socket,
                  username: spi.user,
                  identities: SSHKeyPair.fromPem(privateKey!));
            }
            mainSendPort.send(ServerConnectionState.connected);

            mainSendPort.send(watch.elapsed);
          } catch (e) {
            mainSendPort.send(e);
            mainSendPort.send(ServerConnectionState.failed);
          } finally {
            watch.stop();
          }
        }
        final raw = await client!.run("sh $shellPath").string;
        final segments = raw.split(seperator).map((e) => e.trim()).toList();
        if (raw.isEmpty || segments.length == 1) {
          mainSendPort.send(ServerConnectionState.failed);
          if (status.failedInfo == null || status.failedInfo!.isEmpty) {
            status.failedInfo = 'No data received';
          }
          mainSendPort.send(status);
          return;
        }
        segments.removeAt(0);

        try {
          _getCPU(segments[2], segments[7], segments[8]);
          _getMem(segments[6]);
          _getSysVer(segments[1]);
          _getUpTime(segments[3]);
          _getDisk(segments[5]);
          _getTcp(segments[4]);
          _getNetSpeed(segments[0]);
        } catch (e) {
          mainSendPort.send(ServerConnectionState.failed);
          status.failedInfo = e.toString();
          rethrow;
        } finally {
          mainSendPort.send(status);
        }
    }
  }

  /// [raw] example:
  /// Inter-|   Receive                                                |  Transmit
  ///   face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  ///   lo: 45929941  269112    0    0    0     0          0         0 45929941  269112    0    0    0     0       0          0
  ///   eth0: 48481023  505772    0    0    0     0          0         0 36002262  202307    0    0    0     0       0          0
  /// 1635752901
  void _getNetSpeed(String raw) {
    final split = raw.split('\n');
    final deviceCount = split.length - 3;
    if (deviceCount < 1) return;
    final time = int.parse(split[split.length - 1]);
    final results = <NetSpeedPart>[];
    for (int idx = 2; idx < deviceCount; idx++) {
      final data = split[idx].trim().split(':');
      final device = data.first;
      final bytes = data.last.trim().split(' ');
      bytes.removeWhere((element) => element == '');
      final bytesIn = int.parse(bytes.first);
      final bytesOut = int.parse(bytes[8]);
      results.add(NetSpeedPart(device, bytesIn, bytesOut, time));
    }
    status.netSpeed.update(results);
  }

  void _getSysVer(String raw) {
    final s = raw.split('=');
    if (s.length == 2) {
      status.sysVer = s[1].replaceAll('"', '').replaceFirst('\n', '');
    }
  }

  String _getCPUTemp(String type, String value) {
    const noMatch = "/sys/class/thermal/thermal_zone*/type";
    // Not support to get CPU temperature
    if (value.contains(noMatch) ||
        type.contains(noMatch) ||
        value.isEmpty ||
        type.isEmpty) {
      return '';
    }
    final split = type.split('\n');
    int idx = 0;
    for (var item in split) {
      if (item.contains(cpuTempReg)) {
        break;
      }
      idx++;
    }
    final valueSplited = value.split('\n');
    if (idx >= valueSplited.length) return '';
    final temp = int.tryParse(valueSplited[idx].trim());
    if (temp == null) return '';
    return '${(temp / 1000).toStringAsFixed(1)}°C';
  }

  void _getCPU(String raw, String tempType, String tempValue) {
    final List<CpuStatus> cpus = [];

    for (var item in raw.split('\n')) {
      if (item == '') break;
      final id = item.split(' ').first;
      final matches = item.replaceFirst(id, '').trim().split(' ');
      cpus.add(CpuStatus(
          id,
          int.parse(matches[0]),
          int.parse(matches[1]),
          int.parse(matches[2]),
          int.parse(matches[3]),
          int.parse(matches[4]),
          int.parse(matches[5]),
          int.parse(matches[6])));
    }
    if (cpus.isNotEmpty) {
      status.cpu2Status.update(cpus, _getCPUTemp(tempType, tempValue));
    }
  }

  void _getUpTime(String raw) {
    status.uptime = raw.split('up ')[1].split(', ')[0];
  }

  void _getTcp(String raw) {
    final lines = raw.split('\n');
    final idx = lines.lastWhere((element) => element.startsWith('Tcp:'),
        orElse: () => '');
    if (idx != '') {
      final vals = idx.split(numReg);
      status.tcp = TcpStatus(vals[5].i, vals[6].i, vals[7].i, vals[8].i);
    }
  }

  void _getDisk(String raw) {
    final list = <DiskInfo>[];
    final items = raw.split('\n');
    for (var item in items) {
      if (items.indexOf(item) == 0 || item.isEmpty) {
        continue;
      }
      final vals = item.split(numReg);
      list.add(DiskInfo(vals[0], vals[5],
          int.parse(vals[4].replaceFirst('%', '')), vals[2], vals[1], vals[3]));
    }
    status.disk = list;
  }

  void _getMem(String raw) {
    final items = raw.split('\n').map((e) => memItemReg.firstMatch(e)).toList();
    final total = int.parse(
        items.firstWhere((e) => e?.group(1) == 'MemTotal:')?.group(2) ?? '1');
    final free = int.parse(
        items.firstWhere((e) => e?.group(1) == 'MemFree:')?.group(2) ?? '0');
    final cached = int.parse(
        items.firstWhere((e) => e?.group(1) == 'Cached:')?.group(2) ?? '0');
    final available = int.parse(
        items.firstWhere((e) => e?.group(1) == 'MemAvailable:')?.group(2) ??
            '0');
    status.memory = Memory(
        total: total,
        used: total - available,
        free: free,
        cache: cached,
        avail: available);
  }

  Future<String?> runSnippet(Snippet snippet) async {
    if (client == null) {
      return null;
    }
    return client!.run(snippet.script).string;
  }
}

class SnippetResult {
  final Object? result;
  const SnippetResult(this.result);
}
