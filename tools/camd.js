/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/*
 * Copyright (c) 2014, Joyent, Inc.
 */

/*
 * cachkmd.js - Given a file validate whether or not it contains a valid meta-d
 * expression.
 */

var mod_metad = require('../lib/ca/ca-metad');

function check(file)
{
	var mod, desc;

	process.stdout.write('Checking file: ' + file + '\n');
	mod = require(file);
	desc = mod.cadMetricDesc;

	mod_metad.mdValidateMetaD(desc);
}

function main() {
	var ii;

	if (process.argv.length < 3) {
		process.stdout.write('cachkmd: <file-name>\n');
		process.exit(1);
	}

	for (ii = 2; ii < process.argv.length; ii++)
		check(process.argv[ii]);

	process.stdout.write('Check okay\n');
}

main();
