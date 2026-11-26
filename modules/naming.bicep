@export()
func resourceName(prefix string, domain string, purpose string, env string, regionCode string, instance int) string =>
  '${prefix}-${domain}-${purpose}-${env}-${regionCode}-${padLeft(string(instance), 2, '0')}'
