/// 구독 관련 에러 타입 정의
enum SubscriptionErrorType {
  networkError,
  paymentError,
  serviceUnavailable,
  userCancelled,
  alreadySubscribed,
  invalidProduct,
  unknown,
}