resource "auth0_attack_protection" "this" {
  brute_force_protection {
    enabled      = true
    max_attempts = 10
    mode         = "count_per_identifier_and_ip"
    shields      = ["block", "user_notification"]
  }

  suspicious_ip_throttling {
    enabled = true
    shields = ["block"]
  }

  breached_password_detection {
    enabled = true
    method  = "standard"
    shields = ["block", "user_notification"]

    pre_user_registration {
      shields = ["block"]
    }
  }
}
