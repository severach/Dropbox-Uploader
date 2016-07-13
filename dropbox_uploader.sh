#!/usr/bin/env bash
#
# Dropbox Uploader
#
# Copyright (C) 2010-2015 Andrea Fabrizi <andrea.fabrizi@gmail.com>
# Copyright (C) 2015-2016 Chris Severance <severach.aur aATt spamgourmet.com>
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
# Primary Source: https://github.com/severach/Dropbox-Uploader
# Original Source: https://github.com/andreafabrizi/Dropbox-Uploader

set -u
#Default configuration file
CONFIG_FILE=~/'.dropbox_uploader'
CONFIG_FILE_BASE='dropbox-default'
CONFIG_FILE_FOPT=''

#Default chunk size in bytes for the upload process
#It is recommended to increase this value only if you have enough free space on your /tmp partition
#Lower values may increase the number of http requests
let CHUNK_SIZE=4*1048576  # must be a power of two >=4096
CHUNK_MAX=157286000

#Curl location
#If blank, curl will be searched into the $PATH
CURL_BIN='/usr/bin/curl'
CURL_BIN=''

#Default values
TMP_DIR='/tmp'
DEBUG=0
QUIET=0
SHOW_PROGRESSBAR=0
SKIP_EXISTING_FILES=0
ERROR_STATUS=0
CURL_ACCEPT_CERTIFICATES=''
DELETE_AFTER_PUTGET=0
SHORT_URL='false'
LOGFILE=''
RECURSE=0

# https://www.dropbox.com/developers/documentation/http/documentation
#Don't edit these...
#APIV1_REQUEST_TOKEN_URL='https://api.dropbox.com/1/oauth/request_token'
APIV2_REQUEST_TOKEN_URL='https://api.dropbox.com/oauth2/token'
#APIV1_USER_AUTH_URL='https://www.dropbox.com/1/oauth/authorize'
APIV2_USER_AUTH_URL='https://www.dropbox.com/oauth2/authorize'
APIV1_ACCESS_TOKEN_URL='https://api.dropbox.com/1/oauth/access_token'
APIV1_CHUNKED_UPLOAD_URL='https://api-content.dropbox.com/1/chunked_upload'
APIV1_CHUNKED_UPLOAD_COMMIT_URL='https://api-content.dropbox.com/1/commit_chunked_upload'
APIV2_CHUNKED_SESSION_START_URL='https://content.dropboxapi.com/2/files/upload_session/start'
APIV2_CHUNKED_SESSION_APPEND_URL='https://content.dropboxapi.com/2/files/upload_session/append_v2'
APIV2_CHUNKED_SESSION_FINISH_URL='https://content.dropboxapi.com/2/files/upload_session/finish'
APIV1_UPLOAD_URL='https://api-content.dropbox.com/1/files_put'
APIV2_UPLOAD_URL='https://content.dropboxapi.com/2/files/upload'
APIV1_DOWNLOAD_URL='https://api-content.dropbox.com/1/files'
APIV2_DOWNLOAD_URL='https://content.dropboxapi.com/2/files/download'
APIV1_DELETE_URL='https://api.dropbox.com/1/fileops/delete'
APIV2_DELETE_URL='https://api.dropboxapi.com/2/files/delete'
APIV1_MOVE_URL='https://api.dropbox.com/1/fileops/move'
APIV2_MOVE_URL='https://api.dropboxapi.com/2/files/move'
APIV1_COPY_URL='https://api.dropbox.com/1/fileops/copy'
APIV2_COPY_URL='https://api.dropboxapi.com/2/files/copy'
APIV1_METADATA_URL='https://api.dropbox.com/1/metadata'
APIV2_METADATA_URL='https://api.dropboxapi.com/2/files/get_metadata'
APIV2_LISTFOLDER_URL='https://api.dropboxapi.com/2/files/list_folder'
APIV1_INFO_URL='https://api.dropbox.com/1/account/info'
APIV2_INFO_URL='https://api.dropboxapi.com/2/users/get_current_account'
APIV2_QUOTA_URL='https://api.dropboxapi.com/2/users/get_space_usage'
APIV1_MKDIR_URL='https://api.dropbox.com/1/fileops/create_folder'
APIV2_MKDIR_URL='https://api.dropboxapi.com/2/files/create_folder'
APIV1_SHARES_URL='https://api.dropbox.com/1/shares'
APIV2_SHARES_URL='https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'
APIV2_SHARES_URL_OLD='https://api.dropboxapi.com/2/sharing/create_shared_link'
APP_CREATE_URL='https://www.dropbox.com/developers/apps'
RESPONSE_FILE="${TMP_DIR}/du_resp.$$_${RANDOM}"
#CHUNK_FILE="${TMP_DIR}/du_chunk.$$_${RANDOM}"
TEMP_FILE="${TMP_DIR}/du_tmp.$$_${RANDOM}"
BIN_DEPS='sed basename date grep stat dd mkdir'
VERSION='0.19c'
# Packagers should sed the following to their distro: Arch Linux, Debian, Red Hat, Ubuntu, Gentoo, ...
BRANDING=''
# Packagers should sed the following to the line that installs the ca certs. This line is for Debian Ubuntu
PACKAGE_CACERT_INSTALL='sudo apt-get install ca-certificates'

umask 077

#Check the shell
if [ -z "${BASH_VERSION}" ]; then
  echo -e 'Error: this script requires the BASH shell!'
  exit 1
fi

shopt -s nullglob #Bash allows filename patterns which match no files to expand to a null string, rather than themselves
shopt -s dotglob  #Bash includes filenames beginning with a "." in the results of filename expansion

#Look for optional config file parameter
while getopts ':qpskdf:EuL:r' opt; do
  case "${opt}" in
  'f') CONFIG_FILE="${OPTARG}"; CONFIG_FILE_BASE="$(basename "${CONFIG_FILE}")"; CONFIG_FILE_FOPT="-f $(printf '%q' "${CONFIG_FILE}") ";;
  'd') DEBUG=1;;
  'q') QUIET=1;;
  'p') SHOW_PROGRESSBAR=1;;
  'k') CURL_ACCEPT_CERTIFICATES='-k';;
  's') SKIP_EXISTING_FILES=1;;
  'E') DELETE_AFTER_PUTGET=1;;
  'u') SHORT_URL='true';;
  'L') LOGFILE="${OPTARG}";;
  'r') RECURSE=1;;
  '?' )
    echo "Invalid option: -${OPTARG}" >&2
    exit 1
  ;;

  ':')
    echo "Option -${OPTARG} requires an argument." >&2
    exit 1
  ;;

  esac
done

if [ "${DEBUG}" -ne 0 ]; then
  echo "${VERSION}"
  #set -x # this is too much!
  RESPONSE_FILE="${TMP_DIR}/du_resp_debug"
  CHUNK_SIZE=1048576; CHUNK_MAX=1048576 # This lets us debug chunking without having to send 150MB, must be a power of two >=4096
fi

if [ -z "${CURL_BIN}" ]; then
  CURL_BIN='curl'
  BIN_DEPS="${BIN_DEPS} ${CURL_BIN}"
fi

#Dependencies check
for i in ${BIN_DEPS}; do
  command -v "${i}" >/dev/null 2>&1 || {
    echo -e "Error: Required program could not be found: ${i}"
    exit 1
  }
done
unset i

#Check if readlink is installed and supports the -m option
#It's not necessary, so no problem if it's not installed
which readlink > /dev/null
if [ $? -eq 0 ] && [ "$(readlink -m "//test" 2> /dev/null)" = "/test" ]; then
  HAVE_READLINK=1
else
  HAVE_READLINK=0
fi

#Forcing to use the builtin printf, if it's present, because it's better
#otherwise the external printf program will be used
#Note that the external printf command can cause character encoding issues!
builtin printf '' 2> /dev/null
if [ $? -eq 0 ]; then
  PRINTF='builtin printf'
  PRINTF_OPT='-v o'
else
  PRINTF="$(which printf)"
  if [ $? -ne 0 ]; then
    echo -e 'Error: Required program could not be found: printf'
  fi
  PRINTF_OPT=''
fi

#Print the message based on ${QUIET} variable
#$1: 0=not for log, 1=for log, 2=for log, precede with date, 3=for log only, 4=for log only, precede with date
#$2: 0=routine line suppressed with -q, 1=important line, must be shown to stderr if not debug
#$3 some fluff text. a leading string that does not get printed to the log
#$4 some text. must include \n where desired
#cannot use print, is zsh shell builtin, and too hard to search for
db_print()
{
  if [ "$1" -le 2 ]; then
    if [ "${QUIET}" -eq 0 ]; then
      echo -ne "$3$4"
    elif [ "$2" -ne 0 ]; then
      echo -ne "$3$4" 1>&2
    fi
  fi
  if [ ! -z "${LOGFILE}" ] && [ "$1" -ne 0 ]; then
    if [ "$1" -eq 2 ] || [ "$1" -eq 4 ];  then
      echo -ne "$(date +"%F %T") $4" >> "${LOGFILE}"
    else
      echo -ne "$4" >> "${LOGFILE}"
    fi
  fi
}

#Returns unix timestamp
utime()
{
  echo "$(date +%s)"
}

#Remove temporary files
remove_temp_files()
{
  if [ "${DEBUG}" -eq 0 ]; then
    rm -f "${RESPONSE_FILE}.header" "${RESPONSE_FILE}.data"
    #rm -f "${CHUNK_FILE}"
    rm -f "${TEMP_FILE}"
  fi
}

#Returns the file size in bytes
# Generic GNU Linux: linux-gnu
# Windows Cygwin:    cygwin
# Raspberry Pi:      linux-gnueabihf
# Mac OS X:          darwin10.0
# FreeBSD:           FreeBSD
# QNAP:              linux-gnueabi
# iOS:               darwin9
file_size()
{
  #Some embedded Linux devices
  case "${OSTYPE}" in
  linux-gnueabi|linux-gnu)
    stat -c '%s' "$1"
    return
    ;;

  #Generic Unix
  linux*|cygwin|solaris*)
    stat --format='%s' "$1"
    return
    ;;

  esac
  #BSD, OSX and other OSs
  stat -f '%z' "$1"
}

