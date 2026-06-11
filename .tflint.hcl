plugin "terraform" {
  enabled = true
  version = "~> 0.7"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

# Enforce variable descriptions
rule "terraform_documented_variables" {
  enabled = true
}

# Enforce output descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

# Warn on deprecated interpolation syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Require typed variables
rule "terraform_typed_variables" {
  enabled = true
}

# Naming convention: snake_case
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }

  output {
    format = "snake_case"
  }
}

# Require required_version in root module
rule "terraform_required_version" {
  enabled = true
}

# Require provider version constraints
rule "terraform_required_providers" {
  enabled = true
}
