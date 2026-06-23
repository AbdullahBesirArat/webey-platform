-- Business in-app notification type for customer reviews.
ALTER TABLE `notifications`
  MODIFY `type` enum('booking','cancellation','review','subscription_expiry_3d','subscription_expiry_1d','subscription_expired')
  COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'booking';
