#!/usr/bin/env bash

# Copyright (C) 2015 Chris Severance aur.severach spamgourmet com
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

# Purpose: upload to, download, and delete test files from your dropbox to ensure that all features work correctly.
# Review the script to ensure that names to be written and deleted won't conflict with files already on your dropbox.

# Usage:
# To run all tests         : ./dropbox_unit.sh
# To run all upload tests  : ./dropbox_unit.sh 'Upload'
# To run all download tests: ./dropbox_unit.sh 'Download'
# To run a specific test   : ./dropbox_unit.sh 'Broken Test'

# Download tests require test 'Upload all for download test' to be run to fill dropbox with test files.
# When done you can run test 'Remove download test files from dropbox' or delete unit_test from dropbox manually.

# Note: Dropbox is a case insensitive file system.

# Unit tests allow you to modify the code with confidence that breakage will be
# quickly detected.

# The best way to report a bug is to show what's wrong in an existing unit test
# or write a new one.

# Script errors are not detected. Watch the screen.

set -u
DROPBOXAC='unit.dropbox'
#http://stackoverflow.com/questions/407523/escape-a-string-for-a-sed-replace-pattern
DROPBOXACESC="$(sed -e 's/[]\/$*.^|[]/\\&/g' <<< "${DROPBOXAC}")" # This is set up for / as the s/ delimiter
PWD="`pwd`"

if [ ! -s "${DROPBOXAC}" ]; then
  echo "Please supply a functional dropbox account config: ${DROPBOXAC}"
  exit 1
fi

if [ "${EUID}" -eq 0 ]; then
  echo "This script must not run as root."
  echo "We write files to / and these must be access denied."
  exit 1
fi

#Dependencies check
for i in md5sum sed; do
  command -v "${i}" >/dev/null 2>&1 || {
    echo -e "Error: Required program could not be found: ${i}"
    exit 1
  }
done
unset i
set +u
if [ "$1" = 'Download' -o "$1" = 'Upload' ] && [ $# -ne 1 ]; then
  echo "Download and upload must be specified alone"
  echo "Did you forget to quote?"
  exit 1
fi

TTRUN="$1"
set -u

#echo -e '#\n#\n#\n#\n#\n'

# Ensure the log output is what we expect.
# $1 = title of test
# $2 = expected text
# "$0.tmp" = log for this test
# "$0.log" = unit test log with errors
_fn_checklog() {
  # allow unit tests to be run in any folder and with any dropbox file.
  sed -i -e 's|^[0-9-]\{10\} [0-9:]\{8\} ||' \
         -e "s|${PWD}||g" \
         -e "s/${DROPBOXACESC}/dropbox/g" "$0.tmp"
  if [ "$(echo -n "$2" | md5sum)" = "$(md5sum < "$0.tmp")" ]; then # <<< adds a linefeed
    echo "Success: $1" >> "$0.log"
  else
    echo "Failure: $1" >> "$0.log"
    echo "**Want:" >> "$0.log"
    echo "$2" >> "$0.log"
    echo "**Got:" >> "$0.log"
    cat "$0.tmp" >> "$0.log"
    echo "" >> "$0.log"
  fi
  rm -f "$0.tmp"
}

# grep '\(TTNOW=\|\${TTRUN}\|_fn_dirc\)' dropbox_unit.sh  | less
# grep '\(\${TTRUN}\|_fn_dirc\)' dropbox_unit.sh  | less}

# Make sure each test cleans up local files
_fn_dirchklog() {
  case $1 in
  1)
    echo -n >> "$0.log"
    find . | sort > "/tmp/$0.lst.1"
    TTMD5="$(md5sum < "/tmp/$0.lst.1")"
    ;;
  2)
    find . | sort > "/tmp/$0.lst.2"
    if [ "${TTMD5}" != "$(md5sum < "/tmp/$0.lst.2")" ]; then
      echo "Spurious file: ${TTNOW}" >> "$0.log"
      diff "/tmp/$0.lst."{1,2} >> "$0.log"
    fi
    rm -f "/tmp/$0.lst."{1,2}
    ;;
  esac
}


