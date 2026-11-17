import {
  to = stripe_tax_rate.vat
  id = "txr_1UcUpbABYXXbGldTpgX5Aq0s"
}

resource "stripe_tax_rate" "vat" {
  display_name = "VAT"
  percentage   = 20
  inclusive    = false
  active       = true
}
