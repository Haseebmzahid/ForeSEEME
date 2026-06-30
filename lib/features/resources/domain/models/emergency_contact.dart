/// An emergency service the user can dial with one tap.
class EmergencyContact {
  final String name;

  /// Dialable number (digits only), e.g. `"1122"`.
  final String number;

  /// Short descriptor, e.g. the service operator.
  final String description;

  const EmergencyContact({
    required this.name,
    required this.number,
    required this.description,
  });
}

/// Punjab Emergency Service — the primary one-tap emergency contact.
const EmergencyContact kRescue1122 = EmergencyContact(
  name: 'Rescue 1122',
  number: '1122',
  description: 'Punjab Emergency Service · ambulance & rescue',
);
