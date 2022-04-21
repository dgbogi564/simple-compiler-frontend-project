%{
	#include <stdio.h>
	#include "attr.h"
	#include "instrutil.h"
	int yylex();
	void yyerror(char * s);
	#include "symtab.h"
	FILE *outfile;
	char *CommentBuffer;
%}

%union {
	tokentype token;
	datatype type;
	regInfo targetReg;
	idInfo *idList;
}

%token PROG PERIOD VAR
%token INT BOOL PRT THEN IF DO FI ENDWHILE ENDFOR
%token ARRAY OF
%token BEG END ASG
%token EQ NEQ LT LEQ GT GEQ AND OR TRUE FALSE
%token WHILE FOR ELSE
%token <token> ID ICONST

%type <idList> idlist
%type <type> type stype
%type <targetReg> exp
%type <targetReg> lhs

%start program

%nonassoc EQ NEQ LT LEQ GT GEQ
%left '+' '-' AND
%left '*' OR

%nonassoc THEN
%nonassoc ELSE

%%
	program
		: {
			emitComment("Assign STATIC_AREA_ADDRESS to register \"r0\"");
			emit(NOLABEL, LOADI, STATIC_AREA_ADDRESS, 0, EMPTY);
		}
		PROG ID ';' block PERIOD { }
		;

	block
		: variables cmpdstmt { }
		;

	variables
		: /* empty */
		| VAR vardcls { }
		;

	vardcls
		: vardcls vardcl ';' { }
		| vardcl ';' { }
		| error ';' { yyerror("***Error: illegal variable declaration\n"); }
		;

	vardcl
		: idlist ':' type {
			while ($1 != NULL) {
				idInfo *temp = $1->next;
				insert($1->str, $3.type, NextOffset($3.size), $3.size);
				free($1);
				$1 = temp;
			}
		}
		;

	idlist
		: ID ',' idlist {
			$$ = malloc(sizeof(idInfo));
			$$->str = $1.str;
			$$->next = $3;
		}
		| ID {
			$$ = malloc(sizeof(idInfo));
			$$->str = $1.str;
			$$->next = NULL;
		}
		;


	type
		: ARRAY '[' ICONST ']' OF stype {
			$$ = $6;
			$$.size = $3.num;
		}
		| stype {
			$$ = $1;
			$$.size = 1;
		}
		;

	stype
		: INT { $$.type = TYPE_INT; }
		| BOOL { $$.type = TYPE_BOOL; }
		;

	stmtlist
		: stmtlist ';' stmt { }
		| stmt { }
		| error { yyerror("***Error: ';' expected or illegal statement \n"); }
		;

	stmt
		: ifstmt { }
		| fstmt { }
		| wstmt { }
		| astmt { }
		| writestmt { }
		| cmpdstmt { }
		;

	cmpdstmt
		: BEG stmtlist END { }
		;

	ifstmt
		: ifhead
			THEN
					stmt
			ELSE
					stmt
		FI
		;

	ifhead
		: IF condexp {  }
		;

	writestmt
		: PRT '(' exp ')' {
			int printOffset = -4; /* default location for printing */
			sprintf(CommentBuffer, "Code for \"PRINT\" from offset %d", printOffset);
			emitComment(CommentBuffer);
			emit(NOLABEL, STOREAI, $3.targetRegister, 0, printOffset);
			emit(NOLABEL,
				 OUTPUTAI,
				 0,
				 printOffset,
				 EMPTY);
		}
		;

	fstmt
		: FOR ctrlexp DO stmt { }
		ENDFOR
		;

	wstmt
		: WHILE condexp DO stmt { }
		ENDWHILE
		;


	astmt
		: lhs ASG exp {
			if (! ((($1.type == TYPE_INT) && ($3.type == TYPE_INT)) ||
				   (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL)))) {
				printf("*** ERROR ***: Assignment types do not match.\n");
			}
			emit(NOLABEL,
				 STORE,
				 $3.targetRegister,
				 $1.targetRegister,
				 EMPTY);
		}
		;

	lhs
		: ID {
			SymTabEntry *symbol = lookup($1.str);
			int newReg1 = NextRegister();
            int newReg2 = NextRegister();

			$$.targetRegister = newReg2;
			$$.type = symbol->type;

            sprintf(CommentBuffer, "Compute address of variable \"%s\" at offset %d in register %d", symbol->name, symbol->offset, newReg2);
            emitComment(CommentBuffer);
			emit(NOLABEL, LOADI, symbol->offset, newReg1, EMPTY);
			emit(NOLABEL, ADD, 0, newReg1, newReg2);
		}
		|  ID '[' exp ']' {
			SymTabEntry *symbol = lookup($1.str);
			int newReg1 = NextRegister();
			int newReg2 = NextRegister();
            int newReg3 = NextRegister();
            int newReg4 = NextRegister();
            int newReg5 = NextRegister();

			$$.targetRegister = newReg5;
			$$.type = symbol->type;

            sprintf(CommentBuffer, "Compute address of array variable \"%s\" with base address %d", symbol->name, symbol->offset);
            emitComment(CommentBuffer);
			emit(NOLABEL, LOADI, 4, newReg1, EMPTY);
			emit(NOLABEL, MULT, newReg1, $3.targetRegister, newReg2);
            emit(NOLABEL, LOADI, symbol->offset, newReg3, EMPTY);
            emit(NOLABEL, ADD, 0, newReg3, newReg4);
			emit(NOLABEL, ADD, newReg2, newReg4, newReg5);
		}
		;


	exp
		: exp '+' exp {
			int newReg = NextRegister();

			if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
				printf("*** ERROR ***: Operator types must be integer.\n");
			}
			$$.type = $1.type;

			$$.targetRegister = newReg;
			emit(NOLABEL,
				 ADD,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
		}
		| exp '-' exp {  }
		| exp '*' exp {  }
		| exp AND exp {  }
		| exp OR  exp {  }

		| ID {
			SymTabEntry *symbol = lookup($1.str);
			int newReg = NextRegister();

			$$.targetRegister = newReg;
			$$.type = symbol->type;

            sprintf(CommentBuffer, "Load RHS value of variable \"%s\" at offset %d", symbol->name, symbol->offset);
            emitComment(CommentBuffer);
			emit(NOLABEL, LOADAI, 0, symbol->offset, newReg);
		}
		| ID '[' exp ']' {
			SymTabEntry *symbol = lookup($1.str);
			int newReg1 = NextRegister();
			int newReg2 = NextRegister();
            int newReg3 = NextRegister();
            int newReg4 = NextRegister();
            int newReg5 = NextRegister();
            int newReg6 = NextRegister();

            $$.targetRegister = newReg6;
            $$.type = symbol->type;

            sprintf(CommentBuffer, "Load RHS value of array variable \"%s\" with base address %d", symbol->name, symbol->offset);
            emit(NOLABEL, LOADI, 4, newReg1, EMPTY);
            emit(NOLABEL, MULT, newReg1, $3.targetRegister, newReg2);
            emit(NOLABEL, LOADI, symbol->offset, newReg3, EMPTY);
            emit(NOLABEL, ADD, 0, newReg3, newReg4);
            emit(NOLABEL, ADD, newReg2, newReg4, newReg5);
            emit(NOLABEL, LOAD, newReg5, newReg6, EMPTY);
		}

		| ICONST {
			int newReg = NextRegister();
			$$.targetRegister = newReg;
			$$.type = TYPE_INT;
			emit(NOLABEL, LOADI, $1.num, newReg, EMPTY);
		}
		| TRUE {
			int newReg = NextRegister(); /* TRUE is encoded as value '1' */
			$$.targetRegister = newReg;
			$$.type = TYPE_BOOL;
			emit(NOLABEL, LOADI, 1, newReg, EMPTY);
		}
		| FALSE {
			int newReg = NextRegister(); /* TRUE is encoded as value '0' */
			$$.targetRegister = newReg;
			$$.type = TYPE_BOOL;
			emit(NOLABEL, LOADI, 0, newReg, EMPTY);
		}

		| error { yyerror("***Error: illegal expression\n"); }
		;


	ctrlexp
		: ID ASG ICONST ',' ICONST { }
		;

	condexp
		: exp NEQ exp { }
		| exp EQ exp { }
		| exp LT exp { }
		| exp LEQ exp { }
		| exp GT exp { }
		| exp GEQ exp { }
		| error { yyerror("***Error: illegal conditional expression\n"); }
		;
%%

void yyerror(char * s) {
    fprintf(stderr, "%s\n", s);
}

int main(int argc, char * argv[]) {

    printf("\n     CS415 Spring 2022 Compiler\n\n");

    outfile = fopen("iloc.out", "w");
    if (outfile == NULL) {
        printf("ERROR: Cannot open output file \"iloc.out\".\n");
        return -1;
    }

    CommentBuffer = (char * ) malloc(1961);
    InitSymbolTable();

    printf("1\t");
    yyparse();
    printf("\n");

    PrintSymbolTable();

    fclose(outfile);

    return 1;
}