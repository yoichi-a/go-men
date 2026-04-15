import json
import os
from typing import Any, List, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
from pydantic import BaseModel, Field

load_dotenv()

app = FastAPI(title="Go-men API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.4-mini")

client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None


@app.get("/")
def root():
    return {"message": "Go-men API is running"}


@app.get("/health")
def health():
    return {"status": "ok"}


class ConsultSessionRequest(BaseModel):
    relation_type: str
    relation_detail_labels: List[str] = Field(default_factory=list)
    theme: str
    theme_details: List[str]
    current_status: str
    emotion_level: str
    goal: str
    chat_text: Optional[str] = None
    note: Optional[str] = None
    profile_context: Optional[str] = None
    recent_pattern_summary: Optional[str] = None
    screenshots_base64: List[str] = Field(default_factory=list)
    upload_ids: List[str] = Field(default_factory=list)


class PrecheckRequest(BaseModel):
    relation_type: str
    relation_detail_labels: List[str] = Field(default_factory=list)
    draft_message: str
    optional_context_text: Optional[str] = None
    profile_context: Optional[str] = None
    recent_pattern_summary: Optional[str] = None
    optional_context_upload_ids: List[str] = Field(default_factory=list)


class CompatibilityRequest(BaseModel):
    relation_type: str
    relation_detail_labels: List[str] = Field(default_factory=list)
    profile_context: Optional[str] = None
    recent_pattern_summary: Optional[str] = None
    optional_note: Optional[str] = None


def parse_json_text(result_text: str) -> dict[str, Any]:
    cleaned = result_text.strip()

    if cleaned.startswith("```json"):
        cleaned = cleaned.removeprefix("```json").strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.removeprefix("```").strip()
    if cleaned.endswith("```"):
        cleaned = cleaned.removesuffix("```").strip()

    return json.loads(cleaned)


def _to_string_list(value: Any) -> List[str]:
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item).strip()]


def _ensure_len(items: List[str], n: int, fallback_prefix: str) -> List[str]:
    result = list(items)
    while len(result) < n:
        result.append(f"{fallback_prefix}{len(result) + 1}")
    return result[:n]


def normalize_consult_result(data: dict[str, Any]) -> dict[str, Any]:
    send_timing = data.get("send_timing_recommendation")
    if not isinstance(send_timing, dict):
        send_timing = {}

    reply_options_raw = data.get("reply_options")
    reply_options: List[dict[str, str]] = []
    if isinstance(reply_options_raw, list):
        for item in reply_options_raw:
            if isinstance(item, dict):
                title = str(item.get("title", "")).strip()
                body = str(item.get("body", "")).strip()
                reply_type = str(item.get("type", "")).strip()
                if title and body:
                    reply_options.append(
                        {
                            "type": reply_type or "reply",
                            "title": title,
                            "body": body,
                        }
                    )

    defaults = [
        {
            "type": "best_reply",
            "title": "まずこれがベスト",
            "body": "言い方がきつくなってしまっていたらごめん。今回のことを軽く扱いたいわけではなくて、まずはちゃんと受け止めたい。今すぐ結論を押しつけたいわけじゃないから、落ち着いて話せる形にしたい。",
        },
        {
            "type": "alternative_reply_1",
            "title": "その他には、こう返すなら",
            "body": "責めたいわけじゃなかったけど、そう聞こえたなら本当にごめん。今回のことを自分の中でも整理したいし、誤解があるなら落ち着いて伝え直したい。",
        },
        {
            "type": "alternative_reply_2",
            "title": "その他には、少し落ち着かせるなら",
            "body": "今このままやり取りを続けると余計にこじれそうだから、少しだけ落ち着いてから話したい。無視したいわけじゃなくて、ちゃんと向き合うために少し整えたい。",
        },
    ]

    while len(reply_options) < 3:
        reply_options.append(defaults[len(reply_options)])
    reply_options = reply_options[:3]

    heard_as = _ensure_len(
        _to_string_list(data.get("heard_as_interpretations")),
        2,
        "相手にこう聞こえた可能性",
    )
    avoid_phrases = _ensure_len(
        _to_string_list(data.get("avoid_phrases")),
        2,
        "避けたい表現",
    )
    next_actions = _ensure_len(
        _to_string_list(data.get("next_actions")),
        3,
        "次の行動",
    )
    pre_send_cautions = _ensure_len(
        _to_string_list(data.get("pre_send_cautions")),
        3,
        "送る前の注意",
    )

    return {
        "session_id": str(data.get("session_id", "session_generated")),
        "analysis_status": "completed",
        "safety_flag": bool(data.get("safety_flag", False)),
        "send_timing_recommendation": {
            "code": str(send_timing.get("code", "soften_first")),
            "label": str(send_timing.get("label", "少し整えてから送るのがよい")),
            "reason": str(
                send_timing.get(
                    "reason",
                    "今は伝えたい気持ちよりも、どう聞こえるかの影響が大きい状態です。短く整えてから送る方が悪化しにくいです。",
                )
            ),
        },
        "situation_summary": str(
            data.get(
                "situation_summary",
                "内容そのものより、言い方や受け取り方のズレでこじれている可能性があります。",
            )
        ),
        "partner_feeling_estimate": str(
            data.get(
                "partner_feeling_estimate",
                "相手は怒りそのものより、軽く扱われたことや理解されていないことに反応している可能性があります。",
            )
        ),
        "heard_as_interpretations": heard_as,
        "avoid_phrases": avoid_phrases,
        "reply_options": reply_options,
        "next_actions": next_actions,
        "pre_send_cautions": pre_send_cautions,
    }


