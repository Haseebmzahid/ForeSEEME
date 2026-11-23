import pytest
from firebase_admin import messaging

from app.jobs.alerting.messaging import (
    FirebaseAdminFcmSender,
    PUSH_DISCLAIMER,
    build_notification,
)
from app.jobs.alerting.recommendation_lookup import Recommendation
from app.jobs.alerting.targeting import Target


@pytest.mark.parametrize("level", ["Low", "Medium", "High"])
@pytest.mark.parametrize(("category", "driver", "disease"), [
    ("respiratory", "Air quality", "Smog"),
    ("respiratory", "Respiratory", "Influenza"),
    ("cardiovascular", "Heat", "Smog"),
    ("vector", "Vector-borne", "Dengue"),
])
def test_risk_push_preserves_content_and_includes_disclaimer(level, category, driver, disease):
    target = Target("uid", "Lahore", category, driver, disease, level, "Low")
    rec = Recommendation("tip", category, driver, "Limit strenuous outdoor exercise.",
                         "Test source", "https://example.test", "/risk-details", "")
    title, body, data = build_notification(target, rec, "risk")
    assert "Lahore" in title
    assert body == f"{PUSH_DISCLAIMER} {level} {disease} risk. {rec.text}"
    assert data["deepLink"] == rec.deep_link


@pytest.mark.parametrize("body", ["Alternate copy", f"{PUSH_DISCLAIMER} Existing body"])
def test_common_fcm_payload_carries_disclaimer_without_platform_overrides(monkeypatch, body):
    def send(message):
        assert message.notification.body.startswith(PUSH_DISCLAIMER)
        assert message.notification.body.count(PUSH_DISCLAIMER) == 1
        assert message.notification.body.endswith(body)
        assert message.android is None and message.apns is None and message.webpush is None
        return "message-id"

    monkeypatch.setattr(messaging, "send", send)
    result = FirebaseAdminFcmSender().send(
        token="stub", title="Test notice", body=body, data={"type": "risk_alert"},
    )
    assert result.status == "sent"
