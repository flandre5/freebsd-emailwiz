# Email server setup script

This script installs an email server with all the features required in the
modern web.

This should have been done with an Ansible playbook rather than with a
POSIX shell script.

/!\\ THIS ONLY SUPPORTS DOVECOT <=2.3, NOT THE 2.4 FILE CONFIGURATION SYNTAX
THIS WILL BE PATCHED TO WORK WITH NEWER VERSIONS OF DOVECOT AS SOON AS IT
IS UPDATED IN THE [FREEBSD PORTS](https://www.freshports.org/mail/dovecot) /!\\

## TODO

- [] Port adddomain.sh to OpenSMTPD-FreeBSD

## This script installs

- **OpenSMTPD** to send and receive mail.
- **Dovecot** to get mail to your email client (mutt, Thunderbird, etc.).
- Config files that link the two above securely with native PAM log-ins.
- **rspamd** to prevent spam and allow you to make custom filters.
- **OpenDKIM** to validate you so you can send to Gmail and other big sites.
  
## This script does _not_...

- use a SQL database or anything like that. We keep it simple and use normal
  Unix system users for accounts and passwords.
- set up a graphical web interface for mail like Roundcube or Squirrel Mail.
  You are expected to use a normal mail client like Thunderbird or K-9 for
  Android or good old mutt with
  [mutt-wizard](https://github.com/lukesmithxyz/mutt-wizard). Note that there
  is a guide for [Rainloop](https://landchad.net/rainloop/) on
  [LandChad.net](https://landchad.net) for those that want such a web
  interface.
- Generate certificates for your mail server. It's a pain in the ass to
  maintain + certbot sucks ass + your mail server might not be a web server
  as well. So bring your own certificates.
  
## Prerequisites for Installation

1. FreeBSD server.
2. DNS records that point at least your domain's `mail.` subdomain to your
   server's IP (IPv4). This is required on initial run for certbot to
   get an SSL certificate for your `mail.` subdomain.
3. Your TLS certificates. You'll be prompted by the script where your certs
   are located. You must have `fullchain.pem` and `privkey.pem`. Just like
   certbot generates the certificates.

## Mandatory Finishing Touches

### Unblock your ports

While the script enables your mail ports on your server, it is common practice
for all VPS providers to block mail ports on their end by default. Open a help
ticket with your VPS provider asking them to open your mail ports and they will
do it in short order.

You might also have to configure `pf.conf`

### DNS records

At the end of the script, you will be given some DNS records to add to your DNS
server/registrar's website. These are mostly for authenticating your emails as
non-spam. The 4 records are:

1. An MX record directing to `mail.yourdomain.tld`.
2. A TXT record for SPF (to reduce mail spoofing).
3. A TXT record for DMARC policies.
4. A TXT record with your public DKIM key. This record is long and **uniquely
   generated** while running `emailwiz.sh` and thus must be added after
   installation.

They will look something like this:

```
@	MX	10	mail.example.org
mail._domainkey.example.org    TXT     v=DKIM1; k=rsa; p=anextremelylongsequenceoflettersandnumbersgeneratedbyopendkim
_dmarc.example.org     TXT     v=DMARC1; p=reject; rua=mailto:dmarc@example.org; fo=1
example.org    TXT     v=spf1 mx a: -all
```

The script will create a file, `~/dns_emailwiz` that will list our the records
for your convenience, and also prints them at the end of the script.

### Add a rDNS/PTR record as well!

Set a reverse DNS or PTR record to avoid getting spammed. You can do this at
your VPS provider, and should set it to `mail.yourdomain.tld`. Note that you
should set this for both IPv4 and IPv6.

## Making new users/mail accounts

Let's say we want to add a user Billy and let him receive mail, run this:

```
useradd
Username: test
```
A user's mail will appear in `~/Mail/`. If you want to see your mail while ssh'd
in the server, you could just install mutt, add `set spoolfile="+Inbox"` to
your `~/.muttrc` and use mutt to view and reply to mail. You'll probably want
to log in remotely though:

## Logging in from email clients (Thunderbird/mutt/etc)

Let's say you want to access your mail with Thunderbird or mutt or another
email program. For my domain, the server information will be as follows:

- SMTP server: `mail.example.org`
- SMTP port: 465
- IMAP server: `mail.example.org`
- IMAP port: 993

## Benefited from this?

I am always glad to hear this script is still making life easy for people. If
this script or documentation has saved you some frustration, donate here:

- btc: `bc1q2wt4wyr0j9ffq3668n2vsw3jf6pvqqmq930ts8`
- xmr: `833dPL1CT7GFa4TXPTn33ESS3qetzV8ZcMYQGBT8h2DZAJ5kaYGJ8RLNvyNgSueDCeEXNqZG3iKwiS3tVQTz9EWMS1er5Gh`

## Sites for Troubleshooting

Can't send or receive mail? Getting marked as spam? There are tools to double-check your DNS records and more:

- Always check `/var/log/maillog` first for specific errors.
- [Check your DNS](https://intodns.com/)
- [Test your TXT records via mail](https://appmaildev.com/en/dkim)
- [Is your IP blacklisted?](https://mxtoolbox.com/blacklists.aspx)
- [mxtoolbox](https://mxtoolbox.com/SuperTool.aspx)
- [dataswamp OpenBSD mail guide](https://dataswamp.org/~solene/2024-07-24-openbsd-email-server-setup.html)

## Other versions

- The [original script](https://github.com/lukesmithxyz/emailwiz) for
  Debian-based systems
