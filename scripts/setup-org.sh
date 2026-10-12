#!/usr/bin/env bash
# One-time org bootstrap for ShopLite. Safe to re-run (re-running rotates the deploy key).
#
#   1. Move the repos from a personal account into the org (skipped if already there).
#   2. Allow GitHub Actions to open PRs (the gitops "promote" workflow needs it).
#   3. Create an SSH deploy key that can write ONLY to shoplite-gitops and store its private half
#      ONCE as the organization secret GITOPS_DEPLOY_KEY, shared with the service repos.
#      Service repos receive it via `secrets: inherit` in their ci.yml.
#
# Needs: gh logged in as an org owner with the admin:org scope
#   gh auth refresh -h github.com -s admin:org
set -euo pipefail

ORG=${ORG:-shoplite-lab}
FROM=${FROM:-HoPhan-Alphaway}
ALL="shoplite-ci-workflows shoplite-gitops shoplite-infra shoplite-frontend shoplite-user-service shoplite-product-service shoplite-order-service shoplite-notification-service"
SERVICES="shoplite-frontend shoplite-user-service shoplite-product-service shoplite-order-service shoplite-notification-service"
KEY_TITLE="ci-update-gitops"

echo "== 1. Transfer repos to $ORG"
for r in $ALL; do
  if gh api "repos/$ORG/$r" --silent 2>/dev/null; then
    echo "   $r already in $ORG"
  else
    gh api -X POST "repos/$FROM/$r/transfer" -f new_owner="$ORG" --jq '"   moved " + .full_name'
  fi
done
sleep 5 # transfers are async

echo "== 2. Actions may create pull requests (org + gitops repo)"
gh api -X PUT "orgs/$ORG/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
gh api -X PUT "repos/$ORG/shoplite-gitops/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true

echo "== 3. Deploy key on shoplite-gitops + org secret GITOPS_DEPLOY_KEY"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ssh-keygen -q -t ed25519 -N "" -C "shoplite-ci update-gitops" -f "$tmp/key"

for id in $(gh repo deploy-key list --repo "$ORG/shoplite-gitops" --json id,title --jq ".[] | select(.title==\"$KEY_TITLE\") | .id"); do
  gh repo deploy-key delete "$id" --repo "$ORG/shoplite-gitops"
done
gh repo deploy-key add "$tmp/key.pub" --repo "$ORG/shoplite-gitops" --allow-write --title "$KEY_TITLE"

# Only the service repos can read it — not infra, not gitops itself.
gh secret set GITOPS_DEPLOY_KEY --org "$ORG" --visibility selected \
  --repos "$(echo $SERVICES | tr ' ' ',')" < "$tmp/key"

echo "Done."