def normalize_precheck_result(data: dict[str, Any]) -> dict[str, Any]:
    is_safe = data.get("is_safe_to_send")
    if not isinstance(is_safe, dict):
        is_safe = {}

    softened_message = str(data.get("softened_message", "")).strip()
    if not softened_message:
        softened_message = (
            "言い方が強くなってしまっていたらごめん。責めたいわけじゃなくて、今の気まずさをこれ以上大きくしたくない。少し落ち着いて話せたらうれしい。"
        )

    revised = _to_string_list(data.get("revised_message_options"))
    if not revised:
        revised = [softened_message]

    while len(revised) < 3:
        if len(revised) == 1:
            revised.append(
                "強い言い方になってしまっていたらごめん。今回のことを軽く流したいわけじゃなくて、ちゃんと伝わる形で話し直したい。"
            )
        else:
            revised.append(
                "今のまま続けると余計にこじれそうだから、少し落ち着いてから話したい。無視したいわけじゃなくて、悪化させたくない。"
            )
    revised = revised[:3]

    risk_points = _ensure_len(
        _to_string_list(data.get("risk_points")),
        2,
        "相手には強く聞こえる点",
    )

    return {
        "precheck_id": str(data.get("precheck_id", "precheck_generated")),
        "safety_flag": bool(data.get("safety_flag", False)),
        "is_safe_to_send": {
            "code": str(is_safe.get("code", "soften_recommended")),
            "label": str(is_safe.get("label", "少し整えてから送った方がよい")),
            "reason": str(
                is_safe.get(
                    "reason",
                    "今の文だと気持ちより先に圧や責めが伝わりやすいです。少し整えるだけで受け取られ方がかなり変わります。",
                )
            ),
        },
        "risk_points": risk_points,
        "softened_message": softened_message,
        "revised_message_options": revised,
        "suggest_consult_mode": bool(data.get("suggest_consult_mode", True)),
    }


def build_context_block(
    *,
    note: Optional[str] = None,
    profile_context: Optional[str] = None,
    recent_pattern_summary: Optional[str] = None,
    optional_context_text: Optional[str] = None,
) -> str:
    sections: List[str] = []

    if profile_context and profile_context.strip():
        sections.append(f"【相手プロフィール】\n{profile_context.strip()}")

    if recent_pattern_summary and recent_pattern_summary.strip():
        sections.append(f"【過去相談から見える傾向】\n{recent_pattern_summary.strip()}")

    if note and note.strip():
        sections.append(f"【今回の補足】\n{note.strip()}")

    if optional_context_text and optional_context_text.strip():
        sections.append(f"【今回の補足】\n{optional_context_text.strip()}")

    return "\n\n".join(sections).strip()



def normalize_compatibility_result(data: dict[str, Any]) -> dict[str, Any]:
    def clamp_score(value: Any, fallback: int) -> int:
        try:
            score = int(value)
        except Exception:
            score = fallback
        return max(0, min(100, score))

    positive_points = _to_string_list(
        data.get("positive_points") or data.get("strengths")
    )
    risk_points = _to_string_list(data.get("risk_points"))
    next_actions = _to_string_list(
        data.get("next_actions") or data.get("advice")
    )

    label = str(
        data.get("label")
        or data.get("headline")
        or "相性は悪くない"
    )
    summary = str(
        data.get("summary")
        or data.get("headline")
        or "プロフィールと過去の相談履歴からみると、関係の土台はある一方で、すれ違い方には一定の傾向があります。"
    )

    return {
        "score": clamp_score(data.get("score"), 78),
        "label": label,
        "summary": summary,
        "positive_points": _ensure_len(positive_points, 3, "良い点"),
        "risk_points": _ensure_len(risk_points, 3, "注意点"),
        "next_actions": _ensure_len(next_actions, 3, "次の一手"),
    }



