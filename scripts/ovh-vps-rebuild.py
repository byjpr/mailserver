"""Reinstall a freshly ordered OVHcloud VPS with an SSH key.

Called by infra/servers/ovh (terraform_data.ssh_access). Reads the same
OVH_* credentials from the environment as the Terraform provider, plus:
  VPS_SERVICE_NAME  e.g. vps-1a2b3c4d.vps.ovh.net
  VPS_IMAGE_NAME    e.g. "Debian 13"
  VPS_SSH_KEY       the public key to install
"""

import datetime
import os
import sys
import time

import ovh

service = os.environ["VPS_SERVICE_NAME"]
image_name = os.environ["VPS_IMAGE_NAME"]
ssh_key = os.environ["VPS_SSH_KEY"]

client = ovh.Client()  # configured entirely from OVH_* environment variables


def wait_for(predicate, what, timeout=1800):
    deadline = time.time() + timeout
    while not predicate():
        if time.time() > deadline:
            sys.exit(f"timed out waiting for {what}")
        time.sleep(15)


# A new VPS is delivered asynchronously after the order.
wait_for(lambda: client.get(f"/vps/{service}")["state"] == "running", "VPS delivery")

# This reinstall wipes the disk. It must only ever run right after the order;
# if Terraform recreates this step later (tofu apply -replace, state
# surgery), refuse instead of destroying the mail server.
created = datetime.date.fromisoformat(client.get(f"/vps/{service}/serviceInfos")["creation"])
age_days = (datetime.date.today() - created).days
if age_days > 1 and os.environ.get("OVH_FORCE_REBUILD") != "1":
    sys.exit(
        f"{service} was ordered {age_days} days ago; refusing to reinstall it (that would wipe "
        "the installed mail server). If you really mean to, rerun with OVH_FORCE_REBUILD=1."
    )

images = [client.get(f"/vps/{service}/images/available/{i}")
          for i in client.get(f"/vps/{service}/images/available")]
matches = [i for i in images if i["name"] == image_name]
if not matches:
    names = ", ".join(sorted(i["name"] for i in images))
    sys.exit(f"image {image_name!r} not available for {service}; choose one of: {names}")

print(f"Reinstalling {service} with {image_name} and your SSH key", flush=True)
client.post(f"/vps/{service}/rebuild",
            imageId=matches[0]["id"], publicSshKey=ssh_key, doNotSendPassword=True)

# The state leaves "running" while the rebuild is in progress.
time.sleep(60)
wait_for(lambda: not client.get(f"/vps/{service}/tasks", state="todo")
         and not client.get(f"/vps/{service}/tasks", state="doing")
         and client.get(f"/vps/{service}")["state"] == "running", "reinstallation")
print("Reinstalled.", flush=True)
