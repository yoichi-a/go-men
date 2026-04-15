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

    subscores_raw = data.get("subscores")
    if not isinstance(subscores_raw, dict):
        subscores_raw = {}

    return {
        "score": clamp_score(data.get("score"), 72),
        "headline": str(data.get("headline") or "相性の土台はある一方で、すれ違い方に一定の傾向があります。"),
        "subscores": {
            "communication": clamp_score(subscores_raw.get("communication"), 74),
            "emotional_safety": clamp_score(subscores_raw.get("emotional_safety"), 68),
            "repair_ability": clamp_score(subscores_raw.get("repair_ability"), 76),
            "stability": clamp_score(subscores_raw.get("stability"), 64),
        },
        "strengths": _ensure_len(
            _to_string_list(data.get("strengths")),
            2,
            "強み",
        ),
        "risk_points": _ensure_len(
            _to_string_list(data.get("risk_points")),
            2,
            "注意点",
        ),
        "advice": _ensure_len(
            _to_string_list(data.get("advice")),
            3,
            "おすすめ",
        ),
        "next_action": str(
            data.get("next_action")
            or "結論を急がず、相手が受け取りやすい温度で一度だけ短く伝えるのがおすすめです。"
        ),
    }


def build_compatibility_prompt(request: CompatibilityRequest) -> str:
    relation_details = (
        " / ".join([item for item in request.relation_detail_labels if item.strip()])
        if request.relation_detail_labels
        else "なし"
    )

    profile_context = request.profile_context or "なし"
    recent_pattern_summary = request.recent_pattern_summary or "なし"
    optional_note = request.optional_note or "なし"

    return f"""
あなたは恋愛・家族・友人関係の会話傾向を整理する、慎重で実務的なAI分析アシスタントです。
役割は、相手との関係性を雑に決めつけることではなく、やり取りの傾向から「どこが噛み合いやすく、どこですれ違いやすいか」を整理することです。

必ず valid JSON only で出力してください。
JSON以外の文章は絶対に出さないでください。

出力形式:
{{
  "score": 0-100の整数,
  "headline": "一言の総評",
  "subscores": {{
    "communication": 0-100の整数,
    "emotional_safety": 0-100の整数,
    "repair_ability": 0-100の整数,
    "stability": 0-100の整数
  }},
  "strengths": ["強み1", "強み2"],
  "risk_points": ["注意点1", "注意点2"],
  "advice": ["実践案1", "実践案2", "実践案3"],
  "next_action": "次に取るべき一手"
}}

厳守ルール:
- 占いのように断定しない
- 「相性が悪いから無理」などの決めつけは禁止
- 入力内容に根拠を置く
- 強みも弱みも両方出す
- advice は抽象論ではなく、関係改善に使える短い実践案にする
- next_action は今日からできる一手にする
- headline は読みたくなるが軽すぎない文にする

入力:
relation_type: {request.relation_type}
relation_detail_labels: {relation_details}
profile_context:
{profile_context}

recent_pattern_summary:
{recent_pattern_summary}

optional_note:
{optional_note}
""".strip()