rm -f "$0."{tmp,log}
echo "Runtime: $(date +"%F %T")" >> "$0.log"
echo "$(bash --version | head -n1)" >> "$0.log"
echo 'Note: some tests fail because dropbox is unreliable. Run them again individually.' >> "$0.log"
rm -rf dropbox_unit
mkdir -p 'dropbox_unit'
if pushd 'dropbox_unit'; then
  mkdir -p 'dir '{b1,b2}'/dir '{c1,c2}
  for _no in 1 2; do
    for _fil in file FILE GILE; do
      echo "${_fil} a${_no}" > "${_fil} a${_no}"
      echo "${_fil} b${_no}" > "dir b1/${_fil} b${_no}"
      echo "${_fil} c${_no}" > "dir b1/dir c2/${_fil} c${_no}"
      echo "${_fil} c${_no}" > "dir b2/dir c1/${_fil} c${_no}"
    done
  done
  popd

  TTNOW='Single file upload to root'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/file a1' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'file a1'
    _fn_checklog "${TTNOW}" '/dropbox_unit/file a1 -> dropbox://file a1 0-8 DONE
Deleting dropbox://file a1 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Single file upload to a different file'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/file a1' '/foo bar'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'foo bar'
    _fn_checklog "${TTNOW}" '/dropbox_unit/file a1 -> dropbox://foo bar 0-8 DONE
Deleting dropbox://foo bar DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Single file upload to a different file in a folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/file a1' '/unit_send/foo bar'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send/foo bar'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    _fn_checklog "${TTNOW}" '/dropbox_unit/file a1 -> dropbox://unit_send/foo bar 0-8 DONE
Deleting dropbox://unit_send/foo bar DONE
Deleting dropbox://unit_send DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Folder upload to root'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/dir b1' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'FILE b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'FILE b2'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'GILE b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'GILE b2'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/file b1 -> dropbox://file b1 0-8 DONE
/dropbox_unit/dir b1/FILE b1 -> dropbox://FILE b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://file b2 0-8 DONE
/dropbox_unit/dir b1/FILE b2 -> dropbox://FILE b2 0-8 DONE
/dropbox_unit/dir b1/GILE b1 -> dropbox://GILE b1 0-8 DONE
/dropbox_unit/dir b1/GILE b2 -> dropbox://GILE b2 0-8 DONE
Deleting dropbox://FILE b1 DONE
Deleting dropbox://FILE b2 DONE
Deleting dropbox://GILE b1 DONE
Deleting dropbox://GILE b2 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Folder upload to folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/dir b1' '/unit_send'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/file b1 -> dropbox://unit_send/file b1 0-8 DONE
/dropbox_unit/dir b1/FILE b1 -> dropbox://unit_send/FILE b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://unit_send/file b2 0-8 DONE
/dropbox_unit/dir b1/FILE b2 -> dropbox://unit_send/FILE b2 0-8 DONE
/dropbox_unit/dir b1/GILE b1 -> dropbox://unit_send/GILE b1 0-8 DONE
/dropbox_unit/dir b1/GILE b2 -> dropbox://unit_send/GILE b2 0-8 DONE
Deleting dropbox://unit_send DONE
'
    _fn_dirchklog 2
  fi

  # I don't agree with this one. Dropbox deletes the file and puts a folder there instead.
  TTNOW='Folder upload over file'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/file a1' 'dir b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/dir b1' 'dir b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'dir b1'
    _fn_checklog "${TTNOW}" '/dropbox_unit/file a1 -> dropbox://dir b1 0-8 DONE
/dropbox_unit/dir b1/file b1 -> dropbox://dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/FILE b1 -> dropbox://dir b1/FILE b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://dir b1/file b2 0-8 DONE
/dropbox_unit/dir b1/FILE b2 -> dropbox://dir b1/FILE b2 0-8 DONE
/dropbox_unit/dir b1/GILE b1 -> dropbox://dir b1/GILE b1 0-8 DONE
/dropbox_unit/dir b1/GILE b2 -> dropbox://dir b1/GILE b2 0-8 DONE
Deleting dropbox://dir b1 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload to root, non recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" upload 'dropbox_unit/file a*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'file a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'file a2'
    _fn_checklog "${TTNOW}" '/dropbox_unit/file a1 -> dropbox://file a1 0-8 DONE
/dropbox_unit/file a2 -> dropbox://file a2 0-8 DONE
Deleting dropbox://file a1 DONE
Deleting dropbox://file a2 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload to root series a, recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file a*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'file a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'file a2'
    _fn_checklog "${TTNOW}" '/dropbox_unit/file a1 -> dropbox://file a1 0-8 DONE
