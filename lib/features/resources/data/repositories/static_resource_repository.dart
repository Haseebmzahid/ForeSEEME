import 'package:fyp_foreseeme/features/resources/domain/models/emergency_contact.dart';
import 'package:fyp_foreseeme/features/resources/domain/models/resource_article.dart';
import 'package:fyp_foreseeme/features/resources/domain/repositories/resource_repository.dart';

/// The original, hardcoded Resource Center content.
///
/// Superseded as the **default** production source by
/// [FirestoreResourceRepository] in Sprint M8.3 (SDS FR8.3 — content must be
/// admin-editable), but kept as: (a) the seed data written to Firestore by
/// `backend/scripts/seed_resource_articles.py`, (b) the graceful-degradation
/// fallback [FirestoreResourceRepository] returns if the live collection has
/// never been seeded, and (c) a fast, dependency-free fixture for tests.
///
/// Every article is conservative, widely-accepted public-health guidance
/// attributed to a named authority with a stable source URL — no fabricated or
/// unsourced medical claims. Two articles per topic reuse the SAME vetted
/// source URL for that organisation rather than guessing at a new deep link,
/// so every citation stays honest. The guidance is general and is **not** a
/// substitute for professional medical advice (surfaced as a disclaimer in the
/// UI).
class StaticResourceRepository implements ResourceRepository {
  const StaticResourceRepository();

  static const _who = 'World Health Organization (WHO)';
  static const _whoAirUrl = 'https://www.who.int/health-topics/air-pollution';
  static const _whoHeatUrl = 'https://www.who.int/health-topics/heatwaves';
  static const _cdc = 'U.S. Centers for Disease Control and Prevention (CDC)';
  static const _cdcAsthmaUrl = 'https://www.cdc.gov/asthma/';
  static const _epa = 'U.S. EPA — AirNow';
  static const _epaUrl = 'https://www.airnow.gov/aqi/aqi-basics/';

  @override
  EmergencyContact emergencyContact() => kRescue1122;

  /// The 8 curated articles below, wrapped in an already-resolved [Future] —
  /// this repository never actually awaits anything, matching
  /// [ResourceRepository]'s async contract without adding any real latency.
  @override
  Future<List<ResourceArticle>> articles() => Future.value(_articles);

