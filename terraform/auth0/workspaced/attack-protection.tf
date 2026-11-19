resource "auth0_attack_protection" "this" {
  brute_force_protection {
    enabled      = true
    max_attempts = 10
    mode         = "count_per_identifier_and_ip"
    shields      = ["block", "user_notification"]
  }

  # Every sign-up mails a verification link through the domain's Mailjet account, so a script
  # signing up other people's addresses would spend its reputation. Five from one address, then one
  # more every 12 minutes; Auth0's default allows about 3,000 an hour.
  suspicious_ip_throttling {
    enabled = true
    shields = ["block"]

    pre_user_registration {
      max_attempts = 5
      rate         = 720000
    }
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