def build_consult_prompt(request: ConsultSessionRequest) -> str:
    relation_guide = {
        "couple": "恋人・パートナー間では、正しさよりも『大事にされている感覚』が重要。冷たさ、温度差、見捨てられ感、優先順位の低さとして聞こえないことを重視する。",
        "friend": "友人間では、重すぎる文、詰問、圧のある追撃は負担になりやすい。一方で、雑に扱われた感じや距離の取り方にも敏感。",
        "family": "家族間では、説教・支配・恩着せがましさ・上下感として聞こえないことが重要。近い関係だからこそ、雑さや決めつけが刺さりやすい。",
        "parent_child": "親子間では、説教・支配・恩着せがましさ・上下感として聞こえないことが重要。近い関係だからこそ、雑さや決めつけが刺さりやすい。",
    }.get(request.relation_type, "関係性に応じて、相手の尊重と悪化回避を優先する。")

    relation_detail_text = "、".join(request.relation_detail_labels) if request.relation_detail_labels else "特になし"

    theme_guide_map = {
        "連絡頻度": "『内容』よりも『大事にされていない感じ』『追われている感じ』が火種になりやすい。長文の追撃は悪化しやすい。",
        "言い方がきつい": "相手は事実関係よりも『責められた』『否定された』『見下された』感覚に反応している可能性が高い。",
        "約束": "相手は単なる予定変更ではなく、『軽く扱われた』『誠実さがなかった』と感じている可能性がある。",
        "嫉妬": "安心感の不足、比較された感覚、優先順位の不安が背景にある可能性が高い。説明より安心の回復を重視。",
        "お金": "正しさの押しつけや管理口調は避ける。境界線と敬意の両立が必要。",
        "家事": "作業量そのものより『見えていない』『感謝されていない』不満が火種になりやすい。",
        "距離感": "相手は近すぎる・重すぎる・冷たすぎるのどれかに反応している可能性がある。温度調整が重要。",
        "親の介入": "自分たち二人の問題として扱えていない感覚が不満になりやすい。防衛的な説明は逆効果。",
        "価値観の違い": "勝ち負けにすると悪化しやすい。違いの整理と歩み寄り可能性の見極めを優先。",
        "干渉・信頼": "監視・疑い・コントロールとして聞こえないことが重要。",
        "手伝い・役割分担": "不公平感と感謝不足が火種になりやすい。正論だけでは収まりにくい。",
        "人間関係・温度差": "相手は優先順位や距離感のズレに敏感。説明より、まず不安や違和感の受け止めが必要。",
        "その他": "表面上のテーマだけでなく、言い方・温度・受け取り方のズレを重視する。",
    }
    theme_guide = theme_guide_map.get(
        request.theme,
        "テーマに応じて、内容そのものより受け取り方のズレを重視する。",
    )

    emotion_guide_map = {
        "落ち着いている": "対話余地はある。短く自然なら送ってよい可能性がある。",
        "少ししんどい": "自己弁護が先に出やすい。短文でやわらかく整えるべき。",
        "かなり感情的": "長文・説明・反論は悪化しやすい。送るとしても短文。",
        "今送ると悪化しそう": "原則、待つ方向を強く検討。送るなら関係維持だけを目的にした短文。",
    }
    emotion_guide = emotion_guide_map.get(
        request.emotion_level,
        "感情の温度に応じて慎重に判断する。",
    )

    status_guide_map = {
        "相手が怒っている": "火消し優先。正しさの説明は後回し。",
        "自分が怒っている": "攻撃性や詰問が混ざりやすい。送る前に一段落とす。",
        "お互い感情的": "結論を急がず、まず悪化停止を優先。",
        "既読無視されている": "追撃長文は避ける。相手は距離を取りたい可能性。",
        "未読のまま": "今は相手都合を尊重。返答要求は避ける。",
        "会話が止まっている": "再開の一言は短く、圧をなくす。",
        "さっき電話で揉めた": "電話直後は感情が残りやすい。反論の追送信は危険。",
        "今から返信したい": "即返信したい気持ちと、実際に送っていいかは分けて判断する。",
    }
    status_guide = status_guide_map.get(
        request.current_status,
        "現在状態に応じて悪化回避を優先する。",
    )

    goal_guide_map = {
        "謝りたい": "謝罪は言い訳より先。『でも』を入れない。",
        "誤解を解きたい": "先に相手の嫌だった点を受け止め、その後で短く伝え直す。",
        "落ち着かせたい": "結論より沈静化。短く、圧なく。",
        "仲直りしたい": "関係維持の意思を見せつつ、相手に返答負担をかけすぎない。",
        "距離を置きたい": "拒絶でなく整理のためと伝える。冷たく切らない。",
        "相手の気持ちを知りたい": "問い詰めず、答えやすい聞き方にする。",
    }
    goal_guide = goal_guide_map.get(request.goal, "goal を反映した提案にする。")

    screenshot_note = (
        f"スクリーンショット: {len(request.screenshots_base64)}枚。読める範囲の具体語だけ使ってよい。読めない部分は絶対に補完しない。"
        if request.screenshots_base64
        else "スクリーンショット: なし。"
    )

    context_block = build_context_block(
        note=request.note,
        profile_context=request.profile_context,
        recent_pattern_summary=request.recent_pattern_summary,
    )

    return f"""
あなたは喧嘩やすれ違いの仲裁を支援するアプリ Go-men の分析エンジンです。
役割は、ユーザーの正しさを代弁することではなく、関係を壊しにくい次の一手を提案することです。

今回の出力では、分析コメントよりも「返信候補」を最重要視してください。
特に reply_options の1個目は、「この状況なら今いちばん送る価値がある完成文」として仕上げてください。

最優先事項:
1. 一番おすすめの返信を1つ、はっきり出す
2. そのまま送れる自然な文を作る
3. 相手にどう聞こえたかを具体的に示す
4. 今送るべきかを判定する
5. 他の2案は補助案として方向性を少し変える
6. 相手プロフィールや過去の相談傾向があれば、必ず反映する
7. relation_detail_labels があるなら、必ず関係性の温度感に反映する
8. スクリーンショットがあるなら、読める範囲の具体的要素を反映する

以下を必ず守ってください。
- 必ず JSON オブジェクトのみを返す
- JSON の外に説明文を書かない
- 日本語で返す
- 一般論ではなく、この入力に具体的に合わせる
- 「正しい反論」より「悪化しにくい伝え方」を優先する
- 相手の受け取り方は具体的に書く
- reply_options の body は、そのまま送信できる自然な文章にする
- reply_options の本文は短すぎないこと。原則 2〜4文で書く
- 1個目の返信文は 70〜170文字程度を目安にする
- ただし長すぎる説教文や弁明文にはしない
- 抽象的で無難すぎる表現を避ける
- ただし攻撃的、操作的、圧迫的な表現は使わない
- 既読無視・未読・会話停止では特に追撃感を避ける
- 感情が高い時は、説明より沈静化を優先する
- 相手プロフィールに「傷つきやすい言い方」「避けたいワード」「通りやすい伝え方」があれば、それを返信候補に反映する
- 過去相談の傾向があれば、同じ失敗を繰り返しにくい提案にする
- 1個目の返信文では、theme_details / chat_text / 補足情報 / relation_detail_labels / スクリーンショット のうち、少なくとも2要素を具体的に踏む
- 読めるスクリーンショットがある場合、そこから拾える具体語を1つまで使ってよい
- 読めない箇所は絶対に補完しない
- 1個目の返信文は、実在の人が送る自然さを優先し、AIっぽい説明口調にしない
- 1文目で、相手が嫌だった・しんどかったポイントを具体的に受け止める
- 2文目までに、自分側のまずさを短く引き取る
- 最後は、返事を急かさない一言か、低圧な次の一手で閉じる
- 「でも」「そんなつもりじゃない」「誤解だよ」「ちゃんと話したい」「わかってほしい」で締めるような一般化された文は禁止
- send_timing_recommendation が wait 系でも、reply_options[0] には「今送るならここまで」の最小限で自然な文を必ず出す

差別化ルール:
- 3つの reply_options は、同じ文の言い換えにしない
- reply_options[0] は「本命」
- reply_options[1] は「もう少し率直」
- reply_options[2] は「もう少しやわらかい」
- 3案とも書き出しを変える
- 毎回同じ定型句を使い回さない
- 特に「言い方がきつくなっていたらごめん」「軽く扱いたいわけじゃない」「ちゃんと受け止めたい」は必要な時だけ使う
- 入力に固有の具体語があるなら、1案目では必ず1つ以上入れる
- ただし引用のしすぎや不自然なコピペ口調は避ける

関係性ガイド:
{relation_guide}

関係性の詳細:
{relation_detail_text}

テーマガイド:
{theme_guide}

感情温度ガイド:
{emotion_guide}

現在状態ガイド:
{status_guide}

目的ガイド:
{goal_guide}

返す JSON の shape:
{{
  "session_id": "string",
  "safety_flag": false,
  "send_timing_recommendation": {{
    "code": "send_now_or_soften_first_or_wait_a_bit",
    "label": "string",
    "reason": "string"
  }},
  "situation_summary": "string",
  "partner_feeling_estimate": "string",
  "heard_as_interpretations": ["string", "string"],
  "avoid_phrases": ["string", "string"],
  "reply_options": [
    {{
      "type": "best_reply",
      "title": "まずこれがベスト",
      "body": "string"
    }},
    {{
      "type": "alternative_reply_1",
      "title": "もう少し率直に返すなら",
      "body": "string"
    }},
    {{
      "type": "alternative_reply_2",
      "title": "もう少しやわらかく返すなら",
      "body": "string"
    }}
  ],
  "next_actions": ["string", "string", "string"],
  "pre_send_cautions": ["string", "string", "string"]
}}

入力:
relation_type: {request.relation_type}
relation_detail_labels: {request.relation_detail_labels}
theme: {request.theme}
theme_details: {request.theme_details}
current_status: {request.current_status}
emotion_level: {request.emotion_level}
goal: {request.goal}
chat_text: {request.chat_text or ""}
{screenshot_note}
補足情報:
{context_block}
""".strip()



