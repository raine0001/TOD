import asyncio
from datetime import datetime, timezone

from core.communication_contract import ExpertCommunicationReply
from core.routers.public_chat import _build_public_fallback_reply
from core.routers.public_chat import _build_alternative_resource_query
from core.routers import public_chat
from core.communication_composer import build_deterministic_communication_reply
from core.communication_composer import _model_request_payload


def test_public_mim_weather_question_does_not_repeat_onboarding_prompt(monkeypatch) -> None:
    def _fake_weather() -> str:
        return "Right now London is cool.\n\nThis week's forecast from Open-Meteo:\n- today: cloudy, 10-15C"

    monkeypatch.setattr(public_chat, "_london_weather_summary", _fake_weather)
    reply = _build_public_fallback_reply(
        message="what is the weather like in london today?",
        mode="mim",
        profile={"name": "Dave", "visit_count": 2},
        recall_summary="I remember your name is Dave.",
    )

    assert "This week's forecast from Open-Meteo" in reply
    assert "What are you trying to make progress on" not in reply
    assert "This is the MIM channel" not in reply


def test_public_mim_current_day_question_reaches_composer_with_temporal_context(monkeypatch) -> None:
    monkeypatch.setattr(
        public_chat,
        "_public_chat_now",
        lambda: datetime(2026, 6, 11, 9, 30, tzinfo=timezone.utc),
    )
    captured: dict[str, object] = {}

    async def _fake_composer(*, user_input, context, fallback_reply):
        captured["user_input"] = user_input
        captured["context"] = context
        captured["fallback_reply"] = fallback_reply
        current = context["current_datetime"]
        return ExpertCommunicationReply(
            reply_text=f"Today is {current['current_date']}.",
            topic_hint="conversation",
            response_mode="answer_first",
        )

    monkeypatch.setattr(public_chat, "compose_expert_communication_reply", _fake_composer)
    reply = asyncio.run(public_chat._compose_public_reply(
        message="what day is it MIM?",
        mode="mim",
        profile={"name": "Dave", "visit_count": 2},
        recall_summary="",
        recent_messages=[],
    ))

    assert reply == "Today is Thursday, June 11, 2026."
    assert captured["user_input"] == "what day is it MIM?"
    assert captured["context"]["current_datetime"]["current_date"] == "Thursday, June 11, 2026"
    assert captured["context"]["current_datetime"]["reference_datetimes"]["france"]["zone"] == "Europe/Paris"
    assert "Answer ordinary conversation" in captured["context"]["conversation_policy"]
    assert "This is the MIM channel" not in captured["fallback_reply"]
    assert "focused on planning" not in captured["fallback_reply"]


def test_public_mim_spanish_chat_keeps_language_policy(monkeypatch) -> None:
    captured: dict[str, object] = {}

    async def _fake_composer(*, user_input, context, fallback_reply):
        captured["user_input"] = user_input
        captured["context"] = context
        captured["fallback_reply"] = fallback_reply
        return ExpertCommunicationReply(
            reply_text="Estoy bien. Podemos conversar en espanol y explorar lo que quieras.",
            topic_hint="conversation",
            response_mode="conversational_confident",
        )

    monkeypatch.setattr(public_chat, "compose_expert_communication_reply", _fake_composer)
    reply = asyncio.run(public_chat._compose_public_reply(
        message="Como estas?",
        mode="mim",
        profile={},
        recall_summary="",
        recent_messages=[],
    ))

    assert reply.startswith("Estoy bien.")
    assert captured["user_input"] == "Como estas?"
    assert "same language" in captured["context"]["language_policy"]
    assert "This is the MIM channel" not in captured["fallback_reply"]
    assert "Recommended action:" not in reply


def test_public_mim_location_followup_gets_recent_temporal_context(monkeypatch) -> None:
    monkeypatch.setattr(
        public_chat,
        "_public_chat_now",
        lambda: datetime(2026, 6, 11, 17, 30, tzinfo=timezone.utc),
    )
    monkeypatch.setattr(
        public_chat,
        "_public_zoned_temporal_context",
        lambda zone_name, label: {
            "label": label,
            "timezone": "CEST" if zone_name == "Europe/Paris" else "UTC",
            "zone": zone_name,
            "current_datetime_iso": "2026-06-12T02:30:00+02:00" if zone_name == "Europe/Paris" else "2026-06-12T00:30:00+00:00",
            "current_day": "Friday",
            "current_date": "Friday, June 12, 2026",
            "current_time": "2:30 AM" if zone_name == "Europe/Paris" else "12:30 AM",
        },
    )
    captured: dict[str, object] = {}

    async def _fake_composer(*, user_input, context, fallback_reply):
        captured["user_input"] = user_input
        captured["context"] = context
        return ExpertCommunicationReply(
            reply_text="In France, it is Friday, June 12, 2026.",
            topic_hint="conversation",
            response_mode="answer_first",
        )

    monkeypatch.setattr(public_chat, "compose_expert_communication_reply", _fake_composer)
    reply = asyncio.run(public_chat._compose_public_reply(
        message="what about in France?",
        mode="mim",
        profile={},
        recall_summary="",
        recent_messages=[
            {"role": "visitor", "content": "MIM, what day of the week is it?"},
            {"role": "mim", "content": "Today is Thursday, June 11, 2026."},
        ],
    ))

    assert reply == "In France, it is Friday, June 12, 2026."
    assert captured["user_input"] == "what about in France?"
    assert captured["context"]["current_datetime"]["reference_datetimes"]["france"]["current_date"] == "Friday, June 12, 2026"
    recent = captured["context"]["recent_conversation"]
    assert recent[-2]["content"] == "MIM, what day of the week is it?"
    assert recent[-1]["content"] == "Today is Thursday, June 11, 2026."


