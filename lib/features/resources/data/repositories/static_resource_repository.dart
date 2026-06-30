import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_repository.dart';

/// Ships the curated Resource Center content with the app.
///
/// Every article is conservative, widely-accepted public-health guidance
/// attributed to a named authority with a stable source URL — no fabricated or
/// unsourced medical claims. The guidance is general and is **not** a substitute
/// for professional medical advice (surfaced as a disclaimer in the UI).
class StaticResourceRepository implements ResourceRepository {
  const StaticResourceRepository();

  @override
  EmergencyContact emergencyContact() => kRescue1122;

  @override
  List<ResourceArticle> articles() => const [
    ResourceArticle(
      id: 'lungs-smog',
      title: 'Protecting your lungs on smog days',
      summary: 'Cut your exposure to fine particles when air quality is poor.',
      topic: ResourceTopic.lungs,
      sourceName: 'World Health Organization (WHO)',
      sourceUrl: 'https://www.who.int/health-topics/air-pollution',
      body: [
        'Check your local Air Quality Index before going outside and limit '
            'prolonged or heavy outdoor exertion when it is high.',
        'Keep windows and doors closed during peak smog hours to reduce '
            'indoor particle levels.',
        'If you must be outdoors during heavy smog, a well-fitted N95/FFP2 '
            'mask reduces inhaled fine particles.',
        'Indoors, a HEPA air purifier can lower fine-particle concentrations.',
        'Avoid adding indoor smoke (cigarettes, incense, unventilated cooking).',
      ],
    ),
    ResourceArticle(
      id: 'asthma-poor-air',
      title: 'Managing asthma when air quality is poor',
      summary: 'Stay ahead of flare-ups on high-pollution days.',
      topic: ResourceTopic.asthma,
      sourceName: 'U.S. Centers for Disease Control and Prevention (CDC)',
      sourceUrl: 'https://www.cdc.gov/asthma/',
      body: [
        'Keep your reliever (rescue) inhaler with you and follow your written '
            'asthma action plan.',
        'Avoid outdoor exercise when the Air Quality Index is high; move '
            'activity indoors or to cleaner-air times of day.',
        'Reduce indoor triggers: no smoking indoors, manage dust, and keep '
            'indoor air as clean as possible.',
        'If symptoms worsen — frequent coughing, wheezing or breathlessness — '
            'seek medical care promptly.',
      ],
    ),
    ResourceArticle(
      id: 'when-to-stay-indoors',
      title: 'When to stay indoors (Air Quality Index)',
      summary: 'What each AQI band means for outdoor activity.',
      topic: ResourceTopic.airQuality,
      sourceName: 'U.S. EPA — AirNow',
      sourceUrl: 'https://www.airnow.gov/aqi/aqi-basics/',
      body: [
        'AQI 0–50 (Good): air quality is satisfactory; no precautions needed.',
        'AQI 51–100 (Moderate): unusually sensitive people should consider '
            'limiting prolonged outdoor exertion.',
        'AQI 101–150 (Unhealthy for Sensitive Groups): sensitive groups '
            '(children, older adults, heart/lung conditions) should reduce '
            'prolonged outdoor exertion.',
        'AQI 151–200 (Unhealthy): everyone should reduce prolonged outdoor '
            'exertion; sensitive groups should avoid it.',
        'AQI 201+ (Very Unhealthy/Hazardous): avoid outdoor activity and stay '
            'indoors with clean air where possible.',
      ],
    ),
    ResourceArticle(
      id: 'extreme-heat',
      title: 'Staying safe in extreme heat',
      summary: 'Reduce heat-illness risk during hot spells.',
      topic: ResourceTopic.heat,
      sourceName: 'World Health Organization (WHO)',
      sourceUrl: 'https://www.who.int/health-topics/heatwaves',
      body: [
        'Drink water regularly through the day, even before you feel thirsty.',
        'Avoid the sun during the hottest hours and limit strenuous activity.',
        'Keep your living space cool — shade windows, ventilate at night.',
        'Never leave children or pets in a parked vehicle.',
        'Watch for heat exhaustion (dizziness, headache, nausea); move to a '
            'cool place, rest and rehydrate, and seek help if it does not '
            'improve.',
      ],
    ),
  ];
}
