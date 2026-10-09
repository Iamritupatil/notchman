#!/usr/bin/env python3
"""App Store Connect helper for Notchman's iPhone subscriptions.

  python3 scripts/asc.py status   # the app's Apple ID, subscription groups, products, prices, readiness
  python3 scripts/asc.py setup    # creates what's missing (group, Pro / Pro+ monthly, names, prices, availability)
  python3 scripts/asc.py review-screenshot [png]   # the paywall screenshot App Review needs (docs/screenshots/paywall.png)

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (the App Store Connect API key
used for TestFlight) and optionally APP_BUNDLE_ID (default app.notchman).
Run from GitHub: Actions → App Store.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT (with cryptography)

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("APP_BUNDLE_ID") or "app.notchman"
GROUP_NAME = "Notchman Premium"

# What the app sells (PremiumStore.swift, server/src/plans.ts, the website).
PRODUCTS = [
    {
        "productId": "com.notchman.pro.monthly", "name": "Notchman Pro", "level": 2, "usd": "4.99",
        "description": "25,000 characters a month in the natural voice",
    },
    {
        "productId": "com.notchman.proplus.monthly", "name": "Notchman Pro+", "level": 1, "usd": "9.99",
        "description": "60,000 characters a month in the natural voice",
    },
]


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors) or detail
        except ValueError:
            pass
        raise RuntimeError(f"{method} {path} → {error.code}: {detail[:600]}") from None


def all_pages(path, query=None):
    items, data = [], call("GET", path, query=query)
    items += data.get("data", [])
    while data.get("links", {}).get("next"):
        nxt = urllib.parse.urlparse(data["links"]["next"])
        data = call("GET", nxt.path, query=dict(urllib.parse.parse_qsl(nxt.query)))
        items += data.get("data", [])
    return items


def find_app():
    apps = call("GET", "/v1/apps", query={"filter[bundleId]": BUNDLE_ID}).get("data", [])
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID} in App Store Connect.")
    return apps[0]


def groups_of(app_id):
    return all_pages(f"/v1/apps/{app_id}/subscriptionGroups", {"include": "subscriptions", "limit": 50})


def subscriptions_of(group_id):
    return all_pages(f"/v1/subscriptionGroups/{group_id}/subscriptions", {"limit": 50})


def usd_price(sub_id):
    prices = call("GET", f"/v1/subscriptions/{sub_id}/prices",
                  query={"filter[territory]": "USA", "include": "subscriptionPricePoint", "limit": 5})
    points = {p["id"]: p for p in prices.get("included", []) if p["type"] == "subscriptionPricePoints"}
    for price in prices.get("data", []):
        point = points.get(price["relationships"]["subscriptionPricePoint"]["data"]["id"])
        if point:
            return point["attributes"].get("customerPrice")
    return None


def explain_missing(sub_id, localizations, screenshot):
    """What App Store Connect still counts as missing for one subscription."""
    for loc in localizations:
        la = loc["attributes"]
        print(f"      name {la.get('locale')}: '{la.get('name')}' / '{la.get('description')}' ({len(la.get('description') or '')} chars) | {la.get('state')}")
    if screenshot:
        delivery = screenshot["attributes"].get("assetDeliveryState") or {}
        print(f"      review screenshot: {delivery.get('state')} {delivery.get('errors') or ''}")
    prices = call("GET", f"/v1/subscriptions/{sub_id}/prices", query={"limit": 1})
    print(f"      prices set in {prices.get('meta', {}).get('paging', {}).get('total', '?')} countries")
    try:
        availability = call("GET", f"/v1/subscriptions/{sub_id}/subscriptionAvailability").get("data")
        territories = call("GET", f"/v1/subscriptionAvailabilities/{availability['id']}/availableTerritories",
                           query={"limit": 1}) if availability else {}
        print(f"      available in {territories.get('meta', {}).get('paging', {}).get('total', 0)} countries")
    except RuntimeError as error:
        print(f"      availability: {error}")


def status():
    app = find_app()
    print(f"App: {app['attributes']['name']} ({BUNDLE_ID})")
    print(f"Apple ID (APPLE_APP_ID for the server): {app['id']}")
    groups = groups_of(app["id"])
    if not groups:
        print("Subscription groups: none yet (run setup)")
    for group in groups:
        print(f"\nGroup: {group['attributes'].get('referenceName')} (id {group['id']})")
        for sub in subscriptions_of(group["id"]):
            a = sub["attributes"]
            localizations = call("GET", f"/v1/subscriptions/{sub['id']}/subscriptionLocalizations").get("data", [])
            screenshot = call("GET", f"/v1/subscriptions/{sub['id']}/appStoreReviewScreenshot").get("data")
            print(f"  - {a.get('productId')}: {a.get('name')} | state {a.get('state')} | period {a.get('subscriptionPeriod')} | "
                  f"US price {usd_price(sub['id']) or 'not set'} | names {len(localizations)} | review screenshot {'yes' if screenshot else 'no'}")
            if a.get("state") == "MISSING_METADATA":
                explain_missing(sub["id"], localizations, screenshot)
        names = call("GET", f"/v1/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations").get("data", [])
        print(f"  Group display names: {', '.join(n['attributes'].get('locale', '?') + ' ' + str(n['attributes'].get('state')) for n in names) or 'none (needed)'}")
    wanted = {p["productId"] for p in PRODUCTS}
    have = {s["attributes"]["productId"] for g in groups for s in subscriptions_of(g["id"])}
    missing = sorted(wanted - have)
    print(f"\nMissing products: {', '.join(missing) if missing else 'none'}")


def setup():
    app = find_app()
    groups = groups_of(app["id"])
    group = next((g for g in groups if g["attributes"].get("referenceName") == GROUP_NAME), groups[0] if groups else None)
    if not group:
        group = call("POST", "/v1/subscriptionGroups", {"data": {
            "type": "subscriptionGroups", "attributes": {"referenceName": GROUP_NAME},
            "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
        print(f"Created group {GROUP_NAME}")
    if not call("GET", f"/v1/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations").get("data"):
        call("POST", "/v1/subscriptionGroupLocalizations", {"data": {
            "type": "subscriptionGroupLocalizations", "attributes": {"locale": "en-US", "name": "Notchman Premium"},
            "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group["id"]}}}}})
        print("Added the group's display name")

    existing = {s["attributes"]["productId"]: s for s in subscriptions_of(group["id"])}
    for product in PRODUCTS:
        sub = existing.get(product["productId"])
        if not sub:
            sub = call("POST", "/v1/subscriptions", {"data": {
                "type": "subscriptions",
                "attributes": {"productId": product["productId"], "name": product["name"], "subscriptionPeriod": "ONE_MONTH",
                               "groupLevel": product["level"], "familySharable": False},
                "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group["id"]}}}}})["data"]
            print(f"Created {product['productId']}")
        sid = sub["id"]
        if not call("GET", f"/v1/subscriptions/{sid}/subscriptionLocalizations").get("data"):
            call("POST", "/v1/subscriptionLocalizations", {"data": {
                "type": "subscriptionLocalizations",
                "attributes": {"locale": "en-US", "name": product["name"], "description": product["description"]},
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}}}})
            print(f"  {product['productId']}: added name and description")
        try:
            call("POST", "/v1/subscriptionAvailabilities", {"data": {
                "type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sid}},
                    "availableTerritories": {"data": [{"type": "territories", "id": t["id"]} for t in all_pages("/v1/territories", {"limit": 200})]},
                }}})
            print(f"  {product['productId']}: available in every country")
        except RuntimeError as error:
            print(f"  {product['productId']}: availability not changed ({error})")
        if usd_price(sid):
            print(f"  {product['productId']}: price already set (US {usd_price(sid)})")
            continue
        points = all_pages(f"/v1/subscriptions/{sid}/pricePoints", {"filter[territory]": "USA", "limit": 200})
        point = next((p for p in points if p["attributes"].get("customerPrice") == product["usd"]), None)
        if not point:
            print(f"  {product['productId']}: no US price point at ${product['usd']}")
            continue
        # Apple's equivalent of $X in every other country (it keeps them updated for exchange rates).
        equal = all_pages(f"/v1/subscriptionPricePoints/{point['id']}/equalizations", {"limit": 200, "include": "territory"})
        for p in [point] + equal:
            territory = p["relationships"]["territory"]["data"]["id"] if "relationships" in p and "territory" in p["relationships"] else None
            body = {"data": {"type": "subscriptionPrices", "attributes": {"preserveCurrentPrice": False},
                             "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}},
                                               "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": p["id"]}}}}}
            if territory:
                body["data"]["relationships"]["territory"] = {"data": {"type": "territories", "id": territory}}
            try:
                call("POST", "/v1/subscriptionPrices", body)
            except RuntimeError as error:
                print(f"    price for {territory or 'USA'} not set: {error}")
        print(f"  {product['productId']}: price ${product['usd']} (and the equivalent in {len(equal)} other countries)")
    print()
    status()


def review_screenshot(path="docs/screenshots/paywall.png"):
    """Uploads the paywall screenshot as each subscription's App Review screenshot."""
    import hashlib
    data = open(path, "rb").read()
    app = find_app()
    for group in groups_of(app["id"]):
        for sub in subscriptions_of(group["id"]):
            product = sub["attributes"]["productId"]
            if call("GET", f"/v1/subscriptions/{sub['id']}/appStoreReviewScreenshot").get("data"):
                print(f"{product}: review screenshot already there")
                continue
            reserved = call("POST", "/v1/subscriptionAppStoreReviewScreenshots", {"data": {
                "type": "subscriptionAppStoreReviewScreenshots",
                "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
                "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub["id"]}}}}})["data"]
            for part in reserved["attributes"]["uploadOperations"]:
                chunk = data[part["offset"]:part["offset"] + part["length"]]
                request = urllib.request.Request(part["url"], method=part["method"], data=chunk,
                                                 headers={h["name"]: h["value"] for h in part.get("requestHeaders", [])})
                urllib.request.urlopen(request, timeout=120).read()
            call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{reserved['id']}", {"data": {
                "type": "subscriptionAppStoreReviewScreenshots", "id": reserved["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            print(f"{product}: review screenshot uploaded")
    print()
    status()


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    {"status": status, "setup": setup, "review-screenshot": review_screenshot}[command](*sys.argv[2:])
