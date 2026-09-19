#!/usr/bin/env python3
"""B站视频搜索：给 agent 提供"主动找视频"的能力。

用法:
    python bili_search.py "展锐 刷机 解锁" --limit 5
    python bili_search.py "KernelSU 模块" --json

输出：默认打印紧凑文本（给模型看），--json 打印结构化 JSON。
只读公开搜索接口；失败时打印明确错误并以非 0 退出。
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request

UA = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                   "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
    "Referer": "https://www.bilibili.com/",
    "Accept": "application/json, text/plain, */*",
}

TAG_RE = re.compile(r"<[^>]+>")


def _clean_title(title: str) -> str:
    """搜索结果标题里带 <em class="keyword"> 高亮标签，去掉。"""
    return html.unescape(TAG_RE.sub("", title or "")).strip()


def _get(url: str, timeout: int = 20):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def search_wbi(keyword: str, limit: int):
    """公开搜索接口（search/type）。B站偶发 412，交给调用方重试。"""
    url = ("https://api.bilibili.com/x/web-interface/wbi/search/type?"
           + urllib.parse.urlencode({"search_type": "video", "keyword": keyword, "page": 1}))
    d = _get(url)
    if d.get("code") != 0:
        raise RuntimeError(f"接口返回 code={d.get('code')} message={d.get('message')}")
    out = []
    for it in ((d.get("data") or {}).get("result") or [])[:limit]:
        bvid = it.get("bvid") or ""
        if not bvid:
            continue
        pub = it.get("pubdate")
        out.append({
            "bvid": bvid,
            "title": _clean_title(it.get("title")),
            "url": f"https://www.bilibili.com/video/{bvid}/",
            "author": it.get("author"),
            "duration": it.get("duration"),
            "play": it.get("play"),
            "danmaku": it.get("video_review"),
            "published": time.strftime("%Y-%m-%d", time.localtime(pub)) if pub else None,
            "description": (it.get("description") or "")[:200],
        })
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keyword")
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--retries", type=int, default=3)
    args = ap.parse_args()

    last = None
    results = []
    for i in range(max(1, args.retries)):
        try:
            results = search_wbi(args.keyword, args.limit)
            if results:
                break
            last = RuntimeError("接口返回 0 条结果")
        except Exception as e:  # 412 / 网络抖动都可能，重试
            last = e
            results = []
        time.sleep(0.8 + i * 0.7)

    if not results:
        print(f"搜索失败或无结果: {last}", file=sys.stderr)
        if args.json:
            print(json.dumps({"query": args.keyword, "results": [], "error": str(last)},
                             ensure_ascii=False))
        sys.exit(1)

    if args.json:
        print(json.dumps({"query": args.keyword, "results": results}, ensure_ascii=False, indent=1))
        return

    total_play = sum(r.get("play") or 0 for r in results)
    print(f'B站视频搜索: "{args.keyword}"（{len(results)} 条，按相关度；总播放 {total_play:,}）')
    for i, r in enumerate(results, 1):
        print(f"{i}. [{r['title']}]({r['url']})")
        print(f"   UP: {r.get('author')} | 时长: {r.get('duration')} | "
              f"播放: {r.get('play')} | 发布: {r.get('published')}")
        if r.get("description"):
            print(f"   简介: {r['description']}")


if __name__ == "__main__":
    main()
