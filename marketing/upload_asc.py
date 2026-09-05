#!/usr/bin/env python3
"""Upload the composed screenshots + listing copy to App Store Connect.

Screenshot upload is a four-step dance, not a POST: reserve an asset (ASC replies with the exact
HTTP operations to perform), PUT the bytes to those URLs, commit with an MD5 checksum, then poll
until ASC's own delivery state says COMPLETE. Anything less and the asset silently sits in
UPLOAD_INCOMPLETE and never appears on the product page.

Nothing here submits the app for review. It only fills in the version's assets and text, which is
reversible in the ASC UI.

Usage:
  python3 marketing/upload_asc.py --dry-run          # show what would change
  python3 marketing/upload_asc.py --text             # push subtitle/description/keywords/promo
  python3 marketing/upload_asc.py --shots iphone     # upload the 6.9" set (replaces existing)
  python3 marketing/upload_asc.py --shots ipad       # upload the 13" set
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

import jwt


def _required(name: str, what: str) -> str:
    """Read a required App Store Connect setting, or explain exactly how to supply it.

    These used to be literals. That made the file one account's config rather than tooling —
    a fork could not run it, and the anonymity scrub had already replaced the key path with a
    `<operator>` placeholder that no longer resolved, so the script was broken in place. Names
    match `scripts/asc_assign_build.py`, which has always read its credentials this way.
    """
    value = os.environ.get(name)
    if not value:
        sys.exit(f"{name} is not set — {what}. See docs/ops/testflight.md.")
    return value


KEY_ID = _required("ASC_AUTH_KEY_ID", "the App Store Connect API key id")
ISSUER = _required("ASC_AUTH_ISSUER_ID", "the issuer id from the API Keys page")
APP_ID = _required("ASC_APP_ID", "the numeric app id from the app's App Store Connect URL")
# Same convention as asc_assign_build.py; override for a key kept elsewhere.
P8 = pathlib.Path(
    os.environ.get(
        "ASC_AUTH_KEY_PATH",
        os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"),
    )
)
BASE = "https://api.appstoreconnect.apple.com"
ROOT = pathlib.Path(__file__).resolve().parent

# The display-type wells, PROBED against the live API rather than taken from the docs: the enum
# accepts APP_IPHONE_{35,40,47,55,58,61,65,67} and APP_IPAD_{97,105,PRO_129,PRO_3GEN_11,
# PRO_3GEN_129}. There is no APP_IPHONE_69 and no 13" iPad value — the API's names lag Apple's
# marketing tiers, and the newer sizes post into these wells. See compose.py for the size choice.
DISPLAY_TYPE = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129",
                "watch": "APP_WATCH_SERIES_10"}


def token() -> str:
    return jwt.encode({"iss": ISSUER, "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"},
                      P8.read_text(), algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def api(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    req = urllib.request.Request(
        BASE + path if path.startswith("/") else path, method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
        data=json.dumps(body).encode() if body else None)
    try:
        r = urllib.request.urlopen(req)
        raw = r.read()
        return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:400]}


def editable_version() -> str:
    """The version row we're allowed to edit (never one that's in review)."""
    st, body = api("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=10")
    if st >= 300:
        sys.exit(f"cannot list versions: {body}")
    for v in body["data"]:
        state = v["attributes"].get("appStoreState") or v["attributes"].get("appVersionState")
        if state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                     "METADATA_REJECTED", "INVALID_BINARY"):
            return v["id"]
    sys.exit("no editable version — is one in review? refusing to touch it")


def localization(version_id: str, locale: str = "en-US") -> str:
    st, body = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    for l in body.get("data", []):
        if l["attributes"]["locale"] == locale:
            return l["id"]
    sys.exit(f"no {locale} localization on version {version_id}")


def parse_metadata() -> dict[str, str]:
    """Pull the indented code blocks out of METADATA.md — that file is the single source of
    truth for the copy, so the listing can never drift from what was reviewed."""
    out, head, cur = {}, None, []
    for ln in (ROOT / "METADATA.md").read_text().split("\n"):
        if ln.startswith("## "):
            if head and cur:
                out[head] = "\n".join(cur).strip("\n")
            head, cur = ln[3:].split(" (")[0].strip(), []
        elif ln.startswith("    ") and head is not None:
            cur.append(ln[4:])
        elif head and cur and not ln.strip():
            cur.append("")
    if head and cur:
        out[head] = "\n".join(cur).strip("\n")
    return {k: re.sub(r"\n+$", "", v).strip("\n") for k, v in out.items()}


def app_info_localization(locale: str = "en-US") -> str:
    """The App-Info localization — where `name` and `subtitle` live.

    They are NOT attributes of appStoreVersionLocalizations (the API rejects them there with
    ENTITY_ERROR.ATTRIBUTE.UNKNOWN): name/subtitle are app-level and shared across versions,
    while description/keywords/promotionalText belong to the version being edited.
    """
    st, body = api("GET", f"/v1/apps/{APP_ID}/appInfos")
    if st >= 300 or not body.get("data"):
        sys.exit(f"cannot read appInfos: {body}")
    # Prefer the editable App Info row (the one not already live).
    infos = body["data"]
    chosen = next((i for i in infos
                   if (i["attributes"].get("appStoreState") or i["attributes"].get("state"))
                   not in ("READY_FOR_SALE",)), infos[0])
    st, body = api("GET", f"/v1/appInfos/{chosen['id']}/appInfoLocalizations")
    for l in body.get("data", []):
        if l["attributes"]["locale"] == locale:
            return l["id"]
    sys.exit(f"no {locale} appInfoLocalization")


def push_text(dry: bool) -> None:
    meta = parse_metadata()
    version_attrs = {
        "description": meta["Description"],
        "keywords": meta["Keywords"],
        "promotionalText": meta["Promotional text"],
    }
    info_attrs = {"subtitle": meta["Subtitle"]}
    for k, v in {**info_attrs, **version_attrs}.items():
        print(f"  {k}: {len(v)} chars — {v.splitlines()[0][:64]}…")
    if dry:
        print("  (dry run — nothing sent)")
        return

    loc = localization(editable_version())
    st, body = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc}",
                   {"data": {"type": "appStoreVersionLocalizations", "id": loc,
                             "attributes": version_attrs}})
    print("  version text ->", st, "OK" if st < 300 else body)

    info_loc = app_info_localization()
    st, body = api("PATCH", f"/v1/appInfoLocalizations/{info_loc}",
                   {"data": {"type": "appInfoLocalizations", "id": info_loc,
                             "attributes": info_attrs}})
    print("  subtitle ->", st, "OK" if st < 300 else body)


def screenshot_set(loc_id: str, display_type: str) -> str:
    st, body = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    for s in body.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    st, body = api("POST", "/v1/appScreenshotSets",
                   {"data": {"type": "appScreenshotSets",
                             "attributes": {"screenshotDisplayType": display_type},
                             "relationships": {"appStoreVersionLocalization": {
                                 "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
    if st >= 300:
        sys.exit(f"cannot create screenshot set: {body}")
    return body["data"]["id"]


def upload_one(set_id: str, path: pathlib.Path) -> bool:
    data = path.read_bytes()
    st, body = api("POST", "/v1/appScreenshots",
                   {"data": {"type": "appScreenshots",
                             "attributes": {"fileSize": len(data), "fileName": path.name},
                             "relationships": {"appScreenshotSet": {
                                 "data": {"type": "appScreenshotSets", "id": set_id}}}}})
    if st >= 300:
        print(f"    reserve failed: {body}")
        return False
    shot_id = body["data"]["id"]

    # ASC dictates the exact PUTs (it may chunk); follow them literally.
    for op in body["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=chunk)
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        try:
            urllib.request.urlopen(req)
        except urllib.error.HTTPError as e:
            print(f"    PUT failed: {e.code} {e.read()[:120]}")
            return False

    st, body = api("PATCH", f"/v1/appScreenshots/{shot_id}",
                   {"data": {"type": "appScreenshots", "id": shot_id,
                             "attributes": {"uploaded": True,
                                            "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    if st >= 300:
        print(f"    commit failed: {body}")
        return False

    # The commit returning 200 does NOT mean Apple accepted the asset — poll its delivery state.
    for _ in range(20):
        st, body = api("GET", f"/v1/appScreenshots/{shot_id}")
        state = (body.get("data", {}).get("attributes", {}).get("assetDeliveryState") or {})
        if state.get("state") == "COMPLETE":
            return True
        if state.get("errors"):
            print(f"    ASC rejected: {state['errors']}")
            return False
        time.sleep(3)
    print("    timed out waiting for COMPLETE")
    return False


def push_shots(kind: str, dry: bool) -> None:
    src = "raw/watch" if kind == "watch" else f"out/{kind}"
    files = sorted((ROOT / src).glob("*.png"))
    if not files:
        sys.exit(f"no PNGs in {src}")
    print(f"  {len(files)} images for {DISPLAY_TYPE[kind]}: {', '.join(f.name for f in files)}")
    if dry:
        print("  (dry run — nothing sent)")
        return
    loc = localization(editable_version())
    set_id = screenshot_set(loc, DISPLAY_TYPE[kind])

    # Replace rather than append, so re-running can't leave a stale mix on the page.
    st, body = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=20")
    for old in body.get("data", []):
        api("DELETE", f"/v1/appScreenshots/{old['id']}")

    for f in files:
        ok = upload_one(set_id, f)
        print(f"    {f.name}: {'COMPLETE' if ok else 'FAILED'}")


# --- Listing plumbing: URLs, category, age rating -----------------------------

#: The publisher's own WHOIS-private domain. NOT the app server's hostname: that host sits on a
#: domain fronting unrelated private infrastructure, and every one of these URLs is public — the
#: App Store shows them to anyone. Keep in step with ios/.../BillingConfig.swift.
SITE = "https://legitimateapps.com"
URLS = {"privacy": f"{SITE}/privacy", "support": f"{SITE}/support", "marketing": f"{SITE}/command"}


def push_urls(dry: bool) -> None:
    for k, v in URLS.items():
        print(f"  {k:<9} -> {v}")
    if dry:
        print("  (dry run — nothing sent)")
        return
    loc = localization(editable_version())
    st, body = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc}",
                   {"data": {"type": "appStoreVersionLocalizations", "id": loc,
                             "attributes": {"supportUrl": URLS["support"],
                                            "marketingUrl": URLS["marketing"]}}})
    print("  support+marketing ->", st, "OK" if st < 300 else body)

    info_loc = app_info_localization()
    st, body = api("PATCH", f"/v1/appInfoLocalizations/{info_loc}",
                   {"data": {"type": "appInfoLocalizations", "id": info_loc,
                             "attributes": {"privacyPolicyUrl": URLS["privacy"]}}})
    print("  privacyPolicyUrl  ->", st, "OK" if st < 300 else body)


def app_info_id() -> str:
    st, body = api("GET", f"/v1/apps/{APP_ID}/appInfos")
    infos = body["data"]
    chosen = next((i for i in infos
                   if (i["attributes"].get("appStoreState") or i["attributes"].get("state"))
                   not in ("READY_FOR_SALE",)), infos[0])
    return str(chosen["id"])


def push_category(dry: bool) -> None:
    print("  primaryCategory -> PRODUCTIVITY")
    if dry:
        print("  (dry run — nothing sent)")
        return
    info = app_info_id()
    st, body = api("PATCH", f"/v1/appInfos/{info}",
                   {"data": {"type": "appInfos", "id": info,
                             "relationships": {"primaryCategory": {
                                 "data": {"type": "appCategories", "id": "PRODUCTIVITY"}}}}})
    print("  ->", st, "OK" if st < 300 else body)


def push_age_rating(dry: bool) -> None:
    """The age-rating declaration. This is a statement to Apple about what the app contains, so
    every answer below is the true one for a planner, not the convenient one.

    Field types were PROBED against the live API (it rejects a wrong type with the expected one
    named): nine are BOOLEAN, the rest are enums taking NONE / INFREQUENT_OR_MILD /
    FREQUENT_OR_INTENSE. Sending "NONE" for a boolean 409s.

    The two answers worth defending:
      * `messagingAndChat` = False. Command's assistant is a chat with a model, not with a person.
        There is no user-to-user messaging: accounts are strictly isolated (one account cannot read
        another's data — see the server's per-account scoping tests), and "delegating" writes an
        assignment into your own account. Nobody receives a message from anybody.
      * `userGeneratedContent` = False. The question is about user content OTHER USERS can see —
        a feed, comments, profiles. Command has no shared surface of any kind. What you write is
        visible to you alone.
    Both would be True for an app with a social surface. Command has none. If that ever changes,
    this declaration must change with it.
    """
    booleans = {
        "advertising": False,             # no ad SDKs, in this or any of our apps
        "ageAssurance": False,            # we do not perform age assurance
        "gambling": False,
        "healthOrWellnessTopics": False,  # a planner; it does not give health guidance
        "lootBox": False,
        "messagingAndChat": False,        # see docstring
        "parentalControls": False,        # the app offers no parental-control feature
        "unrestrictedWebAccess": False,   # no in-app browser; the agent's URL fetch is SSRF-guarded
        "userGeneratedContent": False,    # see docstring
    }
    enums = {k: "NONE" for k in (
        "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated",
        "gunsOrOtherWeapons", "horrorOrFearThemes", "matureOrSuggestiveThemes",
        "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
        "sexualContentGraphicAndNudity", "sexualContentOrNudity",
        "violenceCartoonOrFantasy", "violenceRealistic",
        "violenceRealisticProlongedGraphicOrSadistic",
    )}
    decl = {**booleans, **enums}
    print(f"  {len(booleans)} booleans all False, {len(enums)} content enums all NONE")
    if dry:
        print("  (dry run — nothing sent)")
        return
    info = app_info_id()
    st, body = api("GET", f"/v1/appInfos/{info}/ageRatingDeclaration")
    decl_id = body.get("data", {}).get("id")
    if not decl_id:
        print("  no ageRatingDeclaration on this appInfo:", body)
        return
    st, body = api("PATCH", f"/v1/ageRatingDeclarations/{decl_id}",
                   {"data": {"type": "ageRatingDeclarations", "id": decl_id, "attributes": decl}})
    print("  ->", st, "OK" if st < 300 else body)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--text", action="store_true")
    ap.add_argument("--shots", choices=["iphone", "ipad", "watch"])
    ap.add_argument("--urls", action="store_true", help="privacy/support/marketing URLs")
    ap.add_argument("--category", action="store_true")
    ap.add_argument("--age", action="store_true", help="age-rating declaration")
    a = ap.parse_args()
    if not (a.text or a.shots or a.urls or a.category or a.age):
        ap.error("nothing to do")
    if a.text:
        print("TEXT:")
        push_text(a.dry_run)
    if a.shots:
        print(f"SCREENSHOTS ({a.shots}):")
        push_shots(a.shots, a.dry_run)
    if a.urls:
        print("URLS:")
        push_urls(a.dry_run)
    if a.category:
        print("CATEGORY:")
        push_category(a.dry_run)
    if a.age:
        print("AGE RATING:")
        push_age_rating(a.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
