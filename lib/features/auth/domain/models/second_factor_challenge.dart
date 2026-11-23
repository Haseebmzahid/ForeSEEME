import 'user_model.dart';

typedef VerifySecondFactor = Future<UserModel> Function(String code);

class SecondFactorChoice {
  final String label;
  final Future<VerifySecondFactor> Function() prepare;

  const SecondFactorChoice(this.label, this.prepare);
}