/dropbox_unit/file a2 -> dropbox://file a2 0-8 DONE
Deleting dropbox://file a1 DONE
Deleting dropbox://file a2 DONE
'
    _fn_dirchklog 2
  fi

  # This one doesn't work yet
  TTNOW='Multi file upload to root series b, recursive and overwrite'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file b*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file b*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'dir b1'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/file b1 -> dropbox://dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://dir b1/file b2 0-8 DONE
/dropbox_unit/dir b1/file b1 -> dropbox://dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://dir b1/file b2 0-8 DONE
Deleting dropbox://dir b1 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload to root series c, deep recursive and overwrite'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file c*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file c*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'dir b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'dir b2'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/dir c2/file c1 -> dropbox://dir b1/dir c2/file c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/file c2 -> dropbox://dir b1/dir c2/file c2 0-8 DONE
/dropbox_unit/dir b2/dir c1/file c1 -> dropbox://dir b2/dir c1/file c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/file c2 -> dropbox://dir b2/dir c1/file c2 0-8 DONE
/dropbox_unit/dir b1/dir c2/file c1 -> dropbox://dir b1/dir c2/file c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/file c2 -> dropbox://dir b1/dir c2/file c2 0-8 DONE
/dropbox_unit/dir b2/dir c1/file c1 -> dropbox://dir b2/dir c1/file c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/file c2 -> dropbox://dir b2/dir c1/file c2 0-8 DONE
Deleting dropbox://dir b1 DONE
Deleting dropbox://dir b2 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload to root series [FG], recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/[FG]*' './'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'dir b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'dir b2'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'FILE a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'FILE a2'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'GILE a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'GILE a2'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/dir c2/FILE c1 -> dropbox://dir b1/dir c2/FILE c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/FILE c2 -> dropbox://dir b1/dir c2/FILE c2 0-8 DONE
/dropbox_unit/dir b1/dir c2/GILE c1 -> dropbox://dir b1/dir c2/GILE c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/GILE c2 -> dropbox://dir b1/dir c2/GILE c2 0-8 DONE
/dropbox_unit/dir b1/FILE b1 -> dropbox://dir b1/FILE b1 0-8 DONE
/dropbox_unit/dir b1/FILE b2 -> dropbox://dir b1/FILE b2 0-8 DONE
/dropbox_unit/dir b1/GILE b1 -> dropbox://dir b1/GILE b1 0-8 DONE
/dropbox_unit/dir b1/GILE b2 -> dropbox://dir b1/GILE b2 0-8 DONE
/dropbox_unit/dir b2/dir c1/FILE c1 -> dropbox://dir b2/dir c1/FILE c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/FILE c2 -> dropbox://dir b2/dir c1/FILE c2 0-8 DONE
/dropbox_unit/dir b2/dir c1/GILE c1 -> dropbox://dir b2/dir c1/GILE c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/GILE c2 -> dropbox://dir b2/dir c1/GILE c2 0-8 DONE
/dropbox_unit/FILE a1 -> dropbox://FILE a1 0-8 DONE
/dropbox_unit/FILE a2 -> dropbox://FILE a2 0-8 DONE
/dropbox_unit/GILE a1 -> dropbox://GILE a1 0-8 DONE
/dropbox_unit/GILE a2 -> dropbox://GILE a2 0-8 DONE
Deleting dropbox://dir b1 DONE
Deleting dropbox://dir b2 DONE
Deleting dropbox://FILE a1 DONE
Deleting dropbox://FILE a2 DONE
Deleting dropbox://GILE a1 DONE
Deleting dropbox://GILE a2 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload to ERR folder series b'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    rm -f "$0.tmp"
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file b*' '/unit_send'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/file b1 -> dropbox://unit_send/dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://unit_send/dir b1/file b2 0-8 DONE
Deleting dropbox://unit_send DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload to DIR/ folder series b'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file b*' '/unit_send/'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/file b1 -> dropbox://unit_send/dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://unit_send/dir b1/file b2 0-8 DONE
Deleting dropbox://unit_send DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi inner file upload to DIR/ folder series [FG]'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/dir b1/[FG]*' '/unit_send/DIR b1/'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/dir c2/FILE c1 -> dropbox://unit_send/DIR b1/dir c2/FILE c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/FILE c2 -> dropbox://unit_send/DIR b1/dir c2/FILE c2 0-8 DONE
/dropbox_unit/dir b1/dir c2/GILE c1 -> dropbox://unit_send/DIR b1/dir c2/GILE c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/GILE c2 -> dropbox://unit_send/DIR b1/dir c2/GILE c2 0-8 DONE
/dropbox_unit/dir b1/FILE b1 -> dropbox://unit_send/DIR b1/FILE b1 0-8 DONE
/dropbox_unit/dir b1/FILE b2 -> dropbox://unit_send/DIR b1/FILE b2 0-8 DONE
/dropbox_unit/dir b1/GILE b1 -> dropbox://unit_send/DIR b1/GILE b1 0-8 DONE
/dropbox_unit/dir b1/GILE b2 -> dropbox://unit_send/DIR b1/GILE b2 0-8 DONE
Deleting dropbox://unit_send DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Multi file upload skip to DIR/ folder series b'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Upload' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/file b*' '/unit_send/'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r -s upload 'dropbox_unit/file b*' '/unit_send/'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_send'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/file b1 -> dropbox://unit_send/dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://unit_send/dir b1/file b2 0-8 DONE
Skipping already existing file "/unit_send/dir b1/file b1"
Skipping already existing file "/unit_send/dir b1/file b2"
Deleting dropbox://unit_send DONE
'
    _fn_dirchklog 2
  fi

  # Dropbox is case insensitive so there will be overwritten files.
  TTNOW='Upload all for download test'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" delete 'unit_test'
    rm -f "$0.tmp"
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r upload 'dropbox_unit/*' '/unit_test/'
    _fn_checklog "${TTNOW}" '/dropbox_unit/dir b1/dir c2/file c1 -> dropbox://unit_test/dir b1/dir c2/file c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/FILE c1 -> dropbox://unit_test/dir b1/dir c2/FILE c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/file c2 -> dropbox://unit_test/dir b1/dir c2/file c2 0-8 DONE
