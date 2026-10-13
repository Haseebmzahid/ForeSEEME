# Compute-risk input freshness and Firebase reuse

The five-day source-request delay is unchanged: both requests end at the UTC
run date minus five days. It is distinct from the acceptance policy below.
Open-Meteo documents five-day ERA5/ERA5-Land latency, but this does not prove
current availability for either configured endpoint:
https://open-meteo.com/en/docs/historical-weather-api
https://open-meteo.com/en/docs/air-quality-api

Neither the existing configuration nor those documents specify an acceptable
additional trailing gap for this model. The conservative default is therefore
**zero additional days**, not a claim that the sources always satisfy it.
Operators can explicitly configure non-negative integer tolerances:

| Setting | Default | Applies to |
| --- | --- | --- |
| `RISK_WEATHER_MAX_TRAILING_GAP_DAYS` | 0 | temperature, humidity, precipitation |
| `RISK_AQI_MAX_TRAILING_GAP_DAYS` | 0 | PM2.5, PM10, US AQI |

Each configured source variable must have a real, range-valid daily observation
on or after `requested_end - tolerance`. Cleaning coverage statistics are
measured before interpolation. Partial historical windows are accepted when
their trailing observations pass; missing interior history retains the existing
feature/imputation behavior. This is a daily presence check, not a guarantee of
24 complete hourly readings or a minimum historical coverage percentage.

Every cached payload is checked again after cleaning. An incomplete cached file
may continue to be skipped until its requested window changes or the operator
invalidates the cache; this change does not add automatic cache refresh or TTL.
Missing AQI is skipped, never represented as zero. Real zero remains valid.
Latest-week conditions must also be present before prediction/serialization;
older non-null weeks cannot replace them. Source skips log city, source,
variable, observed end date, required date and reason without credentials.

`generatedAt` retains its frozen meaning: computation time. It is not an
observation timestamp. No document field is added. Under the default policy,
accepted observations can still be five days old by design. Raising tolerances
explicitly permits additional age and should require an operational rationale.

Compute-risk and its heartbeat use one guarded Firebase client factory. Apps
created by the factory may be reused only with the same project configuration,
emulator host, ADC file metadata/configuration, and credential object. Unknown
default apps are rejected because their cached endpoint provenance is unknown.
Endpoint or credential changes require a fresh process; cached clients are
never reconfigured. Same-path credential-file replacement is detected through
modification time and size, without reading secrets. In-place edits preserving
both metadata values and changes to an attached identity cannot be detected;
runtime identity/configuration must remain immutable for the process lifetime.
