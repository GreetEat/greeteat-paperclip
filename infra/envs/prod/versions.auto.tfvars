# =============================================================================
# Pinned Paperclip version + image digest.
# =============================================================================
# This file is committed. Bumps follow a strict two-step diff:
#
#   Step 1 (PR A): bump paperclip_version to the desired upstream Paperclip
#                  release tag. Merging triggers .github/workflows/build-image.yml
#                  which builds the image and outputs the digest.
#
#   Step 2 (PR B): bump paperclip_image_digest to the digest CI produced.
#                  Merging triggers .github/workflows/deploy.yml.
#
# The two-step diff makes both "we want to upgrade Paperclip" and "the build
# of that upgrade is the digest" individually auditable in git history.
#
# DO NOT reference paperclip_image_digest from a tag — Terraform consumes
# the digest only, never a mutable tag. (See research.md Decision 12.)

# Pinned upstream Paperclip ref. Accepts EITHER a release tag (preferred)
# OR a full 40-char commit SHA (escape hatch for fixes that haven't been
# tagged yet). The build-image.yml workflow auto-detects which one this
# is and tags the resulting image as either `<tag>` or `sha-<short>`.
#
# Currently pinned to commit ac664df8e48326135a913e97ee7ed937d913586b
# (master @ 2026-04-10 16:55:27Z): "fix(authz): scope import, approvals,
# activity, and heartbeat routes (#3315)". The latest tagged release
# (v2026.403.0, 2026-04-04) is BEFORE this commit and is therefore
# vulnerable to GHSA-68qg-g8mg-6pr7 — a CRITICAL unauthenticated RCE
# published on 2026-04-10. Our PAPERCLIP_AUTH_DISABLE_SIGN_UP=true env
# var breaks the exploit chain at step 1 even on unpatched code, but
# defense in depth says ship the fix anyway.
#
# When upstream cuts a release tag that includes ac664df (likely
# v2026.410.0 or later), switch this back to the tag and rebuild.
paperclip_version = "ac664df8e48326135a913e97ee7ed937d913586b"

# Immutable Artifact Registry digest produced by build-image.yml for the tag above
paperclip_image_digest = "TBD"
