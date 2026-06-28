"""Config-driven acquisition framework for the ForeSeeMe ML pipelines.

Sprint 2, Prompt 2. This is the spine every source-specific pipeline
(Prompts 3-5) builds on, so each of those becomes a thin adapter:

    client = AcquisitionBase()
    result = client.fetch_with_cache(
        source="open_meteo_weather", city="Lahore", window=window,
        url=BASE_URL, params={...},
    )

What the framework guarantees (Shared Principles 3 & 4, enforced in code):

* **No hardcoded paths.** Every directory comes from :mod:`paths` (which reads
  config/env). Filenames are derived deterministically from (source, city,
  window).
* **Idempotent downloads.** If a raw file already exists and its SHA-256 matches
  the manifest entry, the network call is skipped entirely (cache hit). A hash
  mismatch forces a re-download.
* **Provenance manifest.** Every raw file is recorded in
  ``data/raw/manifest.json`` with source, params, url, timestamp, byte count and
  SHA-256. The manifest is written **atomically** (temp file + ``os.replace``)
  so an interrupt cannot corrupt it.
* **Resilient I/O.** Requests retry transient failures (429/5xx and network
  errors) with exponential backoff, respect a minimum inter-request interval,
  and log every attempt.

The HTTP layer and the clock/sleep are injectable so the whole framework is
testable offline with zero real network or wall-clock delay.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Protocol

import httpx

from ml.pipelines import paths

logger = logging.getLogger("foreseeme.ml.acquisition")

#: Manifest schema version, bumped if the entry shape changes.
MANIFEST_VERSION = 1


# --- Errors ----------------------------------------------------------------


class AcquisitionError(RuntimeError):
    """Raised for a non-retryable acquisition failure (e.g. a 4xx, or retries
    exhausted)."""


# --- HTTP indirection (injectable for tests) -------------------------------


class HttpGet(Protocol):
    """Minimal GET callable: ``(url, params) -> response`` with ``.status_code``,
    ``.content`` and ``.json()``. Tests inject a fake to avoid the network."""

    def __call__(self, url: str, params: dict[str, Any]) -> Any: ...


# --- Config model ----------------------------------------------------------


@dataclass(frozen=True)
class Window:
    """A closed date window ``[start, end]`` (ISO ``YYYY-MM-DD`` strings)."""

    start: str
    end: str


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int
    backoff_initial_seconds: float
    backoff_factor: float
    retry_on_status: tuple[int, ...]
    timeout_seconds: float


@dataclass(frozen=True)
class CachePolicy:
    reuse_on_hash_match: bool
    verify_hash: bool


@dataclass(frozen=True)
class RateLimit:
    min_interval_seconds: float


@dataclass(frozen=True)
class PipelineConfig:
    """Parsed ``pipeline.yaml``."""

    window: Window
    cache: CachePolicy
    retry: RetryPolicy
    rate_limit: RateLimit
    log_level: str


def load_pipeline_config(path: Path = paths.PIPELINE_PATH) -> PipelineConfig:
    """Parse ``pipeline.yaml`` into a :class:`PipelineConfig`."""
    import yaml  # local import keeps yaml optional for path-only consumers

    with path.open("r", encoding="utf-8") as handle:
        raw = yaml.safe_load(handle)

    retry = raw["retry"]
    return PipelineConfig(
        window=Window(start=str(raw["window"]["start"]), end=str(raw["window"]["end"])),
        cache=CachePolicy(
            reuse_on_hash_match=bool(raw["cache"]["reuse_on_hash_match"]),
            verify_hash=bool(raw["cache"]["verify_hash"]),
        ),
        retry=RetryPolicy(
            max_attempts=int(retry["max_attempts"]),
            backoff_initial_seconds=float(retry["backoff_initial_seconds"]),
            backoff_factor=float(retry["backoff_factor"]),
            retry_on_status=tuple(int(s) for s in retry["retry_on_status"]),
            timeout_seconds=float(retry["timeout_seconds"]),
        ),
        rate_limit=RateLimit(
            min_interval_seconds=float(raw["rate_limit"]["min_interval_seconds"])
        ),
        log_level=str(raw.get("logging", {}).get("level", "INFO")),
    )


# --- Hashing ---------------------------------------------------------------


def sha256_bytes(data: bytes) -> str:
    """SHA-256 hex digest of ``data``."""
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    """SHA-256 hex digest of a file's contents (streamed)."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --- Atomic writes ---------------------------------------------------------


