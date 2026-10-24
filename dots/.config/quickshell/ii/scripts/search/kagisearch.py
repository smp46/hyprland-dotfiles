#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse
from urllib.parse import urlparse

def get_kagi_suggestions(query):
    encoded = urllib.parse.quote(query)
    url = f"https://kagi.com/api/autosuggest?q={encoded}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"}
    )
    try:
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if len(data) > 1 and isinstance(data[1], list):
                results = []
                for s in data[1]:
                    if s.strip():
                        search_url = f"https://kagi.com/search?q={urllib.parse.quote(s)}"
                        results.append({
                            "title": s,
                            "url": search_url,
                            "snippet": "",
                            "domain": "kagi.com",
                            "type": "suggestion"
                        })
                return results
    except Exception:
        pass
    return []

def get_kagi_api_results(query, token):
    encoded = urllib.parse.quote(query)
    url = f"https://kagi.com/api/v1/search?q={encoded}&limit=6"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bot {token}",
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            items = data.get("data", [])
            results = []
            for item in items:
                title = item.get("title", "")
                link = item.get("url", "")
                snippet = item.get("snippet", "")
                if title and link:
                    domain = urlparse(link).netloc or "kagi.com"
                    results.append({
                        "title": title,
                        "url": link,
                        "snippet": snippet,
                        "domain": domain,
                        "type": "result"
                    })
            if results:
                return results
    except Exception:
        pass
    return []

def main():
    if len(sys.argv) < 2:
        print("[]")
        return
    query = sys.argv[1].strip()
    if not query:
        print("[]")
        return

    token = sys.argv[2].strip() if len(sys.argv) >= 3 else ""

    results = []
    if token:
        results = get_kagi_api_results(query, token)

    # If no token or no results from API, fetch Kagi suggestions
    if not results:
        results = get_kagi_suggestions(query)

    print(json.dumps(results))

if __name__ == "__main__":
    main()
