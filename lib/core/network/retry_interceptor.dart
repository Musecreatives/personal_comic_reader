import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

/// Retries a request once or twice on transient failures: 5xx responses,
/// connection timeouts, and connection errors. Does not retry 4xx - those
/// are the caller's problem (bad auth, bad request, etc).
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Random _random = Random();

  RetryInterceptor({required this.dio, this.maxRetries = 2});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['retryAttempt'] as int?) ?? 0;

    if (attempt >= maxRetries || !_isRetryable(err)) {
      handler.next(err);
      return;
    }

    final delayMs = 200 * pow(2, attempt).toInt() + _random.nextInt(100);
    await Future.delayed(Duration(milliseconds: delayMs));

    final options = err.requestOptions;
    options.extra['retryAttempt'] = attempt + 1;

    try {
      final response = await dio.fetch(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _isRetryable(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode;
    return status != null && status >= 500;
  }
}