/dropbox_unit/dir b1/dir c2/FILE c2 -> dropbox://unit_test/dir b1/dir c2/FILE c2 0-8 DONE
/dropbox_unit/dir b1/dir c2/GILE c1 -> dropbox://unit_test/dir b1/dir c2/GILE c1 0-8 DONE
/dropbox_unit/dir b1/dir c2/GILE c2 -> dropbox://unit_test/dir b1/dir c2/GILE c2 0-8 DONE
/dropbox_unit/dir b1/file b1 -> dropbox://unit_test/dir b1/file b1 0-8 DONE
/dropbox_unit/dir b1/FILE b1 -> dropbox://unit_test/dir b1/FILE b1 0-8 DONE
/dropbox_unit/dir b1/file b2 -> dropbox://unit_test/dir b1/file b2 0-8 DONE
/dropbox_unit/dir b1/FILE b2 -> dropbox://unit_test/dir b1/FILE b2 0-8 DONE
/dropbox_unit/dir b1/GILE b1 -> dropbox://unit_test/dir b1/GILE b1 0-8 DONE
/dropbox_unit/dir b1/GILE b2 -> dropbox://unit_test/dir b1/GILE b2 0-8 DONE
/dropbox_unit/dir b2/dir c1/file c1 -> dropbox://unit_test/dir b2/dir c1/file c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/FILE c1 -> dropbox://unit_test/dir b2/dir c1/FILE c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/file c2 -> dropbox://unit_test/dir b2/dir c1/file c2 0-8 DONE
/dropbox_unit/dir b2/dir c1/FILE c2 -> dropbox://unit_test/dir b2/dir c1/FILE c2 0-8 DONE
/dropbox_unit/dir b2/dir c1/GILE c1 -> dropbox://unit_test/dir b2/dir c1/GILE c1 0-8 DONE
/dropbox_unit/dir b2/dir c1/GILE c2 -> dropbox://unit_test/dir b2/dir c1/GILE c2 0-8 DONE
/dropbox_unit/file a1 -> dropbox://unit_test/file a1 0-8 DONE
/dropbox_unit/FILE a1 -> dropbox://unit_test/FILE a1 0-8 DONE
/dropbox_unit/file a2 -> dropbox://unit_test/file a2 0-8 DONE
/dropbox_unit/FILE a2 -> dropbox://unit_test/FILE a2 0-8 DONE
/dropbox_unit/GILE a1 -> dropbox://unit_test/GILE a1 0-8 DONE
/dropbox_unit/GILE a2 -> dropbox://unit_test/GILE a2 0-8 DONE
'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to new file in root'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -f 'newfile a1'
    _fn_dirchklog 1
    rm -rf 'newfile a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'newfile a1'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /newfile a1 0-8 DONE
