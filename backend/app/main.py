from fastapi.responses import FileResponse
from pathlib import Path
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


BACKEND_ROOT = Path(__file__).resolve().parents[1]

APP_FILE = Path(__file__).resolve()
PROJECT_ROOT = APP_FILE.parents[2]

PAGES_DIR_CANDIDATES = [
    PROJECT_ROOT / "pages",
    PROJECT_ROOT / "backend" / "pages",
    APP_FILE.parents[1] / "pages",
    Path("/opt/render/project/src/pages"),
    Path("/opt/render/project/src/backend/pages"),
]

def resolve_pages_dir() -> Path:
    for candidate in PAGES_DIR_CANDIDATES:
        if candidate.exists():
            return candidate
    return PROJECT_ROOT / "backend" / "pages"

PAGES_DIR = resolve_pages_dir()

@app.api_route("/privacy", methods=["GET", "HEAD"], include_in_schema=False)
@app.api_route("/privacy-policy", methods=["GET", "HEAD"], include_in_schema=False)
@app.api_route("/privacy_policy.html", methods=["GET", "HEAD"], include_in_schema=False)
def privacy_policy_html():
    page = PAGES_DIR / "privacy_policy.html"
    if not page.exists():
        raise HTTPException(status_code=404, detail="privacy_policy.html not found")
    return FileResponse(page)

@app.api_route("/support", methods=["GET", "HEAD"], include_in_schema=False)
@app.api_route("/support.html", methods=["GET", "HEAD"], include_in_schema=False)
def support_html():
    page = PAGES_DIR / "support.html"
    if not page.exists():
        raise HTTPException(status_code=404, detail="support.html not found")
    return FileResponse(page)

