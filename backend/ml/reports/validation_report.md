# Validation Report — ForeSeeMe Dataset Freeze ⛔

**Sprint 2, Prompt 10 — Dataset Validation & Temporal Train/Test Freeze**

## GATE: 🟢 GREEN — modeling may proceed

- Temporal split point: test begins 2025-W27 (52 test weeks).
- Train rows: 735  |  Test rows: 260  |  Excluded (insufficient history): 25
- train.parquet sha256: `5079011c7d0349f2569a0f2711df156e6aeef12de6621f4aa8986a69f04a34c5`
- test.parquet  sha256: `1d18b5ae78c74fa89912990746312fb0e3c96e03d7295c915c2c551cffd98b46`

## Checks

| Check | Status | Detail |
|-------|--------|--------|
| schema | ✅ PASS | all column types, ranges, labels and key uniqueness satisfied |
| feature_leakage | ✅ PASS | all lag/rolling features equal their reconstructed past values (causal, no future leakage) |
| label_consistency | ✅ PASS | probabilities sum to 1 and hard labels match their thresholds |
| temporal_split | ✅ PASS | train <= 2025-W26 < test >= 2025-W27 |
| contamination | ✅ PASS | no (city, year, week) shared between train and test |
| class_distribution | ✅ PASS | every class present in both splits |
| missing_values | ✅ PASS | keys and raw values complete; remaining nulls are documented (anomaly first-cycle, labels) |
| feature_statistics | ✅ PASS | no zero-variance features in train |

### class_distribution

- dengue_label: train={'Low': 292, 'Medium': 187, 'High': 256} test={'Low': 97, 'Medium': 52, 'High': 111}
- dengue_label_sampled: train={'Low': 281, 'Medium': 192, 'High': 262} test={'Low': 96, 'Medium': 57, 'High': 107}
- smog_label: train={'Low': 476, 'Medium': 171, 'High': 88} test={'Low': 175, 'Medium': 51, 'High': 34}
- smog_label_sampled: train={'Low': 477, 'Medium': 172, 'High': 86} test={'Low': 176, 'Medium': 49, 'High': 35}
- influenza_label: train={'Low': 451, 'Medium': 164, 'High': 120} test={'Low': 171, 'Medium': 61, 'High': 28}
- influenza_label_sampled: train={'Low': 452, 'Medium': 166, 'High': 117} test={'Low': 173, 'Medium': 52, 'High': 35}

### missing_values

- train: anomaly nulls (first-cycle climatology) = {'temperature_anom': 235, 'humidity_anom': 235, 'precipitation_anom': 235, 'us_aqi_anom': 235}
- test: anomaly nulls (first-cycle climatology) = {'temperature_anom': 0, 'humidity_anom': 0, 'precipitation_anom': 0, 'us_aqi_anom': 0}

### feature_statistics

- temperature: train μ=22.72 σ=7.25 [7.6,38.2] | test μ=23.13 σ=6.92 [7.3,35.6]
- humidity: train μ=60.72 σ=15.18 [12.6,92.7] | test μ=63.77 σ=14.34 [27.5,91.3]
- precipitation: train μ=12.38 σ=20.92 [0.0,183.3] | test μ=16.59 σ=28.10 [0.0,199.2]
- pm2_5: train μ=42.68 σ=25.35 [11.2,198.9] | test μ=43.34 σ=24.89 [16.1,215.3]
- us_aqi: train μ=113.77 σ=32.35 [53.2,245.0] | test μ=114.27 σ=30.98 [60.2,258.2]
