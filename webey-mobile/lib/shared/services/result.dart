class Result<T> {
  const Result._({
    required this.success,
    this.data,
    this.errorMessage,
    this.statusCode,
  });

  final bool success;
  final T? data;
  final String? errorMessage;
  final int? statusCode;

  bool get isFailure => !success;

  static Result<T> ok<T>(T data, {int? statusCode}) {
    return Result._(success: true, data: data, statusCode: statusCode);
  }

  static Result<void> empty({int? statusCode}) {
    return Result._(success: true, statusCode: statusCode);
  }

  static Result<T> fail<T>(String message, {int? statusCode}) {
    return Result._(
      success: false,
      errorMessage: message,
      statusCode: statusCode,
    );
  }
}
