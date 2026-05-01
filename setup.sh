#!/usr/bin/env bash
set -euo pipefail

# Colors
GRN='\033[32m'
YLO='\033[1;33m'
RED='\033[31m'
CYN='\033[36m'
RST='\033[0m'

log()  { echo -e "${GRN}[*] $*${RST}"; }
warn() { echo -e "${YLO}[!] $*${RST}"; }
err()  { echo -e "${RED}[!] $*${RST}"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    err "Please run as root (or via sudo)."
    exit 1
  fi
}

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID=${ID:-unknown}
    OS_LIKE=${ID_LIKE:-}
  else
    OS_ID=unknown
    OS_LIKE=
  fi

  # Determine family
  if [[ "$OS_ID" =~ (debian|ubuntu|linuxmint|raspbian) ]] || [[ "$OS_LIKE" =~ (debian|ubuntu) ]]; then
    DISTRO_FAMILY=debian
    PKG_MGR=apt
  elif [[ "$OS_ID" =~ (fedora|rhel|centos|rocky|almalinux) ]] || [[ "$OS_LIKE" =~ (rhel|fedora|centos) ]]; then
    DISTRO_FAMILY=fedora
    PKG_MGR=dnf
    command -v dnf >/dev/null 2>&1 || PKG_MGR=yum
  elif [[ "$OS_ID" =~ (arch|manjaro|endeavouros) ]] || [[ "$OS_LIKE" =~ arch ]]; then
    DISTRO_FAMILY=arch
    PKG_MGR=pacman
  else
    DISTRO_FAMILY=unknown
    PKG_MGR=
  fi
}

pkg_update() {
  case "$PKG_MGR" in
    apt) apt-get update -y ;;
    dnf) dnf -y makecache ;;
    yum) yum -y makecache ;;
    pacman) pacman -Sy --noconfirm ;;
    *) err "Unsupported distro (no known package manager)."; exit 1 ;;
  esac
}

pkg_install() {
  local pkgs=("$@")
  case "$PKG_MGR" in
    apt) apt-get install -y "${pkgs[@]}" ;;
    dnf) dnf install -y "${pkgs[@]}" ;;
    yum) yum install -y "${pkgs[@]}" ;;
    pacman) pacman -S --noconfirm --needed "${pkgs[@]}" ;;
    *) err "Unsupported distro (no known package manager)."; exit 1 ;;
  esac
}

svc_enable_now() {
  local svc=$1
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now "$svc"
  else
    warn "systemctl not found; please enable/start $svc manually."
  fi
}

apache_service_name() {
  # Debian uses apache2, RHEL/Fedora typically httpd
  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    echo apache2
  else
    echo httpd
  fi
}

install_apache() {
  log "Installing Apache + ModSecurity (best-effort across distros)"

  case "$DISTRO_FAMILY" in
    debian)
      pkg_update
      pkg_install apache2 apache2-utils libapache2-mod-security2 git
      ;;
    fedora)
      pkg_update
      # Packages vary by distro version/repos
      pkg_install httpd mod_security2 git || pkg_install httpd mod_security git
      ;;
    arch)
      pkg_update
      # Arch package names may differ; keep best-effort
      pkg_install apache git || true
      warn "On Arch, ModSecurity packages may require AUR (e.g., modsecurity / modsecurity-apache)."
      ;;
    *)
      err "Unsupported distro family: $DISTRO_FAMILY"
      exit 1
      ;;
  esac

  # Install configs (Debian layout expected by repo). We copy them, but do not assume paths exist.
  if [[ -d /etc/apache2 ]]; then
    warn "Detected Debian-style Apache layout (/etc/apache2). Applying Debian config files."
    [[ -f /etc/apache2/apache2.conf ]] && cp -a /etc/apache2/apache2.conf "/etc/apache2/apache2.conf.backup.$(date +%F_%H%M%S)" || true
    cp -f apache2/apache2.conf /etc/apache2/
    cp -f apache2/000-default.conf /etc/apache2/sites-available/

    # OWASP hardening snippet (a2enconf-friendly)
    if [[ -f apache2/conf-available/security-owasp.conf ]]; then
      cp -f apache2/conf-available/security-owasp.conf /etc/apache2/conf-available/security-owasp.conf
      if command -v a2enmod >/dev/null 2>&1; then a2enmod headers >/dev/null 2>&1 || true; fi
      if command -v a2enconf >/dev/null 2>&1; then a2enconf security-owasp >/dev/null 2>&1 || true; fi
    fi
  else
    warn "Non-Debian Apache layout detected. Skipping automatic config copy for Apache (paths differ)."
    warn "You can still use repo configs as reference and apply them manually for your distro."
  fi

  # OWASP CRS (Debian example). Only attempt when typical target dir exists.
  if [[ -d /usr/share ]] && [[ -d /etc/modsecurity || -d /etc/modsecurity.d ]]; then
    log "Fetching OWASP Core Rule Set (CRS)"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    git clone --depth 1 https://github.com/coreruleset/coreruleset "$tmpdir/coreruleset"
    mv "$tmpdir/coreruleset/crs-setup.conf.example" "$tmpdir/coreruleset/crs-setup.conf"

    if [[ -d /usr/share/modsecurity-crs ]]; then
      mv /usr/share/modsecurity-crs "/usr/share/modsecurity-crs-backup.$(date +%F_%H%M%S)" || true
    fi
    rm -rf /usr/share/modsecurity-crs
    mv "$tmpdir/coreruleset" /usr/share/modsecurity-crs

    # Debian: /etc/modsecurity
    if [[ -d /etc/modsecurity ]]; then
      cp -f apache2/modsecurity.conf /etc/modsecurity/ || true
    fi
  else
    warn "Skipping CRS auto-install (ModSecurity paths differ or not installed)."
  fi

  svc_enable_now "$(apache_service_name)"
  log "Apache install step completed."
}