def build_compatibility_prompt(request: CompatibilityRequest) -> str:
    relation_details = " / ".join(
        [item.strip() for item in request.relation_detail_labels if item.strip()]
    ) or "なし"

    parts = [
        "あなたは恋愛・友人・家族関係の会話パターンを整理する、慎重で実務的な分析アシスタントです。",
        "次の情報から、この2人の相性を100点満点で採点してください。",
        "",
        f"relation_type: {request.relation_type}",
        f"relation_detail_labels: {relation_details}",
    ]

    if request.profile_context:
        parts.extend(["", "[profile_context]", request.profile_context.strip()])

    if request.recent_pattern_summary:
        parts.extend(
            [
                "",
                "[recent_consultation_history]",
                request.recent_pattern_summary.strip(),
            ]
        )

    if request.optional_note:
        parts.extend(["", "[optional_note]", request.optional_note.strip()])

    parts.extend(
        [
            "",
            "評価ルール:",
            "- score は 0〜100 の整数",
            "- recent_consultation_history がある場合は、その履歴に出た繰り返しパターンを必ず評価へ反映する",
            "- 単発の印象より、継続して起きる傾向を重く見る",
            "- 甘すぎる点数にしないが、改善余地は next_actions に具体的に書く",
            "- 断定しすぎず、やさしいが現実的な日本語にする",
            "",
            "JSON only で返すこと。",
            "{",
            '  "score": 78,',
            '  "label": "相性は悪くない",',
            '  "summary": "2〜4文の総評",',
            '  "positive_points": ["...","...","..."],',
            '  "risk_points": ["...","...","..."],',
            '  "next_actions": ["...","...","..."]',
            "}",
        ]
    )

    return "
".join(parts)



@app.post("/compatibility/score")
def compatibility_score(request: CompatibilityRequest):
    if client is None:
        raise HTTPException(
            status_code=500,
            detail="OPENAI_API_KEY が設定されていません。",
        )

    try:
        response = client.responses.create(
            model=OPENAI_MODEL,
            instructions=(
                "You are a careful relationship compatibility analyst. "
                "Output valid JSON only. "
                "Be practical, kind, and grounded in the provided context."
            ),
            input=build_compatibility_prompt(request),
            text={"format": {"type": "json_object"}},
        )

        result_text = response.output_text
        result_json = parse_json_text(result_text)
        normalized = normalize_compatibility_result(result_json)

        return {"data": normalized}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAI compatibility error: {e}")


@app.post("/consult/sessions")
def create_consult_session(request: ConsultSessionRequest):
    if client is None:
        raise HTTPException(
            status_code=500,
            detail="OPENAI_API_KEY が設定されていません。",
        )

    try:
        response = client.responses.create(
            model=OPENAI_MODEL,
            instructions=(
                "You are a careful relationship mediation assistant. "
                "Output valid JSON only. "
                "Prioritize concrete, copy-ready Japanese replies over generic advice. "
                "Avoid repetitive template-like wording across different cases. "
                "Use relation details, profile context, recent patterns, and readable screenshot cues when available."
            ),
            input=build_consult_input(request),
            text={"format": {"type": "json_object"}},
        )

        result_text = response.output_text
        result_json = parse_json_text(result_text)
        normalized = normalize_consult_result(result_json)

        return {"data": normalized}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAI consult error: {e}")


@app.post("/precheck")
def precheck_message(request: PrecheckRequest):
    if client is None:
        raise HTTPException(
            status_code=500,
            detail="OPENAI_API_KEY が設定されていません。",
        )

    try:
        response = client.responses.create(
            model=OPENAI_MODEL,
            instructions=(
                "You are a careful message precheck assistant. "
                "Output valid JSON only. "
                "Prioritize one best softened message and two concrete alternatives. "
                "Keep the best message concise, usable, and natural. "
                "Avoid repetitive template-like wording across different cases. "
                "Use relation details, profile context, and recent patterns when available."
            ),
            input=build_precheck_prompt(request),
            text={"format": {"type": "json_object"}},
        )

        result_text = response.output_text
        result_json = parse_json_text(result_text)
        normalized = normalize_precheck_result(result_json)

        return {"data": normalized}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAI precheck error: {e}")