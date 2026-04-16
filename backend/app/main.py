import json
import hashlib
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
    recent_consultation_history: List[str] = Field(default_factory=list)
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
            score = int(float(value))
        except Exception:
            score = fallback
        return max(0, min(100, score))

    def read_text(keys: list[str], fallback: str) -> str:
        for key in keys:
            value = data.get(key)
            if value is None:
                continue
            text_value = str(value).strip()
            if text_value:
                return text_value
        return fallback

    positive_points = _ensure_len(
        _to_string_list(
            data.get("positive_points")
            or data.get("strengths")
            or data.get("good_points")
        ),
        3,
        "良い点",
    )
    risk_points = _ensure_len(
        _to_string_list(
            data.get("risk_points")
            or data.get("concerns")
            or data.get("weak_points")
        ),
        3,
        "注意点",
    )
    next_actions = _ensure_len(
        _to_string_list(
            data.get("next_actions")
            or data.get("actions")
            or data.get("advice")
        ),
        3,
        "次の一手",
    )

    raw_score = clamp_score(data.get("score"), 70)

    subscores_raw = data.get("subscores")
    if not isinstance(subscores_raw, dict):
        subscores_raw = {}

    communication = clamp_score(
        subscores_raw.get("communication"),
        raw_score,
    )
    emotional_safety = clamp_score(
        subscores_raw.get("emotional_safety"),
        max(raw_score - 6, 0),
    )
    repair_ability = clamp_score(
        subscores_raw.get("repair_ability"),
        min(raw_score + 2, 100),
    )
    stability = clamp_score(
        subscores_raw.get("stability"),
        max(raw_score - 8, 0),
    )

    weighted_score = round(
        raw_score * 0.55
        + communication * 0.15
        + emotional_safety * 0.15
        + repair_ability * 0.10
        + stability * 0.05
    )
    final_score = max(38, min(92, weighted_score))

    if final_score >= 82:
        label = "かなり相性が良い"
    elif final_score >= 72:
        label = "相性は良い"
    elif final_score >= 60:
        label = "相性は悪くないが、すれ違いが起きやすい"
    elif final_score >= 48:
        label = "相性はあるが、関係維持には工夫が必要"
    else:
        label = "土台から整え直した方がよい"

    summary = read_text(
        ["summary", "headline", "overall_comment"],
        "関係の土台はありますが、会話の進め方や不安の扱い方に一定のパターンがあります。特に繰り返すすれ違いがある場合は、内容そのものより先に伝え方と安心感の整え方を見直すと安定しやすいです。",
    )

    return {
        "score": final_score,
        "label": label,
        "summary": summary,
        "positive_points": positive_points,
        "risk_points": risk_points,
        "next_actions": next_actions,
        "subscores": {
            "communication": communication,
            "emotional_safety": emotional_safety,
            "repair_ability": repair_ability,
            "stability": stability,
        },
    }


def build_compatibility_prompt(request: CompatibilityRequest) -> str:
    relation_map = {
        "couple": "恋人・パートナー",
        "friend": "友人",
        "family": "家族",
        "family_parent_child": "家族 / 親子",
        "parent_child": "家族 / 親子",
        "family_sibling": "家族 / 兄弟姉妹",
        "family_inlaw": "家族 / 義家族",
        "family_other": "家族 / その他",
        "other": "その他",
    }

    relation_label = relation_map.get(request.relation_type, request.relation_type)

    parts: list[str] = [
        "あなたは男女関係・友人関係・家族関係のコミュニケーション分析に強い、日本語の関係性評価AIです。",
        "以下の情報をもとに、この関係の相性を現実的に採点してください。",
        "甘くしすぎず、脅しすぎず、繰り返し出ているパターンを最優先で評価してください。",
        "[relation_type]
" + relation_label,
    ]

    if request.relation_detail_labels:
        labels = [label.strip() for label in request.relation_detail_labels if label.strip()]
        if labels:
            parts.append("[relation_detail_labels]
" + "
".join(labels))

    if request.profile_context and request.profile_context.strip():
        parts.append("[profile_context]
" + request.profile_context.strip())

    if request.recent_pattern_summary and request.recent_pattern_summary.strip():
        parts.append("[recent_consultation_history]
" + request.recent_pattern_summary.strip())

    if request.optional_note and request.optional_note.strip():
        parts.append("[optional_note]
" + request.optional_note.strip())

    parts.append(
        "
".join(
            [
                "必須ルール:",
                "- recent_consultation_history がある場合は、その履歴に出た反復パターンを必ず score / summary / risk_points / next_actions に反映する",
                "- その場の雰囲気より、繰り返される衝突パターンを重く見る",
                "- score は 0-100 の整数",
                "- subscores も 0-100 の整数",
                "- positive_points / risk_points / next_actions はそれぞれ必ず3個",
                "- risk_points は抽象論ではなく、この関係で起きやすいすれ違いを書く",
                "- next_actions は今後7日以内に実行できる具体策にする",
                "- 出力は JSON のみ。前置きや説明文は禁止",
                "{",
                '  "score": 0,',
                '  "label": "...",',
                '  "summary": "...",',
                '  "positive_points": ["...", "...", "..."],',
                '  "risk_points": ["...", "...", "..."],',
                '  "next_actions": ["...", "...", "..."],',
                '  "subscores": {',
                '    "communication": 0,',
                '    "emotional_safety": 0,',
                '    "repair_ability": 0,',
                '    "stability": 0',
                "  }",
                "}",
            ]
        )
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
        normalized = stabilize_compatibility_result(request, result_json)

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