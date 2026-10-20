import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaddai_reader/features/home/home_feed.dart';

DioException _http(int code) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
      type: DioExceptionType.badResponse,
    );

void main() {
  test('401 and 403 mean the login was rejected', () {
    expect(isLoginRejected(_http(401)), isTrue);
    expect(isLoginRejected(_http(403)), isTrue);
  });

  test('other failures are not login problems', () {
    expect(isLoginRejected(_http(500)), isFalse);
    expect(
      isLoginRejected(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      )),
      isFalse,
    );
  });

  test('a wrapped unauthorized message still counts', () {
    expect(isLoginRejected(Exception('Unauthorized')), isTrue);
  });
}