#Usage
usage()
{
  echo -e "Dropbox Uploader v${VERSION} ${BRANDING}"
  echo -e 'Andrea Fabrizi - andrea.fabrizi@gmail.com Chris Severance - severach.aur@spamgourmet.com\n'
  echo -e "Usage: $0 COMMAND [PARAMETERS]..."
  echo -e '\nCommands:'

  echo -e '\t upload   <LOCAL_FILE*/DIR ...>  <REMOTE_FILE/DIR>'
  echo -e '\t  (upload to dir faster with trailing slash)'
  echo -e '\t download <REMOTE_FILE*/DIR> [LOCAL_FILE/DIR]'
  echo -e '\t delete   <REMOTE_FILE/DIR> (no globbing, see -E)'
  echo -e '\t move   <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>'
  echo -e '\t copy   <REMOTE_FILE/DIR> <REMOTE_FILE/DIR>'
  echo -e '\t mkdir  <REMOTE_DIR>'
  echo -e '\t list   [REMOTE_DIR]'
  echo -e '\t share  <REMOTE_FILE>'
  echo -e '\t info'
  echo -e '\t unlink (from dropbox)'

  echo -e '\nOptional parameters:'
  echo -e '\t-f <FILENAME> Load the configuration file from a specific file'
  echo -e '\t-s      Skip already existing files when download/upload. Default: Overwrite'
  echo -e '\t-d      Enable DEBUG mode'
  echo -e "\t-q      Quiet mode. Don't show messages"
  echo -e '\t-p      Show cURL progress meter'
  echo -e "\t-k      Doesn't check for SSL certificates (insecure)"
  echo -e "\t-E      Delete file after successful upload/download"
  echo -e "\t-u      Return short urls"
  echo -e "\t-r      Recurse upload/download"
  echo -e "\t-L      Log transfers and errors (looks like lftp log)"

  echo -e "\nEXIT CODE: 0 for success, 1 for soft or hard failure"

  echo -en 'For more info and examples, please see the README file.'
  remove_temp_files
  exit 1
}

#Check the curl exit code
check_http_response()
{
  CODE="$?"

  #Checking curl exit code
  case "${CODE}" in

    #OK
    0)

    ;;

    #Proxy error
    5)
      db_print 2 1 '\n' "Error: Couldn't resolve proxy. The given proxy host could not be resolved.\n"

      remove_temp_files
      exit 1
    ;;

    #Missing CA certificates
    60|58)
      db_print 2 1 '\n' "Error: cURL is not able to performs peer SSL certificate verification.
Please, install the default ca-certificates bundle.
Try:
  ${PACKAGE_CACERT_INSTALL}

If the problem persists, try the -k option (insecure).\n"

      remove_temp_files
      exit 1
    ;;

    6)
      db_print 2 1 '\n' "Error: Couldn't resolve host.\n"

      remove_temp_files
      exit 1
    ;;

    7)
      db_print 2 1 '\n' "Error: Couldn't connect to host.\n"

      remove_temp_files
      exit 1
    ;;

  esac

  #Checking response file for generic errors
  if grep -q '^HTTP/1.1 400' "${RESPONSE_FILE}.header"; then
    ERROR_MSG="$(cat "${RESPONSE_FILE}.data")"

    case "${ERROR_MSG}" in
    *access?attempt?failed?because?this?app?is?not?configured?to?have*)
      db_print 2 1 '\n' "Error: The Permission type/Access level configured doesn't match the DropBox App settings!\nPlease run \"$0 ${CONFIG_FILE_FOPT}unlink\" and try again."
      remove_temp_files
      exit 1
      ;;
    esac

  fi
  if [ "${CFG_APIVER}" -eq 1 ]; then
    if grep -q '^HTTP/1.1 403 Forbidden' "${RESPONSE_FILE}.header"; then
      if grep -qiF 'This app is currently disabled' "${RESPONSE_FILE}.data"; then
        db_print 2 1 '\n' "Error: Invalid access keys!\nPlease run \"$0 ${CONFIG_FILE_FOPT}unlink\" and try again."
        remove_temp_files
        exit 1
      fi
    fi
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    if grep -q '^HTTP/1.1 401 Unauthorized' "${RESPONSE_FILE}.header"; then
      if grep -qF 'invalid_access_token/' "${RESPONSE_FILE}.data"; then
        db_print 2 1 '\n' "Error: Invalid access token!\nPlease run \"$0 ${CONFIG_FILE_FOPT}unlink\" and try again."
        remove_temp_files
        exit 1
      fi
    fi
  fi

}

#Urlencode
urlencode()
{
  local string="$1"
  local strlen="${#string}"
  local encoded=''
  local o=''

  for (( pos=0 ; pos<strlen ; pos++ )); do
    c="${string:$pos:1}"
    case "${c}" in
      [-_.~a-zA-Z0-9] ) o="${c}" ;;
      * ) ${PRINTF} ${PRINTF_OPT} '%%%02x' "'${c}"
    esac
    encoded+="${o}"
  done

  echo "${encoded}"
}

#clean up paths, if available
normalize_path()
{
  local path="$(echo -e "$1")"
  if [ "${HAVE_READLINK}" -ne 0 ]; then
    local new_path="$(readlink -m "$path")"

    #Adding back the final slash, if present in the source
    if [ "${new_path: -1}" != '/' ] && [ "${path: -1}" = '/' ]; then
      new_path="${new_path}/"
    fi

    echo "${new_path}"
  else
    echo "${path}"
  fi
}

#Check if $1 is a file or directory on dropbox
#Returns FILE/DIR/ERR
#Some functions use the RESPONSE_FILE.
#if stat a dir then the response file contains it's subdir listing
#This can take a long time if a dir is large so avoid db_stat where possible
db_stat()
{
  local FILE="$(normalize_path "$1")"

  # Can't do this here. makes download unreliable. let upload do this itself
  #if [ "${FILE: -1}" = '/' ]; then
  #  echo 'DIR'
  #  return
  #fi
  # API v2 not permitted to stat / for metadata. Test this with 'download /'
  if [ "${CFG_APIVER}" -eq 2 ] && [ "${FILE}" = '/' ]; then
    echo 'DIR'
    return
  fi

  #Checking if it's a file or a directory
  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" "${APIV1_METADATA_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" 2> /dev/null
    check_http_response

    #Even if the file/dir has been deleted from DropBox we receive a 200 OK response
    #So we must check if the file exists or if it has been deleted
    if grep -q '"is_deleted":' "${RESPONSE_FILE}.data"; then
      local IS_DELETED="$(sed -n 's/.*"is_deleted":.\([^,]*\).*/\1/p' "${RESPONSE_FILE}.data")"
    else
      local IS_DELETED='false'
    fi

    #Exits...
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header" && [ "${IS_DELETED}" != 'true' ]; then

      local IS_DIR="$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "${RESPONSE_FILE}.data")" # '

      # It's a directory
      if [ ! -z "${IS_DIR}" ]; then
        echo 'DIR'
      #It's a file
      else
        echo 'FILE'
      fi

    #Doesn't exists
    else
      echo 'ERR'
    fi
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    # stat faster and more reliable in API v2.
    # No longer need to read entire dir to get stat on dir
    local FILE_EX
    if [ "${FILE}" = '/' ]; then
      FILE_EX=''
    else
      FILE_EX="${FILE}"
    fi
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" "${APIV2_METADATA_URL}" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data '{"path": "'"${FILE_EX}"'","include_media_info": false,"include_deleted": false,"include_has_explicit_shared_members": false}' 2> /dev/null
    check_http_response

    #Exits...
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
      # It's a directory
      if grep -q '^{".tag": "folder"' "${RESPONSE_FILE}.data"; then
        echo 'DIR'
      #It's a file
      elif grep -q '^{".tag": "file"' "${RESPONSE_FILE}.data"; then
        echo 'FILE'
      # missing file no longer gives http error. Error found in response
      else
        echo 'ERR'
      fi
    #Doesn't exists
    else
      echo 'ERR'
    fi
  fi
}

# https://www.gnu.org/software/findutils/manual/html_node/find_html/Shell-Pattern-Matching.html
# fnmatch 'ab \?def' 'ab ?def'    && echo 'matched' # \ supported
# fnmatch 'ab ?def' 'ab cdef'     && echo 'matched' # ? supported
# fnmatch 'ab [cd]def' 'ab cdef'  && echo 'matched' # [] supported
# fnmatch 'ab {c,d}def' 'ab cdef' && echo 'matched' # case does not support brace expansion. It's not globbing so shouldn't be supported.
# fnmatch 'ab c*' 'ab cdef'       && echo 'matched' # space supported
# fnmatch 'ab) c*' 'ab) cdef'     && echo 'matched' # ) supported, does not interfere with case
# space compatible shell string matching (globbing) with string variables entirely in POSIX, not the worthless non string only crap [[ $foo == abc* ]] that bash gives us!
# Local files are globbed with find. fnmatch lets us glob dropbox files.
# $1 = GLOB string: 'ab c*'
# $2 = file to be matched 'ab cdef'
# a blank glob matches everything
fnmatch () { [ -z "$1" ] && return 0; case "$2" in $1) return 0 ;; esac; return 1 ; } # works in sh,bash, not in zsh due to autoquoting; http://www.etalabs.net/sh_tricks.html

