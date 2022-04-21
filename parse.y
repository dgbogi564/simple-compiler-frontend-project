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
    ctrlExpInfo ctrlExp;
}

%token PROG PERIOD VAR
%token INT BOOL PRT THEN IF DO FI ENDWHILE ENDFOR
%token ARRAY OF
%token BEG END ASG
%token EQ NEQ LT LEQ GT GEQ AND OR TRUE FALSE
%token WHILE FOR ELSE
%token <token> ID ICONST

%type <idList> idlist
%type <type> type
%type <type> stype
%type <targetReg> exp
%type <targetReg> lhs
%type <ctrlExp> ctrlexp

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
		PROG ID ';' block PERIOD {

    }
		;

	block
		: variables cmpdstmt {

        }
		;

	variables
		: /* empty */
		| VAR vardcls {

            }
		;

	vardcls
		: vardcls vardcl ';' {

        }
		| vardcl ';' {

        }
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
		: BEG stmtlist END {

        }
		;

	ifstmt
		: ifhead THEN stmt ELSE stmt FI {
            // TODO
        }
		;

	ifhead
		: IF condexp { // TODO }
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
		: {
            d;
        }
        FOR ctrlexp DO stmt {
            SymTabEntry *symbol = lookup($2.varName);
            int newLbl1 = NextLabel();
            int newLbl2 = NextLabel();
            int newLbl3 = NextLabel();
            int newReg1 = NextRegister();
            int newReg2 = NextRegister();

            sprintf(CommentBuffer, "// Generate control code for \"FOR\"");
            emitComment(CommentBuffer);
            emit(newLbl1, LOADAI, 0, symbol->offset, newReg1);
            emit(NOLABEL, CMPLE, newReg1, $2.upperBound.targetRegister, newReg2);
            emit(NOLABEL, CBR, newReg2, newLbl2, newLbl3);
            emit(newLbl2, NOP, EMPTY, EMPTY, EMPTY);

            emit(newLbl3, NOP, EMPTY, EMPTY, EMPTY);
        }
		ENDFOR
		;

	wstmt
		: WHILE condexp DO stmt {

        }
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
			$$.type = TYPE_INT;

			$$.targetRegister = newReg;
			emit(NOLABEL,
				 ADD,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
		}
		| exp '-' exp {
			int newReg = NextRegister();

			if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
				printf("*** ERROR ***: Operator types must be integer.\n");
			}
			$$.type = TYPE_INT;

			$$.targetRegister = newReg;
			emit(NOLABEL,
				 SUB,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp '*' exp {
			int newReg = NextRegister();

			if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
				printf("*** ERROR ***: Operator types must be integer.\n");
			}
			$$.type = TYPE_INT;

			$$.targetRegister = newReg;
			emit(NOLABEL,
				 MULT,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp AND exp {
			int newReg = NextRegister();

			if (! (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL))) {
				printf("*** ERROR ***: Operator types must be integer.\n");
			}
			$$.type = TYPE_BOOL;

			$$.targetRegister = newReg;
			emit(NOLABEL,
                 AND_INSTR,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp OR exp {
			int newReg = NextRegister();

			if (! (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL))) {
				printf("*** ERROR ***: Operator types must be integer.\n");
			}
			$$.type = TYPE_BOOL;

			$$.targetRegister = newReg;
			emit(NOLABEL,
                 OR_INSTR,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }

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
            emitComment(CommentBuffer);
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
		: ID ASG ICONST ',' ICONST {
            SymTabEntry *symbol = lookup($1.str);
            int newReg1 = NextRegister();
            int newReg2 = NextRegister();
            int newReg3 = NextRegister();
            int newReg4 = NextRegister();

            $$.varName = $1.str;
            $$.upperBound.targetRegister = newReg4;
            $$.upperBound.type = TYPE_INT;

            sprintf(CommentBuffer, "Initialize ind. variable \"%s\" at offset %d with lower bound value %d", symbol->name, symbol->offset, $3.num);
            emitComment(CommentBuffer);
            emit(NOLABEL, LOADI, symbol->offset, newReg1, EMPTY);
            emit(NOLABEL, ADD, 0, newReg1, newReg2);
            emit(NOLABEL, LOADI, $3.num, newReg3, EMPTY);
            emit(NOLABEL, LOADI, $5.num, newReg4, EMPTY);
            emit(NOLABEL, STORE, newReg3, newReg2, EMPTY);
        }
		;

	condexp
		: exp NEQ exp {
			int newReg = NextRegister();
			$$.type = TYPE_BOOL;
			$$.targetRegister = newReg;
			emit(NOLABEL,
                 CMPNE,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp EQ exp {
			int newReg = NextRegister();
			$$.type = TYPE_BOOL;
			$$.targetRegister = newReg;
			emit(NOLABEL,
                 CMPEQ,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp LT exp {
			int newReg = NextRegister();
			$$.type = TYPE_BOOL;
			$$.targetRegister = newReg;
			emit(NOLABEL,
                 CMPLT,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp LEQ exp {
			int newReg = NextRegister();
			$$.type = TYPE_BOOL;
			$$.targetRegister = newReg;
			emit(NOLABEL,
                 CMPLE,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp GT exp {
			int newReg = NextRegister();
			$$.type = TYPE_BOOL;
			$$.targetRegister = newReg;
			emit(NOLABEL,
                 CMPGT,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
		| exp GEQ exp {
			int newReg = NextRegister();
			$$.type = TYPE_BOOL;
			$$.targetRegister = newReg;
			emit(NOLABEL,
                 CMPGE,
				 $1.targetRegister,
				 $3.targetRegister,
				 newReg);
        }
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