def test_public_mim_composer_payload_includes_recent_followup_context() -> None:
    payload = _model_request_payload(
        user_input="what about in France?",
        context={
            "public_guest_chat": True,
            "response_mode": "conversational_confident",
            "current_datetime": {"current_datetime_iso": "2026-06-11T17:30:00-07:00"},
            "recent_conversation": [
                {"role": "visitor", "content": "MIM, what day of the week is it?"},
                {"role": "mim", "content": "Today is Thursday, June 11, 2026."},
            ],
        },
        fallback_reply="I can chat normally.",
        deterministic_reply=ExpertCommunicationReply(reply_text="I can chat normally."),
    )

    user_payload = payload["messages"][1]["content"]
    assert "what about in France?" in user_payload
    assert "MIM, what day of the week is it?" in user_payload
    assert "Today is Thursday, June 11, 2026." in user_payload


def test_public_guest_chat_does_not_get_operator_impact_contract() -> None:
    reply = build_deterministic_communication_reply(
        user_input="can I just chat with you to learn more?",
        context={"public_guest_chat": True, "response_mode": "conversational_confident"},
        fallback_reply="Absolutely. I can chat, explain MIM and TOD, or help turn a loose thought into clear next steps.",
    )

    assert "Recommended action:" not in reply.reply_text
    assert "Dave needed:" not in reply.reply_text


def test_public_mim_name_intro_gets_direct_acknowledgement() -> None:
    reply = _build_public_fallback_reply(
        message="i am Dave",
        mode="mim",
        profile={},
        recall_summary="",
    )

    assert reply == "Nice to meet you, Dave. I'll remember your name for this public chat."


def test_public_mim_weather_resource_uses_lookup_path(monkeypatch) -> None:
    monkeypatch.setattr(
        public_chat,
        "_fetch_public_url_status",
        lambda url: {"ok": False, "status": 403, "error": "HTTP 403", "source_state": "blocked_by_source"},
    )
    monkeypatch.setattr(
        public_chat,
        "_london_weather_summary",
        lambda: "Right now London is cool.\n\nThis week's forecast from Open-Meteo:\n- today: cloudy, 10-15C",
    )

    reply = _build_public_fallback_reply(
        message=(
            "use this resource and let me know what the weather is going to be like this week in london: "
            "https://www.accuweather.com/en/gb/london/ec4a-2/weather-forecast/328328"
        ),
        mode="mim",
        profile={"name": "Dave", "visit_count": 2},
        recall_summary="I remember your name is Dave.",
    )

    assert "site rejected the server-side request with HTTP 403" in reply
    assert "This week's forecast from Open-Meteo" in reply
    assert "What are you trying to make progress on" not in reply


def test_public_mim_source_aware_blocked_url_does_not_claim_no_web_access(monkeypatch) -> None:
    monkeypatch.setattr(
        public_chat,
        "_fetch_public_url_status",
        lambda url: {"ok": False, "status": 403, "error": "HTTP 403", "source_state": "blocked_by_source"},
    )
    monkeypatch.setattr(
        public_chat,
        "_search_public_alternative_resources",
        lambda query, limit=3: [
            {"title": "Alternative public source", "url": "https://example.org/alternative"},
        ],
    )

    reply = _build_public_fallback_reply(
        message="use this resource and summarize it: https://example.com/protected",
        mode="mim",
        profile={"name": "Dave", "visit_count": 2},
        recall_summary="I remember your name is Dave.",
    )

    assert "source blocked automated access" in reply
    assert "does not mean MIM has no web access" in reply
    assert "searched for alternative public resources" in reply
    assert "https://example.org/alternative" in reply
    assert "What are you trying to make progress on" not in reply


def test_public_mim_alternative_query_uses_blocked_url_context() -> None:
    query = _build_alternative_resource_query(
        "use this resource and summarize it: https://www.accuweather.com/en/gb/london/ec4a-2/weather-forecast/328328",
        "https://www.accuweather.com/en/gb/london/ec4a-2/weather-forecast/328328",
    )

    assert query == "London weather forecast"
