/*
 * V8 DTrace ustack helper for annotating native stack traces with JavaScript
 * function names.  We start with a frame pointer (arg1) and emit a string
 * describing the current function.  We do this by chasing various pointers to
 * extract the function's name (if any) and the filename and line number where
 * the function is defined.
 *
 * To use this helper, you must first build an object file with it using:
 *
 *	# dtrace -C -G -o node_helper.o -s node_helper.d
 *
 * Then link this object file with the final program that uses V8 (e.g., node).
 * Run your program, then run dtrace(1M), using the jstack() action to capture
 * a JavaScript stacktrace.
 */

/*
 * The following offsets are derived from the V8 source.  A completed version
 * of this helper would include these offsets from a header file generated by
 * the build process.  We use these to follow pointers between various
 * structures in the V8 heap.
 */
#define	V8_OFF_FP_FUNC		-0x8
#define	V8_OFF_FUNC_SHARED	0x13
#define	V8_OFF_SHARED_NAME	0x3
#define	V8_OFF_SHARED_SCRIPT	0x1b
#define	V8_OFF_SHARED_FUNTOK	0x4b
#define	V8_OFF_SCRIPT_NAME	0x7
#define	V8_OFF_SCRIPT_LENDS	0x27
#define	V8_OFF_STR_LENGTH	0x3
#define	V8_OFF_STR_CHARS	0xb
#define	V8_OFF_CONSTR_CAR	0xb
#define	V8_OFF_CONSTR_CDR	0xf
#define	V8_OFF_SCRIPT_LINEENDS	0x27
#define	V8_OFF_FA_SIZE		0x3
#define	V8_OFF_FA_DATA		0x7

/*
 * Invalid V8 heap pointers are sometimes represented using the "undefined"
 * heap value (rather than NULL).  In order to compare against this value, we
 * read it in from V8's Heap::roots_ array.
 */
extern uintptr_t _ZN2v88internal4Heap6roots_E;
#define	V8_VAR_ROOTS		(uintptr_t)&``_ZN2v88internal4Heap6roots_E
#define	V8_OFF_ROOTS_UNDEF	0x10	/* 5th pointer in roots_ */

/*
 * V8 represents small integers (SMI) using the upper 31 bits of a 32-bit
 * value.  To extract the actual integer value, we must shift it over.
 */
#define SMI_VALUE(value)		((int32_t)(value) >> 1)

/*
 * The following macros simplify common operations in the helper below.
 */
#define	COPYIN_UINT32(addr)		\
	(*(uint32_t *)copyin((addr), sizeof (uint32_t)))

#define	APPEND_CHR(c)			(this->buf[this->off++] = (c))

#define	APPEND_DGT(i, d)	\
	(((i) / (d)) ? APPEND_CHR('0' + ((i)/(d) % 10)) : 0)

#define	APPEND_NUM(i)		\
	APPEND_DGT((i), 10000);	\
	APPEND_DGT((i), 1000);	\
	APPEND_DGT((i), 100);	\
	APPEND_DGT((i), 10);	\
	APPEND_DGT((i), 1);

/*
 * Clear all variables first so that subsequent clauses can assume they'll be
 * unset if they weren't set this time around.  Otherwise we may have garbage
 * values from previous iterations here.
 *
 * XXX We know that we don't yet handle all possible cases, and we deal with
 * this implicitly by checking in subsequent clauses whether certain variables
 * are set to non-NULL values.  (If we get something wrong due to an unhandled
 * case, we'll likely see a pointer dereference fail and the corresponding
 * variables will be unset.) Still, it would be better to explicitly predicate
 * on the appropriate conditions.
 */
dtrace:helper:ustack:
{
	/* output/control fields */
	this->buf = (char *)0;
	this->off = 0;
	this->done = 0;

	/* program state */
	this->undef_value = 0;
	this->fp = 0;
	this->func = 0;	
	this->shared = 0;	

	this->func_name_obj = 0;
	this->func_name_len = 0;
	this->hasname = 0;

	this->position = 0;	
	this->scriptobj = 0;
	this->line_ends = 0;	

	/* binary search fields */
	this->bsearch_min = 0;
	this->bsearch_max = 0;
	this->ii = 0;
}

/*
 * Initialize variables and read in structures common to all frames.
 */
dtrace:helper:ustack:
{
	this->buf = alloca(128);
	this->fp = arg1;
	this->undef_value = COPYIN_UINT32(V8_VAR_ROOTS + V8_OFF_ROOTS_UNDEF);
	this->func = COPYIN_UINT32(this->fp + V8_OFF_FP_FUNC);
	this->shared = COPYIN_UINT32(this->func + V8_OFF_FUNC_SHARED);
	this->scriptobj = COPYIN_UINT32(this->shared + V8_OFF_SHARED_SCRIPT);

	/* function name information */
	this->func_name_obj = COPYIN_UINT32(this->shared + V8_OFF_SHARED_NAME);
	this->func_name_len = SMI_VALUE(COPYIN_UINT32(this->func_name_obj +
	    V8_OFF_STR_LENGTH));

	/* file name information */
	this->script_name = COPYIN_UINT32(this->scriptobj + V8_OFF_SCRIPT_NAME);
	this->script_name_car = COPYIN_UINT32(this->script_name +
	    V8_OFF_CONSTR_CAR);
	this->script_name_car_len = SMI_VALUE(COPYIN_UINT32(
	    this->script_name_car + V8_OFF_STR_LENGTH));

	/* line number information */
	this->position = COPYIN_UINT32(this->shared + V8_OFF_SHARED_FUNTOK);
	this->line_ends = COPYIN_UINT32(this->scriptobj + V8_OFF_SCRIPT_LENDS);
}

