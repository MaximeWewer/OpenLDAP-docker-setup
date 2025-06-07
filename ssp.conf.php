<?php
### Doc : https://self-service-password.readthedocs.io/en/latest/config_ldap.html 

# LDAP connection
$ldap_url = "ldap://openldap:1389";
$ldap_binddn = "cn=ssp,ou=service-accounts,dc=example,dc=org";
$ldap_bindpw = "ssp";
$ldap_base = "dc=example,dc=org";
$ldap_login_attribute = "uid";
# If LDAPS is required
// $ldap_starttls = true;
// putenv("LDAPTLS_REQCERT=allow");
// putenv("LDAPTLS_CACERT=/etc/ssl/certs/ca-certificates.crt");

### Doc : https://self-service-password.readthedocs.io/en/latest/config_general.html
# General config
$keyphrase = "mysecret";
$debug = false;
$lang = "en";
$allowed_lang = array("en","fr");
// $logo = "images/ltb-logo.png";
// $background_image = "images/unsplash-space.jpeg";
// $custom_css = "css/custom.css";
// $custom_tpl_dir = "templates_custom/";

### Doc : https://self-service-password.readthedocs.io/en/latest/config_ppolicy.html
$hash = "auto";
$pwd_min_length = 16;
$pwd_max_length = 64;
$pwd_min_lower = 2;
$pwd_min_upper = 2;
$pwd_min_digit = 2;
$pwd_min_special = 2;
$pwd_special_chars = "^a-zA-Z0-9";
$pwd_no_special_at_ends = true;
$pwd_no_reuse = true;
$pwd_diff_last_min_chars = 2;
$pwd_show_policy = "always";
$pwd_show_policy_pos = "above";
$use_pwnedpasswords = true;

### Doc : https://self-service-password.readthedocs.io/en/latest/config_tokens.html
$use_tokens = false;

### Doc : https://self-service-password.readthedocs.io/en/latest/config_questions.html
$use_questions = false;

### Doc : https://self-service-password.readthedocs.io/en/latest/config_sms.html
$use_sms = false;

### Doc : https://self-service-password.readthedocs.io/en/latest/config_mail.html
// $mail_from = "noreply@example.org";
// $mail_from_name = "Self Service Password administrator - LDAP";
// $mail_signature = "";
// $notify_on_change = true;
// $mail_sendmailpath = '/usr/sbin/sendmail';
// $mail_protocol = 'smtp';
// $mail_smtp_debug = 0;
// $mail_debug_format = 'html';
// $mail_smtp_host = 'localhost';
// $mail_smtp_auth = false;
// $mail_smtp_user = '';
// $mail_smtp_pass = '';
// $mail_smtp_port = 25;
// $mail_smtp_timeout = 30;
// $mail_smtp_keepalive = false;
// $mail_smtp_secure = 'tls';
// $mail_smtp_autotls = true;
// $mail_smtp_options = array();
// $mail_contenttype = 'text/plain';
// $mail_wordwrap = 0;
// $mail_charset = 'utf-8';
// $mail_priority = 3;
?>
