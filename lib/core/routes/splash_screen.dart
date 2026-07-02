import 'package:flutter/material.dart';

import 'package:fyp_foreseeme/core/widgets/brand_loading.dart';

/// App-level gate shown at `/` while auth + profile state resolve. Uses the
/// unified branded loader so the very first frame speaks the same loading
/// language as the rest of the app (never a bare spinner).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: BrandLoading());
  }
}
