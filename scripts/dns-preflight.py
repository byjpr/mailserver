"""Refuse to create DNS records in Cloudflare next to conflicting ones.

Cloudflare accepts several records with the same name and type. A second SPF
record makes SPF fail with "permerror", an old MX record splits incoming
mail, and two DMARC/MTA-STS records invalidate the policy. This checks every
name we manage against what already exists in the zone and lists conflicts
that are not ours (not in the Terraform state).

    dns-preflight.py <desired-records.json> <managed-ids.json>

Reads CLOUDFLARE_API_TOKEN. Exit status 1 on conflicts.
"""

import json
import os
import sys
import urllib.parse
import urllib.request

API = os.environ.get("CLOUDFLARE_API_BASE", "https://api.cloudflare.com/client/v4")
TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN", "")

# A record of the given type conflicts with an existing record of the same
# name if their contents start with the same tag (or always, for no tag).
TXT_TAGS = ("v=spf1", "v=DMARC1", "v=STSv1", "v=TLSRPTv1", "v=DKIM1")


def get(path, **params):
    url = f"{API}{path}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)
    if not body.get("success"):
        sys.exit(f"Cloudflare API error for {path}: {body.get('errors')}")
    return body


def zone_records(zone):
    zones = get("/zones", name=zone)["result"]
    if not zones:
        sys.exit(f"zone {zone} not found in this Cloudflare account")
    records, page = [], 1
    while True:
        body = get(f"/zones/{zones[0]['id']}/dns_records", per_page=100, page=page)
        records += body["result"]
        if page >= body["result_info"]["total_pages"]:
            return records
        page += 1


def txt_tag(content):
    content = content.strip('"').replace('" "', "")
    return next((t for t in TXT_TAGS if content.lower().startswith(t.lower())), None)


def conflicts(want, existing):
    """Does an existing record clash with a record we want to create?"""
    if existing["type"] == "CNAME" or want["type"] == "CNAME":
        return True  # a CNAME may not coexist with any other record
    if existing["type"] != want["type"]:
        return False
    if want["type"] == "TXT":
        tag = txt_tag(want["value"])
        return tag is not None and txt_tag(existing["content"]) == tag
    return want["type"] in ("MX", "A", "AAAA", "SRV", "CAA")


def main():
    desired = json.load(open(sys.argv[1]))
    managed = set(json.load(open(sys.argv[2])))
    problems = []
    for zone in sorted({r["domain"] for r in desired}):
        existing = [r for r in zone_records(zone) if r["id"] not in managed]
        for want in (r for r in desired if r["domain"] == zone):
            fqdn = zone if want["name"] == "@" else f"{want['name']}.{zone}"
            for rec in existing:
                if rec["name"].lower() == fqdn.lower() and conflicts(want, rec):
                    problems.append(f"  {rec['type']:5} {rec['name']}: {rec['content']}")
    if problems:
        print("These existing records conflict with the ones this setup creates:", file=sys.stderr)
        print("\n".join(sorted(set(problems))), file=sys.stderr)
        print(
            "Delete them in the Cloudflare dashboard (they likely belong to a previous\n"
            "mail provider), then run `just apply` again. To create the records anyway,\n"
            "set DNS_PREFLIGHT=skip.",
            file=sys.stderr,
        )
        sys.exit(1)
    print("No conflicting DNS records.")


if __name__ == "__main__":
    if not TOKEN:
        sys.exit("CLOUDFLARE_API_TOKEN is not set")
    main()