'
    find -maxdepth 1 -type f -name 'newfile a1' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" './newfile a1
'
    rm -f 'newfile a1'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file with new name to existing file in root'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -f 'newfile a1'
    _fn_dirchklog 1
    echo > 'newfile a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'newfile a1'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /newfile a1 0-8 DONE
'
    find -maxdepth 1 -type f -name 'newfile a1' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" './newfile a1
'
    rm -f 'newfile a1'
    _fn_dirchklog 2
  fi

  TTNOW='Download non exist file'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'nonexistfile a1' '.'
    _fn_checklog "dl-${TTNOW}" 'No such file or directory: /nonexistfile a1
'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to access denied root file'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' '/'
    _fn_checklog "dl-${TTNOW}" 'Error writing file /FILE a1: permission denied
'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to access denied root file new name'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' '/newfile a1'
    _fn_checklog "dl-${TTNOW}" 'Error writing file /newfile a1: permission denied
'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to access denied root folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' '/usr'
    _fn_checklog "dl-${TTNOW}" 'Error writing file /usr/FILE a1: permission denied
'
    _fn_dirchklog 2
  fi

  TTNOW='Download folder to access denied root folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/dir b1' '/'
    _fn_checklog "dl-${TTNOW}" 'Creating local directory "/dir b1"... FAILED
'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to existing file in root'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -f 'FILE a1'
    _fn_dirchklog 1
    echo > 'FILE a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' '.'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' ''
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /FILE a1 0-8 DONE
dropbox://unit_test/FILE a1 -> /FILE a1 0-8 DONE
'
    find -maxdepth 1 -type f -name 'FILE a1' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" './FILE a1
'
    rm -f 'FILE a1'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to accidentally overwrite an existing folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'FILE a1'
    _fn_dirchklog 1
    mkdir 'FILE a1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' '.'
    _fn_checklog "dl-${TTNOW}" 'Error writing file /FILE a1: permission denied
'
    find -maxdepth 1 -name 'FILE a1' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" './FILE a1
'
    rmdir 'FILE a1'
    _fn_dirchklog 2
  fi

  #TTNOW='Download single file to overwrite an existing folder/' (not possible as described)
  TTNOW='Download single file to overwrite an existing file/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'dir b1'
    _fn_dirchklog 1
    echo > 'dir b1'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'dir b1/'
    _fn_checklog "dl-${TTNOW}" 'Unable to overwrite existing file /dir b1
'
    find -maxdepth 1 -name 'dir b1' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" './dir b1
'
    rm -rf 'dir b1'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to new folder/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'dir b1'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'dir b1/'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /dir b1/FILE a1 0-8 DONE
'
    find 'dir b1' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'dir b1
dir b1/FILE a1
'
    rm -rf 'dir b1'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to existing folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    mkdir 'unit_test'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'unit_test'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
'
   find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to existing folder/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    mkdir 'unit_test'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
'
   find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download full single folder to a new folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/dir b1' 'unit_test'
    _fn_checklog "dl-${TTNOW}" 'Creating local directory "/unit_test"... DONE
dropbox://unit_test/dir b1/FILE b1 -> /unit_test/FILE b1 0-8 DONE
dropbox://unit_test/dir b1/FILE b2 -> /unit_test/FILE b2 0-8 DONE
dropbox://unit_test/dir b1/GILE b1 -> /unit_test/GILE b1 0-8 DONE
dropbox://unit_test/dir b1/GILE b2 -> /unit_test/GILE b2 0-8 DONE
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE b1
unit_test/GILE b1
unit_test/FILE b2
unit_test/GILE b2
'
     rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download full single folder to a new folder/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/dir b1' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'Creating local directory "/unit_test"... DONE
