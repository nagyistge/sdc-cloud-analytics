#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

#
# Test that the aggregator correctly combines data. Note, catest always
# guarantees us that we are running from our local directory
#

source ../catestlib.sh

function runtest
{
	echo "running test: $*"
	tl_launchsvc agg
	$NODE_EXEC $*
	RET=$?
	tl_killwait $tl_launchpid
	[[ $RET == 0 ]] || tl_fail "FAILED (returned $RET)"
}

runtest http_values.js
runtest testagg.js 'scalar' 1 
runtest testagg.js 'scalar' 10
runtest testagg.js 'key-scalar' 1
runtest testagg.js 'key-scalar' 10
runtest testagg.js 'simple-dist' 10
runtest testagg.js 'hole-dist' 10
runtest testagg.js 'key-dist' 10
runtest testagg.js 'undefined' 1
