import 'package:dartssh2/dartssh2.dart';
import 'package:toolbox/data/model/server/server_private_info.dart';
import 'package:toolbox/data/model/server/server_status.dart';

class Server {
  ServerPrivateInfo spi;
  ServerStatus status;
  SSHClient? client;
  ServerState state;

  Server(this.spi, this.status, this.client, this.state);
}

enum ServerState {
  disconnected,
  connecting,
  connected,
  failed;

  bool get shouldConnect =>
      this == ServerState.disconnected || this == ServerState.failed;
}