@app.api_route("/terms", methods=["GET", "HEAD"], include_in_schema=False)
@app.api_route("/terms.html", methods=["GET", "HEAD"], include_in_schema=False)
def terms_html():
    page = PAGES_DIR / "terms.html"
    if not page.exists():
        raise HTTPException(status_code=404, detail="terms.html not found")
    return FileResponse(page)

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
    theme_detail_keys: List[str] = Field(default_factory=list)
    current_status: str
    current_status_key: Optional[str] = None
    emotion_level: str
    goal: str
    goal_key: Optional[str] = None
    chat_text: Optional[str] = None
    note: Optional[str] = None
    profile_context: Optional[str] = None
    recent_pattern_summary: Optional[str] = None
    recent_consultation_history: List[str] = Field(default_factory=list)
    screenshots_base64: List[str] = Field(default_factory=list)
    upload_ids: List[str] = Field(default_factory=list)
    latent_signals: List[str] = Field(default_factory=list)


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
    def _first_text(*values: Any) -> str:
        for value in values:
            if value is None:
                continue
            if isinstance(value, str):
                s = value.strip()
                if s:
                    return s
            elif isinstance(value, dict):
                continue
            else:
                s = str(value).strip()
                if s:
                    return s
        return ""

    def _read_reply_item(item: Any, fallback_type: str) -> Optional[dict[str, str]]:
        if not isinstance(item, dict):
            return None
        title = str(item.get("title", "")).strip()
        body = str(item.get("body", "")).strip()
        if not title or not body:
            return None
        reply_type = str(item.get("type", "")).strip() or fallback_type
        return {
            "type": reply_type,
            "title": title,
            "body": body,
        }

    send_timing_dict = data.get("send_timing_recommendation")
    if not isinstance(send_timing_dict, dict):
        send_timing_dict = {}

    best_reply = _read_reply_item(data.get("best_reply"), "best_reply")

    other_replies: List[dict[str, str]] = []
    other_replies_raw = data.get("other_replies")
    if isinstance(other_replies_raw, list):
        for i, item in enumerate(other_replies_raw, start=1):
            parsed = _read_reply_item(item, f"alternative_reply_{i}")
            if parsed:
                other_replies.append(parsed)

    reply_options_raw = data.get("reply_options")
    if isinstance(reply_options_raw, list):
        parsed_options: List[dict[str, str]] = []
        for i, item in enumerate(reply_options_raw):
            if isinstance(item, dict):
                title = str(item.get("title", "")).strip()
                body = str(item.get("body", "")).strip()
                reply_type = str(item.get("type", "")).strip() or (
                    "best_reply" if i == 0 else f"alternative_reply_{i}"
                )
                if title and body:
                    parsed_options.append(
                        {
                            "type": reply_type,
                            "title": title,
                            "body": body,
                        }
                    )
        if parsed_options:
            if best_reply is None:
                best_reply = parsed_options[0]
            if not other_replies:
                other_replies = parsed_options[1:3]

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

    reply_options: List[dict[str, str]] = []
    if best_reply:
        reply_options.append(best_reply)
    reply_options.extend(other_replies)

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

    send_timing_label = _first_text(
        data.get("send_timing"),
        send_timing_dict.get("label"),
        "少し整えてから送るのがよい",
    )
    send_timing_reason = _first_text(
        data.get("send_timing_reason"),
        send_timing_dict.get("reason"),
        "今は伝えたい気持ちよりも、どう聞こえるかの影響が大きい状態です。短く整えてから送る方が悪化しにくいです。",
    )

    situation_summary = _first_text(
        data.get("summary"),
        data.get("situation_summary"),
        "内容そのものより、言い方や受け取り方のズレでこじれている可能性があります。",
    )
    partner_feeling_estimate = _first_text(
        data.get("partner_feeling_estimate"),
        "相手は怒りそのものより、軽く扱われたことや理解されていないことに反応している可能性があります。",
    )

    return {
        "session_id": str(data.get("session_id", "session_generated")),
        "analysis_status": "completed",
        "safety_flag": bool(data.get("safety_flag", False)),
        "send_timing_recommendation": {
            "code": str(send_timing_dict.get("code", "soften_first")),
            "label": send_timing_label,
            "reason": send_timing_reason,
        },
        "situation_summary": situation_summary,
        "partner_feeling_estimate": partner_feeling_estimate,
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

    heard_as = _to_string_list(data.get("heard_as_interpretations"))
    if not heard_as:
        heard_as = risk_points[:]
    heard_as = heard_as[:2]

    avoid_phrases = _to_string_list(data.get("avoid_phrases"))
    avoid_phrases = avoid_phrases[:2]

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
        "heard_as_interpretations": heard_as,
        "avoid_phrases": avoid_phrases,
        "softened_message": softened_message,
        "revised_message_options": revised,
        "suggest_consult_mode": bool(data.get("suggest_consult_mode", True)),
    }

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
        "[relation_type]\n" + relation_label,
    ]

    if request.relation_detail_labels:
        labels = [label.strip() for label in request.relation_detail_labels if label.strip()]
        if labels:
            parts.append("[relation_detail_labels]\n" + "\n".join(labels))

    if request.profile_context and request.profile_context.strip():
        parts.append("[profile_context]\n" + request.profile_context.strip())

    if request.recent_pattern_summary and request.recent_pattern_summary.strip():
        parts.append("[recent_consultation_history]\n" + request.recent_pattern_summary.strip())

    if request.optional_note and request.optional_note.strip():
        parts.append("[optional_note]\n" + request.optional_note.strip())

    parts.append(
        "\n".join(
            [
                "必須ルール:",
                "- recent_consultation_history がある場合は、その履歴に出た反復パターンを必ず score / summary / risk_points / next_actions に反映する",
                "- profile_context に通常16タイプ / 恋愛16タイプ / 短い傾向がある場合は、コミュニケーション傾向の仮説として参照する",
                "- ただしタイプだけで断定しない。relation_detail_labels / recent_consultation_history / optional_note と矛盾する場合は実際の文脈を優先する",
                "- type情報は、安心感の作り方・言葉の強さ・返答速度・修復の仕方の調整に使う",
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

    return "\n\n".join(parts)




def stabilize_compatibility_score(
    request: CompatibilityRequest,
    result: dict[str, Any],
) -> dict[str, Any]:
    score = int(result.get("score", 78))
    score = max(0, min(100, score))

    recent = (request.recent_pattern_summary or "").strip()
    note = (request.optional_note or "").strip()
    profile = (request.profile_context or "").strip()

    text_blob = "\n".join([recent, note, profile]).lower()

    risk_hits = 0
    for keyword in [
        "不安",
        "傷つ",
        "冷た",
        "強い言い方",
        "返信が遅い",
        "すれ違",
        "謝る前に正論",
        "衝突",
        "喧嘩",
    ]:
        if keyword.lower() in text_blob:
            risk_hits += 1

    positive_hits = 0
    for keyword in [
        "信頼",
        "安心",
        "落ち着",
        "率直",
        "優しい",
        "思いやり",
        "尊重",
    ]:
        if keyword.lower() in text_blob:
            positive_hits += 1

    score = score - min(risk_hits * 3, 12) + min(positive_hits * 2, 6)
    score = max(0, min(100, score))

    if score >= 85:
        label = "かなり相性が良い"
    elif score >= 70:
        label = "相性は良い"
    elif score >= 55:
        label = "相性は悪くない"
    elif score >= 40:
        label = "調整次第で十分うまくいく"
    else:
        label = "丁寧なすり合わせが必要"

    result["score"] = score
    result["label"] = label

    summary = str(result.get("summary") or "").strip()
    if recent:
        extra = "過去の相談履歴では、繰り返し起きるすれ違いパターンも評価に反映しています。"
        if extra not in summary:
            result["summary"] = (summary + " " + extra).strip() if summary else extra

    return result


def _request_to_prompt_lines(request, heading: str) -> str:
    if hasattr(request, "model_dump"):
        data = request.model_dump()
    elif hasattr(request, "dict"):
        data = request.dict()
    else:
        data = vars(request)

    lines = [heading]

    for key, value in data.items():
        if value is None:
            continue

        if isinstance(value, list):
            cleaned = []
            for item in value:
                s = str(item).strip()
                if s:
                    cleaned.append(s)
            if cleaned:
                lines.append(f"{key}:")
                lines.extend([f"- {item}" for item in cleaned])
            continue

        if isinstance(value, dict):
            if value:
                lines.append(f"{key}: {value}")
            continue

        s = str(value).strip()
        if s:
            lines.append(f"{key}: {s}")

    return "\n".join(lines)


def _request_list_attr(request, name: str) -> List[str]:
    value = getattr(request, name, [])
    if not isinstance(value, list):
        return []
    result: List[str] = []
    for item in value:
        s = str(item).strip()
        if s:
            result.append(s)
    return result


def _request_text_attr(request, name: str) -> str:
    value = getattr(request, name, "")
    if value is None:
        return ""
    return str(value).strip()



def _canonical_relation_type(value: str) -> str:
    relation = str(value or "").strip()

    if relation == "family_inlaw":
        return "inlaw"

    if relation in {"family_parent_child", "parent_child", "family_other"}:
        return "family"

    return relation


def _request_str_attr(request, name: str) -> str:
    value = str(getattr(request, name, "") or "").strip()
    if name == "relation_type":
        return _canonical_relation_type(value)
    return value

    if value is None:
        return ""
    return str(value).strip()


def _consult_semantic_focus(request) -> str:
    signals = set(_request_list_attr(request, "latent_signals"))
    signals.update(_derived_latent_signals_from_keys(request))
    notes: List[str] = []

    if signals & {"contact_anxiety", "response_absence", "seen_no_reply", "uncertainty_high"}:
        notes.append("連絡不安や不確実性を軽く扱わず、安心感と解釈の余地を残す方向で組み立ててください。")

    if signals & {"reciprocity_gap", "emotional_temperature_gap", "meeting_frequency_gap", "closeness_misalignment"}:
        notes.append("どちらが悪いかより、温度差や期待値のズレとして整理してください。")

    if signals & {"overpursuit_risk", "engulfment_pressure", "boundary_tension", "boundary_intent"}:
        notes.append("追い詰め感を避け、相手の余白と境界線を尊重する案を優先してください。")

    if signals & {"hurt_by_partner_tone", "harsh_wording", "condescension_pain", "dismissed_feeling"}:
        notes.append("内容の正しさより、傷つき・尊重不足・受け取り方の悪化を重視してください。")

    if signals & {"trust_damage", "promise_meeting_issue", "promise_future_issue", "partner_broke_promise"}:
        notes.append("単なる事実確認ではなく、信頼の揺れや軽く扱われた感じまで言語化してください。")

    if signals & {"money_share_issue", "reimbursement_issue", "fairness_pain", "future_finance_anxiety"}:
        notes.append("金額の話だけでなく、公平感・負担感・感謝不足・将来不安まで扱ってください。")

    if signals & {"partner_feels_distant", "need_space", "alone_time_gap", "relational_freeze", "distance_increasing"}:
        notes.append("距離感テーマでは、近づきたい側と離れたい側の非対称性を明示してください。")

    if signals & {"active_conflict", "emotional_activation_high", "ongoing_strain", "issue_persisting"}:
        notes.append("正しさの主張より、刺激を下げて悪化を止める案を優先してください。")

    if "repair_intent" in signals:
        notes.append("修復意図が強いため、自己弁護より受け止めと再接続を優先してください。")

    if "clarify_intent" in signals:
        notes.append("確認したい意図が強いため、尋問調ではなく答えやすい聞き方を優先してください。")

    if "align_intent" in signals:
        notes.append("今後のすり合わせ意図が強いため、再発防止や運用の合わせ方まで触れてください。")

    if "pause_intent" in signals:
        notes.append("今すぐ送らない・少し置く選択肢も前向きに提案してください。")

    if "express_intent" in signals:
        notes.append("感情表現が目的でも、重さより伝わりやすさを優先してください。")

    return " ".join(notes)

def _consult_case_style(request) -> str:
    relation = _request_str_attr(request, "relation_type")
    theme = str(getattr(request, "theme", "")).strip()
    current_status = str(getattr(request, "current_status", "")).strip()
    emotion_level = str(getattr(request, "emotion_level", "")).strip()
    goal = str(getattr(request, "goal", "")).strip()
    semantic_focus = _consult_semantic_focus(request)

    notes: List[str] = []

    if relation == "couple":
        notes.append("恋人同士の温度差、安心感、嫉妬、距離感の繊細さを重視してください。")
    elif relation == "friend":
        notes.append("友人関係の礼儀、約束、距離感、温度差を重視してください。")
    elif relation.startswith("family"):
        notes.append("家族関係の干渉、役割、比較、境界線を重視してください。")
    else:
        notes.append("相手との上下関係や距離感のズレを重視してください。")

    if theme in {"嫉妬", "距離感", "人間関係・温度差"}:
        notes.append("感情をぶつけるより、安心感と誤解の修正を優先してください。")
    if theme in {"言い方がきつい", "約束", "親を挟んだ揉めごと", "パートナー経由の伝わり方"}:
        notes.append("言い分の正しさより、受け取り方の悪化を止めることを優先してください。")
    if theme in {"お金", "家事", "家のこと", "家のこと・役割分担", "生活や子育てへの口出し"}:
        notes.append("感情処理だけでなく、境界線や具体的なすり合わせも含めてください。")

    if current_status == "まだ何もしていない":
        notes.append("初動の一通として自然で短い提案を優先してください。")
    elif current_status in {"すでに一度やり取りした", "何往復かしてこじれている"}:
        notes.append("これ以上悪化させない鎮静化を優先してください。")

    if emotion_level in {"かなり感情的", "爆発しそう"}:
        notes.append("感情の勢いをそのまま出す案は避け、短く安全な文を優先してください。")

    if semantic_focus:
        notes.append(semantic_focus)

    if goal == "距離を置きたい":
        notes.append("仲直りの演出より、角が立ちにくい境界線設定を優先してください。")
    elif goal == "今は送らず整理したい":
        notes.append("送らない判断も積極的に提案してください。")
    elif goal in {"謝りたい", "仲直りしたい"}:
        notes.append("自己弁護より、受け止めと安心感を優先してください。")

    return " ".join(notes)



def _compact_case_text(*values: Any) -> str:
    parts: List[str] = []
    for value in values:
        if value is None:
            continue
        if isinstance(value, list):
            for item in value:
                s = str(item).strip()
                if s:
                    parts.append(s)
            continue
        s = str(value).strip()
        if s:
            parts.append(s)
    return "\n".join(parts)


def _contains_any(text: str, needles: list[str]) -> bool:
    lowered = text.lower()
    return any(str(needle).lower() in lowered for needle in needles)


def _consult_case_axis(request) -> str:
    relation = _request_str_attr(request, "relation_type")
    theme = str(getattr(request, "theme", "") or "").strip()
    goal = str(getattr(request, "goal", "") or "").strip()

    details_text = _compact_case_text(
        getattr(request, "relation_detail_labels", []),
        getattr(request, "theme_details", []),
        getattr(request, "theme_detail_keys", []),
        getattr(request, "current_status", ""),
        getattr(request, "current_status_key", ""),
        getattr(request, "emotion_level", ""),
        getattr(request, "goal", ""),
        getattr(request, "goal_key", ""),
        getattr(request, "note", ""),
        getattr(request, "chat_text", ""),
        getattr(request, "recent_pattern_summary", ""),
        getattr(request, "latent_signals", []),
    )

    notes: List[str] = []

    if relation == "couple" and theme == "嫉妬":
        notes.append("嫉妬では、誰が誰に不安を感じているのかを冒頭で明示してください。")
        if _contains_any(details_text, ["疑われた", "束縛", "監視", "詮索", "責められた", "嫉妬された"]):
            notes.append("今回は自分が疑われた・嫉妬された側として整理してください。")
        elif _contains_any(details_text, ["嫉妬してしまう", "不安", "取られそう", "他の女", "他の男", "女友達", "男友達", "元恋人", "元カレ", "元カノ"]):
            notes.append("今回は自分が嫉妬して不安になっている側として整理してください。")
        else:
            notes.append("主体が不明でも、summary の冒頭で仮の対立軸を自然に言語化してください。")
        notes.append("嫉妬は恋愛不安・比較不安として扱い、一般的な価値観のズレに薄めないでください。")

    elif relation == "couple" and theme == "連絡頻度":
        notes.append("連絡頻度では、どちらがより連絡を求めているか、何に傷ついたのかを明示してください。")
        if _contains_any(details_text, ["返信が遅い", "既読無視", "未読", "そっけない", "回数が少ない"]):
            notes.append("返信速度や温度差への不安が中心です。")
        if _contains_any(details_text, ["責めてしまった", "催促", "追いLINE"]):
            notes.append("すでに責めた後の修復として best_reply を作ってください。")
        notes.append("send_timing_reason は追撃が重いか、短い確認ならよいかをこのケースに即して書いてください。")

    elif relation == "couple" and theme == "言い方がきつい":
        notes.append("言い方がきついでは、きつく言った側と傷ついた側を曖昧にしないでください。")
        if _contains_any(details_text, ["自分がきつく言ってしまった", "言い過ぎた", "責めすぎた"]):
            notes.append("今回は自分が強く言ってしまった後の修復として整理してください。")
        elif _contains_any(details_text, ["責められた", "冷たく返された", "馬鹿にされた", "正論で詰められた"]):
            notes.append("今回は相手の言い方で傷ついた側として整理してください。")
        notes.append("best_reply は謝罪なのか境界線なのかを goal に合わせて変えてください。")

    elif relation == "couple" and theme == "距離感":
        notes.append("距離感では、近づきたい側と距離を取りたい側を明示してください。")
        notes.append("重さ・放置・束縛・温度差のどれが主軸かを summary 冒頭で自然にまとめてください。")

    elif relation == "couple" and theme == "約束":
        notes.append("約束では、破られた内容だけでなく、軽く扱われた感じや信頼の揺れも拾ってください。")
        notes.append("best_reply は事実確認だけでなく、今後どう合わせるかまで含めてください。")

    elif relation == "couple" and theme == "お金":
        notes.append("お金では、金額そのものよりも負担感・公平感・感謝不足・当然視のどれが痛点かを明示してください。")
        notes.append("summary で単なるお金の話にせず、信頼や配慮のズレまで言語化してください。")

    elif relation.startswith("family") and theme == "パートナー経由の伝わり方":
        notes.append("家族・義家族の伝わり方では、誰が誰にどう伝えたか、または伝えなかったかを明示してください。")
        notes.append("パートナーが盾になれていない不満なのか、伝言ゲームで歪んだ不満なのかを分けて扱ってください。")

    elif relation.startswith("family") and theme == "行事・付き合い":
        notes.append("行事・付き合いでは、参加義務感・温度差・優先順位・断りづらさのどれが中心かを明示してください。")
        notes.append("best_reply は単なる断り文句ではなく、角を立てずに線引きする形を優先してください。")

    elif relation == "friend" and theme == "人間関係・温度差":
        notes.append("友人の温度差では、期待していた近さと実際の距離のズレを明示してください。")
        notes.append("仲直りしたいのか、関係を軽く整えたいのか、自然にフェードしたいのかを goal に沿って分けてください。")

    if "謝りたい" in goal:
        notes.append("goal は謝罪です。best_reply は説明より先に受け止めと謝意を置いてください。")
    elif "誤解を解きたい" in goal:
        notes.append("goal は誤解の修正です。防御的になりすぎず、認識ズレの整理を優先してください。")
    elif "落ち着かせたい" in goal:
        notes.append("goal は火消しです。正しさの主張よりも刺激を下げる言い方を優先してください。")
    elif "仲直りしたい" in goal:
        notes.append("goal は再接続です。短く安心感を出しつつ、会話の再開余地を残してください。")
    elif "距離を置きたい" in goal:
        notes.append("goal は境界線です。曖昧な優しさより、柔らかいがぶれない線引きを優先してください。")
    elif "相手の気持ちを知りたい" in goal:
        notes.append("goal は確認です。尋問ではなく、答えやすい開き方を優先してください。")

    if _contains_any(details_text, ["今送ると悪化しそう", "かなり感情的", "お互い感情的", "さっき電話で揉めた"]):
        notes.append("send_timing は少し置く寄りを基本線にしてください。")
    elif _contains_any(details_text, ["今から返信したい", "会話が止まっている", "既読無視", "未読のまま"]):
        notes.append("send_timing は短く送るか少し待つかをケースごとに具体的に書いてください。")

    if not notes:
        notes.append("summary の1文目で対立軸を名詞化し、best_reply では goal に合う一手を具体化してください。")

    return " ".join(notes)


def _consult_semantic_directives_text(request) -> str:
    signals = set(_request_list_attr(request, "latent_signals"))
    parts: List[str] = []

    if signals & {"contact_anxiety", "seen_no_reply", "response_absence", "uncertainty_high", "clarify_intent"}:
        parts.append("best_reply は2文以内を基本にし、質問は1つまで、決めつけ語や被害者化表現を避けて、答えやすい確認にしてください。")

    if signals & {"active_conflict", "emotional_activation_high", "ongoing_strain", "issue_persisting"}:
        parts.append("send_timing_recommendation は基本 soften_first 寄りにし、pre_send_cautions の先頭で詰問化・悪化リスクを明示してください。")

    if signals & {"repair_intent", "trust_damage", "partner_broke_promise", "self_broke_promise"}:
        parts.append("best_reply は説明要求より先に hurt や不信感への受け止めを置き、再接続余地を残してください。")

    if signals & {"boundary_intent", "need_space", "engulfment_pressure", "partner_feels_distant", "relational_freeze"}:
        parts.append("best_reply では返答強制を避け、『今すぐ返事じゃなくて大丈夫』のような余白を許可してください。")

    if signals & {"fairness_pain", "money_share_issue", "reimbursement_issue", "future_finance_anxiety"}:
        parts.append("お金テーマでは金額の正しさだけでなく、不公平感・負担感・言い出しにくさを言語化してください。")

    if signals & {"hurt_by_partner_tone", "harsh_wording", "condescension_pain", "dismissed_feeling"}:
        parts.append("言い方テーマでは内容反論より先に、傷つき・尊重不足・受け取りの悪化を扱ってください。")

    return " ".join(parts)


def _consult_all_semantic_keys(request) -> List[str]:
    keys: List[str] = []
    keys.extend(_request_list_attr(request, "theme_detail_keys"))

    current_status_key = _request_str_attr(request, "current_status_key")
    if current_status_key:
        keys.append(current_status_key)

    goal_key = _request_str_attr(request, "goal_key")
    if goal_key:
        keys.append(goal_key)

    return keys


def _derived_latent_signals_from_keys(request) -> List[str]:
    theme = _request_str_attr(request, "theme")
    keys = _consult_all_semantic_keys(request)
    if not keys:
        return []

    derived: set[str] = set()

    def has_suffix(*suffixes: str) -> bool:
        for key in keys:
            for suffix in suffixes:
                if key.endswith(suffix):
                    return True
        return False

    if theme == "連絡頻度":
        if has_suffix("|q1|o2", "|q2|o1"):
            derived.update({"abrupt_change", "seen_no_reply", "contact_anxiety", "response_absence", "uncertainty_high"})
        if has_suffix("|status|o4"):
            derived.update({"active_conflict", "ongoing_strain", "issue_persisting"})
        if has_suffix("|goal|o1"):
            derived.add("clarify_intent")

    elif theme == "言い方がきつい":
        if has_suffix("|q1|o2"):
            derived.add("tone_hurt")
        if has_suffix("|q2|o1"):
            derived.add("repeated_pattern")
        if has_suffix("|status|o4"):
            derived.update({"active_conflict", "issue_persisting"})

    elif theme == "約束":
        if has_suffix("|q1|o1"):
            derived.update({"trust_drop", "hurt_expectation"})
        if has_suffix("|q2|o1"):
            derived.add("repeated_pattern")
        if has_suffix("|status|o4"):
            derived.update({"active_conflict", "issue_persisting"})

    elif theme == "お金":
        if has_suffix("|q1|o2", "|q2|o1"):
            derived.update({"unfairness", "burden_imbalance"})
        if has_suffix("|status|o4"):
            derived.update({"active_conflict", "issue_persisting"})
        if has_suffix("|goal|o2"):
            derived.add("align_intent")

    elif theme == "距離感":
        if has_suffix("|q1|o2", "|q2|o2"):
            derived.update({"partner_feels_distant", "need_space", "distance_increasing"})
        if has_suffix("|status|o4"):
            derived.update({"active_conflict", "issue_persisting"})
        if has_suffix("|goal|o1"):
            derived.add("clarify_intent")

    return sorted(derived)


def _consult_has_signal(request, *names: str) -> bool:
    signals = set(_request_list_attr(request, "latent_signals"))
    signals.update(_derived_latent_signals_from_keys(request))
    return any(name in signals for name in names)


def _consult_goal_intent(request) -> str:
    theme = _request_str_attr(request, "theme")
    goal = _request_str_attr(request, "goal")

    if _consult_has_signal(request, "align_intent"):
        return "align"
    if _consult_has_signal(request, "clarify_intent"):
        return "clarify"
    if _consult_has_signal(request, "repair_intent"):
        return "repair"
    if _consult_has_signal(request, "boundary_intent"):
        return "boundary"

    if theme in {"連絡頻度", "距離感"}:
        if "知りたい" in goal or "気持ち" in goal or "確認" in goal:
            return "clarify"

    if theme == "お金":
        if "納得" in goal or "形にしたい" in goal or "すり合わせ" in goal or "決めたい" in goal:
            return "align"

    if "仲直り" in goal or "修復" in goal:
        return "repair"
    if "距離" in goal or "離れたい" in goal:
        return "boundary"
    if "知りたい" in goal or "確認" in goal:
        return "clarify"
    if "納得" in goal or "整理" in goal or "落ち着いて話したい" in goal:
        return "align"

    return ""




def _consult_has_any_key_suffix(request, *suffixes: str) -> bool:
    keys: List[str] = []

    for value in getattr(request, "theme_detail_keys", []) or []:
        if value:
            keys.append(str(value).strip())

    for value in [
        getattr(request, "current_status_key", ""),
        getattr(request, "goal_key", ""),
    ]:
        if value:
            keys.append(str(value).strip())

    return any(any(key.endswith(suffix) for suffix in suffixes) for key in keys)


def _compose_couple_best_reply(request) -> Optional[str]:
    relation = _request_text_attr(request, "relation_type")
    theme = _request_text_attr(request, "theme")
    intent = _consult_goal_intent(request)

    if relation != "couple":
        return None

    if theme == "連絡頻度":
        if intent == "clarify":
            if _consult_has_signal(request, "active_conflict", "ongoing_strain", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "最近ちょっと連絡が少なくて、私は不安になってた。責める言い方になってたらごめん。今すぐじゃなくて大丈夫だから、落ち着いたら今どんな感じか話せる範囲で教えてもらえると嬉しい。"
            if _consult_has_signal(request, "need_space", "partner_feels_distant", "engulfment_pressure", "distance_increasing", "relational_freeze"):
                return "最近ちょっと連絡が少なくて、私は少し不安になってた。責めたいわけじゃないし、今すぐ返事じゃなくて大丈夫だから、少し距離がほしい感じなのかだけ、話せる時に教えてもらえると嬉しい。"
            if _consult_has_signal(request, "abrupt_change", "seen_no_reply", "contact_anxiety", "response_absence", "uncertainty_high") or _consult_has_any_key_suffix(request, "|q1|o2", "|q2|o1"):
                return "最近ちょっと連絡が少なくて、私は少し不安になってた。責めたいわけじゃなくて、何かあったのか、今どんな感じか話せる範囲で教えてもらえると嬉しい。"
            return "最近ちょっと連絡が少なくて、私は少し不安になってた。責めたいわけじゃなくて、今どんな感じか話せる範囲で教えてもらえると嬉しい。"

        if intent == "repair":
            if _consult_has_signal(request, "active_conflict", "ongoing_strain", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "最近、私も不安で言い方が強くなっていたかもしれない。しんどくさせてたらごめん。今すぐじゃなくて大丈夫だから、落ち着いたら少し話せたらうれしい。"
            return "最近、私も不安で言い方が強くなっていたかもしれない。責めたいわけじゃないから、落ち着いたら今どんな感じか少し話せたらうれしい。"

        if intent == "align":
            if _consult_has_signal(request, "need_space", "partner_feels_distant", "distance_increasing", "relational_freeze"):
                return "最近の連絡ペースのことで、私は少し不安になってた。近すぎるとしんどい時もあると思うから、お互いに無理のない距離感を一度すり合わせられたらうれしい。"
            return "最近の連絡ペースのことで、私は少し不安になってた。無理のない範囲で、お互いに楽な頻度を一度すり合わせられたらうれしい。"

        if intent == "boundary":
            if _consult_has_signal(request, "active_conflict", "ongoing_strain", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "今のままやり取りを続けると、お互いしんどくなりそうだと感じてる。いったん少し間を置いて、落ち着いてから話したい。"
            return "今のまま追って連絡すると、お互いしんどくなりそうだと感じてる。少し間を置いて、また落ち着いて話せる時に話したい。"

        if intent == "pause":
            return "今は気持ちが少し揺れているから、いったん落ち着いてからにするね。また話せる時に話したい。"

        if intent == "express":
            if _consult_has_signal(request, "abrupt_change", "seen_no_reply", "contact_anxiety", "response_absence") or _consult_has_any_key_suffix(request, "|q1|o2", "|q2|o1"):
                return "最近連絡が減って、私は少し寂しさと不安を感じてた。責めたいわけじゃなくて、その変化が気になっていたことだけ伝えたかった。"
            return "最近連絡が減って、私は少し寂しさと不安を感じてた。責めたいわけじゃなくて、その気持ちだけ先に伝えたかった。"

        return "最近ちょっと連絡が少なくて、私は少し不安になってた。責めたいわけじゃなくて、今どんな感じか教えてもらえると嬉しい。"

    if theme == "言い方がきつい":
        if intent == "repair":
            if _consult_has_signal(request, "active_conflict", "ongoing_strain", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "さっきは私も感情的だったかもしれない。きつく返してたらごめん。責め合いたいわけじゃないから、少し落ち着いてから話したい。"
            return "さっきの言い方、きつく聞こえたならごめん。責めたいわけじゃなくて、もう少し落ち着いて話したいだけなんだ。"

        if intent == "express":
            if _consult_has_signal(request, "issue_persisting", "repeated_pattern", "tone_hurt"):
                return "内容そのものより、言い方でしんどくなることが続いていて私はつらい。否定したいわけじゃなくて、もう少し穏やかに話せるとうれしい。"
            return "その言い方だと、私は少し強く責められたように感じてしんどかった。内容を否定したいわけじゃなくて、もう少し穏やかに話せるとうれしい。"

        if intent == "align":
            if _consult_has_signal(request, "issue_persisting", "repeated_pattern") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "話す内容より言い方で毎回しんどくなりやすい気がしてる。感情的になった時はいったん置くなど、話し方のルールを一緒に決めたい。"
            return "内容より言い方でお互いしんどくなりやすい気がしてる。感情的になった時は少し置くとか、話し方を一緒に決められたらうれしい。"

        if intent == "boundary":
            if _consult_has_signal(request, "active_conflict", "tone_hurt") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "今の言い方のままだと、私は落ち着いて話せない。いったん時間を置いて、もう少し穏やかに話せる時に続けたい。"
            return "今の言い方のままだと、私は落ち着いて話せない。少し時間を置いて、もう少し穏やかに話せる時に続けたい。"

        if intent == "clarify":
            if _consult_has_signal(request, "anger_ambiguity", "tone_unclear"):
                return "責めたいわけじゃないんだけど、さっきの言い方は本当に怒っていたのか、ただ余裕がなかっただけなのか知りたい。"
            return "責めたいわけじゃないんだけど、さっきの言い方は怒っていたのか、ただ余裕がなかったのか知りたい。"

        return "その言い方だと、私は少しきつく受け取ってしまう。責めたいわけじゃなくて、もう少し落ち着いて話せるとうれしい。"

    if theme == "約束":
        if intent == "clarify":
            if _consult_has_signal(request, "active_conflict", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "この前の約束のこと、私も感情的になっていたらごめん。大事に受け取ってた分、どういう事情だったのか落ち着いて聞かせてもらえるとうれしい。"
            return "この前の約束のこと、私は大事に受け取ってた分、どういうつもりだったのか気になってる。責めたいわけじゃないから、事情を聞かせてもらえるとうれしい。"

        if intent == "repair":
            if _consult_has_signal(request, "active_conflict", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "約束のことで私も感情的になってしまってごめん。責め合いたいわけじゃなくて、何がずれていたのか落ち着いて整理したい。"
            return "約束のことで私も感情的になってしまってごめん。大事だったからこそ気になっていて、落ち着いて話せる時に少し整理できたらうれしい。"

        if intent == "align":
            if _consult_has_signal(request, "issue_persisting", "repeated_pattern"):
                return "責めたいわけじゃなくて、約束のすれ違いが続くとお互いしんどいから、次からは守れそうなことをどう決めるか一回落ち着いて話したい。"
            return "約束の受け取り方にズレがあった気がしてる。次からどうしたらお互いに無理なく守れるか、一度すり合わせたい。"

        if intent == "boundary":
            if _consult_has_signal(request, "issue_persisting", "trust_drop"):
                return "約束が曖昧なままだと、私はしんどくなりやすい。今後はできることだけ言い合える形にしたい。"
            return "約束が曖昧なままだと、私はしんどくなりやすい。今後はできることだけ言い合える形にしたい。"

        if intent == "express":
            if _consult_has_signal(request, "trust_drop", "hurt_expectation"):
                return "約束のことを軽く扱われた感じが続くと、私は悲しさと不信感が残ってしまう。責めたいというより、その気持ちを伝えておきたい。"
            return "約束のことを軽く扱われた感じがして、私は悲しかった。責めたいというより、そう感じたことを伝えておきたい。"

        return "約束のことが私の中で引っかかってる。責めたいわけじゃないから、どういうつもりだったのか聞かせてもらえるとうれしい。"

    if theme == "お金":
        if intent == "clarify":
            if _consult_has_signal(request, "active_conflict", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "お金のこと、私も感情的になっていたらごめん。責めたいわけじゃないから、どう考えていたか落ち着いて聞かせてもらえると助かる。"
            return "お金のこと、私の中で少し引っかかってる。責めたいわけじゃないから、どう考えていたか聞かせてもらえると助かる。"

        if intent == "repair":
            if _consult_has_signal(request, "active_conflict", "issue_persisting"):
                return "お金の話で私も言い方が強くなっていたらごめん。責め合うより、まず何に引っかかっていたかを落ち着いて整理したい。"
            return "お金の話で私も言い方が強くなっていたらごめん。責め合いたいわけじゃなくて、納得できる形を一緒に考えたい。"

        if intent == "align":
            if _consult_has_signal(request, "unfairness", "burden_imbalance", "issue_persisting"):
                return "お金のことは曖昧だと負担感が偏りやすいから、今後は先に確認して、お互い納得できる形を決めたい。"
            return "お金のことは気まずくなりやすいからこそ、負担感が偏らない形を一度すり合わせたい。"

        if intent == "boundary":
            if _consult_has_signal(request, "unfairness", "burden_imbalance"):
                return "お金のことが曖昧なままだと私はしんどい。今後はその場で流さず、先に確認してからにしたい。"
            return "お金のことが曖昧なままだと私はしんどい。今後は先に確認してからにしたい。"

        if intent == "express":
            if _consult_has_signal(request, "unfairness", "burden_imbalance", "resentment_risk"):
                return "お金のことが続くと、私は少し不公平に感じてしまってしんどい。このまま溜めたくないから、まずはその気持ちだけ伝えさせて。"
            return "お金のことが続くと、私は少し不公平に感じてしまってしんどい。まずはその気持ちだけ伝えさせて。"

        return "お金のこと、責めたいわけじゃなくて、曖昧なままだと負担感が偏りやすいから、次からは先に確認して、お互い納得できる形を決めたい。"

    if theme == "距離感":
        if intent == "align":
            if _consult_has_signal(request, "need_space", "partner_feels_distant", "distance_increasing", "relational_freeze"):
                return "会う頻度や連絡の温度差で、私は少しズレを感じてた。近すぎるとしんどい時もあると思うから、お互いに無理のない距離感を一度すり合わせたい。"
            return "会う頻度や連絡の温度差で、私は少しズレを感じてた。どの距離感がお互いに楽か、一度すり合わせられたらうれしい。"

        if intent == "express":
            if _consult_has_signal(request, "distance_increasing", "contact_anxiety", "relational_freeze"):
                return "最近の距離感で、私は少し寂しさと不安を感じてた。責めたいわけじゃなくて、その変化に戸惑っていたことを伝えたかった。"
            return "最近の距離感で、私は少し寂しさと不安を感じてた。責めたいわけじゃなくて、その気持ちを伝えたかった。"

        if intent == "boundary":
            if _consult_has_signal(request, "engulfment_pressure", "active_conflict") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "今の距離感のままだと、私はしんどくなりやすい。いったん少し自分のペースを大事にしたいと思ってる。"
            return "今の距離感のままだと、私はしんどくなりやすい。少し自分のペースも大事にしたいと思ってる。"

        if intent == "pause":
            return "いったん少し落ち着いて、自分の気持ちを整理したい。また話せる時に話したい。"

        if intent == "repair":
            if _consult_has_signal(request, "contact_anxiety", "active_conflict", "issue_persisting"):
                return "距離感のことで私も不安から重くなっていたかもしれない。しんどくさせていたらごめん。落ち着いて話せる時に少し話したい。"
            return "距離感のことで私も不安から重くなっていたかもしれない。責めたいわけじゃないから、落ち着いて話せる時に少し話したい。"

        if intent == "clarify":
            if _consult_has_signal(request, "need_space", "partner_feels_distant", "distance_increasing"):
                return "最近の距離感について、私は少し不安になってる。責めたいわけじゃないし、今すぐ返事じゃなくて大丈夫だから、今は少し一人の時間がほしい感じなのか、ただ余裕がないだけなのか知りたい。"
            return "最近の距離感について、私は少し不安になってる。今は近づきたい気持ちが弱いのか、ただ余裕がないだけなのか知りたい。"

        return "最近の距離感で、私は少し不安になってる。責めたいわけじゃなくて、今どんな感じか知りたい。"

    return None





def _compose_friend_best_reply(request) -> Optional[str]:
    theme = str(getattr(request, "theme", "")).strip()
    status = str(getattr(request, "current_status", "")).strip()
    intent = _consult_goal_intent(request)

    if theme == "連絡頻度":
        if intent == "clarify":
            if _consult_has_signal(request, "active_conflict", "ongoing_strain", "issue_persisting") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "さっきは言い方がきつくなってたらごめん。責めたいわけじゃなくて、最近ちょっと連絡のテンポが変わって気になってた。落ち着いた時に、今どんな感じか教えてもらえると助かる。"
            if _consult_has_signal(request, "seen_no_reply", "response_absence", "contact_anxiety", "uncertainty_high") or _consult_has_any_key_suffix(request, "|q1|o2", "|q2|o1"):
                return "最近ちょっと連絡のテンポが変わって、少し気になってた。責めたいわけじゃないから、落ち着いた時に今どんな感じか教えてもらえると助かる。"
            return "最近ちょっと連絡のテンポが変わって、少し気になってた。無理に聞きたいわけじゃないから、落ち着いた時に今どんな感じか教えてもらえると助かる。"

        if intent in {"reconcile", "repair"}:
            return "変に気まずくしたいわけじゃないから、落ち着いた時に少しだけ話せたらうれしい。"

        if intent == "boundary":
            return "今すぐ返事がほしいわけじゃないから、落ち着いた頃に連絡もらえたら助かる。"

        return "最近ちょっと連絡のテンポが変わって気になってた。急ぎじゃないから、落ち着いた時に少し話せたらうれしい。"

    if theme == "言い方がきつい":
        if intent in {"calm", "reconcile", "repair"}:
            if _consult_has_signal(request, "tone_hurt", "issue_persisting", "repeated_pattern") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "さっきはお互い少し強くなってたかもしれない。責め合いたいわけじゃないから、もう少し落ち着いて話せたらありがたい。"
            return "ちょっと言い方が強く感じて気になってた。責めたいわけじゃないから、落ち着いて話せると助かる。"

        if intent == "clarify":
            return "さっきの言い方が少し強く聞こえて、ちょっと気になってた。どういう意図だったか、落ち着いた時に聞けると助かる。"

        return "ちょっと強く聞こえた部分があって気になってた。責めたいわけじゃないから、落ち着いて話せるとありがたい。"

    if theme == "約束":
        if intent in {"clarify", "reconcile", "repair"}:
            if _consult_has_signal(request, "issue_persisting", "repeated_pattern") or _consult_has_any_key_suffix(request, "|status|o4"):
                return "約束のこと、私の中で少し引っかかってる。責めたいわけじゃなくて、何がずれてたのか一回整理したい。"
            return "約束のこと、少し気になってた。責めたいわけじゃないから、何がずれてたのか落ち着いて整理できたらうれしい。"

        if intent == "boundary":
            return "次からは曖昧にならないように、約束の確認だけ先にしておきたい。"

        return "約束のこと、少し引っかかってた。責めたいわけじゃないから、一回整理できたら助かる。"

    if theme == "お金":
        if intent in {"clarify", "reconcile", "repair"}:
            if _consult_has_signal(request, "unfairness", "burden_imbalance", "issue_persisting"):
                return "お金のこと、私の中で少し引っかかってる。責めたいわけじゃなくて、次から気まずくならない形を一回すり合わせたい。"
            return "お金のことって曖昧だと気まずくなりやすいから、次からは先に確認できると助かる。"

        if intent == "boundary":
            return "お金のことは曖昧にしないで、次からは先に確認して進めたい。"

        return "立替やお金のこと、責めたいわけじゃないんだけど、曖昧なままだとお互い気まずくなりやすいから、一回整理したい。"

    if theme == "距離感":
        if intent == "clarify":
            if _consult_has_signal(request, "need_space", "partner_feels_distant", "distance_increasing", "relational_freeze"):
                return "最近ちょっと距離を感じて、少し気になってた。無理に詰めたいわけじゃないから、今は少し距離を置きたい感じなのか、ただ余裕がないだけなのか教えてもらえると助かる。"
            return "最近ちょっと距離を感じて、少し気になってた。責めたいわけじゃないから、今どんな感じか落ち着いた時に聞けるとうれしい。"

        if intent == "boundary":
            return "今は少し距離を置きつつ、落ち着いたらまた話せたら助かる。"

        return "最近ちょっと距離を感じて気になってた。無理に詰めたいわけじゃないから、落ち着いた時に少し話せるとうれしい。"

    return None




def _compose_inlaw_best_reply(request) -> Optional[str]:
    theme = str(getattr(request, "theme", "") or "").strip()
    labels = getattr(request, "relation_detail_labels", []) or []
    joined_labels = " ".join(str(x) for x in labels if x)

    if theme == "行事・付き合い":
        if "義父" in joined_labels:
            return "いつも気にかけていただいてありがとうございます。毎回参加するのは少し難しいので、今後は都合を見ながら無理のない範囲で参加できれば助かります。参加できるときはぜひ伺いたいです。"
        return "いつも気にかけてくださってありがとうございます。毎回参加するのは少し難しいので、今後は都合を見ながら無理のない範囲で参加させていただけると助かります。参加できるときはぜひ伺いたいです。"

    return None

def _compose_family_best_reply(request) -> Optional[str]:
    relation = _request_str_attr(request, "relation_type")
    theme = _request_str_attr(request, "theme")

    if theme == "連絡頻度":
        return "最近の連絡のこと、少し気になってる。責めたいわけじゃないから、お互い無理のないペースを一度すり合わせられると助かる。"

    if theme == "言い方がきつい":
        if relation in {"family_parent_child", "parent_child"}:
            return "今は少し気持ちが強くなっているから、落ち着いてから話したいです。言い方が強いと私はしんどくなるので、できればもう少しやわらかく話してもらえると助かります。"
        return "さっきのやり取り、少ししんどかった。責めたいわけじゃないけど、強い言い方だとこちらもきつくなるから、落ち着いて話せる形にしたい。"

    if theme == "約束":
        return "この前の約束のこと、少し引っかかってる。責めたいわけじゃなくて、どういう事情だったのか聞きたいし、次からはどうしたらいいか一回ちゃんと話せると助かる。"

    if theme == "お金":
        return "お金のこと、曖昧なままだと自分の負担が偏っている感じがして気になってる。責めたいわけじゃなくて、今後は誰が何をどこまで負担するかを一度きちんと決めたい。次から同じことが起きないように、分担の仕方を話せると助かる。"

    if theme == "距離感":
        return "今は少し距離がある感じがして気になってる。責めたいわけじゃないから、今どんな距離感なら無理がないかを落ち着いて話せると助かる。"

    if theme == "口出し・干渉":
        return "気にかけてくれているのは分かってる。でも今は少し踏み込まれすぎるとしんどいから、ここは私の判断も尊重してもらえると助かる。"

    if theme == "信頼されていない感じ":
        return "心配してくれているのは分かるけど、毎回確認されると信頼されていないように感じて少ししんどい。どうしたらお互い安心できるか、一度落ち着いて話したい。"

    if theme == "パートナー経由の伝わり方":
        return "この話が間に入る形だと気持ちや意図がずれやすいから、必要なら私にも直接わかる形で伝えてもらえると助かる。"

    if theme == "行事・付き合い":
        return "行事のこと、気持ちは分かるけど今の私たちの負担もあるから、無理のない関わり方を一度すり合わせたい。"

    if theme == "育児方針":
        return "子どものことを大事に思っているのは同じだと思ってる。だからこそ、どちらかを否定する形じゃなくて、優先したいことを一度落ち着いて整理したい。"

    if theme == "家事分担":
        return "家のことが偏っている感じがして少ししんどい。責めたいわけじゃないから、今の負担を見える形にして無理のない分け方を決めたい。"

    return None

def _compose_relation_best_reply(request) -> Optional[str]:
    relation = _request_str_attr(request, "relation_type")
    theme = _request_str_attr(request, "theme")

    if theme == "約束":
        if relation == "couple":
            return "この前の約束のこと、少し引っかかってる。責めたいわけじゃなくて、どういう事情だったのか知りたいし、次からはどうするか一回ちゃんと話したい。"
        if relation == "friend":
            return "この前の約束のこと、少し引っかかってた。責めたいわけじゃないから、どういう感じだったのか聞けると助かる。次から気まずくならない形にしたい。"
        if relation == "family":
            return "この前の約束のこと、少し引っかかってる。責めたいわけじゃなくて、事情は聞きたいし、次からどうするかは一回ちゃんと決めたい。"

    if relation == "couple":
        return _compose_couple_best_reply(request)
    if relation == "friend":
        return _compose_friend_best_reply(request)
    if relation == "family":
        return _compose_family_best_reply(request)
    if relation == "inlaw":
        return _compose_inlaw_best_reply(request)

    return None



def _soften_high_emotion_reply(request, body: str) -> str:
    relation = _request_str_attr(request, "relation_type")
    theme = str(getattr(request, "theme", "") or "").strip()
    emotion = str(getattr(request, "emotion_level", "") or "").strip()
    status = str(getattr(request, "current_status", "") or "").strip()
    labels = " ".join(getattr(request, "relation_detail_labels", []) or [])

    is_hot = (
        emotion in {"少し感情的", "かなり感情的", "爆発しそう"}
        or "こじれ" in status
        or "気まず" in status
    )
    if not is_hot:
        return body

    if any(s in body for s in [
        "責めたいわけじゃ",
        "責めるつもりは",
        "感情的に責めたいわけじゃ",
        "気まずくしたいわけじゃ",
        "今すぐ返事じゃなくて大丈夫",
        "ありがとうございます",
        "ありがたいのですが",
    ]):
        return body

    if relation == "couple" and theme == "連絡頻度":
        return "責めたいわけじゃないんだけど、" + body

    if relation == "couple" and theme == "約束":
        return "感情的に責めたいわけじゃなくて、" + body

    if relation == "couple" and theme == "お金":
        return "責めたいわけじゃなくて、今後こじれないように、" + body

    if relation == "friend" and theme == "お金":
        return "気まずくしたいわけじゃなくて、" + body

    if theme == "行事・付き合い" and ("義" in labels or relation == "family"):
        return "いつも気にかけていただけるのはありがたいのですが、" + body

    return body


def _set_primary_reply(normalized: dict, body: str) -> dict:
    if not body:
        return normalized

    reply_options = normalized.get("reply_options")
    if isinstance(reply_options, list) and reply_options:
        first = reply_options[0]
        if isinstance(first, dict):
            first["body"] = body
            if not first.get("type"):
                first["type"] = "best_reply"
            if not first.get("title"):
                first["title"] = "おすすめの返し方"
        else:
            reply_options[0] = {
                "type": "best_reply",
                "title": "おすすめの返し方",
                "body": body,
            }
    else:
        normalized["reply_options"] = [{
            "type": "best_reply",
            "title": "おすすめの返し方",
            "body": body,
        }]

    return normalized




def _polish_relation_reply(request, body: str) -> str:
    relation = _request_str_attr(request, "relation_type")
    theme = _request_str_attr(request, "theme")

    relation_labels = []
    try:
        relation_labels = list(getattr(request, "relation_detail_labels", []) or [])
    except Exception:
        relation_labels = []

    relation_labels_text = " ".join(str(x) for x in relation_labels)
    is_inlaw = (
        relation == "inlaw"
        or "義母" in relation_labels_text
        or "義父" in relation_labels_text
        or "義家族" in relation_labels_text
        or "義実家" in relation_labels_text
    )

    if relation == "couple" and theme == "お金":
        if "お金のことは曖昧だと負担感が偏りやすい" in body:
            return "お金のこと、責めたいわけじゃなくて、曖昧なままだと負担感が偏りやすいから、次からは先に確認して、お互い納得できる形を決めたい。"

    if relation == "friend" and theme == "お金":
        if "曖昧なままだとお互い気まずくなりやすい" in body:
            return "立替やお金のこと、責めたいわけじゃないんだけど、曖昧なままだとお互い気まずくなりやすいから、一回整理したい。"

    if is_inlaw and theme == "行事・付き合い":
        return "いつも気にかけてくださってありがとうございます。毎回参加するのは少し難しいので、今後は都合を見ながら無理のない範囲で参加させていただけると助かります。参加できるときはぜひ伺いたいです。"

    if "いつも気にかけていただけるのはありがたいのですが、行事のこと、気持ちは分かるけど今の私たちの負担もあるから、無理のない関わり方を一度すり合わせたい。" in body:
        return "いつも気にかけてくださってありがとうございます。毎回参加するのは少し難しいので、今後は都合を見ながら無理のない範囲で参加させていただけると助かります。参加できるときはぜひ伺いたいです。"

    return body



def _compress_overlong_reply(request, body: str) -> str:
    relation = _request_str_attr(request, "relation_type")
    theme = _request_str_attr(request, "theme")

    if relation == "couple" and theme == "連絡頻度":
        if "最近ちょっと連絡が少なくて" in body and "話せる範囲で教えてもらえると嬉しい" in body:
            return "最近ちょっと連絡が少なくて不安になってた。責めたいわけじゃないから、落ち着いた時に今どんな感じか教えてもらえると嬉しい。"

    if relation == "family" and theme == "お金":
        if "今後は誰が何をどこまで負担するかを一度きちんと決めたい" in body:
            return "お金のこと、このまま曖昧だと自分の負担が偏る感じがして気になってる。責めたいわけじゃなくて、今後の分担を一度ちゃんと決めたい。"

    if relation == "family" and theme == "言い方がきつい":
        if "強い言い方だとこちらもきつくなる" in body:
            return "さっきの言い方は少ししんどかった。責めたいわけじゃないけど、もう少し落ち着いて話せると助かる。"

    if relation == "friend" and theme == "連絡頻度":
        if "最近ちょっと連絡のテンポが変わって" in body:
            return "最近ちょっと連絡のテンポが変わって気になってた。責めたいわけじゃないから、落ち着いた時に今どんな感じか教えてもらえると助かる。"

    return body


def _apply_consult_reply_composer(request, normalized: dict) -> dict:
    body = _compose_relation_best_reply(request)
    if not body:
        return normalized
    body = _soften_high_emotion_reply(request, body)
    body = _polish_relation_reply(request, body)
    body = _compress_overlong_reply(request, body)
    return _set_primary_reply(normalized, body)
    if not body:
        return normalized
    return _set_primary_reply(normalized, body)

def build_consult_input(request) -> str:
    base = _request_to_prompt_lines(
        request,
        "以下は相談内容です。json形式で返してください。",
    )

    rules = [
        "[consult_output_rules]",
        "- relation_type / relation_detail_labels / theme / theme_details / current_status / emotion_level / goal を主な判断材料にしてください。",
        "- theme_detail_keys / current_status_key / goal_key / latent_signals も重要な判断材料にしてください。",
        f"- semantic_choice_keys: {_compact_case_text(getattr(request, 'theme_detail_keys', []), getattr(request, 'current_status_key', ''), getattr(request, 'goal_key', '')) or 'なし'}",
        f"- latent_signals: {_compact_case_text(getattr(request, 'latent_signals', [])) or 'なし'}",
        f"- semantic_focus: {_consult_semantic_focus(request) or '特になし'}",
        "- theme_detail_keys / current_status_key / goal_key は同じ表現でも意味の違いを分ける内部手がかりです。返答文にそのまま出さず、解釈の分岐にだけ使ってください。",
        "- latent_signals は表面文言の言い換えではなく、不安・痛点・境界線・修復意図の推定として使ってください。",
        f"- この相談で特に重視する観点: {_consult_case_style(request)}",
        f"- この相談の対立軸: {_consult_case_axis(request)}",
        "- summary の1文目で『誰が・何に・どう困っているか』を、このケースに即してはっきり書いてください。",
        "- partner_feeling_estimate は、相手が防御的なのか、傷ついたのか、距離を取りたいのかなどをこのケースに沿って自然に書いてください。",
        "- send_timing は短い自然な日本語で返してください。",
        "- send_timing_reason は一般論ではなく、このケースの地雷と空気を踏まえて具体的に書いてください。",
        "- best_reply は title と body を持つオブジェクトで返してください。body はそのまま送れる自然な日本語にしてください。",
        "- other_replies は title と body を持つオブジェクトの配列で2件返してください。best_reply とは少し方向性を変えてください。",
        "- heard_as_interpretations は2件、avoid_phrases は2件の自然な日本語配列で返してください。",
        "- next_actions は3件、pre_send_cautions は3件の自然な日本語配列で返してください。",
        "- chat_text や note が少なくても、選択情報だけでケース固有の出力にしてください。",
        "- 似たケースでも relation_type / theme / theme_details / current_status / goal の違いで答えを明確に変えてください。",
        "- 16type は補助的な仮説としてのみ使い、決めつけないでください。",
    ]

    return base + "\\n\\n" + "\\n".join(rules)


def build_precheck_prompt(request) -> str:
    return _request_to_prompt_lines(
        request,
        "以下は送信前チェック依頼です。json形式で、is_safe_to_send・risk_points・heard_as_interpretations・avoid_phrases・softened_message・revised_message_options・suggest_consult_mode を返してください。",
    )

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
                "You are a careful relationship compatibility analyst. ""Output valid JSON only. ""Be practical, kind, and grounded in the provided context. ""Use profile_context 16-type labels and short tendency notes as soft hints only; never stereotype or over-attribute. ""Prioritize actual relationship details, repeated patterns, and the user\'s described situation when they conflict."
            ),
            input=build_compatibility_prompt(request),
            text={"format": {"type": "json_object"}},
        )

        result_text = response.output_text
        result_json = parse_json_text(result_text)
        normalized = stabilize_compatibility_score(request, normalize_compatibility_result(result_json))

        return {"data": normalized}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAI compatibility error: {e}")


# === go-men consult reply composer bundle ===

def _gm_nonempty(*values: Any) -> str:
    for value in values:
        if value is None:
            continue
        if isinstance(value, str):
            s = value.strip()
        else:
            s = str(value).strip()
        if s:
            return s
    return ""


def _gm_relation(request) -> str:
    return _request_str_attr(request, "relation_type").lower()


def _gm_theme(request) -> str:
    return str(getattr(request, "theme", "") or "").strip()


def _gm_blob(request) -> str:
    parts = [
        getattr(request, "chat_text", ""),
        getattr(request, "note", ""),
        getattr(request, "recent_pattern_summary", ""),
        " ".join(getattr(request, "theme_details", []) or []),
        " ".join(getattr(request, "relation_detail_labels", []) or []),
        str(getattr(request, "goal", "") or ""),
        str(getattr(request, "current_status", "") or ""),
    ]
    return " ".join(str(part).strip() for part in parts if str(part).strip())


def _gm_has_repeat(request) -> bool:
    blob = _gm_blob(request)
    markers = ["前にも", "また", "何度か", "繰り返", "毎回", "いつも", "再び"]
    return any(marker in blob for marker in markers)


def _gm_set_primary_reply(normalized: dict, body: str, title: str = "おすすめ返信") -> dict:
    body = str(body or "").strip()
    if not body:
        return normalized

    reply_options = normalized.get("reply_options")
    if not isinstance(reply_options, list):
        reply_options = []
        normalized["reply_options"] = reply_options

    item = {"title": title, "body": body}

    if reply_options:
        if isinstance(reply_options[0], dict):
            merged = dict(reply_options[0])
            merged.update(item)
            reply_options[0] = merged
        else:
            reply_options[0] = item
    else:
        reply_options.append(item)

    if isinstance(normalized.get("best_reply"), dict):
        normalized["best_reply"]["title"] = title
        normalized["best_reply"]["body"] = body

    return normalized


def _gm_compose_couple_best_reply(request) -> Optional[str]:
    theme = _gm_theme(request)

    if theme == "連絡頻度":
        return "最近ちょっと連絡が少なくて不安になってた。責めたいわけじゃないから、落ち着いた時に今どんな感じか教えてもらえると嬉しい。"

    if theme == "お金":
        return "お金のこと、責めたいわけじゃなくて、曖昧なままだと負担感が偏りやすいから、次からは先に確認して、お互い納得できる形を決めたい。"

    if theme == "約束":
        if _gm_has_repeat(request):
            return "この前の約束のこと、少し引っかかってる。責めたいわけじゃなくて、どういう事情だったのか知りたいし、次からはどうするか一回ちゃんと話したい。"
        return "この前の約束のこと、少し引っかかってる。責めたいわけじゃないから、どういう事情だったのか知りたい。次から気まずくならない形を一回話したい。"

    return None


def _gm_compose_friend_best_reply(request) -> Optional[str]:
    theme = _gm_theme(request)

    if theme == "連絡頻度":
        return "最近ちょっと連絡のテンポが変わって気になってた。責めたいわけじゃないから、落ち着いた時に今どんな感じか教えてもらえると助かる。"

    if theme == "お金":
        return "立替やお金のこと、責めたいわけじゃないんだけど、曖昧なままだとお互い気まずくなりやすいから、一回整理したい。"

    if theme == "約束":
        return "この前の約束のこと、少し引っかかってた。責めたいわけじゃないから、どういう感じだったのか聞けると助かる。次から気まずくならない形にしたい。"

    return None


def _gm_compose_family_best_reply(request) -> Optional[str]:
    theme = _gm_theme(request)

    if theme == "言い方がきつい":
        return "さっきの言い方は少ししんどかった。責めたいわけじゃないけど、もう少し落ち着いて話せると助かる。"

    if theme == "お金":
        return "お金のこと、このまま曖昧だと自分の負担が偏る感じがして気になってる。責めたいわけじゃなくて、今後の分担を一度ちゃんと決めたい。"

    if theme == "約束":
        return "この前の約束のこと、少し引っかかってる。責めたいわけじゃなくて、事情は聞きたいし、次からどうするかは一回ちゃんと決めたい。"

    return None


def _gm_compose_inlaw_best_reply(request) -> Optional[str]:
    theme = _gm_theme(request)

    if theme == "行事・付き合い":
        return "いつも気にかけてくださってありがとうございます。毎回参加するのは少し難しいので、今後は都合を見ながら無理のない範囲で参加させていただけると助かります。参加できるときはぜひ伺いたいです。"

    return None


def _gm_compose_relation_best_reply(request) -> Optional[str]:
    relation = _gm_relation(request)
    labels = " ".join(getattr(request, "relation_detail_labels", []) or [])

    if relation.startswith("couple"):
        return _gm_compose_couple_best_reply(request)

    if relation.startswith("friend"):
        return _gm_compose_friend_best_reply(request)

    if relation.startswith("family") or relation == "parent_child":
        return _gm_compose_family_best_reply(request)

    if relation.startswith("inlaw") or "義" in labels:
        return _gm_compose_inlaw_best_reply(request)

    return None


def _gm_polish_relation_reply(request, body: str) -> str:
    body = " ".join(str(body or "").strip().split())
    if not body:
        return body

    while "。。" in body:
        body = body.replace("。。", "。")

    body = body.replace(
        "責めたいわけじゃないんだけど、責めたいわけじゃないんだけど、",
        "責めたいわけじゃないんだけど、",
    )
    body = body.replace(
        "責めたいわけじゃなくて、責めたいわけじゃなくて、",
        "責めたいわけじゃなくて、",
    )

    return body


def _gm_apply_consult_reply_composer(request, normalized: dict) -> dict:
    if not isinstance(normalized, dict):
        return normalized

    body = _gm_compose_relation_best_reply(request)

    if not body:
        reply_options = normalized.get("reply_options")
        if isinstance(reply_options, list) and reply_options and isinstance(reply_options[0], dict):
            body = _gm_nonempty(reply_options[0].get("body"))

    body = _gm_polish_relation_reply(request, body)
    if not body:
        return normalized

    relation = _gm_relation(request)
    title = "おすすめ返信"
    if relation.startswith("inlaw"):
        title = "やわらかく伝える"
    elif relation.startswith("family") or relation == "parent_child":
        title = "落ち着いて伝える"

    return _gm_set_primary_reply(normalized, body, title)

SAFETY_DESTINATION_CATALOG = {
    "police_emergency": {
        "key": "police_emergency",
        "name": "警察",
        "phone": "110",
        "reason": "今まさに危険・暴行・脅迫・監禁・待ち伏せなど差し迫った危険があるとき",
    },
    "ambulance_fire": {
        "key": "ambulance_fire",
        "name": "救急・消防",
        "phone": "119",
        "reason": "けが・急病・意識障害など身体の危険があるとき",
    },
    "police_consult": {
        "key": "police_consult",
        "name": "警察相談専用電話",
        "phone": "#9110",
        "reason": "緊急ではないが、安全面の不安、つきまとい、脅し、詐欺などを相談したいとき",
    },
    "dv_nav": {
        "key": "dv_nav",
        "name": "DV相談ナビ",
        "phone": "#8008",
        "reason": "配偶者・恋人・元交際相手などからの暴力や支配があるとき",
    },
    "sexual_center": {
        "key": "sexual_center",
        "name": "性犯罪・性暴力被害者のためのワンストップ支援センター",
        "phone": "#8891",
        "reason": "性暴力・性的強要・同意のない性的接触があるとき",
    },
    "sexual_police": {
        "key": "sexual_police",
        "name": "性犯罪被害相談電話",
        "phone": "#8103",
        "reason": "警察に性被害を相談したいとき",
    },
    "mental_health": {
        "key": "mental_health",
        "name": "こころの健康相談統一ダイヤル",
        "phone": "0570-064-556",
        "reason": "希死念慮、自傷、消えたい気持ち、強い追い詰められ感があるとき",
    },
    "child_abuse": {
        "key": "child_abuse",
        "name": "児童相談所虐待対応ダイヤル",
        "phone": "189",
        "reason": "子どもへの虐待・ネグレクト・強い安全懸念があるとき",
    },
    "child_rights": {
        "key": "child_rights",
        "name": "子どもの人権110番",
        "phone": "0120-007-110",
        "reason": "子どもへの人権侵害やいじめ・家庭内圧力を相談したいとき",
    },
    "consumer": {
        "key": "consumer",
        "name": "消費者ホットライン",
        "phone": "188",
        "reason": "契約トラブル、返金トラブル、悪質商法、詐欺まがいの勧誘があるとき",
    },
    "human_rights": {
        "key": "human_rights",
        "name": "みんなの人権110番",
        "phone": "0570-003-110",
        "reason": "中傷、脅し、差別、ハラスメントなど人権侵害全般を相談したいとき",
    },
}

def _s(v):
    if v is None:
        return ""
    if isinstance(v, str):
        return v.strip()
    if isinstance(v, dict):
        parts = []
        for k, val in v.items():
            sv = _s(val)
            if sv:
                parts.append(f"{k}: {sv}")
        return " / ".join(parts)
    if isinstance(v, (list, tuple, set)):
        parts = []
        for item in v:
            sv = _s(item)
            if sv:
                parts.append(sv)
        return " / ".join(parts)
    return str(v).strip()

def _arr(v):
    if v is None:
        return []
    if isinstance(v, list):
        return [x for x in (_s(i) for i in v) if x]
    s = _s(v)
    return [s] if s else []

def _b(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, str):
        return v.strip().lower() in {"true", "1", "yes", "y"}
    return bool(v)

def _has(text, words):
    return any(w in text for w in words)

def build_consult_safety(request, result_json):
    combined = "\n".join([
        _s(getattr(request, "relation_type", None)),
        _s(getattr(request, "relation_detail_labels", None)),
        _s(getattr(request, "theme", None)),
        _s(getattr(request, "theme_details", None)),
        _s(getattr(request, "current_status", None)),
        _s(getattr(request, "goal", None)),
        _s(getattr(request, "chat_text", None)),
        _s(getattr(request, "note", None)),
        _s(getattr(request, "recent_pattern_summary", None)),
        _s(result_json.get("situation_summary")),
        _s(result_json.get("partner_feeling_estimate")),
        _s(result_json.get("heard_as_interpretations")),
        _s(result_json.get("avoid_phrases")),
        _s(result_json.get("next_actions")),
        _s(result_json.get("pre_send_cautions")),
        _s(result_json.get("safety_observation")),
        _s(result_json.get("immediate_next_step")),
    ])

    flags = []

    def add_flag(flag):
        if flag not in flags:
            flags.append(flag)

    if _has(combined, ["殴", "蹴", "首を絞", "殺す", "死ね", "包丁", "刃物", "監禁", "閉じ込め", "今から行く", "待ち伏せ"]):
        add_flag("physical_violence_or_threat")
    if _has(combined, ["つきまと", "待ち伏せ", "位置情報", "GPS", "gps", "監視", "家の前", "職場の前"]):
        add_flag("stalking_or_monitoring")
    if _has(combined, ["DV", "dv", "モラハラ", "束縛", "支配", "怒鳴", "人格否定", "経済的DV", "経済的dv"]):
        add_flag("dv_or_coercive_control")
    if _has(combined, ["性行為を強要", "無理やり", "レイプ", "性暴力", "性被害", "同意なく", "裸の写真", "性的画像"]):
        add_flag("sexual_violence")
    if _has(combined, ["死にたい", "消えたい", "自殺", "リスカ", "OD", "od", "オーバードーズ", "いなくなりたい"]):
        add_flag("self_harm_or_suicidal_ideation")
    if _has(combined, ["虐待", "ネグレクト", "子どもが怖が", "子供が怖が", "未成年", "育児放棄", "児相"]):
        add_flag("child_abuse_or_child_safety")
    if _has(combined, ["いじめ", "学校に行けない", "不登校", "担任", "クラス", "部活"]):
        add_flag("school_distress")
    if _has(combined, ["詐欺", "送金", "投資", "副業", "返金されない", "契約トラブル", "解約できない", "違約金"]):
        add_flag("fraud_or_extortion")
    if _has(combined, ["脅し", "晒す", "さらす", "拡散する", "中傷", "セクハラ", "パワハラ", "差別"]):
        add_flag("harassment_or_rights_violation")

    for item in _arr(result_json.get("safety_flags")):
        normalized = item.strip().lower().replace("-", "_").replace(" ", "_")
        if normalized and normalized not in flags:
            flags.append(normalized)

    support = set()
    for item in _arr(result_json.get("support_recommendation_types")):
        key = item.strip().lower().replace("-", "_").replace(" ", "_")
        if key in {
            "police",
            "dv",
            "sexual_violence",
            "mental_health",
            "child_abuse",
            "consumer",
            "human_rights",
            "school",
            "none",
        }:
            support.add(key)

    if "physical_violence_or_threat" in flags:
        support.add("police")
    if "stalking_or_monitoring" in flags:
        support.add("police")
        support.add("human_rights")
    if "dv_or_coercive_control" in flags:
        support.add("dv")
    if "sexual_violence" in flags:
        support.add("sexual_violence")
        support.add("police")
    if "self_harm_or_suicidal_ideation" in flags:
        support.add("mental_health")
    if "child_abuse_or_child_safety" in flags:
        support.add("child_abuse")
    if "school_distress" in flags:
        support.add("school")
        support.add("human_rights")
    if "fraud_or_extortion" in flags:
        support.add("consumer")
        support.add("police")
    if "harassment_or_rights_violation" in flags:
        support.add("human_rights")

    emergency_now = _b(result_json.get("emergency_now")) or _has(
        combined,
        ["今すぐ逃げ", "今から行く", "待ち伏せ", "監禁", "閉じ込め", "首を絞", "殺す", "包丁", "刃物", "自殺する", "飛び降りる"]
    )

    ai_urgency = _s(result_json.get("safety_urgency")).lower()

    if emergency_now:
        risk_level = "emergency"
    elif (
        "physical_violence_or_threat" in flags
        or "sexual_violence" in flags
        or "self_harm_or_suicidal_ideation" in flags
        or "child_abuse_or_child_safety" in flags
    ):
        risk_level = "high"
    elif support.intersection({"police", "dv", "consumer", "human_rights", "school", "mental_health"}):
        risk_level = "medium"
    else:
        risk_level = "low"

    rank = {"low": 1, "medium": 2, "high": 3, "emergency": 4}
    if ai_urgency in rank and rank[ai_urgency] > rank[risk_level]:
        risk_level = ai_urgency

    destinations = []
    seen = set()

    def push(key):
        if key not in seen:
            destinations.append(SAFETY_DESTINATION_CATALOG[key])
            seen.add(key)

    if risk_level == "emergency":
        push("police_emergency")
        push("ambulance_fire")
    if "police" in support:
        push("police_consult")
    if "dv" in support:
        push("dv_nav")
    if "sexual_violence" in support:
        push("sexual_center")
        push("sexual_police")
    if "mental_health" in support:
        push("mental_health")
    if "child_abuse" in support:
        push("child_abuse")
        push("child_rights")
    if "consumer" in support:
        push("consumer")
    if "human_rights" in support:
        push("human_rights")

    safety_observation = _s(result_json.get("safety_observation"))
    if not safety_observation:
        if risk_level == "low":
            safety_observation = "現時点では直ちに緊急窓口が必要と断定できる情報は強くありません。"
        else:
            safety_observation = "相談内容の中に、安全確保や専門窓口の併用を検討したいサインが含まれる可能性があります。"

    immediate_next_step = _s(result_json.get("immediate_next_step"))
    if not immediate_next_step:
        if risk_level == "emergency":
            immediate_next_step = "返信文より先に、安全確保と緊急連絡を優先してください。"
        elif risk_level == "high":
            immediate_next_step = "今日中に専門窓口へつなぐ前提で動いてください。"
        elif risk_level == "medium":
            immediate_next_step = "通常の相談に加えて、必要な窓口を早めに併用してください。"
        else:
            immediate_next_step = "まず相談内容を整理し、不安が強まるなら専門窓口も使ってください。"

    if risk_level == "emergency":
        urgency_message = "今は返信文づくりより安全確保が最優先です。差し迫った危険やけががあるなら110または119を優先してください。"
    elif risk_level == "high":
        urgency_message = "通常の相談だけで抱えず、今日中の専門相談を強く検討する段階です。"
    elif risk_level == "medium":
        urgency_message = "通常の相談に加えて、早めに専門窓口を併用した方がよい可能性があります。"
    else:
        urgency_message = "現時点で緊急相談が必須とは限りませんが、不安が強いなら窓口利用は有効です。"

    support_sorted = [x for x in [
        "police",
        "dv",
        "sexual_violence",
        "mental_health",
        "child_abuse",
        "consumer",
        "human_rights",
        "school",
        "none",
    ] if x in support]
    if not support_sorted and risk_level == "low":
        support_sorted = ["none"]

    return {
        "risk_level": risk_level,
        "emergency_now": emergency_now,
        "safety_observation": safety_observation,
        "risk_flags": flags,
        "support_recommendation_types": support_sorted,
        "immediate_next_step": immediate_next_step,
        "urgency_message": urgency_message,
        "suggested_destinations": destinations,
        "show_support_destinations": len(destinations) > 0,
    }

def build_consult_response_input(request):
    prompt_text = (
        build_consult_input(request)
        + "\n\nスクリーンショットがある場合の追加ルール:\n"
          "- スクリーンショットは高優先度の事実として読むこと。\n"
          "- 上から順に読み、誰が何を言ったか、感情の温度、未返信点、繰り返しパターン、悪化トリガーを具体的に拾うこと。\n"
          "- 補足テキストが短くても、スクリーンショットが十分なら一般論で埋めないこと。\n"
          "- summary / partner_feeling_estimate / heard_as_interpretations / avoid_phrases / best_reply / other_replies / next_actions / pre_send_cautions に、スクリーンショットの具体情報を必ず反映すること。\n"
          "\nReturn valid json only."
    )

    content = [{"type": "input_text", "text": prompt_text}]

    for raw in (request.screenshots_base64 or [])[:10]:
        raw = str(raw).strip()
        if not raw:
            continue
        image_url = raw if raw.startswith("data:image") else f"data:image/png;base64,{raw}"
        content.append({"type": "input_image", "image_url": image_url})

    return [{"role": "user", "content": content}]


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
                "Always return these JSON keys: summary, partner_feeling_estimate, send_timing, send_timing_reason, best_reply, other_replies, heard_as_interpretations, avoid_phrases, next_actions, pre_send_cautions. "
                "best_reply must be an object with title and body. "
                "other_replies must be an array of exactly 2 objects with title and body. "
                "heard_as_interpretations and avoid_phrases must each be arrays of exactly 2 natural Japanese strings. "
                "next_actions and pre_send_cautions must each be arrays of exactly 3 natural Japanese strings. "
                "Prioritize concrete, copy-ready Japanese replies over generic advice. "
                "Avoid repetitive template-like wording across different cases. "
                "Treat screenshots as high-priority evidence when present. "
"Assess whether the case suggests immediate danger, coercive control, stalking, sexual violence, child safety concerns, self-harm risk, fraud/extortion, or harassment. "
"In the JSON output, also include: safety_observation (short string), safety_flags (array of short strings), support_recommendation_types (array chosen from police,dv,sexual_violence,mental_health,child_abuse,consumer,human_rights,school,none), emergency_now (boolean), safety_urgency (one of low, medium, high, emergency), and immediate_next_step (short string). "
"Do not overcall danger when evidence is weak, but do not miss it when evidence is concrete. "
                "Use relation details, profile context, recent patterns, note text, and screenshots together. "
                "When screenshots contain usable evidence, prefer them over generic inference. "
                "When profile_context contains standard or love 16-type labels and short tendency notes, treat them as soft communication hypotheses only. "
                "Do not stereotype. Use them only to adjust wording, pacing, reassurance, and repair style when consistent with the actual case."
            ),
            input=build_consult_response_input(request),
            text={"format": {"type": "json_object"}},
        )

        result_text = response.output_text
        result_json = parse_json_text(result_text)
        normalized = normalize_consult_result(result_json)
        normalized["safety"] = build_consult_safety(request, result_json)

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
                "You are a careful message precheck assistant. ""Output valid JSON only. ""Prioritize one best softened message and two concrete alternatives. Always return these JSON keys: is_safe_to_send, risk_points, heard_as_interpretations, avoid_phrases, softened_message, revised_message_options, suggest_consult_mode. ""Include heard_as_interpretations and avoid_phrases in the JSON. ""Keep the best message concise, usable, and natural. ""Avoid repetitive template-like wording across different cases. ""Use relation details, profile context, and recent patterns when available. ""When profile_context contains standard or love 16-type labels and short tendency notes, treat them as soft communication hypotheses only. ""Do not stereotype. Use them only to soften tone, choose pacing, and improve emotional safety when consistent with the actual case."
            ),
            input=[
                {
                    "role": "user",
                    "content": (
                        build_precheck_prompt(request)
                        + "\n\nReturn valid json only."
                    ),
                }
            ],
            text={"format": {"type": "json_object"}},
        )

        result_text = response.output_text
        result_json = parse_json_text(result_text)
        normalized = normalize_precheck_result(result_json)

        return {"data": normalized}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OpenAI precheck error: {e}")