#Generic upload wrapper around db_upload_file and db_upload_dir functions
#$1 = recursion level 0,1,2,...
#$2 = Local source file/dir
#$3 = Glob if sending a folder
#$4 = Remote destination file/dir
#dbtop functions are named so we know these are called directly by the main loop
#This can be called recursively
dbtop_upload()
{
  #set -x
  local SRC="$(normalize_path "$2")"
  local GLOB="$3"
  local DST="$(normalize_path "$4")"

  #Checking if the file/dir exists
  if [ -d "${SRC}" ]; then
    if [ "${SRC: -1}" != '/' ]; then
      SRC="${SRC}/"
    fi
  elif [ ! -e "${SRC}" ]; then
    db_print 2 1 ' > ' "No such file or directory: ${SRC}\n"
    ERROR_STATUS=1
    return
  fi

  #echo "$FUNCNAME: SRC=${SRC}"; echo "$FUNCNAME: GLOB=${GLOB}"; echo "$FUNCNAME: DST=${DST}"

  #Checking if the file/dir has read permissions
  if [ ! -r "${SRC}" ]; then
    db_print 2 1 ' > ' "Error reading file ${SRC}: permission denied\n"
    ERROR_STATUS=1
    return
  fi

  local TYPE
  if [ "${DST: -1}" = '/' ]; then
    TYPE='DIR'
  elif [ ! -z "${GLOB}" ]; then
    TYPE='DIR'
    # globbing requires DST as folder. This is dangerous in that dropbox overwrites files with folders without warning.
    DST="${DST}/"
  else
    TYPE="$(db_stat "${DST}")" # This can be slow on large dropbox folders so add slash on end of dirs when possible.
  fi

  #If DST it's a file, do nothing, it's the default behaviour
  if [ "${TYPE}" = 'FILE' ]; then
    :
  #if DST doesn't exists
  elif [ "${TYPE}" = 'ERR' ]; then
    # and doesn't ends with a /, it will be the destination file name
    if [ "${DST: -1}" != '/' ]; then
      :
    # and ends with a /, and SRC not ends with a /, it will be the destination folder
    elif [ "${SRC: -1}" != '/' ]; then
      DST="${DST}/$(basename "${SRC}")"
    fi
  #If DST it's directory, it will be the destination folder
  elif [ "${TYPE}" = 'DIR' ]; then
    # Can't use SRC if it's a pure dir
    if [ "${SRC: -1}" != '/' ]; then
      DST="${DST}/$(basename "${SRC}")"
    fi
  fi

  #SRC it's a directory.
  if [ -d "${SRC}" ]; then
    if [ $1 -eq 0 ] || [ "${RECURSE}" -ne 0 ]; then
      local DIR_SRC="${SRC}" # "$(normalize_path "$2")"
      local DIR_DST="${DST}" # "$(normalize_path "$3")"

      # Make folder here to dup all blank folders
      local DIR_MADE=0

      local FILE
      for FILE in "${DIR_SRC}/"*; do
        if [ -f "${FILE}" ] && fnmatch "${GLOB}" "$(basename "${FILE}")"; then
          #Creating remote directory
          if [ "${DIR_MADE}" -eq 0 ]; then
            dbtop_mkdir "${DIR_DST}"
            if [ "${ERROR_STATUS}" -ne 0 ]; then
              break
            fi
            DIR_MADE=1
          fi
          dbtop_upload $(($1+1)) "${FILE}" "${GLOB}" "${DIR_DST}/"
        elif [ ! -z "${GLOB}" ] && [ -d "${FILE}" ]; then
          dbtop_upload $(($1+1)) "${FILE}/" "${GLOB}" "${DIR_DST}/$(basename "${FILE}")/"
        fi
        if [ "${ERROR_STATUS}" -ne 0 ]; then
          break
        fi
      done
      #not good to lose local folder structure. Some might want this for $RECURSE>0
      #if [ "${DELETE_AFTER_PUTGET}" -ne 0 ]; then
      #  rmdir "${DIR_SRC}" && db_print 0 0 ' > ' "Deleted ${DIR_SRC}\n"
      #fi
    fi

    #It's a file
  elif [ -e "${SRC}" ]; then
    db_upload_file "${SRC}" "${DST}"

  #Unsupported object...
  else
    db_print 2 1 ' > ' "Skipping not regular file \"${SRC}\"\n"
  fi
}

#Generic upload wrapper around db_chunked_upload_file and db_simple_upload_file
#The final upload function will be chosen based on the file size
#$1 = Local source file
#$2 = Remote destination file
db_upload_file()
{
  local FILE_SRC="$(normalize_path "$1")"
  local FILE_DST="$(normalize_path "$2")"

  shopt -s nocasematch

  #Checking not allowed file names
  basefile_dst="$(basename "${FILE_DST}")"
  if [ "${basefile_dst}" = 'thumbs.db'   ] || \
     [ "${basefile_dst}" = 'desktop.ini' ] || \
     [ "${basefile_dst}" = '.ds_store'   ] || \
     [ "${basefile_dst}" = 'icon\r'      ] || \
     [ "${basefile_dst}" = '.dropbox'    ] || \
     [ "${basefile_dst}" = '.dropbox.attr' ]; then  \
    db_print 0 0 ' > ' "Skipping not allowed file name \"${FILE_DST}\"\n"
    return
  fi

  shopt -u nocasematch

  #Checking if the file already exists
  if [ "${SKIP_EXISTING_FILES}" -ne 0 ]; then
    local TYPE="$(db_stat "${FILE_DST}")"
    if [ "${TYPE}" != 'ERR' ]; then
      db_print 2 1 ' > ' "Skipping already existing file \"${FILE_DST}\"\n"
      return
    fi
  fi

  #Checking file size
  local FILE_SIZE="$(file_size "${FILE_SRC}")"

  if [ "${FILE_SIZE}" -gt "${CHUNK_MAX}" ]; then
    #If the file is greater than 150Mb, the chunked_upload API will be used
    db_chunked_upload_file "${FILE_SRC}" "${FILE_DST}"
  else
    db_simple_upload_file  "${FILE_SRC}" "${FILE_DST}"
  fi

}

#Simple file upload
#$1 = Local source file
#$2 = Remote destination file
db_simple_upload_file()
{
  local FILE_SRC="$(normalize_path "$1")"
  local FILE_DST="$(normalize_path "$2")"

  if [ "${SHOW_PROGRESSBAR}" -eq 1 ] && [ "${QUIET}" -eq 0 ]; then
    local CURL_PARAMETERS='--progress-bar'
    local LINE_CR='\n'
  else
    local CURL_PARAMETERS='-s'
    local LINE_CR=''
  fi

  if [ ! -z "${LOGFILE}" ]; then
    db_print 4 0 '' "${FILE_SRC} -> ${CONFIG_FILE_BASE}:/${FILE_DST} 0-$(file_size "${FILE_SRC}")"
  fi
  db_print 0 0 '' " > Uploading \"${FILE_SRC}\" to \"${FILE_DST}\"... ${LINE_CR}"
  local UPLOAD_ERROR=0
  while :; do
    if [ "${CFG_APIVER}" -eq 1 ]; then
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} ${CURL_PARAMETERS} --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --upload-file "${FILE_SRC}" "${APIV1_UPLOAD_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE_DST}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}"
    elif [ "${CFG_APIVER}" -eq 2 ]; then
      # Dropbox does not support transparent compression. I tried compressed --header 'Content-Type: application/gzip'
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} ${CURL_PARAMETERS} -X 'POST' --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        --header 'Dropbox-API-Arg: {"path": "'"${FILE_DST}"'","mode": "overwrite","autorename": false,"mute": false}' \
        --header 'Content-Type: application/octet-stream' \
        --upload-file "${FILE_SRC}" \
        "${APIV2_UPLOAD_URL}"
        # --data-binary "@${FILE_SRC}"
    fi
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
      db_print 1 0 '' ' DONE\n'
      if [ "${DELETE_AFTER_PUTGET}" -ne 0 ]; then
        rm -f "${FILE_SRC}"HTTP/1.1 500 Internal Server Error
        db_print 0 0 '' " > Deleted ${FILE_SRC}\n"
      fi
    # This hasn't been checked for APIv1
    elif  [ "${UPLOAD_ERROR}" -le 2 ] && grep -q '^HTTP/1.1 500 Internal Server Error' "${RESPONSE_FILE}.header"; then
      let UPLOAD_ERROR=${UPLOAD_ERROR}+1
      if [ "${DEBUG}" -ne 0 ]; then
        echo "Error ${UPLOAD_ERROR}, waiting 3" 1>&2
      fi
      sleep 3
      continue
    else
      cat "${RESPONSE_FILE}.header" "${RESPONSE_FILE}.data" >> '/tmp/du_resp_debug_upload' # DEBUG_LINE figure out why some uploads are failing
      db_print 1 0 '' ' FAILED\n'
      db_print 0 0 '' 'An error occurred requesting /upload\n'
      ERROR_STATUS=1
    fi
    break
  done
}