def build_precheck_prompt(request: PrecheckRequest) -> str:
    relation_guide = {
        "couple": "恋人同士では、責任追及より『大事にされているか』が重要。冷たさ、見捨てられ感、温度差に敏感。",
        "friend": "友人同士では、重すぎる文、詰問口調、圧のある追撃は負担になりやすい。",
        "family": "家族では、説教・支配・決めつけ・上下感として聞こえないことが重要。近い関係ほど雑な言い方が刺さりやすい。",
        "parent_child": "親子では、説教・支配・決めつけ・上下感として聞こえないことが重要。近い関係ほど雑な言い方が刺さりやすい。",
    }.get(request.relation_type, "関係性に応じて、圧迫感や責任追及の響きを避ける。")

    relation_detail_text = "、".join(request.relation_detail_labels) if request.relation_detail_labels else "特になし"

    context_block = build_context_block(
        optional_context_text=request.optional_context_text,
        profile_context=request.profile_context,
        recent_pattern_summary=request.recent_pattern_summary,
    )

    return f"""
あなたは喧嘩やすれ違いの仲裁を支援するアプリ Go-men の送信前チェックエンジンです。
役割は、下書きメッセージを「相手にどう聞こえるか」という観点から分析し、
悪化しにくい表現へ整えることです。

今回の出力では、分析コメントよりも「今そのまま送れる修正文」を最重要視してください。
特に softened_message は、一番おすすめの完成文として扱ってください。

最優先事項:
1. 今そのまま送って危険かを判定する
2. 一番おすすめの修正文を1つ、はっきり出す
3. そのほかの代案を2つ出す
4. 相手にどう響くかを具体的に示す
5. 相手プロフィールや過去相談傾向があれば、必ず反映する
6. relation_detail_labels があるなら、文の温度感に反映する

必ず守ること:
- 必ず JSON オブジェクトのみを返す
- 日本語で返す
- 一般論ではなく、この文面に具体的に反応する
- 自己弁護、責任転嫁、詰問、急かし、皮肉、圧、見下しに敏感であること
- 改善案はそのまま送れる自然な文章にする
- softened_message は短すぎないこと。原則 2〜3文
- softened_message は 60〜140文字程度を目安にする
- revised_message_options も短すぎないこと。原則 2〜4文
- ただし、相談モードよりは少し短くする
- 一番おすすめの文は「すぐ使える」ことを優先する
- 「ごめん」だけ、「そんなつもりじゃない」だけ、のような浅い文は禁止
- draft_message の核心の意図はできるだけ残しつつ、刺さる部分だけを落とす
- 1文目で、相手がしんどく感じそうな点を受け止めるか、圧を下げる
- 2文目までに、自分側のまずさ・急かし・強さを整える
- 最後は返事を強要しない形で閉じる
- 相手プロフィールに「傷つきやすい言い方」「避けたいワード」「通りやすい伝え方」があれば、それを修正文に反映する
- 過去相談の傾向があれば、同じ悪化パターンを避ける
- 新しい論点を増やしすぎず、今ある文面を実戦向けに整える
- relation_detail_labels と補足情報がある場合は、読み取れる範囲で具体性に使う
- 毎回同じ定型句を使い回さない
- 特に「言い方が強くなっていたらごめん」「ちゃんと伝わる形で話したい」は必要な時だけ使う

差別化ルール:
- softened_message は最もバランスの良い1案
- revised_message_options[1] は「もう少し率直」
- revised_message_options[2] は「もう少しやわらかい」
- 3案とも書き出しを変える
- 3案を単なる語尾違いにしない
- draft_message に固有の論点があるなら、必ず1つ以上残す

関係性ガイド:
{relation_guide}

関係性の詳細:
{relation_detail_text}

返す JSON の shape:
{{
  "precheck_id": "string",
  "safety_flag": false,
  "is_safe_to_send": {{
    "code": "safe_or_soften_recommended_or_wait_recommended",
    "label": "string",
    "reason": "string"
  }},
  "risk_points": ["string", "string"],
  "softened_message": "string",
  "revised_message_options": ["string", "string", "string"],
  "suggest_consult_mode": true
}}

追加ルール:
- risk_points は必ず2個以上
- revised_message_options は必ず3個
- softened_message は最もバランスの良い1案
- softened_message は 2〜3文で、短く使いやすく、でも浅くしない
- revised_message_options[0] は softened_message と同じ内容でよい
- revised_message_options[1] は「もう少し率直」
- revised_message_options[2] は「もう少しやわらかい」
- risk_points は「相手にどう聞こえるか」を短く鋭く書く
- is_safe_to_send.reason は短く、実務的に書く
- draft_message の具体的な問題点を必ず反映する
- 今回の補足、相手プロフィール、過去相談の傾向があるなら必ず反映する
- 「でも」「誤解してる」「そんなつもりじゃない」「なんで無視するの」で締める文にしない
- 相手に返答義務を強く感じさせる締めは避ける

入力:
relation_type: {request.relation_type}
relation_detail_labels: {request.relation_detail_labels}
draft_message: {request.draft_message}
補足情報:
{context_block}
""".strip()



def build_consult_input(request: ConsultSessionRequest) -> List[dict[str, Any]]:
    content: List[dict[str, Any]] = [
        {
            "type": "input_text",
            "text": build_consult_prompt(request),
        }
    ]

    for image_base64 in request.screenshots_base64[:3]:
        cleaned = image_base64.strip()
        if not cleaned:
            continue

        content.append(
            {
                "type": "input_image",
                "image_url": f"data:image/png;base64,{cleaned}",
                "detail": "auto",
            }
        )

    return [{"role": "user", "content": content}]


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