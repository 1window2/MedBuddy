// File Name: pooled_http_transport.dart
// Role: Lets screen-owned API clients share one connection pool while each still aborts its own requests when closed.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// Class Name: PooledHttpTransport
// Role: Sends requests through one isolate-wide HTTP client instead of a new client per owner.
// Responsibilities:
// - Reuse kept-alive connections, so a screen recreated on every visit does not pay a new TCP and TLS handshake.
// - On close, abort only the requests this owner started, as closing an owned client did, and leave the shared pool open.
// Attributes:
// - _pooledClient (IOClient?): The isolate's default transport, created on first use.
// - _shared (http.Client): Transport this owner sends through.
// - _ownsTransport (bool): Whether close also closes _shared (a client from an http.runWithClient zone).
// - _closing (Completer<void>): Completed by close to abort this owner's requests.
class PooledHttpTransport extends http.BaseClient {
  static IOClient? _pooledClient;
  final http.Client _shared;
  final bool _ownsTransport;
  final Completer<void> _closing = Completer<void>();

  // Function Name: PooledHttpTransport
  // Description: Uses the isolate-wide client unless a test supplies a shared transport or the current zone overrides http.Client() with http.runWithClient.
  // Parameters:
  // - shared (http.Client?): Shared transport; it is never closed by this owner.
  // Returns:
  // - PooledHttpTransport: the initialized instance.
  factory PooledHttpTransport({http.Client? shared}) {
    if (shared != null) return PooledHttpTransport._(shared, owns: false);
    final client = http.Client();
    if (client is! IOClient) {
      // A zone override (tests use http.runWithClient) keeps its per-owner client and close behaviour.
      return PooledHttpTransport._(client, owns: true);
    }
    final pooled = _pooledClient;
    if (pooled == null) {
      _pooledClient = client;
      return PooledHttpTransport._(client, owns: false);
    }
    client.close();
    return PooledHttpTransport._(pooled, owns: false);
  }

  // Function Name: PooledHttpTransport._
  // Description: Binds the transport and whether this owner closes it.
  // Parameters: shared: transport to send through; owns: close it on close.
  // Returns: PooledHttpTransport: the initialized instance.
  PooledHttpTransport._(this._shared, {required bool owns})
    : _ownsTransport = owns;

  // Function Name: send
  // Description: Forwards the request as an abortable copy whose trigger fires on close or on the caller's own abort trigger.
  // Parameters:
  // - request (http.BaseRequest): Request to send.
  // Returns:
  // - Future<http.StreamedResponse>: The shared transport's response; a request started after close fails with RequestAbortedException.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closing.isCompleted) {
      return Future.error(http.RequestAbortedException(request.url));
    }
    final callerTrigger = request is http.Abortable
        ? request.abortTrigger
        : null;
    // finalize first: a multipart request writes its Content-Type with the part boundary only then.
    final body = request.finalize();
    final copy =
        http.AbortableStreamedRequest(
            request.method,
            request.url,
            abortTrigger: callerTrigger == null
                ? _closing.future
                : Future.any([_closing.future, callerTrigger]),
          )
          ..headers.addAll(request.headers)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection
          ..contentLength = request.contentLength;
    // A body stream error is forwarded into the copy, so the shared transport fails the request as before.
    unawaited(
      copy.sink
          .addStream(body)
          .whenComplete(copy.sink.close)
          .catchError((Object _) {}),
    );
    return _shared.send(copy);
  }

  // Function Name: close
  // Description: Aborts this owner's unfinished requests and refuses new ones without closing the shared pool.
  // Parameters:
  // - None.
  // Returns:
  // - None.
  @override
  void close() {
    if (!_closing.isCompleted) _closing.complete();
    if (_ownsTransport) _shared.close();
  }
}
