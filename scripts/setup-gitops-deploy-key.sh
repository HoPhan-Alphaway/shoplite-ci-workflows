#!/usr/bin/env bash
# One-time setup (re-run to rotate): an SSH deploy key that may write ONLY to shoplite-gitops.
#   public key  -> deploy key (write) on shoplite-gitops
#   private key -> secret GITOPS_DEPLOY_KEY on every service repo (used by update-gitops.yml)
# The private key never touches disk outside a temp dir and is deleted at the end.
set -euo pipefail

OWNER=${OWNER:-HoPhan-Alphaway}
SERVICES="shoplite-frontend shoplite-user-service shoplite-product-service shoplite-order-service shoplite-notification-service"
TITLE="ci-update-gitops"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ssh-keygen -q -t ed25519 -N "" -C "shoplite-ci update-gitops" -f "$tmp/key"

# Rotation: remove the previous key with the same title.
for id in $(gh repo deploy-key list --repo "$OWNER/shoplite-gitops" --json id,title --jq ".[] | select(.title==\"$TITLE\") | .id"); do
  gh repo deploy-key delete "$id" --repo "$OWNER/shoplite-gitops"
done
gh repo deploy-key add "$tmp/key.pub" --repo "$OWNER/shoplite-gitops" --allow-write --title "$TITLE"

for r in $SERVICES; do
  gh secret set GITOPS_DEPLOY_KEY --repo "$OWNER/$r" < "$tmp/key"
done
echo "Done: deploy key on $OWNER/shoplite-gitops, secret GITOPS_DEPLOY_KEY on $(echo $SERVICES | wc -w) repos."