install_nginx() {
  log "Installing Nginx"
  case "$DISTRO_FAMILY" in
    debian)
      pkg_update
      pkg_install nginx apache2-utils
      ;;
    fedora)
      pkg_update
      pkg_install nginx httpd-tools
      ;;
    arch)
      pkg_update
      pkg_install nginx
      ;;
    *)
      err "Unsupported distro family: $DISTRO_FAMILY"
      exit 1
      ;;
  esac

  # Install nginx.conf if path exists (common across distros)
  if [[ -d /etc/nginx ]]; then
    [[ -f /etc/nginx/nginx.conf ]] && cp -a /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.backup.$(date +%F_%H%M%S)" || true
    cp -f nginx/nginx.conf /etc/nginx/nginx.conf || true

    # OWASP snippet: Debian-style conf-available/conf-enabled
    if [[ -d /etc/nginx/conf-available && -d /etc/nginx/conf-enabled && -f nginx/conf-available/security-owasp.conf ]]; then
      cp -f nginx/conf-available/security-owasp.conf /etc/nginx/conf-available/security-owasp.conf
      ln -sf /etc/nginx/conf-available/security-owasp.conf /etc/nginx/conf-enabled/security-owasp.conf
    else
      warn "Nginx conf-available/conf-enabled not found."
      warn "If you want the snippet, include it manually from nginx.conf inside the http{} block."
    fi
  else
    warn "/etc/nginx not found; skipping config copy."
  fi

  svc_enable_now nginx
  log "Nginx install step completed."
}

install_fail2ban() {
  log "Installing Fail2ban"
  case "$DISTRO_FAMILY" in
    debian)
      pkg_update
      pkg_install fail2ban iptables
      ;;
    fedora)
      pkg_update
      # Fedora/RHEL family may use firewalld/nftables; still install fail2ban.
      pkg_install fail2ban
      ;;
    arch)
      pkg_update
      pkg_install fail2ban
      ;;
    *)
      err "Unsupported distro family: $DISTRO_FAMILY"
      exit 1
      ;;
  esac

  if [[ -d /etc/fail2ban ]]; then
    install -d /etc/fail2ban/jail.d
    # Prefer jail.d drop-in baseline
    if [[ -f fail2ban/jail.d/owasp-baseline.local ]]; then
      install -m 0644 fail2ban/jail.d/owasp-baseline.local /etc/fail2ban/jail.d/owasp-baseline.local
    else
      # fallback to existing jail.local
      install -m 0644 fail2ban/jail.local /etc/fail2ban/jail.local
    fi
  fi

  svc_enable_now fail2ban
  log "Fail2ban install step completed."
  if command -v fail2ban-client >/dev/null 2>&1; then
    fail2ban-client status sshd || true
  fi
}

main_menu() {
  while true; do
    warn "Caution: do not run blindly on production systems. Review changes first."
    echo -e "${GRN}[*] 1) Install Apache (and best-effort ModSecurity/CRS)"
    echo -e "[*] 2) Install Nginx"
    echo -e "[*] 3) Install Fail2ban"
    echo -e "[*] 4) Install All (Apache + Nginx + Fail2ban)"
    echo -e "[*] 5) Exit${RST}"
    echo -en "${CYN}Select an option: ${RST}"
    read -r choice

    case "$choice" in
      1) install_apache ;;
      2) install_nginx ;;
      3) install_fail2ban ;;
      4) install_apache; install_nginx; install_fail2ban ;;
      5) exit 0 ;;
      *) err "Invalid option" ;;
    esac

    echo
  done
}

need_root
detect_distro
log "Detected distro family: ${DISTRO_FAMILY} (ID=${OS_ID})"
main_menu
