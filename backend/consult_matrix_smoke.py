import json
import urllib.error
import urllib.request

URL = "http://127.0.0.1:8000/consult/sessions"

cases = [
    (
        "COUPLE / 連絡頻度",
        {
            "relation_type": "couple",
            "relation_detail_labels": ["恋人"],
            "theme": "連絡頻度",
            "theme_details": [],
            "current_status": "少しこじれている",
            "emotion_level": "少し感情的",
            "goal": "気持ちを確認したい",
            "chat_text": "最近返信が遅くて、既読はつくのに返ってこないことが増えて不安。",
            "note": "追撃して少し気まずい",
            "recent_pattern_summary": "ここ2週間くらい返信が遅い",
            "upload_ids": [],
        },
    ),
    (
        "COUPLE / お金",
        {
            "relation_type": "couple",
            "relation_detail_labels": ["恋人"],
            "theme": "お金",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "すり合わせたい",
            "chat_text": "最近、自分の方が多く払ってる気がして引っかかってる。",
            "note": "金額より当然みたいになってる感じが嫌",
            "recent_pattern_summary": "前にも似たモヤモヤがあった",
            "upload_ids": [],
        },
    ),
    (
        "FRIEND / 連絡頻度",
        {
            "relation_type": "friend",
            "relation_detail_labels": ["友達"],
            "theme": "連絡頻度",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "状況を知りたい",
            "chat_text": "最近、こっちから送らないと続かない感じがして気になってる。",
            "note": "切りたいわけではない",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
    (
        "FRIEND / お金",
        {
            "relation_type": "friend",
            "relation_detail_labels": ["友達"],
            "theme": "お金",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "整理したい",
            "chat_text": "立替が続いてるけど、精算の話を出しづらい。",
            "note": "細かいと思われたくない",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
    (
        "FAMILY / 言い方がきつい",
        {
            "relation_type": "family",
            "relation_detail_labels": ["家族"],
            "theme": "言い方がきつい",
            "theme_details": [],
            "current_status": "少しこじれている",
            "emotion_level": "少し感情的",
            "goal": "落ち着いて話したい",
            "chat_text": "さっきも強い言い方をされてしんどかった。",
            "note": "毎回傷つく",
            "recent_pattern_summary": "前にも似たことがあった",
            "upload_ids": [],
        },
    ),
    (
        "FAMILY / お金",
        {
            "relation_type": "family",
            "relation_detail_labels": ["家族"],
            "theme": "お金",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "今後ははっきりさせたい",
            "chat_text": "家族だからで流されて、自分の負担が増えている。",
            "note": "曖昧なまま続くのがつらい",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
    (
        "INLAW / 行事・付き合い",
        {
            "relation_type": "inlaw",
            "relation_detail_labels": ["義家族"],
            "theme": "行事・付き合い",
            "theme_details": [],
            "current_status": "断りづらい",
            "emotion_level": "少し感情的",
            "goal": "角を立てずに調整したい",
            "chat_text": "毎回の行事参加がしんどいけど、強くは言いたくない。",
            "note": "義母には悪気はない",
            "recent_pattern_summary": "参加頻度が多い",
            "upload_ids": [],
        },
    ),
    (
        "COUPLE / 約束",
        {
            "relation_type": "couple",
            "relation_detail_labels": ["恋人"],
            "theme": "約束",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "わかってほしい",
            "chat_text": "前にも約束してたのに、また守ってもらえなかったのが引っかかってる。",
            "note": "繰り返しがあるので不信感がある",
            "recent_pattern_summary": "前にも似たことがあった",
            "upload_ids": [],
        },
    ),
    (
        "FRIEND / 約束",
        {
            "relation_type": "friend",
            "relation_detail_labels": ["友達"],
            "theme": "約束",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "納得したい",
            "chat_text": "約束してたのに直前で変わって、ちょっとモヤモヤしてる。",
            "note": "怒ってはいるが切りたくはない",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
    (
        "FAMILY / 約束",
        {
            "relation_type": "family",
            "relation_detail_labels": ["家族"],
            "theme": "約束",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "今後ははっきりさせたい",
            "chat_text": "約束の時間をまた守ってもらえなくて困ってる。",
            "note": "家族だから流されやすい",
            "recent_pattern_summary": "何度か似たことがあった",
            "upload_ids": [],
        },
    ),
]



EXTRA_CASES_MISSING_BRANCHES = [
    (
        "COUPLE / 嫉妬",
        {
            "relation_type": "couple",
            "relation_detail_labels": ["恋人"],
            "theme": "嫉妬",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "落ち着いて伝えたい",
            "chat_text": "その人の話が続くと、正直ちょっとモヤモヤする。",
            "note": "束縛したいわけではないが不安になる",
            "recent_pattern_summary": "前にも似たことで引っかかった",
            "upload_ids": [],
        },
    ),
    (
        "COUPLE / 言い方がきつい",
        {
            "relation_type": "couple",
            "relation_detail_labels": ["恋人"],
            "theme": "言い方がきつい",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "落ち着いて話したい",
            "chat_text": "さっきの言い方、ちょっときつく感じて引っかかってる。",
            "note": "言い返したくなるが悪化は避けたい",
            "recent_pattern_summary": "前にも似たやり取りがあった",
            "upload_ids": [],
        },
    ),
    (
        "COUPLE / 距離感",
        {
            "relation_type": "couple",
            "relation_detail_labels": ["恋人"],
            "theme": "距離感",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "ちょうどいい距離感を見つけたい",
            "chat_text": "最近ちょっと距離が近すぎる感じがして、少ししんどい。",
            "note": "嫌いではないが一人の時間もほしい",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
    (
        "FAMILY / パートナー経由の伝わり方",
        {
            "relation_type": "family",
            "relation_detail_labels": ["家族"],
            "theme": "パートナー経由の伝わり方",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "角を立てずに整理したい",
            "chat_text": "私に直接じゃなくて、パートナー経由で言われるのがちょっとしんどい。",
            "note": "誤解も生まれやすいので直接話してほしい",
            "recent_pattern_summary": "前にも似た伝わり方があった",
            "upload_ids": [],
        },
    ),
    (
        "FAMILY / 行事・付き合い",
        {
            "relation_type": "family",
            "relation_detail_labels": ["家族"],
            "theme": "行事・付き合い",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "無理のない関わり方にしたい",
            "chat_text": "行事のたびに毎回参加前提なのが少し負担に感じてる。",
            "note": "関係は悪くしたくないが頻度は調整したい",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
    (
        "FRIEND / 人間関係・温度差",
        {
            "relation_type": "friend",
            "relation_detail_labels": ["友達"],
            "theme": "人間関係・温度差",
            "theme_details": [],
            "current_status": "少し気まずい",
            "emotion_level": "少し感情的",
            "goal": "関係を壊さず整理したい",
            "chat_text": "私は仲いいと思ってたけど、相手との温度差がある気がして少しモヤモヤする。",
            "note": "切りたいわけではないが距離感を知りたい",
            "recent_pattern_summary": "",
            "upload_ids": [],
        },
    ),
]

cases.extend(EXTRA_CASES_MISSING_BRANCHES)

def post(payload):
    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


for label, payload in cases:
    print("\n" + "=" * 100)
    print(label)
    try:
        obj = post(payload)
        d = obj["data"]
        print("- send_timing:", d["send_timing_recommendation"]["code"], "/", d["send_timing_recommendation"]["label"])
        print("- summary:", d["situation_summary"])
        print("- partner:", d["partner_feeling_estimate"])
        print("- best_reply:", d["reply_options"][0]["body"])
        print("- caution1:", d["pre_send_cautions"][0])
    except urllib.error.HTTPError as e:
        print("HTTP ERROR:", e.code)
        print(e.read().decode("utf-8"))
    except Exception as e:
        print("ERROR:", repr(e))