#Chunked file upload
#$1 = Local source file
#$2 = Remote destination file
db_chunked_upload_file()
{
  local FILE_SRC="$(normalize_path "$1")"
  local FILE_DST="$(normalize_path "$2")"
  local FILE_SIZE="$(file_size "${FILE_SRC}")"

  db_print 4 0 '' "${FILE_SRC} -> ${CONFIG_FILE_BASE}:/${FILE_DST} 0-${FILE_SIZE} "
  db_print 0 0 '' " > Uploading \"${FILE_SRC}\" to \"${FILE_DST}\" "

  local OFFSET=0
  local UPLOAD_ID=''
  local UPLOAD_ERROR=0
  local APIV1_CHUNK_PARAMS
  local APIV2_CHUNKED_CMD_URL
  local APIV2_API_ARG
  local DD_BS
  local DD_SKIP
  local DD_COUNT
  #local APIV2_CLOSE

  #Uploading chunks...
  while [ "${OFFSET}" -lt "${FILE_SIZE}" ]; do

    #let OFFSET_CHK=${OFFSET}/${CHUNK_SIZE}
    #db_print 0 0 '' " Chunk #${OFFSET_CHK} @${OFFSET}+${CHUNK_SIZE}\n"

    let DD_SKIP=OFFSET/4096
    if (( OFFSET+CHUNK_SIZE >= FILE_SIZE )); then
      # less optimal buffering.
      let DD_BS=4096
      let DD_COUNT=(FILE_SIZE-OFFSET)/4096+1 # No need to be exact at EOF
      APIV1_CHUNK_PARAMS="upload_id=${UPLOAD_ID}&offset=${OFFSET}"
      APIV2_CHUNKED_CMD_URL="${APIV2_CHUNKED_SESSION_FINISH_URL}"
      APIV2_API_ARG='Dropbox-API-Arg: {"cursor": {"session_id": "'"${UPLOAD_ID}"'","offset": '"${OFFSET}"'},"commit": {"path": "'"${FILE_DST}"'","mode": "overwrite","autorename": false,"mute": false}}'
    elif [ "${OFFSET}" -ne 0 ]; then
      # This math requires that CHUNK_SIZE be a power of two >=4096
      let DD_BS=4096
      let DD_COUNT=CHUNK_SIZE/4096
      APIV1_CHUNK_PARAMS="upload_id=${UPLOAD_ID}&offset=${OFFSET}"
      APIV2_CHUNKED_CMD_URL="${APIV2_CHUNKED_SESSION_APPEND_URL}"
      APIV2_API_ARG='Dropbox-API-Arg: {"cursor": {"session_id": "'"${UPLOAD_ID}"'","offset": '"${OFFSET}"'},"close": false}'
    else
      let DD_BS=4096
      let DD_COUNT=CHUNK_SIZE/4096
      #Only for the first request these parameters are not included
      APIV1_CHUNK_PARAMS=''
      APIV2_CHUNKED_CMD_URL="${APIV2_CHUNKED_SESSION_START_URL}"
      APIV2_API_ARG='Dropbox-API-Arg: {"close": false}'
    fi

    #Uploading the chunk, now using pipe for best value on limited performance machines...
    if [ "${CFG_APIVER}" -eq 1 ]; then
      dd if="${FILE_SRC}" bs="${DD_BS}" skip="${DD_SKIP}" count="${DD_COUNT}" 2> /dev/null | \
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --upload-file - "${APIV1_CHUNKED_UPLOAD_URL}?${APIV1_CHUNK_PARAMS}&oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" 2> /dev/null
    elif [ "${CFG_APIVER}" -eq 2 ]; then
      dd if="${FILE_SRC}" bs="${DD_BS}" skip="${DD_SKIP}" count="${DD_COUNT}" 2> /dev/null | \
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        --header "${APIV2_API_ARG}" \
        --header 'Content-Type: application/octet-stream' \
        --upload-file - \
      "${APIV2_CHUNKED_CMD_URL}" 2> /dev/null
      # --data-binary @-
    fi
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
      db_print 1 0 '' '.'
      UPLOAD_ERROR=0
      if [ "${CFG_APIVER}" -eq 1 ]; then
        UPLOAD_ID="$(sed -n 's/.*"upload_id": *"*\([^"]*\)"*.*/\1/p' "${RESPONSE_FILE}.data")" # '
        OFFSET="$(sed -n 's/.*"offset": *\([^}]*\).*/\1/p' "${RESPONSE_FILE}.data")"
        #db_print 0 0 '' "ID {$UPLOAD_ID} offset=${OFFSET}\n"
      elif [ "${CFG_APIVER}" -eq 2 ]; then
        if [ "${OFFSET}" -eq 0 ]; then 
          UPLOAD_ID="$(sed -n 's/.*"session_id": *"*\([^"]*\)"*.*/\1/p' "${RESPONSE_FILE}.data")" # ' # 2/files/upload_session/append_v2 doesn't return anything. All we see is "null" 7/1/2016
        fi
        let OFFSET+=CHUNK_SIZE
      fi
    else
      db_print 1 0 '' '*'
      let UPLOAD_ERROR=${UPLOAD_ERROR}+1

      #On error, the upload is retried for max 3 times
      if [ "${DEBUG}" -ne 0 ] || [ "${UPLOAD_ERROR}" -gt 2 ]; then
        db_print 1 1 ' ' ' FAILED\n'
        db_print 0 0 '' 'An error occurred requesting /chunked_upload\n'
        ERROR_STATUS=1
        return
      fi
    fi

  done

  UPLOAD_ERROR=0

  #Commit the upload
  while :; do
    if [ "${CFG_APIVER}" -eq 1 ]; then
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "upload_id=${UPLOAD_ID}&oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${APIV1_CHUNKED_UPLOAD_COMMIT_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE_DST}")" 2> /dev/null
      check_http_response
    elif [ "${CFG_APIVER}" -eq 2 ]; then
      UPLOAD_ERROR=99999 # Reuse RESPONSE_FILE above. Prevent any more retries
    fi

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
      db_print 1 0 '' '$'
      UPLOAD_ERROR=0
      break
    else
      db_print 1 0 '' 'E'
      let UPLOAD_ERROR=${UPLOAD_ERROR}+1

      #On error, the commit is retried for max 3 times
      if [ "${DEBUG}" -ne 0 ] || [ "${UPLOAD_ERROR}" -gt 2 ]; then
        db_print 1 1 ' ' ' FAILED\n'
        db_print 0 0 '' 'An error occurred requesting /commit_chunked_upload\n'
        ERROR_STATUS=1
        return
      fi
    fi

  done

  db_print 1 0 '' ' DONE\n'
  if [ "${DELETE_AFTER_PUTGET}" -ne 0 ]; then
    rm -f "${FILE_SRC}"
    db_print 0 0 '' " > Deleted ${FILE_SRC}\n"
  fi
}

#Interesting function, not used anywhere, therefore not converted to APIV2. Similar to dbtop_account_info()
#Returns the free space on DropBox in bytes
db_free_quota()
{
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${APIV1_INFO_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then

    local quota="$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}.data")"
    local used="$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}.data")"
    local free_quota
    let free_quota=${quota}-${used}
    echo "${free_quota}"

  else
    echo 0
  fi
}

#Generic download wrapper
#$1 = recursion level 0...
#$2 = Remote source file/dir
#$3 = Glob if sending a folder
#$4 = Local destination file/dir
#This may be called recursively
dbtop_download()
{
  local SRC="$(normalize_path "$2")"
  local GLOB="$3"
  local DST="$(normalize_path "$4")"

  #If the DST folder is not specified, I assume that is the current directory
  if [ -z "${DST}" ]; then
    DST="$(normalize_path "./")"
  fi

  #Checking if the file/dir exists
  if [ ! -z "${DST}" ] && [ -d "${DST}" ]; then
    if [ "${DST: -1}" != '/' ]; then
      DST="${DST}/"
    fi
  fi

  if [ "${DEBUG}" -ne 0 ]; then
    echo "$FUNCNAME: SRC=${SRC}"; echo "$FUNCNAME: GLOB=${GLOB}"; echo "$FUNCNAME: DST=${DST}"
  fi

  local TYPE
  # we don't trust user calling from level 0. Level 1+ from dropbox trusted.
  # In APIV1 we must db_stat even if already known as dir. Back comes directory as side affect needed below
  if [ "${CFG_APIVER}" -ne 1 ] && [ "$1" -gt 0 ] && [ "${SRC: -1}" = '/' ]; then
    TYPE='DIR'
  else
    TYPE="$(db_stat "${SRC}")"
  fi

  if [ "${DEBUG}" -ne 0 ]; then
    echo "$FUNCNAME: SRC TYPE=${TYPE}"
  fi

  # check for globbing
  #if [ "${TYPE}" = 'ERR' ] && [ "${SRC: -1}" != '/' ]; then # basename refuses to return blank with a trailing slash
  #  GLOB="$(basename "${SRC}")"
  #   SRC="$(dirname  "${SRC}")"
  #  TYPE="$(db_stat  "${SRC}")"
  #  if [ "${TYPE}" != 'DIR' ]; then
  #    db_print 1 1 ' > ' "Directory component is file or missing: ${SRC}\n"
  #    ERROR_STATUS=1
  #    return
  #  fi
  #fi
  #It's a directory
  if [ "${TYPE}" = 'DIR' ]; then

    #Checking if the destination directory exists
    local basedir
    if [ ! -d "${DST}" ] || [ ! -z "${GLOB}" ]; then
      basedir=''
    else
      basedir="$(basename "${SRC}")"
    fi

    if [ "${DEBUG}" -ne 0 ]; then
      echo "$FUNCNAME: basedir=${basedir}"
    fi

    local DEST_DIR="$(normalize_path "${DST}/${basedir}")"
    if [ "${DEBUG}" -ne 0 ]; then
      echo "$FUNCNAME: DEST_DIR=${DEST_DIR}"
    fi
    #if [ ! -d "${DEST_DIR}" ]; then
    #  db_print 2 0 ' > ' "Creating local directory \"${DEST_DIR}\"... "
    #  mkdir -p "${DEST_DIR}"

    #  #Check
    #  if [ $? -eq 0 ] && [ -d "${DEST_DIR}" ]; then
    #    db_print 1 0 '' 'DONE\n'
    #  else
    #    db_print 1 0 '' 'FAILED\n'
    #    ERROR_STATUS=1
    #    return
    #  fi
    #fi
    db_print 0 0 ' > ' "Downloading folder \"${SRC}\" to \"${DEST_DIR}\"... \n"

    #Extracting files and subfolders
    local TMP_DIR_CONTENT_FILE="${RESPONSE_FILE}.$1._${RANDOM}"
    #echo -e "$FUNCNAME: RESPONSE_FILE=${RESPONSE_FILE}\nTMP_DIR_CONTENT_FILE=${TMP_DIR_CONTENT_FILE}\nPress Enter"; read x

    if [ "${CFG_APIVER}" -eq 1 ]; then
      #1 Discard all but subdirectory content [...], last line from db_stat response
      #2 Separate each entry with \n, replacing "}, {" with "}\n{", allowing sed to process lines
      #3 Discard all but file:is_dir false=file, true=dir
      #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
      # This data file is left over from db_stat().
      sed -n -e 's/.*: \[{\(.*\)/\1/p' "${RESPONSE_FILE}.data" | \
      sed    -e 's/}, *{/}\
{/g' | \
      sed -n -e 's/.*"path": *"\([^"]*\)",.*"is_dir": *\([^"]*\),.*/\2:\1/p' > "${TMP_DIR_CONTENT_FILE}"
      rm -f "${RESPONSE_FILE}.data"
      printf "\n" >> "${TMP_DIR_CONTENT_FILE}"
    elif [ "${CFG_APIVER}" -eq 2 ]; then
      # In APIV2 db_stat does not make a folder listing so we need to do it manually.
      local DIR_SRC_EX
      if [ "${SRC}" = "/" ]; then
        DIR_SRC_EX=''
      else
        DIR_SRC_EX="${SRC}"
      fi
      # Limit 2000 files
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        --header 'Content-Type: application/json' \
        --data '{"path": "'"${DIR_SRC_EX}"'","recursive": false,"include_media_info": false,"include_deleted": false,"include_has_explicit_shared_members": false}' \
        "${APIV2_LISTFOLDER_URL}" 2> /dev/null
      check_http_response
      sed -e 's:{".tag":\n&:g' -e 's/}], "cursor":/}], \n"cursor":/g' "${RESPONSE_FILE}.data" | \
      sed -n -e 's/^{"\.tag":\s\+"\([^"]\+\)",.*"path_display":\s\+"\([^"]\+\)",.*$/\1:\2/p' > "${TMP_DIR_CONTENT_FILE}"
    fi

    #For each entry...
    local FILE
    while read -r line; do

      if [ ! -z "${line}" ]; then
        TYPE="${line%:*}"
        FILE="${line#*:}"

        #Removing all path info on dirs (basename)
        FILE="${FILE##*/}"

        if [ "${TYPE}" = 'false' ] || [ "${TYPE}" = 'file' ]; then
          if fnmatch "${GLOB}" "${FILE}"; then
            db_download_file "${SRC}/${FILE}" "${DEST_DIR}/${FILE}"
            if [ "${ERROR_STATUS}" -ne 0 ]; then
              return
            fi
          fi
        elif [ "${RECURSE}" -ne 0 ]; then
          dbtop_download $(($1+1)) "${SRC}/${FILE}/" "${GLOB}" "${DEST_DIR}/${FILE}"
          # should we abort recursive copy on ERROR_STATUS here?
        fi
      fi

    done < "${TMP_DIR_CONTENT_FILE}"
    if [ "${DEBUG}" -eq 0 ]; then
      rm -f "${TMP_DIR_CONTENT_FILE}"
    fi

  #It's a file
  elif [ "${TYPE}" = 'FILE' ]; then

    #Checking DST
    if [ -z "${DST}" ]; then
      DST="$(basename "${SRC}")"
    fi

    #If the destination is a directory, the file will be download into
    if [ -d "${DST}" ]; then
      DST="${DST}/$(basename "${SRC}")"
    fi

    db_download_file "${SRC}" "${DST}"

  #Doesn't exists
  else
    db_print 2 1 ' > ' "No such file or directory: ${SRC}\n"
    ERROR_STATUS=1
    return
  fi
}

#Simple file download
#$1 = Remote source file
#$2 = Local destination file
db_download_file()
{
  local FILE_SRC="$(normalize_path "$1")"
  local FILE_DST="$(normalize_path "$2")"
  local DEST_DIR="$(dirname "${FILE_DST}")" # DEST_DIR cannot be used if FILE_DST ends in a slash

  if [ "${DEBUG}" -ne 0 ]; then
    echo "$FUNCNAME: FILE_SRC=${FILE_SRC}"; echo "$FUNCNAME: FILE_DST=${FILE_DST}"; echo "$FUNCNAME: DEST_DIR=${DEST_DIR}"
  fi

  if [ "${FILE_DST: -1}" = '/' ]; then
    DEST_DIR='/' # Nullify this variable to ensure it doesn't get used later
    if [ -f "${FILE_DST:: -1}" ]; then
      db_print 2 1 ' > ' "Unable to overwrite existing file ${FILE_DST:: -1}\n"
      ERROR_STATUS=1
      return
    fi
    if [ ! -d "${FILE_DST:: -1}" ]; then
      db_print 0 0 '' " > Creating folder ${FILE_DST:: -1}\n"
      mkdir -p "${FILE_DST:: -1}"
      if [ ! -d "${FILE_DST:: -1}" ]; then
        db_print 2 1 ' > ' "Unable to create folder ${FILE_DST}\n"
        ERROR_STATUS=1
        return
      fi
    fi
    FILE_DST="${FILE_DST}$(basename "${FILE_SRC}")"
  elif [ ! -d "${DEST_DIR}" ]; then
    db_print 2 0 ' > ' "Creating local directory \"${DEST_DIR}\"... "
    #Check
    if mkdir -p "${DEST_DIR}" 2>/dev/null && [ -d "${DEST_DIR}" ]; then
      db_print 1 0 '' 'DONE\n'
    else
      db_print 1 0 '' 'FAILED\n'
      ERROR_STATUS=1
      return
    fi
  fi

  if [ "${SHOW_PROGRESSBAR}" -eq 1 ] && [ "${QUIET}" -eq 0 ]; then
    local CURL_PARAMETERS='--progress-bar'
    local LINE_CR='\n'
  else
    local CURL_PARAMETERS='-s'
    local LINE_CR=''
  fi

  #Checking if the file already exists
  if [ -e "${FILE_DST}" ] && [ "${SKIP_EXISTING_FILES}" -eq 1 ]; then
    db_print 2 1 ' > ' "Skipping already existing file \"${FILE_DST}\"\n"
    return
  fi

  #Creating the empty file, that for two reasons:
  #1) In this way I can check before download if the destination file is writeable or not
  #2) Curl doesn't automatically creates files with 0 bytes size
  if ! dd if=/dev/zero of="${FILE_DST}" count=0 2> /dev/null; then
    db_print 2 1 ' > ' "Error writing file ${FILE_DST}: permission denied\n"
    ERROR_STATUS=1
    return
  fi

  if [ ! -z "${LOGFILE}" ]; then
    db_print 4 0 '' "${CONFIG_FILE_BASE}:/${FILE_SRC} -> ${FILE_DST} "
  fi
  db_print 0 0 '' " > Downloading \"${FILE_SRC}\" to \"${FILE_DST}\"... ${LINE_CR}"
  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} ${CURL_PARAMETERS} --globoff -D "${RESPONSE_FILE}.header" -o "${FILE_DST}" "${APIV1_DOWNLOAD_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE_SRC}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}"
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    # Transfer compression is not supported --tr-encoding
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' ${CURL_PARAMETERS} --globoff -D "${RESPONSE_FILE}.header" -o "${FILE_DST}" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      --header 'Dropbox-API-Arg: {"path": "'"${FILE_SRC}"'"}' \
      "${APIV2_DOWNLOAD_URL}"
  fi
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
    db_print 3 0 '' "0-$(file_size "${FILE_DST}") "
    db_print 1 0 '' 'DONE\n'
    if [ "${DELETE_AFTER_PUTGET}" -ne 0 ]; then
      dbtop_delete "${FILE_SRC}"
    fi
  else
    db_print 1 1 '' 'FAILED\n'
    rm -f "${FILE_DST}"
    ERROR_STATUS=1
    return
  fi
}

# $1 number to print. Will be scaled down to print KiB, MiB, GiB, TiB as appropriate
printmb()
{
  if [ "$1" -ge 10000000000000 ]; then
    echo -n "$(($1/1099511627776)) TiB"
  elif [ "$1" -ge 10000000000 ]; then
    echo -n "$(($1/1073741824)) GiB"
  elif [ "$1" -ge 10000000 ]; then
    echo -n "$(($1/1048576)) MiB"
  elif [ "$1" -ge 10000 ]; then
    echo -n "$(($1/1024)) KiB"
  else
    echo -n "$1"
  fi
}

#Prints account info
dbtop_account_info()
{
  db_print 0 0 '' "Dropbox Uploader v${VERSION}\n\n"
  db_print 0 0 '' ' > Getting info... '
  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${APIV1_INFO_URL}" 2> /dev/null
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then

      local name="$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      echo -e "\n\nName:\t${name}"

      local uid="$(sed -n 's/.*"uid": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      echo -e "UID:\t${uid}"

      local email="$(sed -n 's/.*"email": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      echo -e "Email:\t${email}"

      local quota="$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      local quota_mb
      let quota_mb=${quota}/1024/1024
      echo -e "Quota:\t${quota_mb} Mb"

      local used="$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      local used_mb
      let used_mb=${used}/1024/1024
      echo -e "Used:\t${used_mb} Mb"

      local free_mb
      let free_mb=(${quota}-${used})/1024/1024
      echo -e "Free:\t$free_mb Mb"

      echo ''
    else
      db_print 1 1 '' 'FAILED\n'
      ERROR_STATUS=1
    fi
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      "${APIV2_INFO_URL}"
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then

      local name="$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      echo -e "\n\nName:\t${name}"

      local uid="$(sed -n 's/.*"account_id": "\([^"]*\)".*/\1/p' "${RESPONSE_FILE}.data")" # '
      echo -e "UID:\t${uid}"

      local email="$(sed -n 's/.*"email": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}.data")"
      echo -e "Email:\t${email}"

      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.quotaheader" -o "${RESPONSE_FILE}.quotadata" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        "${APIV2_QUOTA_URL}"
      check_http_response

      if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.quotaheader"; then
        # Yet another json parser
        local line="$(grep '^{"used":' "${RESPONSE_FILE}.quotadata")"
        line="${line//{/ { }" 
        line="${line//\}/ \} }" 
        local level=0
        local item
        local pitem=''
        for item in ${line}; do
          case "${item}" in
          '{') let level=level+1;;
          '}') let level=level-1;; # This should be down below but for our purposes its not necessary
          esac
          case "${pitem}" in
          '');;
          '"used":')
            if [ "${level}" -eq 1 ]; then
              local used="${item%,}"
            fi
            if [ "${level}" -eq 2 ]; then
              local typeused="${item%,}"
            fi
            ;;
          '".tag"')
            local type="${item%\",}"
            type="${type#\"}"
            ;;
          '"allocated":') local quota="${item}";;
          esac
          pitem="${item}"
        done

        echo -e "Quota:\t$(printmb "${quota}")"
        echo -e "Used:\t$(printmb "${used}")"
        echo -e "Free:\t$(printmb "$((quota-used))")" # "

        echo ''
      else
        db_print 1 1 '' 'INCOMPLETE\n'
      fi
      if [ "${DEBUG}" -eq 0 ]; then
        rm -f "${RESPONSE_FILE}.quotaheader" "${RESPONSE_FILE}.quotadata"
      fi
    else
      db_print 1 1 '' 'FAILED\n'
      ERROR_STATUS=1
    fi
  fi
}

