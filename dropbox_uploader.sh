#!/usr/bin/env bash
#
# Dropbox Uploader
#
# Copyright (C) 2010-2015 Andrea Fabrizi <andrea.fabrizi@gmail.com>
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

set -u
#Default configuration file
CONFIG_FILE=~/'.dropbox_uploader'
CONFIG_FILE_BASE='dropbox-default'

#Default chunk size in bytes for the upload process
#It is recommended to increase this value only if you have enough free space on your /tmp partition
#Lower values may increase the number of http requests
let CHUNK_SIZE=4*1048576
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

#Don't edit these...
API_REQUEST_TOKEN_URL='https://api.dropbox.com/1/oauth/request_token'
API_USER_AUTH_URL='https://www.dropbox.com/1/oauth/authorize'
API_ACCESS_TOKEN_URL='https://api.dropbox.com/1/oauth/access_token'
API_CHUNKED_UPLOAD_URL='https://api-content.dropbox.com/1/chunked_upload'
API_CHUNKED_UPLOAD_COMMIT_URL='https://api-content.dropbox.com/1/commit_chunked_upload'
API_UPLOAD_URL='https://api-content.dropbox.com/1/files_put'
API_DOWNLOAD_URL='https://api-content.dropbox.com/1/files'
API_DELETE_URL='https://api.dropbox.com/1/fileops/delete'
API_MOVE_URL='https://api.dropbox.com/1/fileops/move'
API_COPY_URL='https://api.dropbox.com/1/fileops/copy'
API_METADATA_URL='https://api.dropbox.com/1/metadata'
API_INFO_URL='https://api.dropbox.com/1/account/info'
API_MKDIR_URL='https://api.dropbox.com/1/fileops/create_folder'
API_SHARES_URL='https://api.dropbox.com/1/shares'
APP_CREATE_URL='https://www.dropbox.com/developers/apps'
RESPONSE_FILE="${TMP_DIR}/du_resp.$$_${RANDOM}"
CHUNK_FILE="${TMP_DIR}/du_chunk.$$_${RANDOM}"
TEMP_FILE="${TMP_DIR}/du_tmp.$$_${RANDOM}"
BIN_DEPS='sed basename date grep stat dd mkdir'
VERSION='0.15c'
# Packagers should sed the following to their distro: Arch Linux, Debian, Red Hat, Ubuntu, Gentoo, ...
BRANDING=''

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
  'f') CONFIG_FILE="${OPTARG}"; CONFIG_FILE_BASE="$(basename "${CONFIG_FILE}")";;
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
  CHUNK_SIZE=1048576; CHUNK_MAX=1048576 # This lets us debug chunking without having to send 150MB
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
  if [ ! -z "${LOGFILE}" -a "$1" -ne 0 ]; then
    if [ "$1" -eq 2 -o "$1" -eq 4 ];  then
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
    rm -f "${RESPONSE_FILE}"
    rm -f "${CHUNK_FILE}"
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
  echo -e 'Andrea Fabrizi - andrea.fabrizi@gmail.com\n'
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
      db_print 2 1 '\n' 'Error: cURL is not able to performs peer SSL certificate verification.
Please, install the default ca-certificates bundle.
To do this in a Debian/Ubuntu based system, try:
  sudo apt-get install ca-certificates

