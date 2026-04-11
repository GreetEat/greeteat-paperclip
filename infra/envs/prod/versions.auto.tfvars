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

# Paperclip release tag (operator decision; see https://github.com/paperclipai/paperclip/releases)
paperclip_version = "v2026.403.0"

# Immutable Artifact Registry digest produced by build-image.yml for the tag above
paperclip_image_digest = "TBD"
