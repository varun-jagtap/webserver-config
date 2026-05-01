# <span style="color: red;">Disclaimer</span>

These files are not created for production server. This are created for understanding basic server security. So don't use these files in production server and also don't test this files on main system as you may lock down your own system.

<hr>

## Summary

These are web server config file to sercure web servers and understanding basics of web server security. These only provide basic level like firewall and secure ssh.

**Added in latest update:**
- OWASP-oriented security snippets for **Apache2** and **Nginx** (easy enable/disable)
- Fail2ban baseline hardening using `jail.d` drop-in config
- `setup.sh` updated to support major distro families (Debian based, Fedora/RHEL based, Arch based)

<hr>

# Note 
By default it will create backups of your default configuration files.
But it will still ask for overwrite permission. So if want you want create backup manually You will get a chance to do that. 
<hr>

## Installation

<strong>Scripts supports Debian based, Fedora based and Arch based distributions.</strong>

```bash
git clone https://github.com/varun-jagtap/webserver-config
cd webserver-config
sudo bash setup.sh
```
<hr>

## Owasp coreruleset
Modsecurity default rule set will be replaced with owasp coreruleset for apache2 only (best effort, distro dependent). You can get more about owasp coreruleset <a href="https://github.com/coreruleset/coreruleset">here</a> 

<hr>

## Apache2
By default script will install Apache with ModSecurity (best effort across distros).

### Apache OWASP security snippet
New file:
- `apache2/conf-available/security-owasp.conf`

Enable on Debian/Ubuntu:
```bash
sudo a2enmod headers
sudo a2enconf security-owasp
sudo systemctl reload apache2
```

<hr>

## Nginx
Nginx will have its default but modified configuration.

### Nginx OWASP security snippet
New file:
- `nginx/conf-available/security-owasp.conf`

Enable on Debian/Ubuntu style Nginx layout:
```bash
sudo install -m 0644 nginx/conf-available/security-owasp.conf /etc/nginx/conf-available/security-owasp.conf
sudo ln -sf /etc/nginx/conf-available/security-owasp.conf /etc/nginx/conf-enabled/security-owasp.conf
sudo nginx -t && sudo systemctl reload nginx
```

<hr>

## Fail2ban
It's highly recommend to have a firewall so this will install fail2ban.

### Fail2ban baseline (jail.d drop-in)
New file:
- `fail2ban/jail.d/owasp-baseline.local`

Install:
```bash
sudo install -d /etc/fail2ban/jail.d
sudo install -m 0644 fail2ban/jail.d/owasp-baseline.local /etc/fail2ban/jail.d/owasp-baseline.local
sudo systemctl restart fail2ban
```

<hr>

## Virtual host
By default virtual files will not be installed. So if want install it just copy the following file into:

<strong>Apache2</strong> 
site.com.conf > /etc/apache2/sites-available/ <br>
And enable them with command:<br>
`sudo a2ensite filename` 

make sure that you have disabled the default files(000-default.conf). If you haven't then use command:<br>
`sudo a2dissite filename` do disable 

<strong>Nginx</strong>
site.com > /etc/nginx/sites-available/ <br>
And enable them with command:<br>

```bash
cd /etc/nginx/site-enabled/
sudo ln -s /etc/nginx/sites-available/filename
```
make sure that you have disabled the default files(default). If you haven't then use command:<br>

```bash
cd /etc/nginx/site-enabled/
sudo rm default
```  
