#!/usr/bin/env bash

############## Begin Function Section ##############


set -x
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAILCOW_CONF="${SCRIPT_DIR}/mailcow.conf"

# Ensure the script is run from the directory that contains mailcow.conf
if [ ! -f "${PWD}/mailcow.conf" ]; then
  if [ -f "${SCRIPT_DIR}/mailcow.conf" ]; then
    echo -e "\e[33mPlease run this script directly from the mailcow installation directory:\e[0m"
    echo -e "  \e[36mcd ${SCRIPT_DIR} && ./update.sh\e[0m"
    exit 1
  else
    echo -e "\e[31mmailcow.conf not found in current directory or script directory (\e[36m${SCRIPT_DIR}\e[31m).\e[0m"
    echo -e "\e[33mRun this script directly from your mailcow installation directory.\e[0m"
    exit 1
  fi
fi
BRANCH="$(cd "${SCRIPT_DIR}" && git rev-parse --abbrev-ref HEAD)"

MODULE_DIR="${SCRIPT_DIR}/_modules"
# Calculate hash before fetch
if [[ -d "${MODULE_DIR}" && -n "$(ls -A "${MODULE_DIR}" 2>/dev/null)" ]]; then
  MODULES_HASH_BEFORE=$(find "${MODULE_DIR}" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | awk '{print $1}')
else
  MODULES_HASH_BEFORE="EMPTY"
fi

echo -e "\e[33mFetching latest _modules from origin/${BRANCH}…\e[0m"
git fetch origin "${BRANCH}"
git checkout "origin/${BRANCH}" -- _modules

if [[ ! -d "${MODULE_DIR}" || -z "$(ls -A "${MODULE_DIR}")" ]]; then
  echo -e "\e[31mError: _modules is still missing or empty after fetch!\e[0m"
  exit 2
fi

# Calculate hash after fetch
MODULES_HASH_AFTER=$(find "${MODULE_DIR}" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | awk '{print $1}')

# Check if modules changed
if [[ "${MODULES_HASH_BEFORE}" != "${MODULES_HASH_AFTER}" ]]; then
  echo -e "\e[33m_modules have been updated. Please restart the update script.\e[0m"
  exit 2
fi

source _modules/scripts/core.sh
source _modules/scripts/ipv6_controller.sh
source _modules/scripts/new_options.sh
source _modules/scripts/migrate_options.sh

############## End Function Section ##############

# Check permissions
if [ "$(id -u)" -ne "0" ]; then
  echo "You need to be root"
  exit 1
fi

# Run pre-update-hook
if [ -f "${SCRIPT_DIR}/pre_update_hook.sh" ]; then
  bash "${SCRIPT_DIR}/pre_update_hook.sh"
fi

# Exit on error and pipefail
set -o pipefail

# Setting high dc timeout
export COMPOSE_HTTP_TIMEOUT=600

# Add /opt/bin to PATH
PATH=$PATH:/opt/bin

umask 0022

# Unset COMPOSE_COMMAND and DOCKER_COMPOSE_VERSION Variable to be on the newest state.
unset COMPOSE_COMMAND
unset DOCKER_COMPOSE_VERSION

get_installed_tools

get_docker_version

export LC_ALL=C
DATE=$(date +%Y-%m-%d_%H_%M_%S)
BRANCH="$(cd "${SCRIPT_DIR}"; git rev-parse --abbrev-ref HEAD)"

while (($#)); do
  case "${1}" in
    --skip-start)
      SKIP_START=y
    ;;
    --skip-ping-check)
      SKIP_PING_CHECK=y
    ;;
    --stable)
      CURRENT_BRANCH="$(cd "${SCRIPT_DIR}"; git rev-parse --abbrev-ref HEAD)"
      NEW_BRANCH="mailman3"
    ;;
    --gc)
      echo -e "\e[32mCollecting garbage...\e[0m"
      docker_garbage
      exit 0
    ;;
    --nightly)
      CURRENT_BRANCH="$(cd "${SCRIPT_DIR}"; git rev-parse --abbrev-ref HEAD)"
      NEW_BRANCH="nightly"
    ;;
    --prefetch)
      echo -e "\e[32mPrefetching images...\e[0m"
      prefetch_images
      exit 0
    ;;
    -f|--force)
      echo -e "\e[32mRunning in forced mode...\e[0m"
      FORCE=y
    ;;
    -d|--dev)
      echo -e "\e[32mRunning in Developer mode...\e[0m"
      DEV=y
    ;;
    --legacy)
      CURRENT_BRANCH="$(cd "${SCRIPT_DIR}"; git rev-parse --abbrev-ref HEAD)"
      NEW_BRANCH="legacy"
    ;;
    --help|-h)
    echo './update.sh [-c|--check, --check-tags, --ours, --gc, --nightly, --prefetch, --skip-start, --skip-ping-check, --stable, --legacy, -f|--force, -d|--dev, -h|--help]

  -c|--check           -   Check for updates and exit (exit codes => 0: update available, 3: no updates)
  --check-tags         -   Check for newer tags and exit (exit codes => 0: newer tag available, 3: no newer tag)
  --ours               -   Use merge strategy option "ours" to solve conflicts in favor of non-mailcow code (local changes over remote changes), not recommended!
  --gc                 -   Run garbage collector to delete old image tags
  --nightly            -   Switch your mailcow updates to the unstable (nightly) branch. FOR TESTING PURPOSES ONLY!!!!
  --prefetch           -   Only prefetch new images and exit (useful to prepare updates)
  --skip-start         -   Do not start mailcow after update
  --skip-ping-check    -   Skip ICMP Check to public DNS resolvers (Use it only if you'\''ve blocked any ICMP Connections to your mailcow machine)
  --stable             -   Switch your mailcow updates to the stable (master) branch. Default unless you changed it with --nightly or --legacy.
  --legacy             -   Switch your mailcow updates to the legacy branch. The legacy branch will only receive security updates until February 2026.
  -f|--force           -   Force update, do not ask questions
  -d|--dev             -   Enables Developer Mode (No Checkout of update.sh for tests)
