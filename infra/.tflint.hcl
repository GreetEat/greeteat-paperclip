// Terraform linter configuration for the GreetEat Paperclip deployment.
//
// Run from infra/envs/prod/ as:
//   tflint --config=$(pwd)/../../.tflint.hcl --recursive
//
// Or hooked into PR-time CI via .github/workflows/terraform-plan.yml (T065).

config {
  // Walk into module sources (we have lots of local modules under infra/modules/)
  call_module_type = "all"

  // Fail on warnings as well as errors when run in CI
  force = false
}

// Core Terraform language rules (recommended preset)
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

// Google provider rules — pin a known-good plugin version
plugin "google" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