dropbox://unit_test/dir b1/FILE b1 -> /unit_test/FILE b1 0-8 DONE
dropbox://unit_test/dir b1/FILE b2 -> /unit_test/FILE b2 0-8 DONE
dropbox://unit_test/dir b1/GILE b1 -> /unit_test/GILE b1 0-8 DONE
dropbox://unit_test/dir b1/GILE b2 -> /unit_test/GILE b2 0-8 DONE
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE b1
unit_test/GILE b1
unit_test/FILE b2
unit_test/GILE b2
'
     rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download empty single folder to a new folder'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    echo -n >> "$0.tmp"
    _fn_checklog "dl-${TTNOW}" ''
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/dir b2' 'unit_test'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" ''
    #rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download empty single folder to a new folder/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    echo -n >> "$0.tmp"
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/dir b2' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" ''
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" ''
     rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file a new folder/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download single file to existing folder/'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    mkdir 'unit_test'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/FILE a1' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download glob series F non recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/F*' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'Creating local directory "/unit_test"... DONE
dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
dropbox://unit_test/FILE a2 -> /unit_test/FILE a2 0-8 DONE
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
unit_test/FILE a2
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download glob series F recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r download 'unit_test/F*' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'Creating local directory "/unit_test/dir b1/dir c2"... DONE
dropbox://unit_test/dir b1/dir c2/FILE c1 -> /unit_test/dir b1/dir c2/FILE c1 0-8 DONE
dropbox://unit_test/dir b1/dir c2/FILE c2 -> /unit_test/dir b1/dir c2/FILE c2 0-8 DONE
dropbox://unit_test/dir b1/FILE b1 -> /unit_test/dir b1/FILE b1 0-8 DONE
dropbox://unit_test/dir b1/FILE b2 -> /unit_test/dir b1/FILE b2 0-8 DONE
Creating local directory "/unit_test/dir b2/dir c1"... DONE
dropbox://unit_test/dir b2/dir c1/FILE c1 -> /unit_test/dir b2/dir c1/FILE c1 0-8 DONE
dropbox://unit_test/dir b2/dir c1/FILE c2 -> /unit_test/dir b2/dir c1/FILE c2 0-8 DONE
dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
dropbox://unit_test/FILE a2 -> /unit_test/FILE a2 0-8 DONE
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
unit_test/dir b1
unit_test/dir b1/FILE b1
unit_test/dir b1/FILE b2
unit_test/dir b1/dir c2
unit_test/dir b1/dir c2/FILE c2
unit_test/dir b1/dir c2/FILE c1
unit_test/dir b2
unit_test/dir b2/dir c1
unit_test/dir b2/dir c1/FILE c2
unit_test/dir b2/dir c1/FILE c1
unit_test/FILE a2
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download series F non recursive no overwrite'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/F*' 'unit_test/'
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -s download 'unit_test/F*' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" 'Creating local directory "/unit_test"... DONE
dropbox://unit_test/FILE a1 -> /unit_test/FILE a1 0-8 DONE
dropbox://unit_test/FILE a2 -> /unit_test/FILE a2 0-8 DONE
Skipping already existing file "/unit_test/FILE a1"
Skipping already existing file "/unit_test/FILE a2"
'
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
unit_test/FILE a1
unit_test/FILE a2
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download glob no files non recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    mkdir 'unit_test'
    echo -n >> "$0.tmp"
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" download 'unit_test/none*' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" ''
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Download glob no files recursive'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    rm -rf 'unit_test'
    _fn_dirchklog 1
    mkdir 'unit_test'
    echo -n >> "$0.tmp"
    ./dropbox_uploader.sh -f "${DROPBOXAC}" -L "$0.tmp" -r download 'unit_test/none*' 'unit_test/'
    _fn_checklog "dl-${TTNOW}" ''
    find 'unit_test' > "$0.tmp"
    _fn_checklog "fi-${TTNOW}" 'unit_test
'
    rm -rf 'unit_test'
    _fn_dirchklog 2
  fi

  TTNOW='Remove download test files from dropbox'
  if [ -z "${TTRUN}" -o "${TTRUN}" = 'Download' -o "${TTRUN}" = "${TTNOW}" ]; then
    ./dropbox_uploader.sh -f "${DROPBOXAC}"             delete 'unit_test'
  fi
fi
