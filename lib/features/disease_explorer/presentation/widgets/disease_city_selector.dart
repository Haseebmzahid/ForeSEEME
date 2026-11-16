import 'package:flutter/material.dart';
import '../../../../core/theme/foreseeme_theme.dart';
import '../../../../core/theme/foreseeme_tokens.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../health_profile/domain/constants/cities_constants.dart';
import 'disease_glass.dart';

class DiseaseCitySelector extends StatelessWidget {
  const DiseaseCitySelector({
    super.key,
    required this.city,
    required this.onChanged,
  });
  final String city;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DiseaseGlass(
    radius: ForeSeeMeRadius.lg,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: AnimatedSwitcher(
      duration: AppMotion.reduceMotion(context)
          ? Duration.zero
          : AppMotion.fast,
      child: DropdownButtonFormField<String>(
        key: ValueKey(city),
        initialValue: city,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Selected city',
          prefixIcon: Icon(
            Icons.location_on_outlined,
            color: context.fsmPalette.secondary,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          filled: false,
        ),
        items: [
          for (final name in kSupportedCities)
            DropdownMenuItem(value: name, child: Text(name)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    ),
  );
}
