import 'package:toolbox/data/model/server/server_connection_state.dart';
import 'package:toolbox/data/model/server/server_private_info.dart';
import 'package:toolbox/data/model/server/server_status.dart';

class ServerInfo {
  ServerPrivateInfo info;
  ServerStatus status;
  ServerConnectionState connectionState;

  ServerInfo(this.info, this.status, this.connectionState);
}