#Account unlink
dbtop_unlink()
{
  echo -ne 'Are you sure you want unlink this script from your Dropbox account? [y/n]'
  local answer
  read answer
  if [ "${answer,,}" = 'y' ]; then
    echo rm -f "${CONFIG_FILE}"
    rm -f "${CONFIG_FILE}"
    echo -ne 'DONE\n'
  fi
}

#Delete a remote file or folder (rmdir)
#$1 = Remote file to delete
dbtop_delete()
{
  local FILE_DST="$(normalize_path "$1")"

  if [ ! -z "${LOGFILE}" ]; then
    db_print 4 0 '' "Deleting ${CONFIG_FILE_BASE}:/${FILE_DST} "
  fi
  db_print 0 0 ' > ' "Deleting \"${FILE_DST}\"... "
  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&path=$(urlencode "${FILE_DST}")" "${APIV1_DELETE_URL}" 2> /dev/null
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data '{"path": "'"${FILE_DST}"'"}' \
      "${APIV2_DELETE_URL}"
  fi
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
    db_print 1 0 '' 'DONE\n'
  else
    db_print 1 0 '' 'FAILED\n'
    ERROR_STATUS=1
  fi
}

#Move/Rename a remote file
#$1 = Remote file to rename or move
#$2 = New file name or location
dbtop_move()
{
  local FILE_SRC="$(normalize_path "$1")"
  local FILE_DST="$(normalize_path "$2")"

  local TYPE="$(db_stat "${FILE_DST}")"

  #If the destination it's a directory, the source will be moved into it
  if [ "${TYPE}" = 'DIR' ]; then
    local filename="$(basename "${FILE_SRC}")"
    FILE_DST="$(normalize_path "${FILE_DST}/${filename}")"
  fi

  if [ ! -z "${LOGFILE}" ]; then
    db_print 4 0 '' "Moving ${CONFIG_FILE_BASE}:/${FILE_SRC} -> ${FILE_DST} 0-? "
  fi
  db_print 0 0 ' > ' "Moving \"${FILE_SRC}\" to \"${FILE_DST}\" ... "
  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&from_path=$(urlencode "${FILE_SRC}")&to_path=$(urlencode "${FILE_DST}")" "${APIV1_MOVE_URL}" 2> /dev/null
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data '{"from_path": "'"${FILE_SRC}"'","to_path": "'"${FILE_DST}"'"}' \
      "${APIV2_MOVE_URL}"
  fi
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
    db_print 1 0 '' 'DONE\n'
  else
    db_print 1 1 '' 'FAILED\n'
    ERROR_STATUS=1
  fi
}

