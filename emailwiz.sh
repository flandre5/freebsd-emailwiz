#!/bin/sh
# BEFORE INSTALLING

# Have a FreeBSD server with a static IP and DNS records (usually
# A) that point your domain name to it.

# AFTER INSTALLING

# More DNS records will be given to you to install. One of them will be
# different for every installation and is uniquely generated on your machine.

umask 0022

install_packages="opensmtpd dovecot dovecot-pigeonhole opendkim opendkim rspamd opensmtpd-filter-rspamd"

service dovecot stop
service smtpd stop
pkg remove -y $install_packages
pkg install -y $install_packages

# CHANGE THIS LINE WITH YOUR DOMAIN!
domain="example.org"
subdom=${MAIL_SUBDOM:-mail}
maildomain="$subdom.$domain"

allow_suboptimal_ciphers="yes" #yes no
mailbox_format="maildir" # maildir sdbox
allowed_protocols=" imap"  #imap pop3

country_name="" # IT US UK IN etc etc
state_or_province_name=""
organization_name=""
common_name="$( hostname -f )"


# Preliminary record checks
ipv4=$(host "$domain" | grep -m1 -Eo '([0-9]+\.){3}[0-9]+')
[ -z "$ipv4" ] && echo "\033[0;31mPlease point your domain ("$domain") to your server's ipv4 address." && exit 1

echo -n "Enter your certificate directory: "
read certdir

echo "Configuring OpenSMTPD's main.cf..."
echo "$maildomain" > /usr/local/etc/mail/mailname
echo "#OpenSMTPD Config
## this defines the paths for the X509 certificate
pki $domain cert \"$certdir/fullchain.pem\"
pki $domain key \"$certdir/privkey.pem\"
pki $domain dhe auto

## this defines how the local part of email addresses can be split
# defaults to '+', so solene+foobar@domain matches user
# solene@domain. Due to the '+' character being a regular source of issues
# with many online forms, I recommend using a character such as '_',
# '.' or '-'. This feature is very handy to generate infinite unique emails
# addresses without pre-defining aliases.
# Using '_', solene_openbsd@domain and solene_buystuff@domain lead to the
# same address
smtp sub-addr-delim '_'

## this defines an external filter
# rspamd does dkim signing and spam filter
filter rspamd proc-exec \"/usr/local/libexec/opensmtpd/opensmtpd-filter-rspamd\"

## this defines which file will contain aliases
# this can be used to define groups or redirect emails to users
table aliases file:/etc/mail/aliases

## this defines all the ports to use
# mask-src hides system hostname, username and public IP when sending an email
listen on 0.0.0.0 port 25  tls         pki \"$domain\" filter \"rspamd\" 
listen on 0.0.0.0 port 465 smtps       pki \"$domain\" auth mask-src filter \"rspamd\"
listen on 0.0.0.0 port 587 tls-require pki \"$domain\" auth mask-src filter \"rspamd\"

## this defines actions
# either deliver to lmtp or to an external server
action \"local\" lmtp \"/var/run/dovecot/lmtp\" alias <aliases>
action \"outbound\" relay

## this defines what should be done depending on some conditions
# receive emails (local or from external server for \"$domain\")
match from any for domain \"$domain\" action \"local\"
match from local for local action \"local\"

# send email (from local or authenticated user)
match from any auth for any action \"outbound\"
match from local for any action \"outbound\"
" > /usr/local/etc/mail/smtpd.conf


# By default, dovecot has a bunch of configs in /etc/dovecot/conf.d/ These
# files have nice documentation if you want to read it, but it's a huge pain to
# go through them to organize.  Instead, we simply overwrite
# /etc/dovecot/dovecot.conf because it's easier to manage. You can get a backup
# of the original in /usr/share/dovecot if you want.
mv /usr/local/etc/dovecot/dovecot.conf /usr/local/etc/dovecot/dovecot.backup.conf

