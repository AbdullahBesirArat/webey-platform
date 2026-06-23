import '../mock/mock_data.dart';
import '../models/beauty_models.dart';
import 'result.dart';

abstract class NotificationRepository {
  Future<Result<List<NotificationItem>>> getNotifications();

  Future<Result<void>> markAllRead();
}

class MockNotificationRepository implements NotificationRepository {
  const MockNotificationRepository();

  @override
  Future<Result<List<NotificationItem>>> getNotifications() async {
    return Result.ok(MockData.notifications);
  }

  @override
  Future<Result<void>> markAllRead() async {
    return Result.empty();
  }
}
