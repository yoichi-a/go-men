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


def _consult_case_style(request) -> str:
    relation = str(getattr(request, "relation_type", "")).strip()
    theme = str(getattr(request, "theme", "")).strip()
    current_status = str(getattr(request, "current_status", "")).strip()
    emotion_level = str(getattr(request, "emotion_level", "")).strip()
    goal = str(getattr(request, "goal", "")).strip()

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

    if goal == "距離を置きたい":
        notes.append("仲直りの演出より、角が立ちにくい境界線設定を優先してください。")
    elif goal == "今は送らず整理したい":
        notes.append("送らない判断も積極的に提案してください。")
    elif goal in {"謝りたい", "仲直りしたい"}:
        notes.append("自己弁護より、受け止めと安心感を優先してください。")

    return " ".join(notes)


def build_consult_input(request) -> str:
    base = _request_to_prompt_lines(
        request,
        "以下は相談内容です。json形式で返してください。",
    )

    rules = [
        "[consult_output_rules]",
        "- relation_type / relation_detail_labels / theme / theme_details / current_status / emotion_level / goal を主な判断材料にしてください。",
        "- chat_text が短い場合や空欄の場合でも、選択された情報から具体的にケースを読み分けてください。",
        f"- この相談で特に重視する観点: {_consult_case_style(request)}",
        "- summary はこのケース特有の状況整理を1〜2文で書いてください。",
        "- partner_feeling_estimate は相手がどう受け取ったかを、このケースに即して自然な日本語で書いてください。",
        "- send_timing は短い自然な日本語で返してください。",
        "- send_timing_reason は、このケースでなぜその判断になるのかを具体的に書いてください。",
        "- best_reply は title と body を持つオブジェクトで返してください。",
        "- other_replies は title と body を持つオブジェクトの配列で、2件返してください。",
        "- heard_as_interpretations は2件、avoid_phrases は2件の自然な日本語配列で返してください。",
        "- next_actions は3件、pre_send_cautions は3件の自然な日本語配列で返してください。",
        "- 似たケースでも relation_type や goal が違えば、答えも明確に変えてください。",
        "- 16type は補助的な仮説としてのみ使い、決めつけないでください。",
    ]

    return base + "\n\n" + "\n".join(rules)


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
                "Do not collapse different cases into the same answer. "
                "The selected relation, theme, theme details, current status, emotion level, and goal must materially change the output. "
                "Use relation details, profile context, recent patterns, and readable screenshot cues when available. "
                "When profile_context contains standard or love 16-type labels and short tendency notes, treat them as soft communication hypotheses only. "
                "Do not stereotype. Use them only to adjust wording, pacing, reassurance, and repair style when consistent with the actual case."
            ),
            input=[
                {
                    "role": "user",
                    "content": (
                        build_consult_input(request)
                        + "\n\nReturn valid json only."
                    ),
                }
            ],
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