echo "Generating dovecot's DH Key"
if [ ! -f /usr/local/share/dovecot/dh.pem ]; then
    openssl dhparam -out /usr/local/share/dovecot/dh.pem 4096
fi

echo "Creating Dovecot config..."

echo "# Dovecot config
# Note that in the dovecot conf, you can use:
# %u for username
# %n for the name in name@domain.tld
# %d for the domain
# %h the user's home directory

ssl = required
ssl_cert = <$certdir/fullchain.pem
ssl_key = <$certdir/privkey.pem
ssl_min_protocol = TLSv1.2
ssl_cipher_list = "'EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA256:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EDH+aRSA+AESGCM:EDH+aRSA+SHA256:EDH+aRSA:EECDH:!aNULL:!eNULL:!MEDIUM:!LOW:!3DES:!MD5:!EXP:!PSK:!SRP:!DSS:!RC4:!SEED'"
ssl_prefer_server_ciphers = yes
ssl_dh = </usr/local/share/dovecot/dh.pem
auth_mechanisms = plain login
auth_username_format = %n
listen = *


protocols = \$protocols $allowed_protocols

# Search for valid users in /etc/passwd
userdb {
	driver = passwd
}
#Fallback: Use plain old PAM to find user passwords
passdb {
	driver = pam
}

# Our mail for each user will be in ~/Mail, and the inbox will be ~/Mail/Inbox
# The LAYOUT option is also important because otherwise, the boxes will be \`.Sent\` instead of \`Sent\`.
mail_location = $mailbox_format:~/Mail:INBOX=~/Mail/Inbox:LAYOUT=fs
namespace inbox {
	inbox = yes
	mailbox Drafts {
	special_use = \\Drafts
	auto = subscribe
}
	mailbox Junk {
	special_use = \\Junk
	auto = subscribe
	autoexpunge = 30d
}
	mailbox Sent {
	special_use = \\Sent
	auto = subscribe
}
	mailbox Trash {
	special_use = \\Trash
}
	mailbox Archive {
	special_use = \\Archive
}
}

protocol lda {
  mail_plugins = \$mail_plugins sieve
}

protocol lmtp {
  mail_plugins = \$mail_plugins sieve
}

protocol imap {
  
  mail_plugins = $mail_plugins imap_sieve
  mail_max_userip_connections = 25
}

" > /usr/local/etc/dovecot/dovecot.conf

# If using an old version of Dovecot, remove the ssl_dl line.
case "$(dovecot --version)" in
	1|2.1*|2.2*) sed -ibak '/^ssl_dh/d' /etc/dovecot/dovecot.conf ;;
esac

mkdir /usr/local/var/lib/dovecot/sieve/

echo "require [\"fileinto\", \"mailbox\"];
if header :contains \"X-Spam-Flag\" \"YES\"
	{
		fileinto \"Junk\";
	}" > /var/lib/dovecot/sieve/default.sieve

grep -q '^vmail:' /etc/passwd || useradd vmail
chown -R vmail:vmail /var/lib/dovecot
sievec /var/lib/dovecot/sieve/default.sieve

# OpenDKIM

# A lot of the big name email services, like Google, will automatically reject
# as spam unfamiliar and unauthenticated email addresses. As in, the server
# will flatly reject the email, not even delivering it to someone's Spam
# folder.

# OpenDKIM is a way to authenticate your email so you can send to such services
# without a problem.