'
    exit 0
  esac
  shift
done

[[ ! -f mailcow.conf ]] && { echo -e "\e[31mmailcow.conf is missing! Is mailcow installed?\e[0m"; exit 1;}

chmod 600 mailcow.conf
source mailcow.conf

get_compose_type

DOTS=${MAILCOW_HOSTNAME//[^.]};
if [ ${#DOTS} -lt 1 ]; then
  echo -e "\e[31mMAILCOW_HOSTNAME (${MAILCOW_HOSTNAME}) is not a FQDN!\e[0m"
  sleep 1
  echo "Please change it to a FQDN and redeploy the stack with $COMPOSE_COMMAND up -d"
  exit 1
elif [[ "${MAILCOW_HOSTNAME: -1}" == "." ]]; then
  echo "MAILCOW_HOSTNAME (${MAILCOW_HOSTNAME}) is ending with a dot. This is not a valid FQDN!"
  exit 1
elif [ ${#DOTS} -eq 1 ]; then
  echo -e "\e[33mMAILCOW_HOSTNAME (${MAILCOW_HOSTNAME}) does not contain a Subdomain. This is not fully tested and may cause issues.\e[0m"
  echo "Find more information about why this message exists here: https://github.com/mailcow/mailcow-dockerized/issues/1572"
  read -r -p "Do you want to proceed anyway? [y/N] " response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    echo "OK. Proceeding."
  else
    echo "OK. Exiting."
    exit 1
  fi
fi

detect_bad_asn

if [[ ("${SKIP_PING_CHECK}" == "y") ]]; then
echo -e "\e[32mSkipping Ping Check...\e[0m"

else
   echo -en "Checking internet connection... "
   if ! check_online_status; then
      echo -e "\e[31mfailed\e[0m"
      exit 1
   else
      echo -e "\e[32mOK\e[0m"
   fi
fi

if [ ! "$FORCE" ]; then
  read -r -p "Are you sure you want to update mailcow: dockerized? All containers will be stopped. [y/N] " response
  if [[ ! "${response}" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    echo "OK, exiting."
    exit 0
  fi
  detect_major_update
fi

echo -e "\e[32mValidating docker-compose stack configuration...\e[0m"
sed -i 's/HTTPS_BIND:-:/HTTPS_BIND:-/g' docker-compose.yml
sed -i 's/HTTP_BIND:-:/HTTP_BIND:-/g' docker-compose.yml
if ! $COMPOSE_COMMAND config -q; then
  echo -e "\e[31m\nOh no, something went wrong. Please check the error message above.\e[0m"
  exit 1
fi

echo -e "\e[32mChecking for conflicting bridges...\e[0m"
MAILCOW_BRIDGE=$($COMPOSE_COMMAND config | grep -i com.docker.network.bridge.name | cut -d':' -f2)
while read NAT_ID; do
  iptables -t nat -D POSTROUTING "$NAT_ID"
done < <(iptables -L -vn -t nat --line-numbers | grep "$IPV4_NETWORK" | grep -E 'MASQUERADE.*all' | grep -v "${MAILCOW_BRIDGE}" | cut -d' ' -f1)

echo -e "\e[32mPrefetching images...\e[0m"
prefetch_images

echo -e "\e[32mStopping mailcow...\e[0m"
sleep 2
MAILCOW_CONTAINERS=($($COMPOSE_COMMAND ps -q))
$COMPOSE_COMMAND down
echo -e "\e[32mChecking for remaining containers...\e[0m"
sleep 2
for container in "${MAILCOW_CONTAINERS[@]}"; do
  docker rm -f "$container" 2> /dev/null
done

configure_ipv6

[[ -f data/conf/nginx/ZZZ-ejabberd.conf ]] && rm data/conf/nginx/ZZZ-ejabberd.conf
migrate_config_options
adapt_new_options

echo -e "\e[32mFetching new images, if any...\e[0m"
sleep 2
$COMPOSE_COMMAND pull

# Fix missing SSL, does not overwrite existing files
[[ ! -d data/assets/ssl ]] && mkdir -p data/assets/ssl
cp -n -d data/assets/ssl-example/*.pem data/assets/ssl/

echo -e "Checking IPv6 settings... "
if grep -q 'SYSCTL_IPV6_DISABLED=1' mailcow.conf; then
  echo
  echo '!! IMPORTANT !!'
  echo
  echo 'SYSCTL_IPV6_DISABLED was removed due to complications. IPv6 can be disabled by editing "docker-compose.yml" and setting "enable_ipv6: true" to "enable_ipv6: false".'
  echo "This setting will only be active after a complete shutdown of mailcow by running $COMPOSE_COMMAND down followed by $COMPOSE_COMMAND up -d."
  echo
  echo '!! IMPORTANT !!'
  echo
  read -p "Press any key to continue..." < /dev/tty
fi

# Checking for old project name bug
sed -i --follow-symlinks 's#COMPOSEPROJECT_NAME#COMPOSE_PROJECT_NAME#g' mailcow.conf

# Fix Rspamd maps
if [ -f data/conf/rspamd/custom/global_from_blacklist.map ]; then
  mv data/conf/rspamd/custom/global_from_blacklist.map data/conf/rspamd/custom/global_smtp_from_blacklist.map
fi
if [ -f data/conf/rspamd/custom/global_from_whitelist.map ]; then
  mv data/conf/rspamd/custom/global_from_whitelist.map data/conf/rspamd/custom/global_smtp_from_whitelist.map
fi

# Fix deprecated metrics.conf
if [ -f "data/conf/rspamd/local.d/metrics.conf" ]; then
  if [ ! -z "$(git diff --name-only origin/mailman3 data/conf/rspamd/local.d/metrics.conf)" ]; then
    echo -e "\e[33mWARNING\e[0m - Please migrate your customizations of data/conf/rspamd/local.d/metrics.conf to actions.conf and groups.conf after this update."
    echo "The deprecated configuration file metrics.conf will be moved to metrics.conf_deprecated after updating mailcow."
  fi
  mv data/conf/rspamd/local.d/metrics.conf data/conf/rspamd/local.d/metrics.conf_deprecated
fi

# Set app_info.inc.php
if [ ${BRANCH} == "mailman3" ]; then
  mailcow_git_version=$(git describe --tags $(git rev-list --tags --max-count=1))
elif [ ${BRANCH} == "nightly" ]; then
  mailcow_git_version=$(git rev-parse --short $(git rev-parse @{upstream}))
  mailcow_last_git_version=""
else
  mailcow_git_version=$(git rev-parse --short HEAD)
  mailcow_last_git_version=""
fi

mailcow_git_commit=$(git rev-parse "origin/${BRANCH}")
mailcow_git_commit_date=$(git log -1 --format=%ci @{upstream} )

if [ $? -eq 0 ]; then
  echo '<?php' > data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_VERSION="'$mailcow_git_version'";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_LAST_GIT_VERSION="";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_OWNER="mailcow";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_REPO="mailcow-dockerized";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_URL="https://github.com/siesta-it-admins/tsg-mailcow";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_COMMIT="'$mailcow_git_commit'";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_COMMIT_DATE="'$mailcow_git_commit_date'";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_BRANCH="'$BRANCH'";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_UPDATEDAT='$(date +%s)';' >> data/web/inc/app_info.inc.php
  echo '?>' >> data/web/inc/app_info.inc.php
else
  echo '<?php' > data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_VERSION="'$mailcow_git_version'";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_LAST_GIT_VERSION="";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_OWNER="mailcow";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_REPO="mailcow-dockerized";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_URL="https://github.com/siesta-it-admins/tsg-mailcow";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_COMMIT="";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_GIT_COMMIT_DATE="";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_BRANCH="'$BRANCH'";' >> data/web/inc/app_info.inc.php
  echo '  $MAILCOW_UPDATEDAT='$(date +%s)';' >> data/web/inc/app_info.inc.php
  echo '?>' >> data/web/inc/app_info.inc.php
  echo -e "\e[33mCannot determine current git repository version...\e[0m"
fi

if [[ ${SKIP_START} == "y" ]]; then
  echo -e "\e[33mNot starting mailcow, please run \"$COMPOSE_COMMAND up -d --remove-orphans\" to start mailcow.\e[0m"
else
  echo -e "\e[32mStarting mailcow...\e[0m"
  sleep 2
  $COMPOSE_COMMAND up -d --remove-orphans
fi

echo -e "\e[32mCollecting garbage...\e[0m"
docker_garbage

# Run post-update-hook
if [ -f "${SCRIPT_DIR}/post_update_hook.sh" ]; then
  bash "${SCRIPT_DIR}/post_update_hook.sh"
fi

# echo "In case you encounter any problem, hard-reset to a state before updating mailcow:"
# echo
# git reflog --color=always | grep "Before update on "
# echo
# echo "Use \"git reset --hard hash-on-the-left\" and run $COMPOSE_COMMAND up -d afterwards."
