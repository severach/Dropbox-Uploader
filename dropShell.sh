#!/usr/bin/env bash
#
# DropShell
#
# Copyright (C) 2013-2014 Andrea Fabrizi <andrea.fabrizi@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#

SHELL_HISTORY=~/.dropshell_history
VERSION='0.2'
# Packagers should sed the following to their distro: Arch Linux, Debian, Red Hat, Ubuntu, Gentoo, ...
BRANDING=''

#Looking for dropbox uploader
set -u
if [ -f './dropbox_uploader.sh' ]; then
  DU='./dropbox_uploader.sh'
else
  DU="$(which dropbox_uploader.sh)"
  if [ $? -ne 0 ]; then
    echo 'Dropbox Uploader not found!'
    exit 1
  fi
fi

#For MacOSX, install coreutils (which includes greadlink)
# $brew install coreutils
if [ "${OSTYPE:0:6}" == 'darwin' ]; then
  READLINK='greadlink'
else
  READLINK='readlink'
fi

if [ $# -eq 0 ]; then
  DU_OPT='' # '-q'
else
  DU_OPT="$*"
fi
BIN_DEPS="id ${READLINK} ls basename ls pwd cut"

umask 077

#Dependencies check
for i in ${BIN_DEPS}; do
  command -v "${i}" >/dev/null 2>&1 || {
    echo -e "Error: Required program could not be found: ${i}"
    exit 1
  }
done
unset i

#Check DropBox Uploader
if [ ! -f "${DU}" ]; then
  echo "Dropbox Uploader not found: "${DU}""
  echo "Please change the 'DU' variable according to the Dropbox Uploader location."
  exit 1
else
  DU="$("${READLINK}" -m ""${DU}"")"
fi
DUS="$(basename "$DU")"

#Returns the current user
get_current_user()
{
  id -nu
}

# $1: your CWD, which will only be used if $2 doesn't start with a /
# $2: your path. The path is normalized (-m) independent of the system
normalize_path()
{
  local new_path
  if [ "${2:0:1}" == '/' ]; then
    new_path="$("${READLINK}" -m "$2")"
  else
    new_path="$("${READLINK}" -m "$1/$2")"
  fi
  #Adding back the final slash, if present in the source
  if [[ "${2: -1}" == '/' && "${new_path: -1}" != '/' ]]; then
    new_path="${new_path}/"
  fi
  echo "${new_path}"
}

################
#### START  ####
################

echo -e "DropShell v${VERSION} ${BRANDING}"
echo -e 'The Interactive Dropbox SHELL'
echo -e 'Andrea Fabrizi - andrea.fabrizi@gmail.com\n'
echo -e 'Type help for the list of the available commands.\n'

history -r "${SHELL_HISTORY}"
username="$(get_current_user)"

#Initial Working Directory
CWD='/'

sh_ls()
{
  if [ "$2" == '.' ]; then
    local arg3="$3"
    #Listing current dir
    if [ -z "${arg3}" ]; then
      arg3="${CWD}"
    fi

    #Listing $3
    echo ${DUS} ${DU_OPT} list "$(normalize_path "${CWD}" "${arg3}")"
        "${DU}" ${DU_OPT} list "$(normalize_path "${CWD}" "${arg3}")"

    #Checking for errors
    if [ $? -ne 0 ]; then
      echo -e "$1: cannot access '${arg3}': No such file or directory"
    fi
    return 0
  fi
  echo -e "syntax: $1 [<REMOTE_DIR>]"
  echo -e "Show directory listing on dropbox"
}

sh_cd()
{
  if [ "$2" == '.' ]; then
    local NEW_CWD
    if [ -z "$3" ]; then
      NEW_CWD='/'
    else
      NEW_CWD="$(normalize_path "${CWD}" "$3/")"
    fi

    echo ${DUS} ${DU_OPT} list "${NEW_CWD}" > /dev/null
        "${DU}" ${DU_OPT} list "${NEW_CWD}" > /dev/null # This is dangerous. My dropbox has 120,000 files in it

    #Checking for errors
    if [ $? -ne 0 ]; then
      echo -e "$1: $3: No such file or directory"
    else
      CWD="${NEW_CWD}"
    fi
    return 0
  fi
  echo -e "syntax: $1 <REMOTE_DIR>"
  echo -e "Set current directory on dropbox"
}

sh_get()
{
  if [ "$2" == '.' ]; then
    if [ ! -z "$3" ]; then

      echo ${DUS} ${DU_OPT} download "$(normalize_path "${CWD}" "$3")" "$4"
          "${DU}" ${DU_OPT} download "$(normalize_path "${CWD}" "$3")" "$4"

      #Checking for errors
      if [ $? -ne 0 ]; then
        echo -e "$1: download error"
      fi
      return 0
    #args error
    else
      echo -e "$1: missing operand"
    fi
  fi
  echo -e "syntax: $1 <REMOTE_FILE*/DIR> <FILE/DIR>"
  echo -e 'download file from dropbox'
}

sh_put()
{
  if [ ! -z "$5" ]; then
    echo -e "$1 multiple does not work in the interactive shell.\n"
  elif [ "$2" == '.' ]; then
    if [ ! -z "$3" ]; then

      echo ${DUS} ${DU_OPT} upload "$3" "$(normalize_path "${CWD}" "$4")"
          "${DU}" ${DU_OPT} upload "$3" "$(normalize_path "${CWD}" "$4")"

      #Checking for errors
      if [ $? -ne 0 ]; then
        echo -e "$1: upload error"
      fi
      return 0
    #args error
    else
      echo -e "$1: missing operand"
    fi
  fi
  echo -e "syntax: $1 <FILE*/DIR> <REMOTE_FILE/DIR>"
  echo -e 'upload file to dropbox'
  echo -e "The uploader tool can handle multiple source files. This interactive shell can't."
}

sh_rm()
{
  if [ "$2" == '.' ]; then
    if [ ! -z "$3" ]; then

      echo ${DUS} ${DU_OPT} remove "$(normalize_path "${CWD}" "$3")" "$4"
          "${DU}" ${DU_OPT} remove "$(normalize_path "${CWD}" "$3")" "$4" # $4 is only there to cause errors

      #Checking for errors
      if [ $? -ne 0 ]; then
        echo -e "rm: cannot remove '$3'"
      fi
      return 0
    #args error
    else
      echo -e "$1: missing operand"
    fi
  fi
  echo -e "syntax: $1 <FILE/DIR>"
  echo -e "Erase file or folder on dropbox."
}

sh_mkdir()
{
  if [ "$2" == '.' ]; then
    if [ ! -z "$3" ]; then

      echo ${DUS} ${DU_OPT} mkdir "$(normalize_path "${CWD}" "$3")"
          "${DU}" ${DU_OPT} mkdir "$(normalize_path "${CWD}" "$3")"

      #Checking for errors
      if [ $? -ne 0 ]; then
        echo -e "$1: cannot create directory '$3'"
      fi
      return 0
    #args error
    else
      echo -e "$1: missing operand"
    fi
  fi
  echo -e "syntax: $1 <DIR_NAME>"
  echo -e 'Create directory on dropbox'
}

sh_cpmv()
{
  local CPYCMD; [[ "$1" = 'cp' ]] && CPYCMD='copy' || CPYCMD='move' # http://stackoverflow.com/questions/3953645/ternary-operator-in-bash
  if [ "$2" == '.' ]; then
    if [ ! -z "$3" -a ! -z "$4" ]; then

      echo ${DUS} ${DU_OPT} "${CPYCMD}" "$(normalize_path "${CWD}" "$3")" "$(normalize_path "${CWD}" "$4")"
          "${DU}" ${DU_OPT} "${CPYCMD}" "$(normalize_path "${CWD}" "$3")" "$(normalize_path "${CWD}" "$4")"

      #Checking for errors
      if [ $? -ne 0 ]; then
        echo -e "$1: cannot ${CPYCMD} '$3' to '$4'"
      fi
      return 0
    #args error
    else
      echo -e "$1: missing operand"
    fi
  fi
  echo -e "syntax: $1 <FILE/DIR> <DEST_FILE/DIR>"
  echo -e "${CPYCMD} from one dropbox file to another. Use get or put to copy from or to a local file."
}

sh_free()
{
  if [ "$2" == '.' ]; then
    echo ${DUS} ${DU_OPT} info
        "${DU}" ${DU_OPT} info | grep 'Free:' | cut -f 2
    return 0
  fi
  echo -e "syntax: $1"
  echo -e "Show free space on dropbox."
}

sh_cat_less()
{
  if [ "$2" == '.' ]; then
    if [ ! -z "$3" ]; then
      local tmp_cat="/tmp/${FUNCNAME}_${RANDOM}"
      echo sh_get "$(normalize_path "${CWD}" "$3")" "${tmp_cat}"
      sh_get "$(normalize_path "${CWD}" "$3")" "${tmp_cat}"
      $1 "${tmp_cat}"
      rm -fr "${tmp_cat}"
      return 0
    else #args error
      echo -e "$1: missing operand"
    fi
  fi
  echo -e "syntax: $1 <REMOTE FILE>"
  echo -e "Download and $1 file from dropbox. Both less and cat are available."
}

sh_lls()
{
  if [ "$2" == '.' ]; then
    ls -l
    return 0
  fi
  echo -e 'syntax: $1'
  echo -e 'Shows directory listing of current local directory'
}

sh_lpwd()
{
  if [ "$2" == '.' ]; then
    pwd
    return 0
  fi
  echo -e "syntax: $1"
  echo -e 'Shows current local directory for lls get put'
}

sh_lcd()
{
  if [ "$2" == '.' ]; then
    cd "$3"
    return 0
  fi
  echo -e "syntax: $1 <LOCAL DIRECTORY>"
  echo -e 'Changes local directory to the specified directory for lls get put'
}

sh_help()
{
  if [ "$2" != '.' ]; then
    echo -e "$1 $1: infinite loop... unwinding universe to top of stack! ;)"
  fi
  echo -e "try $1 <command> where command is something other than $1"
  echo 'Supported commands: ls, cd, pwd, get, put, cat, less, rm, mkdir, mv, cp, free, lls, lpwd, lcd, help, exit'
}

sh_exit()
{
  if [ "$2" == '.' ]; then
    set +u
    exit 0
  fi
  echo "syntax: $1"
  echo -e 'quit exit and bye are all the same'
}

sh_pwd()
{
  if [ "$2" == '.' ]; then
    echo "${CWD}"
    return 0
  fi
  echo "syntax: $1"
  echo -e 'Show working directory on dropbox'
}

DONE='false'
until "${DONE}"; do

  #Reading command from shell
  read -e -p "${username}@Dropbox:${CWD}$ " input || DONE='true' # handle ^D and EOF

  #Tokenizing command
  set -f # we don't do any globbing here. dropbox-uploader does it all.
  eval tokens=(${input})
  set +f
  set +u
  cmd="${tokens[0]}"
  arg1="${tokens[1]}"
  arg2="${tokens[2]}"
  arg3="${tokens[3]}"
  set -u
  if [[ "${cmd}" == 'help' || "${cmd}" == 'HELP' ]] && [[ ! -z "${arg1}" ]]; then
    HELPME='.help'
    cmd="${arg1}"
    arg1=''
    arg2=''
  else
    HELPME='.'
  fi

  #Saving command in the history file
  history -s "${input}"
  history -w "${SHELL_HISTORY}"

  case "${cmd}" in
    ls)         sh_ls "${cmd}" "${HELPME}" "${arg1}";;
    cd)         sh_cd "${cmd}" "${HELPME}" "${arg1}";;
    pwd)       sh_pwd "${cmd}" "${HELPME}" "${arg1}";;
    get)       sh_get "${cmd}" "${HELPME}" "${arg1}" "${arg2}";;
    put)       sh_put "${cmd}" "${HELPME}" "${arg1}" "${arg2}" "${arg3}";;
    rm)         sh_rm "${cmd}" "${HELPME}" "${arg1}" "${arg2}";;
    mkdir)   sh_mkdir "${cmd}" "${HELPME}" "${arg1}";;
    mv|cp)    sh_cpmv "${cmd}" "${HELPME}" "${arg1}" "${arg2}";;
    cat|less) sh_cat_less "${cmd}" "${HELPME}" "${arg1}";;
    free)     sh_free "${cmd}" "${HELPME}";;
    lls)       sh_lls "${cmd}" "${HELPME}";;
    lpwd)     sh_lpwd "${cmd}" "${HELPME}";;
    lcd)       sh_lcd "${cmd}" "${HELPME}" "${arg1}";;
    help)     sh_help "${cmd}" "${HELPME}";;
    quit|exit|bye) sh_exit "${cmd}" "${HELPME}";;
    *) test -z "${cmd}" || echo -ne "Unknown command: ${cmd}\n";;
  esac
done