#Copy a remote file to a remote location
#$1 = Remote file to copy
#$2 = New file name or location
dbtop_copy()
{
  local FILE_SRC="$(normalize_path "$1")"
  local FILE_DST="$(normalize_path "$2")"

  local TYPE="$(db_stat "${FILE_DST}")"

  #If the destination it's a directory, the source will be copied into it
  if [ "${TYPE}" = 'DIR' ]; then
    local filename="$(basename "${FILE_SRC}")"
    FILE_DST="$(normalize_path "${FILE_DST}/${filename}")"
  fi

  if [ ! -z "${LOGFILE}" ]; then
    db_print 4 0 '' "Copying ${CONFIG_FILE_BASE}:/${FILE_SRC} -> ${FILE_DST} 0-? "
  fi
  db_print 0 0 ' > ' "Copying \"${FILE_SRC}\" to \"${FILE_DST}\" ... "
  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&from_path=$(urlencode "${FILE_SRC}")&to_path=$(urlencode "${FILE_DST}")" "${APIV1_COPY_URL}" 2> /dev/null
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data '{"from_path": "'"${FILE_SRC}"'","to_path": "'"${FILE_DST}"'"}' \
      "${APIV2_COPY_URL}"
  fi
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
    db_print 1 0 '' 'DONE\n'
  else
    db_print 1 0 '' 'FAILED\n'
    ERROR_STATUS=1
  fi
}

#Create a new directory
#$1 = Remote directory to create
dbtop_mkdir()
{
  local DIR_DST="$(normalize_path "$1")"

  if [ "${DIR_DST}" != '/' ]; then
    db_print 0 0 '' " > Creating Directory \"${DIR_DST}\"... "
    if [ "${CFG_APIVER}" -eq 1 ]; then
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&path=$(urlencode "${DIR_DST}")" "${APIV1_MKDIR_URL}" 2> /dev/null
      check_http_response

      #Check
      if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
        db_print 0 0 '' 'DONE\n'
      elif grep -q '^HTTP/1.1 403 Forbidden' "${RESPONSE_FILE}.header"; then
        # .data does not report whether it's a folder or file so we must stat it. Overwrites .header .data
        if [ "$(db_stat "${DIR_DST}")" = 'FILE' ]; then 
          db_print 0 0 '' 'ALREADY EXISTS FILE\n'
          ERROR_STATUS=1
        else
          db_print 0 0 '' 'ALREADY EXISTS\n'
        fi
      else
        db_print 0 0 '' 'FAILED\n'
        ERROR_STATUS=1
      fi
    elif [ "${CFG_APIVER}" -eq 2 ]; then
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        --header 'Content-Type: application/json' \
        --data '{"path": "'"${DIR_DST}"'"}' \
        "${APIV2_MKDIR_URL}"
      check_http_response

      #Check
      if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
        db_print 0 0 '' 'DONE\n'
      elif grep -q '^HTTP/1.1 409 Conflict' "${RESPONSE_FILE}.header"; then
        if grep -qF 'path/conflict/file/' "${RESPONSE_FILE}.data"; then 
          db_print 0 0 '' 'ALREADY EXISTS FILE\n'
          ERROR_STATUS=1
        else
          db_print 0 0 '' 'ALREADY EXISTS\n'
        fi
      else
        db_print 0 0 '' 'FAILED\n'
        ERROR_STATUS=1
      fi
    fi
  fi
}

