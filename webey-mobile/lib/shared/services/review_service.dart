import '../mock/mock_data.dart';
import '../models/beauty_models.dart';
import 'result.dart';

abstract class ReviewRepository {
  Future<Result<List<Review>>> getSalonReviews(String salonId);

  Future<Result<void>> replyToReview(String reviewId, String reply);
}

class MockReviewRepository implements ReviewRepository {
  const MockReviewRepository();

  @override
  Future<Result<List<Review>>> getSalonReviews(String salonId) async {
    return Result.ok(MockData.reviewsForSalon(salonId));
  }

  @override
  Future<Result<void>> replyToReview(String reviewId, String reply) async {
    if (reply.trim().isEmpty) return Result.fail('Yanıt boş olamaz.');
    return Result.empty();
  }
}
