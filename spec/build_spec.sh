#!/usr/bin/env sh
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

Describe 'build.sh logic'
  Include lib/logger.sh
  Include lib/build.sh

  Context 'build related functionality'
    tmpdir="${TMPDIR:-/tmp}/build-sh-tmp"

    hasathunk="${tmpdir}/hasathunk"
    hasthunks="${tmpdir}/hasthunks"
    nothunks="${tmpdir}/nothunks"
    nobeginthunk="${tmpdir}/nobeginthunk"
    noendthunk="${tmpdir}/noendthunk"
    thunkfiletagmismatch="${tmpdir}/thunkfiletagmismatch"
    leadingspacesdisagree="${tmpdir}/leadingspacesdisagree"

    exists="${tmpdir}/exists"

    Before 'setup'
    After 'teardown'

    setup() {
        rm -fr "${tmpdir}"
        install -dm755 "${tmpdir}"
        cat <<EOF > "${exists}"
this should be inserted with whitespace
and handlemissingnewlines
EOF
        cat <<EOF > "${hasathunk}"
foo
bar
    #__beginthunk__ ${exists}
    #__endthunk__ ${exists}
EOF
        cat <<EOF > "${hasthunks}"
foo
bar
    #__beginthunk__ ${exists}
    #__endthunk__ ${exists}

  #__beginthunk__ ${exists}
  #__endthunk__ ${exists}
EOF

        cat <<EOF > "${nothunks}"
foo
bar
EOF
        cat <<EOF > "${nobeginthunk}"
foo
bar
    #__endthunk__ ${exists}
EOF

        cat <<EOF > "${noendthunk}"
foo
bar
    #__beginthunk__ ${exists}
EOF

        cat <<EOF > "${leadingspacesdisagree}"
foo
bar
    #__beginthunk__ ${exists}
   #__endthunk__ ${exists}
EOF
        cat <<EOF > "${thunkfiletagmismatch}"
foo
bar
    #__beginthunk__ exists
    #__endthunk__ otherexists
EOF

    }

    teardown() {
      rm -fr "${tmpdir}"
    }

    It 'can detect no thunks present'
      When call hasthunks "${nothunks}"
      The status should equal 1
    End

    It 'can detect single thunks'
      When call hasthunks "${hasathunk}"
      The status should equal 0
    End

    It 'can detect multiple thunks'
      When call hasthunks "${hasthunks}"
      The status should equal 0
    End

    It 'can detect thunks even if invalid'
      When call hasthunks "${noendthunk}"
      The status should equal 0
    End

    It 'can detect a valid thunk aka begin/end are in agreement with one thunk'
      When call validthunks "${hasathunk}"
      The status should equal 0
    End

    It 'can detect valid thunks aka begin/end are in agreement with multiple thunks'
      When call validthunks "${hasthunks}"
      The status should equal 0
    End

    It 'can detect invalid thunk counts (missing a begin)'
      When call validthunks "${nobeginthunk}"
      The status should equal 1
      The stderr should equal "warn: begin not equal to end found 0 and 1"
    End

    It 'can detect invalid thunk counts (missing an end)'
      When call validthunks "${noendthunk}"
      The status should equal 1
      The stderr should equal "warn: begin not equal to end found 1 and 0"
    End

    It 'can detect invalid thunk, whitespace mismatch'
      When call validthunks "${leadingspacesdisagree}"
      The status should equal 1
      The stderr should equal "warn: begin/end block issues found"
    End

    It 'can detect invalid thunk, file tag mismatch'
      When call validthunks "${thunkfiletagmismatch}"
      The status should equal 1
      The stderr should equal "warn: begin/end block issues found"
    End

  End
End
