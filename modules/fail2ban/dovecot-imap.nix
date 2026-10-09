# fail2ban filter for failed IMAP logins with Dovecot 2.4.
#
# fail2ban's bundled dovecot filter does not work on NixOS 26.05: it reads the
# journal of `dovecot2.service` (the unit is `dovecot.service` now), and its
# patterns predate Dovecot 2.4's log format:
#
#   imap-login: Login aborted: Logged out (auth failed, 1 attempts in 4 secs)
#     (auth_failed): user=<a@example.com>, method=PLAIN, rip=192.0.2.1, ...
#
# Checked against real Dovecot 2.4 output by the `fail2ban-dovecot` flake
# check (tests/fail2ban/dovecot.log: 4 failed logins must match, a
# successful login, a temporary auth failure and a connection without any
# login attempt must not).
{
  INCLUDES.before = "common.conf";
  Definition = {
    _daemon = "dovecot";
    prefregex = "^%(__prefix_line)s(?:imap|pop3|submission|managesieve)-login: (?:Info: )?Login aborted: <F-CONTENT>.+</F-CONTENT>$";
    failregex = "^.*\\((?:auth failed, \\d+ attempts(?: in \\d+ secs)?|tried to use (?:disabled|disallowed) \\S+ auth)\\) \\(\\w+\\): user=<<F-USER>[^>]*</F-USER>>, (?:method=\\S+, )?rip=<HOST>,";
    ignoreregex = "";
    journalmatch = "_SYSTEMD_UNIT=dovecot.service";
  };
}
