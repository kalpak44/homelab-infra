# Auth0's sign-in and sign-up pages look like the app's own sign-in card: zinc on white, a dark
# primary button, the same corners. The app's colours live in apps/web, so change both together.
resource "auth0_branding_theme" "this" {
  display_name = "workspaced"

  borders {
    button_border_radius = 8
    button_border_weight = 1
    buttons_style        = "rounded"
    input_border_radius  = 8
    input_border_weight  = 1
    inputs_style         = "rounded"
    show_widget_shadow   = true
    widget_border_weight = 1
    widget_corner_radius = 12
  }

  colors {
    body_text                 = "#71717a"
    error                     = "#be123c"
    header                    = "#18181b"
    icons                     = "#71717a"
    input_background          = "#ffffff"
    input_border              = "#d4d4d8"
    input_filled_text         = "#18181b"
    input_labels_placeholders = "#71717a"
    links_focused_components  = "#18181b"
    primary_button            = "#18181b"
    primary_button_label      = "#ffffff"
    secondary_button_border   = "#d4d4d8"
    secondary_button_label    = "#3f3f46"
    success                   = "#059669"
    widget_background         = "#ffffff"
    widget_border             = "#e4e4e7"
  }

  fonts {
    links_style         = "normal"
    reference_text_size = 14

    body_text {
      bold = false
      size = 100
    }

    buttons_text {
      bold = false
      size = 100
    }

    input_labels {
      bold = false
      size = 100
    }

    links {
      bold = true
      size = 100
    }

    title {
      bold = true
      size = 150
    }

    subtitle {
      bold = false
      size = 100
    }
  }

  page_background {
    background_color = "#fafafa"
    page_layout      = "center"
  }

  # The site publishes this logo for the mail too.
  widget {
    header_text_alignment = "left"
    logo_height           = 32
    logo_position         = "left"
    logo_url              = "https://workspaced.online/mail-logo.png"
    social_buttons_layout = "bottom"
  }
}

# The same words as the app's sign-in card, so the hand-over reads as one page.
resource "auth0_prompt_custom_text" "login" {
  prompt   = "login"
  language = "en"
  body = jsonencode({
    login = {
      title       = "Sign in"
      description = "Welcome back. Pick up where your agents left off."
    }
  })
}

resource "auth0_prompt_custom_text" "signup" {
  prompt   = "signup"
  language = "en"
  body = jsonencode({
    signup = {
      title       = "Create account"
      description = "You will get an email to verify your address before your first sign-in."
    }
  })
}
