#!/usr/bin/env python3
"""App Store Connect helper for Notchman's iPhone subscriptions.

  python3 scripts/asc.py status   # the app's Apple ID, subscription groups, products, prices, readiness
  python3 scripts/asc.py setup    # creates what's missing (group, Pro / Pro+ monthly, names, prices, availability)
  python3 scripts/asc.py review-screenshot [png]   # the paywall screenshot App Review needs (docs/screenshots/paywall.png)
  python3 scripts/asc.py builds   # the latest TestFlight builds, whether they're installable, tester groups
  python3 scripts/asc.py readiness   # everything App Review needs, and what's still missing
  python3 scripts/asc.py listing   # applies design/store/listing.json, Free price, availability, newest build
  python3 scripts/asc.py store-screenshots   # uploads docs/store/*.png (scripts/store_screenshots.py)
  python3 scripts/asc.py declarations   # age rating (all "none": 4+) and content rights

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


def builds():
    """The latest TestFlight builds, whether they can be installed, and the tester groups."""
    app = find_app()
    data = call("GET", "/v1/builds", query={"filter[app]": app["id"], "sort": "-uploadedDate", "limit": 5,
                                            "include": "preReleaseVersion,buildBetaDetail"})
    included = {(i["type"], i["id"]): i["attributes"] for i in data.get("included", [])}
    print("Latest builds (newest first):")
    for build in data.get("data", []):
        a, rel = build["attributes"], build["relationships"]
        version = included.get(("preReleaseVersions", (rel["preReleaseVersion"].get("data") or {}).get("id")), {}).get("version", "?")
        beta = included.get(("buildBetaDetails", (rel["buildBetaDetail"].get("data") or {}).get("id")), {})
        print(f"  - {version} ({a.get('version')}) uploaded {a.get('uploadedDate', '')[:16]} | processing {a.get('processingState')} | "
              f"internal testing {beta.get('internalBuildState')} | external {beta.get('externalBuildState')}"
              f"{' | EXPIRED' if a.get('expired') else ''}")
    print("\nTester groups:")
    groups = all_pages(f"/v1/apps/{app['id']}/betaGroups", {"limit": 50})
    for group in groups:
        g = group["attributes"]
        testers = call("GET", f"/v1/betaGroups/{group['id']}/betaTesters", query={"limit": 1}).get("meta", {}).get("paging", {}).get("total", 0)
        link = f" | public link {g.get('publicLink')}" if g.get("publicLinkEnabled") else ""
        print(f"  - {g.get('name')}: {'internal' if g.get('isInternalGroup') else 'external'} | {testers} testers | "
              f"{'gets every build' if g.get('hasAccessToAllBuilds') else 'only builds added to it'}{link}")
    if not groups:
        print("  none: App Store Connect → TestFlight → Internal Testing → + to add yourself")


def try_call(label, fn):
    try:
        return fn()
    except RuntimeError as error:
        print(f"  {label}: couldn't read ({error})")
        return None


def readiness():
    """Everything App Review needs, and what's still missing."""
    app = find_app()
    a = app["attributes"]
    print(f"App: {a.get('name')} ({BUNDLE_ID}), Apple ID {app['id']}, primary language {a.get('primaryLocale')}")
    print(f"Content rights declared: {a.get('contentRightsDeclaration') or 'NOT ANSWERED'}")

    infos = try_call("app info", lambda: call("GET", f"/v1/apps/{app['id']}/appInfos",
                                               query={"include": "primaryCategory,secondaryCategory"})) or {}
    for info in infos.get("data", []):
        ia, rel = info["attributes"], info["relationships"]
        print(f"\nApp info ({ia.get('state') or ia.get('appStoreState')}): age rating {ia.get('appStoreAgeRating') or 'NOT SET'}")
        print(f"  categories: {(rel['primaryCategory'].get('data') or {}).get('id', 'NOT SET')} / "
              f"{(rel['secondaryCategory'].get('data') or {}).get('id', 'none')}")
        for loc in (try_call("names", lambda: call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")) or {}).get("data", []):
            la = loc["attributes"]
            print(f"  {la.get('locale')}: name '{la.get('name')}' | subtitle '{la.get('subtitle') or ''}' | "
                  f"privacy policy {la.get('privacyPolicyUrl') or 'MISSING'}")
        rating = (try_call("age rating", lambda: call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")) or {}).get("data")
        if rating:
            answered = {k: v for k, v in rating["attributes"].items() if v not in (None, "NONE", False)}
            unanswered = [k for k, v in rating["attributes"].items() if v is None]
            print(f"  age rating answers that aren't 'none': {answered or 'none'}")
            print(f"  age rating questions not answered: {', '.join(unanswered) or 'none'}")

    versions = (try_call("versions", lambda: call("GET", f"/v1/apps/{app['id']}/appStoreVersions",
                                                  query={"filter[platform]": "IOS", "limit": 5})) or {}).get("data", [])
    if not versions:
        print("\nApp Store versions: none yet (create version 1.0 in App Store Connect, or run 'listing')")
    for version in versions:
        va = version["attributes"]
        print(f"\nVersion {va.get('versionString')}: {va.get('appStoreState') or va.get('appVersionState')} | "
              f"copyright '{va.get('copyright') or 'MISSING'}' | release {va.get('releaseType')}")
        build = (try_call("build", lambda: call("GET", f"/v1/appStoreVersions/{version['id']}/build")) or {}).get("data")
        print(f"  build attached: {build['attributes']['version'] if build else 'NONE'}")
        for loc in (try_call("listing", lambda: call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")) or {}).get("data", []):
            la = loc["attributes"]
            print(f"  {la.get('locale')}: description {len(la.get('description') or '')} chars | keywords "
                  f"{len(la.get('keywords') or '')}/100 | promo {len(la.get('promotionalText') or '')}/170 | "
                  f"support {la.get('supportUrl') or 'MISSING'} | marketing {la.get('marketingUrl') or '-'}")
            sets = (try_call("screenshots", lambda: call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
                                                          query={"include": "appScreenshots"})) or {}).get("data", [])
            for shot_set in sets:
                count = len(shot_set["relationships"]["appScreenshots"].get("data") or [])
                print(f"    screenshots {shot_set['attributes']['screenshotDisplayType']}: {count}")
            if not sets:
                print("    screenshots: NONE")
        review = (try_call("review details", lambda: call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")) or {}).get("data")
        if review:
            ra = review["attributes"]
            print(f"  review contact: {ra.get('contactFirstName') or '?'} {ra.get('contactLastName') or '?'} | "
                  f"{ra.get('contactEmail') or 'NO EMAIL'} | {'phone set' if ra.get('contactPhone') else 'NO PHONE'} | "
                  f"notes {len(ra.get('notes') or '')} chars")
        else:
            print("  review contact and notes: MISSING")

    price = try_call("price", lambda: call("GET", f"/v1/apps/{app['id']}/appPriceSchedule",
                                           query={"include": "manualPrices,baseTerritory"}))
    if price is not None:
        print(f"\nPrice schedule: {'set' if price.get('data') else 'NOT SET (choose Free)'}"
              f" ({len([i for i in price.get('included', []) if i['type'] == 'appPrices'])} price entries)")
    availability = try_call("availability", lambda: call("GET", f"/v1/apps/{app['id']}/appAvailabilityV2"))
    if availability is not None:
        print(f"Availability: {'set' if availability.get('data') else 'NOT SET'}")
    print("\nNot readable through the API (check in App Store Connect): App Privacy answers, Paid Apps Agreement, tax and banking.")


def editable_version(app):
    """The version being prepared (created as 1.0 if there's none)."""
    versions = call("GET", f"/v1/apps/{app['id']}/appStoreVersions", query={"filter[platform]": "IOS", "limit": 10})["data"]
    editable = [v for v in versions if (v["attributes"].get("appStoreState") or "") in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    if editable:
        return editable[0]
    return call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": "1.0"},
        "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]


def step(label, fn):
    try:
        fn()
        print(f"  ✓ {label}")
    except RuntimeError as error:
        print(f"  ✗ {label}: {error}")


def listing(path="design/store/listing.json"):
    """Applies design/store/listing.json: name, subtitle, keywords, description,
    URLs, categories, copyright, review notes, free price, availability and the
    newest build. Nothing is submitted for review."""
    data = json.load(open(path))
    app = find_app()
    info = call("GET", f"/v1/apps/{app['id']}/appInfos")["data"][0]
    version = editable_version(app)
    vid = version["id"]
    print(f"Version {version['attributes']['versionString']} ({version['attributes'].get('appStoreState')})")

    def app_info_localization():
        locs = call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]
        attrs = {"name": data["name"], "subtitle": data["subtitle"], "privacyPolicyUrl": data["privacyPolicyUrl"]}
        loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if loc:
            call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
        else:
            call("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": {"locale": "en-US", **attrs},
                                                               "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
    step(f"name '{data['name']}', subtitle '{data['subtitle']}', privacy policy link", app_info_localization)

    step(f"categories {data['primaryCategory']} / {data['secondaryCategory']}", lambda: call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {
        "type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": data["primaryCategory"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": data["secondaryCategory"]}}}}}))

    def version_localization():
        locs = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
        attrs = {k: data[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
        loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if loc:
            call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
        else:
            call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": "en-US", **attrs},
                                                                        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    step(f"description ({len(data['description'])} chars), keywords ({len(data['keywords'])}/100), promotional text, support and marketing links",
         version_localization)

    step(f"copyright '{data['copyright']}'", lambda: call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {
        "type": "appStoreVersions", "id": vid, "attributes": {"copyright": data["copyright"]}}}))

    def review_detail():
        contact = data["reviewContact"]
        attrs = {"contactFirstName": contact["firstName"], "contactLastName": contact["lastName"],
                 "contactEmail": contact["email"], "demoAccountRequired": False, "notes": data["reviewNotes"]}
        existing = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
        if existing:
            call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {"data": {"type": "appStoreReviewDetails", "id": existing["id"], "attributes": attrs}})
        else:
            call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                                                               "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    step("App Review contact (name, email) and notes; the phone number is yours to add", review_detail)

    def free_price():
        points = call("GET", f"/v1/apps/{app['id']}/appPricePoints", query={"filter[territory]": "USA", "limit": 200})["data"]
        free = next(p for p in points if float(p["attributes"].get("customerPrice") or 0) == 0)
        call("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": {"data": {"type": "apps", "id": app["id"]}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    step("price: Free", free_price)

    def availability():
        territories = all_pages("/v1/territories", {"limit": 200})
        call("POST", "/v2/appAvailabilities", {
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}},
                                       "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": f"${{{t['id']}}}"} for t in territories]}}},
            "included": [{"type": "territoryAvailabilities", "id": f"${{{t['id']}}}",
                          "attributes": {"available": True, "releaseDate": None, "preOrderEnabled": False},
                          "relationships": {"territory": {"data": {"type": "territories", "id": t["id"]}}}} for t in territories]})
    step("available in every country", availability)

    def attach_build():
        builds = call("GET", "/v1/builds", query={"filter[app]": app["id"], "filter[processingState]": "VALID",
                                                  "filter[preReleaseVersion.version]": version["attributes"]["versionString"],
                                                  "sort": "-uploadedDate", "limit": 1})["data"]
        if not builds:
            raise RuntimeError(f"no processed build for version {version['attributes']['versionString']}")
        call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": builds[0]["id"]}})
        print(f"    build {builds[0]['attributes']['version']}")
    step("newest build attached", attach_build)
    print()
    readiness()


def store_screenshots(folder="docs/store/main"):
    """Replaces the version's 6.9-inch iPhone screenshots with docs/store/main/*.png."""
    import hashlib
    files = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
    if not files:
        sys.exit(f"No screenshots in {folder} (run scripts/store_screenshots.py)")
    app = find_app()
    version = editable_version(app)
    locs = call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    loc = next(l for l in locs if l["attributes"]["locale"] == "en-US")
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    shot_set = None
    for display in ("APP_IPHONE_69", "APP_IPHONE_67"):
        shot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display), None)
        if shot_set:
            break
        try:
            shot_set = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                                                                    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
            break
        except RuntimeError as error:
            print(f"{display}: {error}")
    print(f"Screenshot set: {shot_set['attributes']['screenshotDisplayType']}")
    for old in call("GET", f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")["data"]:
        call("DELETE", f"/v1/appScreenshots/{old['id']}")
    for name in files:
        data = open(os.path.join(folder, name), "rb").read()
        reserved = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(data)},
                                                              "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": shot_set["id"]}}}}})["data"]
        for part in reserved["attributes"]["uploadOperations"]:
            request = urllib.request.Request(part["url"], method=part["method"], data=data[part["offset"]:part["offset"] + part["length"]],
                                             headers={h["name"]: h["value"] for h in part.get("requestHeaders", [])})
            urllib.request.urlopen(request, timeout=120).read()
        call("PATCH", f"/v1/appScreenshots/{reserved['id']}", {"data": {"type": "appScreenshots", "id": reserved["id"],
                                                                         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(f"  uploaded {name}")
    time.sleep(20)
    for shot in call("GET", f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")["data"]:
        state = shot["attributes"].get("assetDeliveryState") or {}
        print(f"  {shot['attributes'].get('fileName')}: {state.get('state')} {state.get('errors') or ''}")


def declarations():
    """Age rating (nothing objectionable: 4+) and content rights (it opens
    third-party pages the person links to, and has the rights to do so)."""
    import re
    app = find_app()
    step("content rights: uses third-party content, with the rights to it", lambda: call("PATCH", f"/v1/apps/{app['id']}", {"data": {
        "type": "apps", "id": app["id"], "attributes": {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}}))
    info = call("GET", f"/v1/apps/{app['id']}/appInfos")["data"][0]
    rating = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    # Every question answered "none"/"no". Apple's API mixes yes/no questions
    # (booleans) and frequency questions ("NONE"…); a wrong guess is reported
    # by name, so flip it and retry. Optional fields (Korea, kids band) stay empty.
    skip = {"kidsAgeBand", "gracRatingClassificationNumber", "developerAgeRatingInfoUrl", "ageRatingOverride",
            "ageRatingOverrideV2", "koreaAgeRatingOverride"}
    booleans = {"advertising", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat", "parentalControls",
                "ageAssurance", "socialMedia", "socialMediaAgeRestricted", "unrestrictedWebAccess", "userGeneratedContent",
                "seventeenPlus"}
    answers = {k: (False if k in booleans else "NONE") for k, v in rating["attributes"].items() if v is None and k not in skip}
    for _ in range(12):
        try:
            call("PATCH", f"/v1/ageRatingDeclarations/{rating['id']}", {"data": {
                "type": "ageRatingDeclarations", "id": rating["id"], "attributes": answers}})
            print(f"  ✓ age rating: {len(answers)} questions answered 'none' / 'no'")
            break
        except RuntimeError as error:
            named = [k for k in answers if re.search(rf"\b{re.escape(k)}\b", str(error))]
            if not named:
                print(f"  ✗ age rating: {error}")
                break
            for key in named:
                if "not allowed" in str(error) or "cannot be" in str(error):
                    answers.pop(key)
                else:
                    answers[key] = "NONE" if isinstance(answers[key], bool) else False
    print()
    readiness()


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
    {"status": status, "setup": setup, "review-screenshot": review_screenshot, "builds": builds,
     "readiness": readiness, "listing": listing, "store-screenshots": store_screenshots,
     "declarations": declarations}[command](*sys.argv[2:])