# Create an OpenDKIM key in the proper place with proper permissions.
echo 'Generating OpenDKIM keys...'
mkdir -p "/usr/local/etc/mail/dkim/$domain"
opendkim-genkey -D "/usr/local/etc/mail/dkim/$domain" -d "$domain" -s "$subdom"
chgrp -R opendkim /usr/local/etc/mail/dkim/*
chmod -R g+r /usr/local/mail/dkim/*

# Generate the OpenDKIM info:
echo 'Configuring OpenDKIM...'
grep -q "$domain" /usr/local/etc/mail/dkim/keytable 2>/dev/null ||
echo "$subdom._domainkey.$domain $domain:$subdom:/usr/local/etc/mail/dkim/$domain/$subdom.private" >> /usr/local/etc/mail/dkim/keytable

grep -q "$domain" /usr/local/etc/mail/dkim/signingtable 2>/dev/null ||
echo "*@$domain $subdom._domainkey.$domain" >> /usr/local/etc/mail/dkim/signingtable

grep -q '127.0.0.1' /usr/local/etc/mail/dkim/trustedhosts 2>/dev/null ||
	echo '127.0.0.1
10.1.0.0/16' >> /usr/local/etc/mail/dkim/trustedhosts

# ...and source it from opendkim.conf
grep -q '^KeyTable' /usr/local/etc/opendkim.conf 2>/dev/null || echo 'KeyTable file:/usr/local/etc/mail/dkim/keytable
SigningTable refile:/usr/local/etc/mail/dkim/signingtable
InternalHosts refile:/usr/local/etc/mail/dkim/trustedhosts' >> /usr/local/etc/opendkim.conf

sed -ibak '/^#Canonicalization/s/simple/relaxed\/simple/' /usr/local/etc/opendkim.conf
sed -ibak '/^#Canonicalization/s/^#//' /usr/local/etc/opendkim.conf

sed -ibak '/Socket/s/^#*/#/' /usr/local/etc/opendkim.conf
grep -q '^Socket\s*inet:12301@localhost' /usr/local/etc/opendkim.conf || echo 'Socket inet:12301@localhost' >> /etc/opendkim.conf

# Configure rspamd in OpenDKIM

echo "# our usernames does not contain the domain part
# so we need to enable this option
allow_username_mismatch = true;

# this configures the domain $domain to use the selector \"dkim\"
# and where to find the private key
domain {
    $domain {
        path = \"/usr/local/etc/mail/dkim/$domain\";
        selector = \"dkim\";
    }
}"


for x in milter-opendkim dovecot smtpd rspamd; do
    printf "Restarting %s..." "$x"
    	service "$x" enable
	service "$x" restart && printf " ...done\\n"

done

pval="$(tr -d '\n' <"/usr/local/etc/mail/dkim/$domain/mail.txt" | sed -e 's/k=rsa.* "p=/k=rsa; p=/' -e 's/"[[:space:]]*"//' -e 's/"[[:space:]]*).*$//' | grep -o 'p=.*')"
dkimentry="$subdom._domainkey.$domain	TXT	v=DKIM1; k=rsa; $pval"
dmarcentry="_dmarc.$domain	TXT	v=DMARC1; p=reject; rua=mailto:postmaster@$domain; fo=1"
spfentry="$domain	TXT	v=spf1 mx a:$maildomain ip4:$ipv4 -all"
mxentry="$domain	MX	10	$maildomain	300"

# Create a cronjob that deletes month-old postmaster mails:

echo "NOTE: Elements in the entries might appear in a different order in your registrar's DNS settings.
$dkimentry
$dmarcentry
$spfentry
$mxentry" > "$HOME/dns_emailwizard"

printf "\033[31m
 _   _
| \ | | _____      ___
|  \| |/ _ \ \ /\ / (_)
| |\  | (_) \ V  V / _
|_| \_|\___/ \_/\_/ (_)\033[0m

Add these three records to your DNS TXT records on either your registrar's site
or your DNS server:
\033[32m
$dkimentry

$dmarcentry

$spfentry

$mxentry
\033[0m
NOTE: You may need to omit the \`.$domain\` portion at the beginning if
inputting them in a registrar's web interface.

Also, these are now saved to \033[34m~/dns_emailwizard\033[0m in case you want them in a file.

Once you do that, you're done! Check the README for how to add users/accounts
and how to log in.\n"