/*
 * Output the function name.
 * XXX assumes seqascii string
 * XXX ascii heuristics are too cheesy
 */
dtrace:helper:ustack:
/this->func_name_obj &&
 (this->chr = *(char *)copyin(this->func_name_obj + V8_OFF_STR_CHARS,
  sizeof (char))) >= ' ' && this->chr <= '~'/
{
	this->hasname = 1;
	copyinto((uintptr_t)this->func_name_obj + V8_OFF_STR_CHARS,
	    this->func_name_len, this->buf + this->off);
	this->off += this->func_name_len;
	APPEND_CHR(' ');
	APPEND_CHR('(');
}

dtrace:helper:ustack:
/!this->hasname/
{
	APPEND_CHR('<');
	APPEND_CHR('u');
	APPEND_CHR('n');
	APPEND_CHR('k');
	APPEND_CHR('n');
	APPEND_CHR('o');
	APPEND_CHR('w');
	APPEND_CHR('n');
	APPEND_CHR('>');
	APPEND_CHR(' ');
	APPEND_CHR('(');
}

/*
 * Output the file name.
 * XXX assumes cons string
 */
dtrace:helper:ustack:
/this->script_name_car &&
 (this->chr = *(char *)copyin(this->script_name_car + V8_OFF_STR_CHARS,
  sizeof (char))) >= ' ' && this->chr <= '~'/
{
	this->hasfile = 1;
	copyinto((uintptr_t)this->script_name_car + V8_OFF_STR_CHARS,
	    this->script_name_car_len, this->buf + this->off);
	this->off += this->script_name_car_len;
	APPEND_CHR(' ');
}

dtrace:helper:ustack:
/!this->hasfile/
{
	APPEND_CHR('<');
	APPEND_CHR('u');
	APPEND_CHR('n');
	APPEND_CHR('k');
	APPEND_CHR('n');
	APPEND_CHR('o');
	APPEND_CHR('w');
	APPEND_CHR('n');
	APPEND_CHR('>');
	APPEND_CHR(' ');
}

/*
 * If we don't even have position information, we're done.
 */
dtrace:helper:ustack:
/this->position == 0/
{
	APPEND_CHR('<');
	APPEND_CHR('u');
	APPEND_CHR('n');
	APPEND_CHR('k');
	APPEND_CHR('n');
	APPEND_CHR('o');
	APPEND_CHR('w');
	APPEND_CHR('n');
	APPEND_CHR('>');
	APPEND_CHR('\0');
	this->done = 1;
	stringof(this->buf);
}

/*
 * If we have position information but no line number information, we
 * just report the position.
 */
dtrace:helper:ustack:
/!this->done && (this->line_ends == 0 || this->line_ends == this->undef_value)/
{
	APPEND_CHR('p');
	APPEND_CHR('o');
	APPEND_CHR('s');
	APPEND_CHR('i');
	APPEND_CHR('t');
	APPEND_CHR('i');
	APPEND_CHR('o');
	APPEND_CHR('n');
	APPEND_CHR(' ');
	APPEND_NUM(this->position);
	APPEND_CHR(')');
	APPEND_CHR('\0');
	this->done = 1;
	stringof(this->buf);
}

/*
 * If we're not done yet, it's because we have enough information to do a full
 * binary search to find the line number.
 */
dtrace:helper:ustack:
/!this->done/
{
	/* initialize binary search */
	this->bsearch_line = this->position < COPYIN_UINT32(
	    this->line_ends + V8_OFF_FA_DATA) ? 1 : 0;
	this->bsearch_min = 0;
	this->bsearch_max = this->bsearch_line != 0 ? 0 :
	    SMI_VALUE(COPYIN_UINT32(this->line_ends + V8_OFF_FA_SIZE)) - 1;
}

#define	BSEARCH_LOOP							\
dtrace:helper:ustack:							\
/!this->done && this->bsearch_max >= 1/					\
{									\
	this->ii = (this->bsearch_min + this->bsearch_max) >> 1;	\
}									\
									\
dtrace:helper:ustack:							\
/!this->done && this->bsearch_max >= 1 &&				\
 this->position > COPYIN_UINT32(this->line_ends + V8_OFF_FA_DATA +	\
    this->ii * sizeof (uint32_t))/					\
{									\
	this->bsearch_min = this->ii + 1;				\
}									\
									\
dtrace:helper:ustack:							\
/!this->done && this->bsearch_max >= 1 &&				\
 this->position <= COPYIN_UINT32(this->line_ends + V8_OFF_FA_DATA + 	\
    (this->ii - 1) * sizeof (uint32_t))/				\
{									\
	this->bsearch_max = this->ii - 1;				\
}

BSEARCH_LOOP
BSEARCH_LOOP
BSEARCH_LOOP
BSEARCH_LOOP
BSEARCH_LOOP
BSEARCH_LOOP

dtrace:helper:ustack:
/!this->done && !this->bsearch_line/
{
	this->bsearch_line = this->ii + 1;
}

dtrace:helper:ustack:
/!this->done/
{
	APPEND_CHR('l');
	APPEND_CHR('i');
	APPEND_CHR('n');
	APPEND_CHR('e');
	APPEND_CHR(' ');
	APPEND_NUM(this->bsearch_line);
	APPEND_CHR(')');
	APPEND_CHR('\0');
	this->done = 1;
	stringof(this->buf);
}