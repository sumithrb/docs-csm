#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#

# TODO: the detection and "do stuff" logic is a bit copy/pasted.
#
# Needs a red/green/refactor run at some point.

# Depends on the logger.sh lib for logging, caller is responsible for importing.

# Find thunk strings in the file given. File name is required.
hasthunks() {
  file="${1?}"
  if [ -e "${file}" ]; then
    if grep -E '__(begin|end)thunk__' "${file}" > /dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

# Determine if the thunks make sense logically, aka:
# being/end are == in count
# each begin/end pair agree in their leading whitespace
#
# If not call the file invalid, File name is required.
validthunks() {
  file="${1?}"

  begins=$(grep -Ec '__beginthunk__' "${file}")
  ends=$(grep -Ec '__endthunk__' "${file}")

  ok=0
  nok=0

  # Simple stuff first, is the begin count == to the end count?
  if [ "${begins}" = "${ends}" ]; then
    ok=$((ok + 1))
  else
    warn "begin not equal to end found ${begins} and ${ends}"
  fi

  bidx=0
  {
    IFS='
'
    busted=false

    # Why not a while read loop? to use that we'd need to pipe and while read
    # through a pipe is an implicit subshell so I can't assign to any vars inside
    # the while read loop. No shellcheck, read loops are not always "this is the way".
    #shellcheck disable=SC2013
    for beginthunk in $(grep -E '__beginthunk__' "${file}"); do
      # info ${beginthunk}
      bidx=$((bidx + 1))
      eidx=0

      for endthunk in $(grep -E '__endthunk__' "${file}"); do
        eidx=$((eidx + 1))
        # This breaks the if so... no. Feel free to quote the $() and fix the failing unit tests...
        # shellcheck disable=SC2046
        if [ "${bidx}" = "${eidx}" ] && [ $(printf "%s\n%s" "${beginthunk}" "${endthunk}" | grep -E '__(begin|end)thunk__' | sed -e 's|#__beginthunk__ ||g' -e 's|#__endthunk__ ||g' | sort -u | wc -l) != "1" ]; then
          nok=$((nok + 1))
          busted=true
        else
          bfile=$(echo "${beginthunk}" | awk '{print $2}')
          if ! [ -e "${bfile}" ]; then
            warn "file in begin thunk named \"${bfile}\" doesn't exist"
            busted=true
          fi

          efile=$(echo "${endthunk}" | awk '{print $2}')
          if ! [ -e "${efile}" ]; then
            warn "file in end thunk named \"${efile}\" doesn't exist"
            busted=true
          fi
        fi
      done
    done

    if $busted; then
      # This is internal tooling, I'm not going too crazy figuring out exactly
      # whats wrong for internal developers, future enhancement maybe but for v0
      # just saying stuffs wrong is OK, future someone can say if its whitespace
      # or file mismatches. Wouldn't be hard just pressed for time and not
      # bothering.
      warn "begin/end block issues found" >&2
    fi
  }

  if [ "${nok}" -gt 0 ]; then
    return 1
  fi

  if [ "${ok}" -gt 0 ]; then
    return 0
  fi

  return 1
}