If the problem persists, try to use the -k option (insecure).\n'

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
  if grep -q 'HTTP/1.1 400' "${RESPONSE_FILE}"; then
    ERROR_MSG="$(sed -n -e 's/{"error": "\([^"]*\)"}/\1/p' "${RESPONSE_FILE}")" #'#Fix mc syntax highlighting

    case "${ERROR_MSG}" in
       *access?attempt?failed?because?this?app?is?not?configured?to?have*)
        db_print 2 1 '\n' "Error: The Permission type/Access level configured doesn't match the DropBox App settings!\nPlease run \"$0 unlink\" and try again."
        exit 1
      ;;
    esac

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
    if [ "${new_path: -1}" != '/' -a "${path: -1}" = '/' ]; then
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

  #Checking if it's a file or a directory
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" "${API_METADATA_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" 2> /dev/null
  check_http_response

  #Even if the file/dir has been deleted from DropBox we receive a 200 OK response
  #So we must check if the file exists or if it has been deleted
  if grep -q '"is_deleted":' "${RESPONSE_FILE}"; then
    local IS_DELETED="$(sed -n 's/.*"is_deleted":.\([^,]*\).*/\1/p' "${RESPONSE_FILE}")"
  else
    local IS_DELETED='false'
  fi

  #Exits...
  grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"
  if [ $? -eq 0 -a "${IS_DELETED}" != 'true' ]; then

    local IS_DIR="$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "${RESPONSE_FILE}")" # '

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
    #DST="${DST}"
    :
  #if DST doesn't exists
  elif [ "${TYPE}" = 'ERR' ]; then
    # and doesn't ends with a /, it will be the destination file name
    if [ "${DST: -1}" != '/' ]; then
      # DST="${DST}"
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
    if [ $1 -eq 0 -o "${RECURSE}" -ne 0 ]; then
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
            DIR_MADE=1
          fi
          dbtop_upload $(($1+1)) "${FILE}" "${GLOB}" "${DIR_DST}/"
        elif [ ! -z "${GLOB}" -a -d "${FILE}" ]; then
          dbtop_upload $(($1+1)) "${FILE}/" "${GLOB}" "${DIR_DST}/$(basename "${FILE}")/"
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
  if [ "${basefile_dst}" = 'thumbs.db'   -o \
       "${basefile_dst}" = 'desktop.ini' -o \
       "${basefile_dst}" = '.ds_store'   -o \
       "${basefile_dst}" = 'icon\r'      -o \
       "${basefile_dst}" = '.dropbox'    -o \
       "${basefile_dst}" = '.dropbox.attr'  \
     ]; then
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

  if [ "${SHOW_PROGRESSBAR}" -eq 1 -a "${QUIET}" -eq 0 ]; then
    CURL_PARAMETERS='--progress-bar'
    LINE_CR='\n'
  else
    CURL_PARAMETERS='-s'
    LINE_CR=''
  fi

  [ -z "${LOGFILE}" ] || db_print 4 0 '' "${FILE_SRC} -> ${CONFIG_FILE_BASE}:/${FILE_DST} 0-$(file_size "${FILE_SRC}")"
  db_print 0 0 '' " > Uploading \"${FILE_SRC}\" to \"${FILE_DST}\"... ${LINE_CR}"
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} ${CURL_PARAMETERS} -i --globoff -o "${RESPONSE_FILE}" --upload-file "${FILE_SRC}" "${API_UPLOAD_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE_DST}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}"
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
    db_print 1 0 '' ' DONE\n'
    if [ "${DELETE_AFTER_PUTGET}" -ne 0 ]; then
      rm -f "${FILE_SRC}"
      db_print 0 0 '' " > Deleted ${FILE_SRC}\n"
    fi
  else
    db_print 1 0 '' ' FAILED\n'
    db_print 0 0 '' 'An error occurred requesting /upload\n'
    ERROR_STATUS=1
  fi
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
  local CHUNK_PARAMS=''

  #Uploading chunks...
  while [ "${OFFSET}" -ne "${FILE_SIZE}" ]; do

    #let OFFSET_CHK=${OFFSET}/${CHUNK_SIZE}
    #db_print 0 0 '' " Chunk #${OFFSET_CHK} @${OFFSET}+${CHUNK_SIZE}\n"

    #Create the chunk
    #dd if="${FILE_SRC}" of="${CHUNK_FILE}" bs="${CHUNK_SIZE}" skip="${OFFSET_CHK}" count=1 2> /dev/null
    dd if="${FILE_SRC}" of="${CHUNK_FILE}" bs="1" skip="${OFFSET}" count="${CHUNK_SIZE}" 2> /dev/null

    #Only for the first request these parameters are not included
    if [ "${OFFSET}" -ne 0 ]; then
      CHUNK_PARAMS="upload_id=${UPLOAD_ID}&offset=${OFFSET}"
    fi

    #Uploading the chunk...
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --upload-file "${CHUNK_FILE}" "${API_CHUNKED_UPLOAD_URL}?${CHUNK_PARAMS}&oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" 2> /dev/null
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
      db_print 1 0 '' '.'
      UPLOAD_ERROR=0
      UPLOAD_ID="$(sed -n 's/.*"upload_id": *"*\([^"]*\)"*.*/\1/p' "${RESPONSE_FILE}")" # '
      OFFSET="$(sed -n 's/.*"offset": *\([^}]*\).*/\1/p' "${RESPONSE_FILE}")"
      #db_print 0 0 '' "ID {$UPLOAD_ID} offset=${OFFSET}\n"
    else
      db_print 1 0 '' '*'
      let UPLOAD_ERROR=${UPLOAD_ERROR}+1

      #On error, the upload is retried for max 3 times
      if [ "${UPLOAD_ERROR}" -gt 2 ]; then
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

    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "upload_id=${UPLOAD_ID}&oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${API_CHUNKED_UPLOAD_COMMIT_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE_DST}")" 2> /dev/null
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
      db_print 1 0 '' '$'
      UPLOAD_ERROR=0
      break
    else
      db_print 1 0 '' 'E'
      let UPLOAD_ERROR=${UPLOAD_ERROR}+1

      #On error, the commit is retried for max 3 times
      if [ "${UPLOAD_ERROR}" -gt 2 ]; then
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

#Returns the free space on DropBox in bytes
db_free_quota()
{
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${API_INFO_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then

    local quota="$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}")"
    local used="$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}")"
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
  if [ ! -z "${DST}" -a -d "${DST}" ]; then
    if [ "${DST: -1}" != '/' ]; then
      DST="${DST}/"
    fi
  fi

  echo "$FUNCNAME: SRC=${SRC}"; echo "$FUNCNAME: GLOB=${GLOB}"; echo "$FUNCNAME: DST=${DST}"

  local TYPE
  # we don't trust user calling from level 0. Level 1+ from dropbox trusted.
  if [ "$1" -gt 0 -a "${SRC: -1}" = '/' ]; then
    TYPE='DIR'
  else
    TYPE="$(db_stat "${SRC}")"
  fi

  echo "$FUNCNAME: SRC TYPE=${TYPE}"

  # check for globbing
  #if [ "${TYPE}" = 'ERR' -a "${SRC: -1}" != '/' ]; then # basename refuses to return blank with a trailing slash
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
    if [ ! -d "${DST}" -o ! -z "${GLOB}" ]; then
      basedir=''
    else
      basedir="$(basename "${SRC}")"
    fi

    echo "$FUNCNAME: basedir=${basedir}"

    local DEST_DIR="$(normalize_path "${DST}/${basedir}")"
    echo "$FUNCNAME: DEST_DIR=${DEST_DIR}"
    #if [ ! -d "${DEST_DIR}" ]; then
    #  db_print 2 0 ' > ' "Creating local directory \"${DEST_DIR}\"... "
    #  mkdir -p "${DEST_DIR}"

    #  #Check
    #  if [ $? -eq 0 -a -d "${DEST_DIR}" ]; then
    #    db_print 1 0 '' 'DONE\n'
    #  else
    #    db_print 1 0 '' 'FAILED\n'
    #    ERROR_STATUS=1
    #    return
    #  fi
    #fi
    db_print 0 0 ' > ' "Downloading folder \"${SRC}\" to \"${DEST_DIR}\"... \n"

    #Extracting files and subfolders
    local TMP_DIR_CONTENT_FILE
    # random isn't enough. For recursion we must guarantee a unique file
    while :; do 
      TMP_DIR_CONTENT_FILE="${RESPONSE_FILE}_${RANDOM}"
      if [ ! -f "${TMP_DIR_CONTENT_FILE}" ]; then
        break
      fi
    done

    #1 Discard all but subdirectory content [...], last line from db_stat response
    #2 Separate each entry with \n, replacing "}, {" with "}\n{", allowing sed to process lines
    #3 Discard all but file:is_dir false=file, true=dir
    #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
    sed -n 's/.*: \[{\(.*\)/\1/p' "${RESPONSE_FILE}" | \
    sed    's/}, *{/}\
{/g' | \
    sed -n 's/.*"path": *"\([^"]*\)",.*"is_dir": *\([^"]*\),.*/\1:\2/p' \
       > "${TMP_DIR_CONTENT_FILE}"
    printf "\n" >> "${TMP_DIR_CONTENT_FILE}"
    #echo -e "$FUNCNAME: RESPONSE_FILE=${RESPONSE_FILE}\nTMP_DIR_CONTENT_FILE=${TMP_DIR_CONTENT_FILE}\nPress Enter"; read x

    #For each entry...
    local FILE
    while read -r line; do

      if [ ! -z "${line}" ]; then
        FILE="${line%:*}"
        TYPE="${line#*:}"

        #Removing unneeded / on dirs
        FILE="${FILE##*/}"

        if [ "${TYPE}" = 'false' ]; then
          if fnmatch "${GLOB}" "${FILE}"; then
            db_download_file "${SRC}/${FILE}" "${DEST_DIR}/${FILE}"
            if [ "${ERROR_STATUS}" -ne 0 ]; then
              return
            fi
          fi
        elif [ "${RECURSE}" -ne 0 ]; then
          dbtop_download $(($1+1)) "${SRC}/${FILE}" "${GLOB}" "${DEST_DIR}/${FILE}"
          # should we abort recursive copy on ERROR_STATUS here?
        fi
      fi

    done < "${TMP_DIR_CONTENT_FILE}"

    rm -f "${TMP_DIR_CONTENT_FILE}"

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

  echo "$FUNCNAME: FILE_SRC=${FILE_SRC}"; echo "$FUNCNAME: FILE_DST=${FILE_DST}"; echo "$FUNCNAME: DEST_DIR=${DEST_DIR}"

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
    mkdir -p "${DEST_DIR}"

    #Check
    if [ $? -eq 0 -a -d "${DEST_DIR}" ]; then
      db_print 1 0 '' 'DONE\n'
    else
      db_print 1 0 '' 'FAILED\n'
      ERROR_STATUS=1
      return
    fi
  fi

  if [ "${SHOW_PROGRESSBAR}" -eq 1 -a "${QUIET}" -eq 0 ]; then
    local CURL_PARAMETERS='--progress-bar'
    local LINE_CR='\n'
  else
    local CURL_PARAMETERS='-s'
    local LINE_CR=''
  fi

  #Checking if the file already exists
  if [ -e "${FILE_DST}" -a "${SKIP_EXISTING_FILES}" -eq 1 ]; then
    db_print 2 1 ' > ' "Skipping already existing file \"${FILE_DST}\"\n"
    return
  fi

  #Creating the empty file, that for two reasons:
  #1) In this way I can check if the destination file is writeable or not
  #2) Curl doesn't automatically creates files with 0 bytes size
  dd if=/dev/zero of="${FILE_DST}" count=0 2> /dev/null
  if [ $? -ne 0 ]; then
    db_print 2 1 ' > ' "Error writing file ${FILE_DST}: permission denied\n"
    ERROR_STATUS=1
    return
  fi

  [ -z "${LOGFILE}" ] || db_print 4 0 '' "${CONFIG_FILE_BASE}:/${FILE_SRC} -> ${FILE_DST} "
  db_print 0 0 '' " > Downloading \"${FILE_SRC}\" to \"${FILE_DST}\"... ${LINE_CR}"
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} ${CURL_PARAMETERS} --globoff -D "${RESPONSE_FILE}" -o "${FILE_DST}" "${API_DOWNLOAD_URL}/${ACCESS_LEVEL}/$(urlencode "${FILE_SRC}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}"
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
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

