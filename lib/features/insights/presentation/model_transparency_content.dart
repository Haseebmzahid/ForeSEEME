// Static, SOURCED content for the Model Transparency page (Sprint 5, Prompt 7).
//
// Framework-free (no `package:flutter`) so it is directly unit-testable and can
// never drift into UI logic. Every statement here is drawn faithfully from the
// committed model documentation — nothing is invented:
//   • backend/ml/reports/MODEL_CARD.md          (model 1.0.0 / rf-1.0.0)
//   • backend/ml/reports/label_methodology.md   (labels, determinants, citations)
// If those source documents change, this content must be updated to match.

/// The headline honesty statement — environmental risk, NOT outbreak/clinical
/// prediction. Surfaced prominently at the top of the page.
const String kNotClinicalStatement =
    'ForeSeeMe estimates environmental disease-risk suitability — it is not '
    'outbreak prediction, and not a clinical or diagnostic tool.';

/// A documented sub-heading + its content, rendered as a card on the page.
class TransparencySection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const TransparencySection({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

/// The ordered sections of the transparency page. Sourced from the model card
/// and the label methodology (see file header).
const List<TransparencySection> kModelTransparencySections = [
  TransparencySection(
    title: 'What ForeSeeMe predicts',
    paragraphs: [
      'ForeSeeMe scores how favourable a city’s environment is, each week, '
          'for three disease families — dengue, smog / respiratory illness, and '
          'influenza. Each estimate is a Low, Medium or High environmental risk '
          'level with a confidence.',
      'It is built from a transparent, literature-grounded index of '
          'environmental suitability. The app only reads these estimates from the '
          'backend — the model never runs on your device.',
    ],
  ),
  TransparencySection(
    title: 'What it is NOT',
    bullets: [
      'Not outbreak prediction or forecasting — it does not predict case counts, '
          'epidemic timing, or transmission.',
      'Not clinical or diagnostic — it says nothing about any individual’s '
          'health and must not inform diagnosis or treatment.',
      'Not a substitute for official public-health surveillance — it complements '
          'it, never replaces it.',
      'Unsupported outside the five modelled cities or the environmental ranges '
          'it was trained on.',
    ],
  ),
  TransparencySection(
    title: 'Where the data comes from',
    paragraphs: [
      'Weather — temperature, humidity and precipitation — comes from Open-Meteo '
          'ERA5, and air quality — PM2.5, PM10 and US-AQI — from CAMS, for '
          'Islamabad, Rawalpindi, Lahore, Karachi and Peshawar.',
      'The records are weekly, from 5 August 2022 to 28 June 2026, bounded by '
          'real air-quality coverage. No records are fabricated or back-filled. '
          'The model is trained on the earliest 735 weeks and tested on the most '
          'recent 260 — a strict time-based split, never shuffled.',
    ],
  ),
  TransparencySection(
    title: 'How the risk labels are made',
    paragraphs: [
      'For each disease, documented environmental determinants are combined into '
          'a weighted suitability score from 0 to 1, then mapped to Low, Medium or '
          'High with a soft transition band. Every determinant, threshold and '
          'weight is cited to published literature.',
    ],
    bullets: [
      'Dengue — temperature (optimum ~26–30 °C), humidity, and rainfall 2–4 '
          'weeks earlier.',
      'Smog / respiratory — PM2.5, the October–January season, low temperature '
          'and low rainfall.',
      'Influenza — low temperature, low humidity, and the December–February '
          'winter window.',
    ],
  ),
  TransparencySection(
    title: 'The model',
    paragraphs: [
      'There is one scikit-learn pipeline per disease — median imputation, then '
          'scaling, then a balanced Random Forest — behind a single prediction '
          'interface. It reads 36 leakage-free engineered features: raw values, '
          '1–4 week lags, rolling averages, seasonal anomalies, a cyclical week '
          'encoding, and city indicators.',
    ],
  ),
  TransparencySection(
    title: 'How we judge it — honestly',
    paragraphs: [
      'Because the labels are derived from the same environmental features the '
          'model reads, high accuracy is expected by construction and is not the '
          'scientific claim. The model is evaluated as a calibrated surrogate of '
          'the environmental index.',
      'The evidence that matters is calibration (are the confidences '
          'trustworthy?), robustness to input noise, whether the important '
          'features match the epidemiology, and — decisively — whether High-risk '
          'weeks fall in the documented seasons. They do: smog concentrates in '
          'Oct–Jan, influenza in Dec–Feb, and dengue across the warm '
          'post-monsoon period.',
      'On the held-out test set the surrogate tracks the index closely (dengue, '
          'smog and influenza accuracy 0.85–0.95 with high ROC-AUC), but the '
          'accuracy figure is a consequence of the labelling, not a claim about '
          'real-world cases.',
    ],
  ),
  TransparencySection(
    title: 'Why each estimate looks the way it does',
    paragraphs: [
      'Every estimate carries the model’s own top environmental drivers — '
          'with their direction and strength — and a plain-language confidence '
          'rationale, shown on the Risk Details screen. These come directly from '
          'the model, not written by hand.',
    ],
  ),
  TransparencySection(
    title: 'Limitations',
    bullets: [
      'Environmental suitability, not incidence — it does not count or forecast '
          'cases and is not clinically validated.',
      'No human immunity, mobility, vaccination, vector control, or reporting '
          'effects are modelled.',
      'The weighting and Low/Medium/High cut-offs are transparent design '
          'choices, not derived constants — an examiner can and should challenge '
          'them.',
      'The data window is short (from August 2022), so long-term climatological '
          'context is limited.',
      'Risk is only as fresh as the weekly pipeline; stale or missing data is '
          'flagged, never hidden.',
    ],
  ),
];

/// Peer-reviewed sources behind the label determinants (from the label
/// methodology). Listed to make the honest-labelling story auditable.
const List<String> kTransparencyCitations = [
  'Mordecai EA, et al. (2017). Temperature and transmission of dengue, Zika and '
      'chikungunya. PLoS Neglected Tropical Diseases 11(4):e0005568.',
  'Naish S, et al. (2014). Climate change and dengue: a systematic review. BMC '
      'Infectious Diseases 14:167.',
  'Reiter P. (2001). Climate change and mosquito-borne disease. Environmental '
      'Health Perspectives 109(Suppl 1):141–161.',
  'WHO (2021). Global Air Quality Guidelines — PM2.5 24-hour level 15 µg/m³.',
  'US EPA. Air Quality Index (AQI) technical assistance — PM2.5 breakpoints.',
  'Lowen AC, et al. (2007). Influenza transmission depends on humidity and '
      'temperature. PLoS Pathogens 3(10):e151.',
  'Shaman J, Kohn M. (2009). Absolute humidity modulates influenza seasonality. '
      'PNAS 106(9):3243–3248.',
];

/// Provenance footer — pins the exact model version and source documents.
const String kTransparencyFooter =
    'Model version rf-1.0.0 (seed 42). Sourced from the ForeSeeMe Model Card '
    '1.0.0 and the label methodology (backend/ml/reports).';