  static const List<ResourceArticle> _articles = [
    ResourceArticle(
      id: 'lungs-smog',
      title: 'Protecting your lungs on smog days',
      summary: 'Cut your exposure to fine particles when air quality is poor.',
      topic: ResourceTopic.lungs,
      sourceName: _who,
      sourceUrl: _whoAirUrl,
      content: [
        ArticleBlock.heading('Before you go outside'),
        ArticleBlock.paragraph(
          'Check your local Air Quality Index before heading out, and limit '
          'prolonged or heavy outdoor exertion when it is high.',
        ),
        ArticleBlock.paragraph(
          'Keep windows and doors closed during peak smog hours to reduce '
          'indoor particle levels.',
        ),
        ArticleBlock.heading('If you must be outside'),
        ArticleBlock.tip(
          'A well-fitted N95/FFP2 mask reduces the fine particles you '
          'inhale during heavy smog.',
        ),
        ArticleBlock.paragraph(
          'Indoors, a HEPA air purifier can lower fine-particle '
          'concentrations.',
        ),
        ArticleBlock.warning(
          'Avoid adding indoor smoke — cigarettes, incense, or unventilated '
          'cooking — on top of outdoor smog.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'lungs-indoor-air',
      title: 'Indoor air quality on polluted days',
      summary: 'Keep the air inside cleaner while outdoor smog is high.',
      topic: ResourceTopic.lungs,
      sourceName: _who,
      sourceUrl: _whoAirUrl,
      content: [
        ArticleBlock.heading('Reduce indoor sources'),
        ArticleBlock.paragraph(
          'Most indoor air pollution comes from combustion — cooking smoke, '
          'candles, incense and tobacco — so cutting these sources matters as '
          'much as sealing out the smog outside.',
        ),
        ArticleBlock.tip(
          'Use an extractor fan or open a window briefly while cooking, then '
          'reseal the room once smoke has cleared.',
        ),
        ArticleBlock.heading('When outdoor air improves'),
        ArticleBlock.paragraph(
          'Ventilate during the cleanest part of the day (check your AQI '
          'trend) rather than leaving windows open continuously.',
        ),
        ArticleBlock.warning(
          'Never use an unvented gas or charcoal appliance indoors — it can '
          'raise indoor pollution and carbon-monoxide risk sharply.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'asthma-poor-air',
      title: 'Managing asthma when air quality is poor',
      summary: 'Stay ahead of flare-ups on high-pollution days.',
      topic: ResourceTopic.asthma,
      sourceName: _cdc,
      sourceUrl: _cdcAsthmaUrl,
      content: [
        ArticleBlock.heading('Stay ahead of a flare-up'),
        ArticleBlock.paragraph(
          'Keep your reliever (rescue) inhaler with you and follow your '
          'written asthma action plan.',
        ),
        ArticleBlock.tip(
          'Move exercise indoors or to cleaner-air times of day when the '
          'Air Quality Index is high.',
        ),
        ArticleBlock.heading('At home'),
        ArticleBlock.paragraph(
          'Reduce indoor triggers: no smoking indoors, manage dust, and keep '
          'indoor air as clean as possible.',
        ),
        ArticleBlock.warning(
          'If symptoms worsen — frequent coughing, wheezing or '
          'breathlessness — seek medical care promptly.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'asthma-action-plan',
      title: 'Building your asthma action plan',
      summary: 'A written plan turns a bad day into a manageable one.',
      topic: ResourceTopic.asthma,
      sourceName: _cdc,
      sourceUrl: _cdcAsthmaUrl,
      content: [
        ArticleBlock.heading('What a plan covers'),
        ArticleBlock.paragraph(
          'A written asthma action plan sets out your daily medicines, the '
          'early warning signs of a flare-up, and exactly what to do at each '
          'stage — agreed in advance with your clinician.',
        ),
        ArticleBlock.tip(
          'Keep a copy where you can find it quickly, and share one with a '
          'family member or housemate.',
        ),
        ArticleBlock.heading('Reviewing it'),
        ArticleBlock.paragraph(
          'Revisit the plan with your clinician after any flare-up, or at '
          'least once a year, so it stays matched to how your asthma is '
          'behaving.',
        ),
        ArticleBlock.warning(
          'A plan is guidance, not a diagnosis — always follow your own '
          'clinician\'s instructions over general guidance like this.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'when-to-stay-indoors',
      title: 'When to stay indoors (Air Quality Index)',
      summary: 'What each AQI band means for outdoor activity.',
      topic: ResourceTopic.airQuality,
      sourceName: _epa,
      sourceUrl: _epaUrl,
      content: [
        ArticleBlock.heading('Reading the bands'),
        ArticleBlock.paragraph(
          'AQI 0–50 (Good): air quality is satisfactory; no precautions '
          'needed.',
        ),
        ArticleBlock.paragraph(
          'AQI 51–100 (Moderate): unusually sensitive people should consider '
          'limiting prolonged outdoor exertion.',
        ),
        ArticleBlock.paragraph(
          'AQI 101–150 (Unhealthy for Sensitive Groups): sensitive groups '
          '(children, older adults, heart/lung conditions) should reduce '
          'prolonged outdoor exertion.',
        ),
        ArticleBlock.heading('When it gets serious'),
        ArticleBlock.tip(
          'AQI 151–200 (Unhealthy): everyone should reduce prolonged '
          'outdoor exertion; sensitive groups should avoid it.',
        ),
        ArticleBlock.warning(
          'AQI 201+ (Very Unhealthy/Hazardous): avoid outdoor activity and '
          'stay indoors with clean air where possible.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'aqi-pm-sizes',
      title: 'Understanding PM2.5 vs PM10',
      summary: 'The two particle sizes behind most AQI readings, explained.',
      topic: ResourceTopic.airQuality,
      sourceName: _epa,
      sourceUrl: _epaUrl,
      content: [
        ArticleBlock.heading('What the numbers mean'),
        ArticleBlock.paragraph(
          'PM2.5 (particles under 2.5 micrometres) travel deepest into the '
          'lungs and bloodstream and drive most health guidance; PM10 '
          '(under 10 micrometres) affects the upper airway more.',
        ),
        ArticleBlock.tip(
          'On a smoggy day, PM2.5 is usually the number worth checking — it '
          'is the more sensitive signal.',
        ),
        ArticleBlock.heading('Where they come from'),
        ArticleBlock.paragraph(
          'Vehicle exhaust, industrial smoke and burning are common PM2.5 '
          'sources; dust and pollen contribute more to PM10.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'extreme-heat',
      title: 'Staying safe in extreme heat',
      summary: 'Reduce heat-illness risk during hot spells.',
      topic: ResourceTopic.heat,
      sourceName: _who,
      sourceUrl: _whoHeatUrl,
      content: [
        ArticleBlock.heading('Through the day'),
        ArticleBlock.paragraph(
          'Drink water regularly through the day, even before you feel '
          'thirsty.',
        ),
        ArticleBlock.paragraph(
          'Avoid the sun during the hottest hours and limit strenuous '
          'activity.',
        ),
        ArticleBlock.tip(
          'Keep your living space cool — shade windows, ventilate at '
          'night.',
        ),
        ArticleBlock.heading('Warning signs'),
        ArticleBlock.warning(
          'Watch for heat exhaustion (dizziness, headache, nausea); move to '
          'a cool place, rest and rehydrate, and seek help if it does not '
          'improve. Never leave children or pets in a parked vehicle.',
        ),
      ],
    ),
    ResourceArticle(
      id: 'heat-exhaustion-vs-stroke',
      title: 'Recognizing heat exhaustion vs heat stroke',
      summary: 'Know the difference — one of them is a medical emergency.',
      topic: ResourceTopic.heat,
      sourceName: _who,
      sourceUrl: _whoHeatUrl,
      content: [
        ArticleBlock.heading('Heat exhaustion'),
        ArticleBlock.paragraph(
          'Heavy sweating, dizziness, headache, nausea and cool clammy skin. '
          'Move to shade or air conditioning, loosen clothing, and rehydrate '
          'with water.',
        ),
        ArticleBlock.heading('Heat stroke'),
        ArticleBlock.paragraph(
          'Hot, dry or flushed skin, confusion, or loss of consciousness are '
          'signs the body has stopped regulating its temperature.',
        ),
        ArticleBlock.warning(
          'Heat stroke is a medical emergency. Call for emergency help '
          'immediately and cool the person while waiting — do not wait to '
          'see if it improves.',
        ),
      ],
    ),
  ];
}
