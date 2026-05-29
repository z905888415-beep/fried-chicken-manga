import 'package:dio/dio.dart';

/// App-wide network error helpers.
class NetworkError {
  static const rateLimitMessage = '请求过于频繁，已被限速，请稍后再试';

  static Interceptor rateLimitInterceptor() {
    return InterceptorsWrapper(
      onResponse: (response, handler) {
        if (response.statusCode == 429) {
          return handler.reject(_rateLimitFromResponse(response));
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (isRateLimited(error)) {
          return handler.reject(_rateLimitFromError(error));
        }
        handler.next(error);
      },
    );
  }

  static bool isRateLimited(Object? error) {
    if (error is RateLimitDioException) return true;
    if (error is DioException) return error.response?.statusCode == 429;
    if (error is Response) return error.statusCode == 429;
    return false;
  }

  static String message(Object error) {
    if (isRateLimited(error)) return rateLimitMessage;
    if (error is DioException) {
      final dataMessage = _messageFromData(error.response?.data);
      if (dataMessage != null) return dataMessage;
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
    }
    return error.toString();
  }

  static String? _messageFromData(Object? data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  static RateLimitDioException _rateLimitFromResponse(
    Response<dynamic> response,
  ) {
    return RateLimitDioException(
      requestOptions: response.requestOptions,
      response: response,
    );
  }

  static RateLimitDioException _rateLimitFromError(DioException error) {
    return RateLimitDioException(
      requestOptions: error.requestOptions,
      response: error.response,
      type: error.type,
      stackTrace: error.stackTrace,
    );
  }
}

class RateLimitDioException extends DioException {
  RateLimitDioException({
    required super.requestOptions,
    super.response,
    super.type = DioExceptionType.badResponse,
    super.stackTrace,
  }) : super(
         error: NetworkError.rateLimitMessage,
         message: NetworkError.rateLimitMessage,
       );

  @override
  String toString() => NetworkError.rateLimitMessage;
}
