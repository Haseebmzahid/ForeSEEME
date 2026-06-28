# Disease & Seasonality Reference — VALIDATION ONLY

> **CLASSIFICATION: VALIDATION_ONLY**
>
> This dataset exists **solely** to validate the epidemiological plausibility of generated risk labels (Prompt 12). It is **never** a training feature or label. A code guard (`ValidationOnlyAccessError`) blocks any module named like `*feature*`, `*label*`, or `*train*` from importing or loading it.

_Encoded 2026-06-28. Region: Pakistan — Islamabad, Rawalpindi, Lahore, Karachi, Peshawar._

Where only qualitative seasonality is public, it is encoded as a structured, sourced table. Every entry is attributed to the responsible public-health / government body or to documented seasonality — nothing here is fabricated, and no uncited claims are included.

## Seasonal windows

| Disease / signal | Window | Cities | Citation |
|------------------|--------|--------|----------|
| Dengue | August–November (post-monsoon) | Islamabad, Rawalpindi, Lahore, Karachi, Peshawar | [WHO Regional Office for the Eastern Mediterranean (EMRO) — Pakistan](https://www.emro.who.int/pak/) |
| Air-quality hazard (smog / particulate exposure) | October–January (smog season) | Lahore, Rawalpindi, Islamabad | Government of Punjab (Environmental Protection Department) — smog-season advisories; documented air-quality literature |
| Influenza (seasonal) | December–February (winter) | Islamabad, Rawalpindi, Lahore, Karachi, Peshawar | [WHO Global Influenza Programme](https://www.who.int/teams/global-influenza-programme) |

## Documented outbreak years

| Year | Disease | Region | Citation |
|------|---------|--------|----------|
| 2011 | Dengue | Lahore | [WHO EMRO Pakistan / Government of Punjab dengue response](https://www.emro.who.int/pak/) |
| 2019 | Dengue | Islamabad, Rawalpindi, Karachi, Lahore | [WHO EMRO Pakistan](https://www.emro.who.int/pak/) |

## Full citations

- **dengue_post_monsoon** — Aedes aegypti dengue transmission rises after the monsoon, as standing water enables breeding; reported cases peak in the post-monsoon months (~Aug–Nov) and decline through winter. Strongest in Punjab and Sindh urban centres (Lahore, Rawalpindi, Islamabad, Karachi).
  - WHO Regional Office for the Eastern Mediterranean (EMRO) — Pakistan — WHO EMRO Pakistan dengue situation updates and provincial surveillance consistently document a post-monsoon (Aug–Nov) seasonal peak in dengue transmission. (`who_emro`) https://www.emro.who.int/pak/
  - Government of Punjab, Directorate General Health Services — Provincial dengue surveillance reporting for Punjab. (`punjab_dengue_surveillance`) https://dghs.punjab.gov.pk/
- **punjab_smog_winter** — Punjab's smog season runs roughly October–January, when cooler temperatures, low wind, temperature inversions and seasonal crop-residue burning trap particulates — elevating PM2.5/PM10 and associated respiratory risk, most severely in Lahore.
  - Government of Punjab (Environmental Protection Department) — smog-season advisories; documented air-quality literature — Government of Punjab smog advisories and published air-quality studies document a recurring Oct–Jan smog season over Punjab, centred on Lahore. URL omitted rather than cite a non-canonical link; attribution is to the responsible authority and documented seasonality. (`documented_seasonality`) (no canonical URL; attributed to authority/documented seasonality)
- **influenza_winter** — In Pakistan's northern subtropical/temperate climate, seasonal influenza activity rises in the colder months and peaks in winter (~Dec–Feb).
  - WHO Global Influenza Programme — WHO influenza-seasonality guidance describes winter-peaking influenza activity in northern-hemisphere temperate/subtropical zones, which includes northern Pakistan. (`documented_seasonality`) https://www.who.int/teams/global-influenza-programme
- **dengue_epidemic_2011_punjab** — 2011 saw a major dengue epidemic in Punjab, centred on Lahore — one of the largest recorded dengue outbreaks in Pakistan. Recorded qualitatively (no case counts asserted here).
  - WHO EMRO Pakistan / Government of Punjab dengue response — The 2011 Lahore/Punjab dengue epidemic is widely documented by WHO EMRO and the Government of Punjab as a major outbreak year. (`who_emro`) https://www.emro.who.int/pak/
- **dengue_surge_2019_pakistan** — 2019 saw a marked nationwide dengue surge across Pakistan, with notable activity around Islamabad/Rawalpindi and other cities. Recorded qualitatively.
  - WHO EMRO Pakistan — WHO EMRO Pakistan reporting documents an elevated 2019 dengue season nationally. (`who_emro`) https://www.emro.who.int/pak/

## How this is used (and not used)

- **Used** (Prompt 12 only): compare the seasonality/timing of generated labels against these windows and outbreak years to flag implausible output.
- **Never used**: as a feature, as a label, or anywhere in model training. The import guard enforces this structurally; see `acquire_disease_reference.py` and `test_disease_reference_guard.py`.