def _write_atomic(path: Path, data: bytes) -> None:
    """Write ``data`` to ``path`` atomically (temp file in the same dir + replace).

    ``os.replace`` is atomic on the same filesystem, so a crash mid-write leaves
    either the old file or the new one — never a truncated blob.
    """
    paths.ensure_dir(path.parent)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    with tmp.open("wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def write_raw_atomic(path: Path, data: bytes) -> None:
    """Persist a raw download blob atomically."""
    _write_atomic(path, data)


# --- Manifest --------------------------------------------------------------


def empty_manifest() -> dict[str, Any]:
    """A fresh, empty manifest document."""
    return {"version": MANIFEST_VERSION, "entries": {}}


def load_manifest(path: Path = paths.MANIFEST_PATH) -> dict[str, Any]:
    """Load the manifest, or return an empty one if it does not exist yet."""
    if not path.exists():
        return empty_manifest()
    return json.loads(path.read_text(encoding="utf-8"))


def _serialize_manifest(manifest: dict[str, Any]) -> bytes:
    """Deterministic JSON so re-runs that change nothing produce byte-identical
    manifests (sorted keys, stable indent, trailing newline)."""
    text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    return text.encode("utf-8")


def save_manifest_atomic(
    manifest: dict[str, Any], path: Path = paths.MANIFEST_PATH
) -> None:
    """Write the manifest atomically (no corruption on interrupt)."""
    _write_atomic(path, _serialize_manifest(manifest))


# --- Result type -----------------------------------------------------------


@dataclass(frozen=True)
class FetchResult:
    """Outcome of :meth:`AcquisitionBase.fetch_with_cache`.

    Attributes:
        path: Absolute path to the raw file on disk.
        key: Manifest key (the POSIX-relative path under ``data/``).
        entry: The manifest entry dict for this file.
        from_cache: True when served from cache (no network call was made).
    """

    path: Path
    key: str
    entry: dict[str, Any]
    from_cache: bool


# --- Clock helper ----------------------------------------------------------


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# --- The framework ---------------------------------------------------------


class AcquisitionBase:
    """Reusable fetch-with-cache + manifest engine for source pipelines.

    All collaborators (HTTP getter, sleep, clock, data dir, manifest path,
    logger) are injectable, defaulting to production behaviour. Source pipelines
    typically just call :meth:`fetch_with_cache`.
    """

    def __init__(
        self,
        *,
        config: PipelineConfig | None = None,
        get: HttpGet | None = None,
        sleep: Callable[[float], None] | None = None,
        now: Callable[[], str] | None = None,
        data_dir: Path | None = None,
        manifest_path: Path | None = None,
        logger_: logging.Logger | None = None,
    ) -> None:
        self.config = config or load_pipeline_config()
        self.sleep = sleep or time.sleep
        self.now = now or _utcnow_iso
        self.data_dir = Path(data_dir) if data_dir is not None else paths.DATA_DIR
        self.manifest_path = (
            Path(manifest_path) if manifest_path is not None else paths.MANIFEST_PATH
        )
        self.log = logger_ or logger
        timeout = self.config.retry.timeout_seconds
        self.get: HttpGet = get or (
            lambda url, params: httpx.get(url, params=params, timeout=timeout)
        )
        # Monotonic timestamp of the last real request, for rate limiting.
        self._last_request_monotonic: float | None = None

    # -- caching ------------------------------------------------------------

    def fetch_with_cache(
        self,
        *,
        source: str,
        city: str,
        window: Window | dict[str, Any] | tuple[str, str],
        url: str,
        params: dict[str, Any],
        ext: str = "json",
        subdir: str | None = None,
        name: str | None = None,
    ) -> FetchResult:
        """Fetch one (source, city, window) blob, reusing the cache when valid.

        Cache hit (no network) requires: caching enabled, the raw file present,
        a manifest entry present, the recorded window matching the requested one,
        and — when ``verify_hash`` is on — the on-disk hash matching the recorded
        one. Otherwise the blob is downloaded (with retry/backoff), written
        atomically, and the manifest updated atomically.

        ``subdir``/``name`` select the per-source layout (e.g. ``raw/weather/
        Lahore.json``); omit them for the default flat, window-stamped layout.
        """
        key = paths.raw_relpath(source, city, window, ext, subdir=subdir, name=name)
        target = self.data_dir / key
        manifest = load_manifest(self.manifest_path)
        entry = manifest["entries"].get(key)

        if self._cache_is_valid(target, entry, window):
            self.log.info(
                "cache_hit",
                extra={"source": source, "city": city, "key": key},
            )
            return FetchResult(path=target, key=key, entry=entry, from_cache=True)

        if entry is not None and target.exists():
            self.log.warning(
                "cache_hash_mismatch_redownload",
                extra={"source": source, "city": city, "key": key},
            )

        response = self._request_with_retry(url, params)
        data: bytes = response.content
        write_raw_atomic(target, data)

        new_entry = {
            "source": source,
            "city": city,
            "window": {"start": _bounds(window)[0], "end": _bounds(window)[1]},
            "url": url,
            "params": params,
            "path": key,
            "bytes": len(data),
            "sha256": sha256_bytes(data),
            "fetched_at": self.now(),
        }
        manifest["entries"][key] = new_entry
        save_manifest_atomic(manifest, self.manifest_path)
        self.log.info(
            "downloaded",
            extra={
                "source": source,
                "city": city,
                "key": key,
                "bytes": new_entry["bytes"],
            },
        )
        return FetchResult(path=target, key=key, entry=new_entry, from_cache=False)

    def _cache_is_valid(
        self,
        target: Path,
        entry: dict[str, Any] | None,
        window: Window | dict[str, Any] | tuple[str, str],
    ) -> bool:
        """True when the cached file may be reused without a network call."""
        if not self.config.cache.reuse_on_hash_match:
            return False
        if entry is None or not target.exists():
            return False
        # Window must match: in the per-source layout the filename omits the
        # window, so a changed window must force a re-download, not a stale hit.
        start, end = _bounds(window)
        recorded = entry.get("window") or {}
        if recorded.get("start") != start or recorded.get("end") != end:
            return False
        if not self.config.cache.verify_hash:
            return True
        return sha256_file(target) == entry.get("sha256")

    # -- networking ---------------------------------------------------------

    def _request_with_retry(self, url: str, params: dict[str, Any]) -> Any:
        """GET with exponential backoff over transient failures.

        Retries network errors and configured status codes (429/5xx) up to
        ``max_attempts``; a non-retryable 4xx raises immediately. Every attempt
        is logged.
        """
        retry = self.config.retry
        delay = retry.backoff_initial_seconds
        last_status: int | None = None

        for attempt in range(1, retry.max_attempts + 1):
            self._respect_rate_limit()
            self.log.info(
                "http_get",
                extra={"url": url, "params": params, "attempt": attempt},
            )
            try:
                response = self.get(url, params)
            except httpx.RequestError as exc:
                if attempt >= retry.max_attempts:
                    raise AcquisitionError(
                        f"GET {url} failed after {attempt} attempts: {exc}"
                    ) from exc
                self.log.warning(
                    "http_retry_error",
                    extra={"url": url, "attempt": attempt, "error": str(exc)},
                )
                self.sleep(delay)
                delay *= retry.backoff_factor
                continue

            status = response.status_code
            if status in retry.retry_on_status:
                last_status = status
                if attempt >= retry.max_attempts:
                    raise AcquisitionError(
                        f"GET {url} returned {status} after {attempt} attempts"
                    )
                self.log.warning(
                    "http_retry_status",
                    extra={"url": url, "attempt": attempt, "status": status},
                )
                self.sleep(delay)
                delay *= retry.backoff_factor
                continue

            if status >= 400:
                raise AcquisitionError(f"GET {url} returned non-retryable {status}")

            return response

        # Unreachable: the loop either returns or raises. Guard for type checkers.
        raise AcquisitionError(f"GET {url} exhausted retries (last status {last_status})")

    def _respect_rate_limit(self) -> None:
        """Sleep just enough to honour ``min_interval_seconds`` between requests."""
        min_interval = self.config.rate_limit.min_interval_seconds
        if min_interval <= 0:
            return
        now = time.monotonic()
        if self._last_request_monotonic is not None:
            elapsed = now - self._last_request_monotonic
            if elapsed < min_interval:
                self.sleep(min_interval - elapsed)
        self._last_request_monotonic = time.monotonic()


def _bounds(window: Window | dict[str, Any] | tuple[str, str]) -> tuple[str, str]:
    """Normalize a window to (start, end) strings for the manifest entry."""
    if isinstance(window, Window):
        return window.start, window.end
    return paths._window_bounds(window)