#Prints account info
dbtop_account_info()
{
  db_print 0 0 '' "Dropbox Uploader v${VERSION}\n\n"
  db_print 0 0 '' ' > Getting info... '
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${API_INFO_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then

    local name="$(sed -n 's/.*"display_name": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}")"
    echo -e "\n\nName:\t${name}"

    local uid="$(sed -n 's/.*"uid": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}")"
    echo -e "UID:\t${uid}"

    local email="$(sed -n 's/.*"email": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}")"
    echo -e "Email:\t${email}"

    local quota="$(sed -n 's/.*"quota": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}")"
    local quota_mb
    let quota_mb=${quota}/1024/1024
    echo -e "Quota:\t${quota_mb} Mb"

    local used="$(sed -n 's/.*"normal": \([0-9]*\).*/\1/p' "${RESPONSE_FILE}")"
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
}

#Account unlink
dbtop_unlink()
{
  echo -ne 'Are you sure you want unlink this script from your Dropbox account? [y/n]'
  local answer
  read answer
  if [ "${answer}" = 'y' ]; then
    rm -f "${CONFIG_FILE}"
    echo -ne 'DONE\n'
  fi
}

#Delete a remote file
#$1 = Remote file to delete
dbtop_delete()
{
  local FILE_DST="$(normalize_path "$1")"

  [ -z "${LOGFILE}" ] || db_print 4 0 '' "Deleting ${CONFIG_FILE_BASE}:/${FILE_DST} "
  db_print 0 0 ' > ' "Deleting \"${FILE_DST}\"... "
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&path=$(urlencode "${FILE_DST}")" "${API_DELETE_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
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

  [ -z "${LOGFILE}" ] || db_print 4 0 '' "Moving ${CONFIG_FILE_BASE}:/${FILE_SRC} -> ${FILE_DST} 0-? "
  db_print 0 0 ' > ' "Moving \"${FILE_SRC}\" to \"${FILE_DST}\" ... "
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&from_path=$(urlencode "${FILE_SRC}")&to_path=$(urlencode "${FILE_DST}")" "${API_MOVE_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
    db_print 1 0 '' 'DONE\n'
  else
    db_print 1 1 '' 'FAILED\n'
    ERROR_STATUS=1
  fi
}

#Copy a remote file to a remote location
#$1 = Remote file to rename or move
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

  [ -z "${LOGFILE}" ] || db_print 4 0 '' "Copying ${CONFIG_FILE_BASE}:/${FILE_SRC} -> ${FILE_DST} 0-? "
  db_print 0 0 ' > ' "Copying \"${FILE_SRC}\" to \"${FILE_DST}\" ... "
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&from_path=$(urlencode "${FILE_SRC}")&to_path=$(urlencode "${FILE_DST}")" "${API_COPY_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
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

  if [ "${DIR_DST}" == '/' ]; then
    :
  else
    db_print 0 0 '' " > Creating Directory \"${DIR_DST}\"... "
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&root=${ACCESS_LEVEL}&path=$(urlencode "${DIR_DST}")" "${API_MKDIR_URL}" 2> /dev/null
    check_http_response

    #Check
    if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
      db_print 0 0 '' 'DONE\n'
    elif grep -q '^HTTP/1.1 403 Forbidden' "${RESPONSE_FILE}"; then
      db_print 0 0 '' 'ALREADY EXISTS\n'
    else
      db_print 0 0 '' 'FAILED\n'
      ERROR_STATUS=1
    fi
  fi
}

#List remote directory
#$1 = Remote directory
dbtop_list()
{
  local DIR_DST="$(normalize_path "$1")"

  db_print 0 0 '' " > Listing \"${DIR_DST}\"... "
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" "${API_METADATA_URL}/${ACCESS_LEVEL}/$(urlencode "${DIR_DST}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then

    local IS_DIR="$(sed -n 's/^\(.*\)\"contents":.\[.*/\1/p' "${RESPONSE_FILE}")" # '

    #It's a directory
    if [ ! -z "${IS_DIR}" ]; then

      db_print 0 0 '' 'DONE\n'

      #Extracting directory content [...]
      #and replacing "}, {" with "}\n{"
      #I don't like this piece of code... but seems to be the only way to do this with SED, writing a portable code...
      local DIR_CONTENT="$(sed -n 's/.*: \[{\(.*\)/\1/p' "${RESPONSE_FILE}" | sed 's/}, *{/}\
{/g')"

      #Converting escaped quotes to unicode format
      echo "${DIR_CONTENT}" | sed 's/\\"/\\u0022/' > "${TEMP_FILE}"

      #Extracting files and subfolders
      rm -f "${RESPONSE_FILE}"
      local line
      local FILE
      local SIZE
      while read -r line; do

        FILE="$(echo "$line" | sed -n 's/.*"path": *"\([^"]*\)".*/\1/p')" # '
        IS_DIR="$(echo "$line" | sed -n 's/.*"is_dir": *\([^,]*\).*/\1/p')"
        SIZE="$(echo "$line" | sed -n 's/.*"bytes": *\([0-9]*\).*/\1/p')"

        echo -e "${FILE}:${IS_DIR};${SIZE}" >> "${RESPONSE_FILE}"

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
      done < "${RESPONSE_FILE}"

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

      done < "${RESPONSE_FILE}"

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

      done < "${RESPONSE_FILE}"

    #It's a file
    else
      db_print 0 0 '' "FAILED: ${DIR_DST} is not a directory!\n"
      ERROR_STATUS=1
    fi

  else
    db_print 0 0 '' 'FAILED\n'
    ERROR_STATUS=1
  fi
}

#Share remote file
#$1 = Remote file
dbtop_share()
{
  local FILE_DST="$(normalize_path "$1")"

  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" "$API_SHARES_URL/${ACCESS_LEVEL}/$(urlencode "${FILE_DST}")?oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_ACCESS_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_ACCESS_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}&short_url=${SHORT_URL}" 2> /dev/null
  check_http_response

  #Check
  if grep -q '^HTTP/1.1 200 OK' "${RESPONSE_FILE}"; then
    db_print 0 0 '' ' > Share link: '
    SHARE_LINK="$(sed -n 's/.*"url": "\([^"]*\).*/\1/p' "${RESPONSE_FILE}")"
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
if [ -e "${CONFIG_FILE}" ]; then

  #Back compatibility with previous Dropbox Uploader versions
  ACCESS_LEVEL=''
  #Loading data... and change old format config if necessary.
  source "${CONFIG_FILE}" 2>/dev/null || {
    sed -i'' 's/:/=/' "${CONFIG_FILE}" && source "${CONFIG_FILE}" 2>/dev/null
  }

  #Checking the loaded data
  if [ -z "${APPKEY}" -o -z "${APPSECRET}" -o -z "${OAUTH_ACCESS_TOKEN_SECRET}" -o -z "${OAUTH_ACCESS_TOKEN}" ]; then
    echo -ne "Error loading data from ${CONFIG_FILE}...\n"
    echo -ne "It is recommended to run $0 unlink\n"
    remove_temp_files
    exit 1
  fi

  #Back compatibility with previous Dropbox Uploader versions
  if [ -z "${ACCESS_LEVEL}" ]; then
    ACCESS_LEVEL='dropbox'
  fi

#NEW SETUP...
else

  echo -ne '\n This is the first time you run this script.\n\n'
  echo -ne " 1) Open the following URL in your Browser, and log in using your account: ${APP_CREATE_URL}\n"
  echo -ne 'You can select an existing app and go directly to # App key\n'
  echo -ne ' 2) Click on "Create App", then select "Dropbox API app"\n'
  echo -ne ' 3) Now go on with the configuration, choosing the app permissions and access restrictions to your DropBox folder\n'
  echo -ne ' 4) Enter the "App Name" that you prefer '"(e.g. MyUploader${RANDOM}${RANDOM}${RANDOM})\n\n"

  echo -ne ' Now, click on the "Create App" button.\n\n'

  echo -ne ' When your new App is successfully created, please type the\n'
  echo -ne ' App Key, App Secret and the Permission type shown in the confirmation page:\n\n'

  #Getting the app key and secret from the user
  while :; do

    echo -n ' # App key: '
    read APPKEY

    echo -n ' # App secret: '
    read APPSECRET

    echo -ne "\nPermission type:\n App folder [a]: If you choose that the app only needs access to files it creates\n Full Dropbox [f]: If you choose that the app needs access to files already on Dropbox\n\n # Permission type [a/f]: "
    read ACCESS_LEVEL

    if [ "${ACCESS_LEVEL}" = 'a' ]; then
      ACCESS_LEVEL='sandbox'
      ACCESS_MSG='App Folder'
    else
      ACCESS_LEVEL='dropbox'
      ACCESS_MSG='Full Dropbox'
    fi

    echo -ne "\n > App key is ${APPKEY}, App secret is ${APPSECRET} and Access level is ${ACCESS_MSG}. Looks ok? [y/n]: "
    read answer
    if [ "${answer}" = 'y' ]; then
      break;
    fi

  done

  #TOKEN REQUESTS
  echo -ne '\n > Token request... '
  "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${API_REQUEST_TOKEN_URL}" 2> /dev/null
  check_http_response
  OAUTH_TOKEN_SECRET="$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\).*/\1/p' "${RESPONSE_FILE}")"
  OAUTH_TOKEN="$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)/\1/p' "${RESPONSE_FILE}")"

  if [ ! -z "${OAUTH_TOKEN}" -a ! -z "${OAUTH_TOKEN_SECRET}" ]; then
    echo -ne 'OK\n'
  else
    echo -ne ' FAILED\n\n Please, check your App key and secret...\n\n'
    remove_temp_files
    exit 1
  fi

  while :; do

    #USER AUTH
    echo -ne '\n Please open the following URL in your browser, and allow Dropbox Uploader\n'
    echo -ne " to access your DropBox folder:\n\n --> ${API_USER_AUTH_URL}?oauth_token=${OAUTH_TOKEN}\n"
    echo -ne '\nPress enter when done...\n'
    read

    #API_ACCESS_TOKEN_URL
    echo -ne ' > Access Token request... '
    "${CURL_BIN}" ${CURL_ACCEPT_CERTIFICATES} -s --show-error --globoff -i -o "${RESPONSE_FILE}" --data "oauth_consumer_key=${APPKEY}&oauth_token=${OAUTH_TOKEN}&oauth_signature_method=PLAINTEXT&oauth_signature=${APPSECRET}%26${OAUTH_TOKEN_SECRET}&oauth_timestamp=$(utime)&oauth_nonce=${RANDOM}" "${API_ACCESS_TOKEN_URL}" 2> /dev/null
    check_http_response
    OAUTH_ACCESS_TOKEN_SECRET="$(sed -n 's/oauth_token_secret=\([a-z A-Z 0-9]*\)&.*/\1/p' "${RESPONSE_FILE}")"
    OAUTH_ACCESS_TOKEN="$(sed -n 's/.*oauth_token=\([a-z A-Z 0-9]*\)&.*/\1/p' "${RESPONSE_FILE}")"
    OAUTH_ACCESS_UID="$(sed -n 's/.*uid=\([0-9]*\)/\1/p' "${RESPONSE_FILE}")"

    if [ ! -z "${OAUTH_ACCESS_TOKEN}" -a ! -z "${OAUTH_ACCESS_TOKEN_SECRET}" -a ! -z "$OAUTH_ACCESS_UID" ]; then
      echo -ne 'OK\n'

      #Saving data in new format, compatible with source command.
      cat > "${CONFIG_FILE}" << EOF
# Dropbox configuration for dropbox-uploader
APPKEY='${APPKEY}'
APPSECRET='${APPSECRET}'
ACCESS_LEVEL='${ACCESS_LEVEL}'
OAUTH_ACCESS_TOKEN='${OAUTH_ACCESS_TOKEN}'
OAUTH_ACCESS_TOKEN_SECRET='${OAUTH_ACCESS_TOKEN_SECRET}'
EOF
      echo -ne '\n Setup completed!\n'
      break
    else
      db_print 0 0 '' ' FAILED\n'
      ERROR_STATUS=1
    fi

  done

  remove_temp_files
  exit ${ERROR_STATUS}
fi
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
      if [ "${FILE_SRC_NMPT: -1}" != '/' -a ! -e "${FILE_SRC_NMPT}" -a ! -d "${FILE_SRC_NMPT}" ] && [ "${FILE_SRC_NMPT//[[*?\]]/}" != "${FILE_SRC_NMPT}" ]; then
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

    if [ "${FILE_SRC: -1}" != '/' -a "${FILE_SRC//[[*?\]]//}" != "${FILE_SRC}" ] && [ "$(db_stat "${FILE_SRC}")" = 'ERR' ]; then # short circuit required
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
