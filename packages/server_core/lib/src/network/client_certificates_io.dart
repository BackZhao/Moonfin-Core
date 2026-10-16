import 'dart:io';

import 'client_certificate_material.dart';
import 'insecure_certificates.dart';

final _contexts = Expando<SecurityContext>();

/// Makes [client] present the certificate bound to each host it connects to.
///
/// An [HttpClient] holds one [SecurityContext] for its whole life, so the
/// context has to be picked per connection instead. dart:io tunnels proxied
/// connections with the client's own context, so mTLS through a proxy isn't
/// supported.
void applyClientCertificates(HttpClient client, {SecurityContext? fallback}) {
  client.connectionFactory = (uri, proxyHost, proxyPort) {
    if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
    if (!uri.isScheme('https') && !uri.isScheme('wss')) {
      return Socket.startConnect(uri.host, uri.port);
    }
    final certificate = clientCertificateFor(uri.host);
    return SecureSocket.startConnect(
      uri.host,
      uri.port,
      context: certificate == null
          ? fallback
          : _contexts[certificate] ??= _contextFor(certificate),
      onBadCertificate: (_) => gAllowSelfSignedCertificates,
    );
  };
}

SecurityContext _contextFor(ClientCertificateMaterial certificate) {
  return SecurityContext(withTrustedRoots: true)
    ..useCertificateChainBytes(certificate.chainPem.codeUnits)
    ..usePrivateKeyBytes(certificate.keyPem.codeUnits)
    // Same as the default context, for proxies that still renegotiate.
    ..allowLegacyUnsafeRenegotiation = true;
}
