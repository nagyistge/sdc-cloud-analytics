#define V8CTF_HEAPOBJ_FIELD(klass, name, type, offsetname)	\
    extern int v8ctf_##klass##__##name##__##type = klass::offsetname;

#include "v8.h"
#include "objects-inl.h"

/*
 * Define some of our own that are otherwise left undefined.
 */
namespace v8 {
namespace internal {
V8CTF_HEAPOBJ_FIELD(HeapObject, map, Map, kMapOffset);
V8CTF_HEAPOBJ_FIELD(JSObject, elements, Object, kElementsOffset);
}
}

#include <unistd.h>
#include <demangle.h>
#include <libelf.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dlfcn.h>

typedef struct field {
	struct field	*f_next;
	size_t		f_offset;
	char 		f_name[64];
	char 		f_typename[64];
} field_t;

typedef struct klass {
	struct klass	*c_next;
	field_t		*c_fields;
	char		c_name[64];
} klass_t;

klass_t *klasses;

const char *v8ctf_prefix = "v8::internal::v8ctf";

const char *code_header =
    "/*\n"
    " * heap-dbg-inl.h: auto-generated.  Do not edit directly.\n"
    " * See heap-dbg-common.h for details."
    " */\n"
    "\n"
    "#include \"heap-dbg-common.h\"\n"
    "\n";

const char *const_prefix = "V8_OFF";

static int process_symbols(Elf *);
static int parse_symbol(char *, char **, char **, char **);
static int add_field(char *, char *, char *, char *);

static void emit_code(void);
static void emit_head(void);
static void emit_constants(void);

int
main(int argc, char *argv[])
{
	int fd;
	Elf *arf, *elf;
	Elf32_Ehdr *ehdr;
	Elf_Cmd cmd;

	if (elf_version(EV_CURRENT) == EV_NONE) {
		(void) fprintf(stderr, "libelf out of date\n");
		return (1);
	}

	if ((fd = open(argv[0], O_RDONLY)) < 0) {
		perror("failed to open self\n");
		return (1);
	}

	cmd = ELF_C_READ;
	arf = elf_begin(fd, cmd, NULL);
	while ((elf = elf_begin(fd, cmd, arf)) != 0) {
		if ((ehdr = elf32_getehdr(elf)) == 0)
			continue;

		if (process_symbols(elf) != 0)
			return (1);

		cmd = elf_next(elf);
		elf_end(elf);
	}

	(void) close(fd);

	emit_code();

	return (0);
}

static int
process_symbols(Elf *elf)
{
	Elf_Data *sdata;
	Elf_Scn *scn = NULL;
	Elf32_Sym *sym;
	Elf32_Shdr *shdr;
	int ii, nsym;
	char *symname;
	char *klass, *type, *field;
	char demangled[128];

	while ((scn = elf_nextscn(elf, scn)) != NULL) {
		if ((shdr = elf32_getshdr(scn)) == NULL) {
			(void) fprintf(stderr, "failed to get shdr\n");
			return (-1);
		}

		if (shdr->sh_type != SHT_SYMTAB)
			continue;

		if ((sdata = elf_getdata(scn, NULL)) == NULL) {
			(void) fprintf(stderr, "failed to get symtab data\n");
			return (-1);
		}

		nsym = shdr->sh_size / shdr->sh_entsize;
		for (ii = 0; ii < nsym; ii++) {
			sym = &((Elf32_Sym *)sdata->d_buf)[ii];

			if (ELF32_ST_BIND(sym->st_info) != STB_GLOBAL)
				continue;

			symname = elf_strptr(elf, shdr->sh_link, sym->st_name);

			if (cplus_demangle(symname, demangled,
			    sizeof (demangled)) != 0)
				continue;

			if (strncmp(demangled, v8ctf_prefix,
			    strlen(v8ctf_prefix)) != 0)
				continue;

			if (parse_symbol(demangled, &klass, &field, &type) != 0)
				continue;

			if (add_field(symname, klass, field, type) != 0)
				return (-1);
		}
	}

	return (0);
}

static int
parse_symbol(char *demangled, char **klassp, char **fieldp, char **typep)
{
	char *pp, *qq;

	pp = *klassp = demangled + strlen(v8ctf_prefix) + 1;
	if ((qq = strstr(pp, "__")) == NULL) {
		(void) fprintf(stderr, "malformed: %s\n", demangled);
		return (-1);
	}

	*qq = '\0';
	pp = qq + 2;

	*fieldp = pp;
	if ((qq = strstr(pp, "__")) == NULL) {
		(void) fprintf(stderr, "malformed: %s\n", demangled);
		return (-1);
	}

	*qq = '\0';
	pp = qq + 2;

	*typep = pp;
	return (0);
}

static int
add_field(char *symname, char *klass, char *field, char *type)
{
	uint32_t *addr;
	klass_t *clp = NULL;
	field_t *flp, *oflp;

	if ((addr = (uint32_t *)dlsym(RTLD_DEFAULT, symname)) == NULL) {
		(void) fprintf(stderr, "symbol not found: %s\n", symname);
		return (-1);
	}

	for (clp = klasses; clp != NULL; clp = clp->c_next) {
		if (strcmp(clp->c_name, klass) == 0)
			break;
	}

	if (clp == NULL) {
	       	if ((clp = (klass_t *)malloc(sizeof (*clp))) == NULL) {
			perror("malloc");
			return (-1);
		}

		(void) strlcpy(clp->c_name, klass, sizeof (clp->c_name));

		clp->c_fields = NULL;
		clp->c_next = klasses;
		klasses = clp;
	}

	if ((flp = (field_t *)malloc(sizeof (*flp))) == NULL) {
		perror("malloc");
		return (-1);
	}

	flp->f_offset = *addr;
	(void) strlcpy(flp->f_name, field, sizeof (flp->f_name));
	(void) strlcpy(flp->f_typename, type, sizeof (flp->f_typename));

	if (clp->c_fields == NULL || clp->c_fields->f_offset > flp->f_offset) {
		flp->f_next = clp->c_fields;
		clp->c_fields = flp;
		return (0);
	}

	for (oflp = clp->c_fields; oflp->f_next != NULL; oflp = oflp->f_next) {
		if (oflp->f_next->f_offset > flp->f_offset)
			break;
	}

	flp->f_next = oflp->f_next;
	oflp->f_next = flp;

	return (0);
}

static void
emit_code(void)
{
	emit_head();
	emit_constants();
}

static void
emit_head(void)
{
	(void) printf(code_header);
}

static void
emit_constants(void)
{
	klass_t *clp;
	field_t *flp;

	for (clp = klasses; clp != NULL; clp = clp->c_next) {
		(void) printf("/* %s class constants */\n", clp->c_name);

		for (flp = clp->c_fields; flp != NULL; flp = flp->f_next)
			(void) printf("#define\t%s_%s_%s\t"
			    "(V8_OFF_HEAP(0x%x))\n", const_prefix,
			    clp->c_name, flp->f_name, flp->f_offset);

		(void) printf("\n");
	}
}