# TODO: /2/files/list_folder/continue
#List remote directory
#$1 = Remote directory
dbtop_list()
{
  local DIR_DST="$(normalize_path "$1")"

  db_print 0 0 '' " > Listing \"${DIR_DST}\"... "
  if [ "${CFG_APIVER}" -eq 1 ]; then
    # APIV1 limit 10000 files
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" "${APIV1_METADATA_URL}/${ACCESS_LEVEL}/$(urlencode "${DIR_DST}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" 2> /dev/null
    check_http_response
    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then

      local IS_DIR="$(sed -n -e 's/^\(.*\)\"contents":.\[.*/\1/p' "${RESPONSE_FILE}.data")" # '

      #It's a directory
      if [ ! -z "${IS_DIR}" ]; then

        db_print 0 0 '' 'DONE\n'

        #Extracting directory content [...]
        #and replacing "}, {" with "}\n{"
        #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
        local DIR_CONTENT="$(sed -n 's/.*: \[{\(.*\)/\1/p' "${RESPONSE_FILE}.data" | sed 's/}, *{/}\
{/g')"

        #Converting escaped quotes to unicode format
        echo "${DIR_CONTENT}" | sed 's/\\"/\\u0022/' > "${TEMP_FILE}"

        #Extracting files and subfolders
        rm -f "${RESPONSE_FILE}.data"
        local line
        local FILE
        local SIZE
        while read -r line; do

          FILE="$(echo "$line" | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p')" # '
          IS_DIR="$(echo "$line" | sed -n 's/.*"is_dir": *\([^,]*\).*/\1/p')"
          SIZE="$(echo "$line" | sed -n 's/.*"bytes": *\([0-9]*\).*/\1/p')"

          echo -e "${FILE}:${IS_DIR};${SIZE}" >> "${RESPONSE_FILE}.data"

        done < "${TEMP_FILE}"

        #Looking for the biggest file size
        #to calculate the padding to use
        local padding=0
        local META
        while read -r line; do
          FILE="${line%:*}"
          META="${line##*:}"
          SIZE="${META#*;}"

          if [ "${padding}" -lt "${#SIZE}" ]; then
            padding="${#SIZE}"
          fi
        done < "${RESPONSE_FILE}.data"

        #For each entry, printing directories...
        local TYPE
        while read -r line; do

          FILE="${line%:*}"
          META="${line##*:}"
          TYPE="${META%;*}"
          SIZE="${META#*;}"

          #Removing unneeded /
          FILE="${FILE##*/}"

          if [ "${TYPE}" = 'true' ]; then
            FILE="$(echo -e "${FILE}")"
            ${PRINTF} " [D] %-${padding}s %s\n" "${SIZE}" "${FILE}"
          fi

        done < "${RESPONSE_FILE}.data"

        #For each entry, printing files...
        while read -r line; do

          FILE="${line%:*}"
          META="${line##*:}"
          TYPE="${META%;*}"
          SIZE="${META#*;}"

          #Removing unneeded /
          FILE="${FILE##*/}"

          if [ "${TYPE}" = 'false' ]; then
            FILE="$(echo -e "${FILE}")"
            ${PRINTF} " [F] %-${padding}s %s\n" "${SIZE}" "${FILE}"
          fi

        done < "${RESPONSE_FILE}.data"

      #It's a file
      else
        db_print 0 0 '' "FAILED: ${DIR_DST} is not a directory!\n"
        ERROR_STATUS=1
      fi

    else
      db_print 0 0 '' 'FAILED\n'
      ERROR_STATUS=1
    fi
  else
    local DIR_DST_EX
    if [ "${DIR_DST}" = "/" ]; then
      DIR_DST_EX=''
    else
      DIR_DST_EX="${DIR_DST}"
    fi
    # Limit 2000 files
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
      --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
      --header 'Content-Type: application/json' \
      --data '{"path": "'"${DIR_DST_EX}"'","recursive": false,"include_media_info": false,"include_deleted": false,"include_has_explicit_shared_members": false}' \
      "${APIV2_LISTFOLDER_URL}" 2> /dev/null
    check_http_response
    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then

      #It's a directory
      if grep -q '^{"entries": \[' "${RESPONSE_FILE}.data"; then

        db_print 0 0 '' 'DONE\n'

        #Extracting directory content [...]
        #and replacing .tag with "\n"
        # Here follows Cthulhu's json parser http://stackoverflow.com/questions/1732348/regex-match-open-tags-except-xhtml-self-contained-tags/1732454#1732454
        local DIR_CONTENT="$(sed -e 's:{".tag":\n&:g' -e 's/}], "cursor":/}], \n"cursor":/g' "${RESPONSE_FILE}.data")"

        #Converting escaped quotes to unicode format
        echo "${DIR_CONTENT}" | sed 's/\\"/\\u0022/' > "${TEMP_FILE}"

        #Extracting files and subfolders
        rm -f "${RESPONSE_FILE}.dir" "${RESPONSE_FILE}.file"

        # We can get padding and sort dirs on top of files in just 2 stages
        #Looking for the biggest file size to calculate the padding to use.
        local padding=0
        local line
        local FILE
        local IS_DIR
        local SIZE
        while read -r line; do

          FILE="$(echo "$line" | sed -n -e 's/.*"path_display": *"\([^"]*\)".*/\1/p')" # '
          IS_DIR="$(echo "$line" | sed -n -e 's/.*".tag": *"\([^"]*\)".*/\1/p')" # '

          if [ "${IS_DIR}" = 'folder' ]; then
            IS_DIR='[D]'
            # File goes last because it might contain : delimiter
            echo -e "${IS_DIR}:0:${FILE}" >> "${RESPONSE_FILE}.dir"
          elif [ "${IS_DIR}" = 'file' ]; then
            IS_DIR='[F]'
            SIZE="$(echo "${line}" | sed -n -e 's/.*"size": *\([0-9]*\).*/\1/p')"
            echo -e "${IS_DIR}:${SIZE}:${FILE}" >> "${RESPONSE_FILE}.file"
            if [ "${padding}" -lt "${#SIZE}" ]; then
              padding="${#SIZE}"
            fi
          fi
        done < "${TEMP_FILE}"

        if [ -s "${RESPONSE_FILE}.file" ]; then
          cat "${RESPONSE_FILE}.file" >> "${RESPONSE_FILE}.dir"
          if [ "${DEBUG}" -eq 0 ]; then
            rm -f "${RESPONSE_FILE}.file"
          fi
        fi

        #For each entry
        local TYPE
        local META
        while read -r line; do
          TYPE="${line%%:*}"
          META="${line#*:}"
          SIZE="${META%%:*}"
          FILE="${META#*:}"

          #Removing unneeded /
          FILE="${FILE##*/}"
          FILE="$(echo -e "${FILE}")"
          ${PRINTF} " %s %-${padding}s %s\n" "${TYPE}" "${SIZE}" "${FILE}"

        done < "${RESPONSE_FILE}.dir"
        if [ "${DEBUG}" -eq 0 ]; then
          rm -f "${RESPONSE_FILE}.dir"
        fi
        if grep -qF '"has_more": true' "${TEMP_FILE}"; then
          db_print 0 0 '' " Too many files in folder\n"
        fi

      #It's a file
      else
        db_print 0 0 '' "FAILED: ${DIR_DST} is not a directory!\n"
        ERROR_STATUS=1
      fi

    else
      db_print 0 0 '' 'FAILED\n'
      ERROR_STATUS=1
    fi
  fi
}

#Share remote file
#$1 = Remote file
dbtop_share()
{
  local FILE_DST="$(normalize_path "$1")"

  if [ "${CFG_APIVER}" -eq 1 ]; then
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" "$APIV1_SHARES_URL/${ACCESS_LEVEL}/$(urlencode "${FILE_DST}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&short_url=${SHORT_URL}" 2> /dev/null
  elif [ "${CFG_APIVER}" -eq 2 ]; then
    if [ "${SHORT_URL}" = 'true' ]; then
      # We use the deprecated API to get the short URL.
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        --header 'Content-Type: application/json' \
        --data '{"path": "'"${FILE_DST}"'","short_url": true}' \
        "${APIV2_SHARES_URL_OLD}" 2> /dev/null
   else
      "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -X 'POST' -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
        --header "Authorization: Bearer ${CFG_ACCESS_TOKEN}" \
        --header 'Content-Type: application/json' \
        --data '{"path": "'"${FILE_DST}"'","settings": {"requested_visibility": "public"}}' \
        "${APIV2_SHARES_URL}" 2> /dev/null
    fi
  fi
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}.header"; then
    db_print 0 0 '' ' > Share link: '
    SHARE_LINK="$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}.data")"
    echo "${SHARE_LINK}"
  else
    db_print 0 0 '' 'FAILED\n'
    ERROR_STATUS=1
  fi
}

################
#### SETUP  ####
################

db_setup()
{
  #CHECKING FOR AUTH FILE
  if [ -s "${CONFIG_FILE}" ]; then

    # API v2 config items
    CFG_APIVER=''
    CFG_ACCESS_TOKEN=''
    # API v1 config items
    #Back compatibility with previous Dropbox Uploader versions
    APPKEY=''
    APPSECRET=''
    ACCESS_LEVEL=''
    OAUTH_ACCESS_TOKEN=''
    OAUTH_ACCESS_TOKEN_SECRET=''

    #Loading data... and change old format config if necessary.
    source "${CONFIG_FILE}" 2>/dev/null || {
      sed -i'' -e 's/:/=/' "${CONFIG_FILE}" && source "${CONFIG_FILE}" 2>/dev/null
    }

    if [ -z "${CFG_APIVER}" ]; then
      CFG_APIVER=1
    fi
    #Checking the loaded data
    case "${CFG_APIVER}" in
    1)
      if [ -z "${APPKEY}" ] || [ -z "${APPSECRET}" ] || [ -z "${OAUTH_ACCESS_TOKEN_SECRET}" ] || [ -z "${OAUTH_ACCESS_TOKEN}" ]; then
        echo -ne "Error loading Dropbox API v1 data from ${CONFIG_FILE}...\n"
        echo -ne "It is recommended to run $0 ${CONFIG_FILE_FOPT}unlink\n"
        remove_temp_files
        exit 1
      fi
      #Back compatibility with previous Dropbox Uploader versions
      if [ -z "${ACCESS_LEVEL}" ]; then
        ACCESS_LEVEL='dropbox'
      fi
      db_print 0 1 '\n' "Warning: Dropbox API Version 1 expires June 28, 2017\nFor uninterrupted service reauthorize your account with\n  $0 ${CONFIG_FILE_FOPT}unlink\n  $0 ${CONFIG_FILE_FOPT}info\n\n"
      ;;
    2)
      if [ -z "${CFG_ACCESS_TOKEN}" ]; then
        echo -ne "Error loading Dropbox API v2 data  from ${CONFIG_FILE}...\n"
        echo -ne "It is recommended to run $0 ${CONFIG_FILE_FOPT}unlink\n"
        remove_temp_files
        exit 1
      fi
      ;;
    esac
    return # success!
  fi

  echo -ne '\n This is the first time you run this script.\n\n'
  echo -ne " 1) Open the following URL in your Browser, and log in using your account: ${APP_CREATE_URL}\n"
  echo -ne 'You can select an existing app and go directly to # App key\n'
  echo -ne ' 2) Click on "Create App", then select "Dropbox API app"\n'
  echo -ne ' 3) Now go on with the configuration, choosing the app permissions and access restrictions to your DropBox folder\n'
  echo -ne ' 4) Enter the "App Name" that you prefer '"(e.g. DoxBashUploader${RANDOM}${RANDOM}${RANDOM})\n\n"

  echo -ne ' Now, click on the "Create App" button.\n\n'

  echo -ne ' When your new App is successfully created, please type the\n'
  echo -ne ' App key and App Secret shown in the confirmation page:\n\n'

  #Getting the app key and secret from the user
  while :; do
    echo -n ' # App key (15 characters a-z 0-9): '
    read APPKEY
    if [ "${#APPKEY}" -ne 15 ]; then
      echo -ne "\n An app key must be 15 characters long\n"
      continue
    fi
    # Careful checking eliminates the need to urlencode()
    if [[ ! "${APPKEY}" =~ ^[0-9a-z]{15}$ ]]; then
      echo -ne "\n An app key must consist of a-z and 0-9 as shown on the DropBox app page\n"
      continue
    fi
    break
  done

  echo -ne '\n Tip: To copy in Firefox, double click holding mouse down, and hit Ctrl-C to copy\n'
  while :; do
    echo -n ' # App secret (15 characters a-z 0-9): '
    read APPSECRET
    if [ "${#APPSECRET}" -ne 15 ]; then
      echo -ne "\n An app secret must be 15 characters long\n"
      continue
    fi
    if [[ ! "${APPSECRET}" =~ ^[0-9a-z]{15}$ ]]; then
      echo -ne "\n An app secret must consist of a-z and 0-9\n"
      continue
    fi
    break
  done

  echo -ne " \n Please visit ${APIV2_USER_AUTH_URL}?client_id=${APPKEY}&response_type=code\n"
  echo -ne ' Authorize this app and enter or paste the long code that appears\n\n'

  while :; do
    echo -n ' # Auth code (43 characters A-Z a-z 0-9): '
    local AUTHCODE
    read AUTHCODE
    if [ "${#AUTHCODE}" -ne 43 ]; then
      echo -ne "\n An auth code must be 43 characters long\n"
      continue
    fi
    if [[ ! "${AUTHCODE}" =~ ^[-0-9a-zA-Z_]{43}$ ]]; then
      echo -ne "\n An auth code must consist of a-z and 0-9 as shown on the DropBox authorize_submit page\n"
      continue
    fi
    break
  done
  
  #TOKEN REQUESTS, APIV2 only, APIV1 code removed.
  echo -ne '\n > Token request... '
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -D "${RESPONSE_FILE}.header" -o "${RESPONSE_FILE}.data" \
    --data "code=${AUTHCODE}&grant_type=authorization_code&client_id=${APPKEY}&client_secret=${APPSECRET}" \
    "${APIV2_REQUEST_TOKEN_URL}" 2> /dev/null
  CFG_APIVER=0 # block error checking
  check_http_response
  # Sample {"access_token": "ABCDEFG", "token_type": "bearer", "account_id": "dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc", "uid": "12345"}
  CFG_ACCESS_TOKEN="$(sed -n -e 's/^.\+"access_token": "\([^"]*\)".*$/\1/p' "${RESPONSE_FILE}.data")" # '

  if [ -z "${CFG_ACCESS_TOKEN}" ]; then
    echo -ne ' FAILED\n\n Please, check your App key and secret...\n\n'
    cat "${RESPONSE_FILE}.data"
    remove_temp_files
    exit 1
  fi
  echo -ne 'OK\n'
  #Saving data in new format, compatible with source command.
  cat > "${CONFIG_FILE}" << EOF
# Dropbox configuration for dropbox-uploader
# Created $(date +'%F %T')
CFG_APIVER=2
CFG_ACCESS_TOKEN='${CFG_ACCESS_TOKEN}'
EOF
  echo -ne '\n Setup completed!\n'
  exit ${ERROR_STATUS}
}

################
#### START  ####
################

COMMAND="${@:$OPTIND:1}"
ARG1="${@:$OPTIND+1:1}"
ARG2="${@:$OPTIND+2:1}"
ARG3="${@:$OPTIND+3:1}"

let argnum=$#-${OPTIND}

#CHECKING PARAMS VALUES
case "${COMMAND}" in

  upload)
    db_setup

    if [ "${argnum}" -lt 2 ]; then
      usage
    fi

    FILE_DST="${@:$#:1}"
    #ALL_FILE_FND=0

    for (( i=${OPTIND}+1; i<$#; i++ )); do
      #FILE_FND=0
      FILE_SRC_NMPT="${@:${i}:1}"
      if [ "${FILE_SRC_NMPT: -1}" != '/' ] && [ ! -e "${FILE_SRC_NMPT}" ] && [ ! -d "${FILE_SRC_NMPT}" ] && [ "${FILE_SRC_NMPT//[[*?\]]/}" != "${FILE_SRC_NMPT}" ]; then
        FILE_SRC_GLOB="$(basename "${FILE_SRC_NMPT}")"
        FILE_SRC_NMPT="$(dirname "${FILE_SRC_NMPT}")/"
        if [ -d "${FILE_SRC_NMPT}" ]; then
          echo dbtop_upload 0 "${FILE_SRC_NMPT}" "${FILE_SRC_GLOB}" "/${FILE_DST}"
          dbtop_upload 0 "${FILE_SRC_NMPT}" "${FILE_SRC_GLOB}" "/${FILE_DST}"
        else
          db_print 2 1 ' > ' "No such file or directory: ${@:${i}:1}\n"
          ERROR_STATUS=1
        fi
      else
        echo dbtop_upload 0 "${FILE_SRC_NMPT}" '' "/${FILE_DST}"
        dbtop_upload 0 "${FILE_SRC_NMPT}" '' "/${FILE_DST}"
      fi
      #set +x
      # Old version, no cooperation with dbtop_upload so didn't work right!
      # 1. Use find since I hadn't found how to get bash to shell match from a string
      # 2. Find a way to get the result securely line by line without being inside of a subshell where we lose access to our functions and can't add 1 to our counters.
      # http://stackoverflow.com/questions/8677546/bash-for-in-looping-on-null-delimited-string-variable
      if ! :; then
        FILE_SRC_DIR='.'
        FILE_SRC_BASE="${@:${i}:1}"
        if [[ "${FILE_SRC_BASE}" == */* && "${FILE_SRC_BASE}" != */ ]]; then
          FILE_SRC_DIR="$(dirname "${FILE_SRC_BASE}")/"
          FILE_SRC_BASE="$(basename "${FILE_SRC_BASE}")"
        fi
        [ "${RECURSE}" -ne 0 ] && RECURSE_CMD='-o -type d' || RECURSE_CMD=''
        # IFS must be preserved for <(find)
        OLDIFS="${IFS}"
        while IFS= read -r -d '' FILE_SRC; do
          IFS="${OLDIFS}"
          dbtop_upload 0 "${FILE_SRC}" "/${FILE_DST}"
          let FILE_FND=${FILE_FND}+1
          let ALL_FILE_FND=${ALL_FILE_FND}+1
        done < <(find "${FILE_SRC_DIR}" -maxdepth 1 -a "(" -type f ${RECURSE_CMD} ")" -a -name "${FILE_SRC_BASE}" -print0)
        IFS="${OLDIFS}"
        if [ "${FILE_FND}" -eq 0 ]; then
          dbtop_upload 0 "${@:${i}:1}" "/${FILE_DST}"
          if [ "${ERROR_STATUS}" -eq 0 ]; then
            let ALL_FILE_FND=${ALL_FILE_FND}+1
          fi
          # db_print 0 0 '' "Error: No files found ${@:${i}:1}\n\n"
          # ERROR_STATUS=1 # It is not an error to not find some of the files
        fi
      fi
    done
    #if [ "${ALL_FILE_FND}" -eq 0 ]; then
    #  ERROR_STATUS=1
    #fi
  ;;

  download)
    db_setup

    if [ "${argnum}" -lt 1 ]; then
      usage
    fi

    FILE_SRC="${ARG1}"
    FILE_DST="${ARG2}"
    FILE_GLOB=''

    if [ "${FILE_SRC: -1}" != '/' ] && [ "${FILE_SRC//[[*?\]]//}" != "${FILE_SRC}" ] && [ "$(db_stat "${FILE_SRC}")" = 'ERR' ]; then # short circuit required
      FILE_GLOB="$(basename "${FILE_SRC}")"
      FILE_SRC="$(dirname "${FILE_SRC}")"
    fi
    dbtop_download 0 "/${FILE_SRC}" "${FILE_GLOB}" "${FILE_DST}"

  ;;

  share)
    db_setup

    if [ "${argnum}" -lt 1 ]; then
      usage
    fi

    FILE_DST="${ARG1}"

    dbtop_share "/${FILE_DST}"

  ;;

  info)
    db_setup

    dbtop_account_info

  ;;

  delete|remove)
    db_setup

    if [ "${argnum}" -lt 1 ]; then
      usage
    fi

    FILE_DST="${ARG1}"

    if [ ! -z "${ARG2}" ]; then
      db_print 0 0 '' "Error: Files with spaces must be quoted otherwise we might delete something we don't want to\n\n"
      ERROR_STATUS=1
    else
      dbtop_delete "/${FILE_DST}"
    fi

  ;;

  move|rename)
    db_setup

    if [ "${argnum}" -lt 2 ]; then
      usage
    fi

    FILE_SRC="${ARG1}"
    FILE_DST="${ARG2}"

    dbtop_move "/${FILE_SRC}" "/${FILE_DST}"

  ;;

  copy)
    db_setup

    if [ "${argnum}" -lt 2 ]; then
      usage
    fi

    FILE_SRC="${ARG1}"
    FILE_DST="${ARG2}"

    dbtop_copy "/${FILE_SRC}" "/${FILE_DST}"

  ;;

  mkdir)
    db_setup

    if [ "${argnum}" -lt 1 ]; then
      usage
    fi

    DIR_DST="${ARG1}"

    dbtop_mkdir "/${DIR_DST}"

  ;;

  list)
    db_setup

    DIR_DST="${ARG1}"

    #Checking DIR_DST
    if [ -z "${DIR_DST}" ]; then
      DIR_DST='/'
    fi

    dbtop_list "/${DIR_DST}"

  ;;

  unlink)

    dbtop_unlink

  ;;

  *)

    if [ ! -z "${COMMAND}" ]; then
      db_print 0 0 '' "Error: Unknown command: ${COMMAND}\n\n"
      ERROR_STATUS=1
    fi
    usage

  ;;

esac

remove_temp_files
exit ${ERROR_STATUS}
