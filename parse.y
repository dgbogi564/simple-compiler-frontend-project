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
    jmpInfo jmp;
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
%type <targetReg> condexp
%type <targetReg> ifhead
%type <ctrlExp> ctrlexp
%type <jmp> ifstmt
%type <jmp> wstmt

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
                SymTabEntry *symbol = lookup($1->str);
                if (symbol) {
                    printf("\n***Error: duplicate declaration of %s\n", $1->str);
                }
                insert($1->str, $3.type, NextOffset($3.size), $3.size, $3.isArray);
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
            $$.isArray = 1;
		}
		| stype {
			$$ = $1;
			$$.size = 1;
            $$.isArray = 0;
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
            {
                $<jmp>$ = (jmpInfo) { NextLabel(), NextLabel(), NextLabel() };

                emit(NOLABEL, CBR, $1.targetRegister, $<jmp>$.label[0], $<jmp>$.label[1]);
            }
            THEN
                {
                    emit($<jmp>2.label[0], NOP, EMPTY, EMPTY, EMPTY);
                    sprintf(CommentBuffer, "This is the \"true\" branch");
                    emitComment(CommentBuffer);
                }
                stmt
                {
                    sprintf(CommentBuffer, "Branch to statement following the \"else\" statement list");
                    emitComment(CommentBuffer);
                    emit(NOLABEL, BR, $<jmp>2.label[2], EMPTY, EMPTY);
                }
            ELSE
                {
                    emit($<jmp>2.label[1], NOP, EMPTY, EMPTY, EMPTY);
                    sprintf(CommentBuffer, "This is the \"false\" branch");
                    emitComment(CommentBuffer);
                }
                stmt
        FI
            {
                emit($<jmp>2.label[2], NOP, EMPTY, EMPTY, EMPTY);
            }
        ;

	ifhead
		: IF condexp {
            if ($2.type != TYPE_BOOL) {
                printf("\n***Error: exp in if stmt must be boolean\n");
            }
            $$ = $2;
        }
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
		: FOR ctrlexp DO stmt {
            SymTabEntry *symbol = lookup($2.iterName);
            if (!symbol) {
                printf("\n***Error: undeclared identifier %s\n", $2.iterName);
            } else {
                int newReg1 = NextRegister();
                int newReg2 = NextRegister();

                emit(NOLABEL, LOADAI, 0, symbol->offset, newReg1);
                emit(NOLABEL, ADDI, newReg1, 1, newReg2);
                emit(NOLABEL, STOREAI, newReg2, 0, symbol->offset);
                emit(NOLABEL, BR, $2.bgnLbl, EMPTY, EMPTY);
                emit($2.endLbl, NOP, EMPTY, EMPTY, EMPTY);
            }
        }
		ENDFOR
		;
	wstmt
		: {
            $<jmp>$ = (jmpInfo) { NextLabel(), NextLabel(), NextLabel() };
            emit($<jmp>$.label[0], NOP, EMPTY, EMPTY, EMPTY);
            sprintf(CommentBuffer, "Control code for \"WHILE DO\"");
            emitComment(CommentBuffer);
        }
        WHILE condexp DO
            {
                if ($3.type != TYPE_BOOL) {
                    printf("\n***Error: exp in while stmt must be boolean\n");
                } else {
                    emit(NOLABEL, CBR, $3.targetRegister, $<jmp>1.label[1], $<jmp>1.label[2]);
                    emit($<jmp>1.label[1], NOP, EMPTY, EMPTY, EMPTY);
                    sprintf(CommentBuffer, "Body of \"WHILE\" construct starts here");
                    emitComment(CommentBuffer);
                }
            }
            stmt
		ENDWHILE
        {
            emit(NOLABEL, BR, $<jmp>1.label[0], EMPTY, EMPTY);
            emit($<jmp>1.label[2], NOP, EMPTY, EMPTY, EMPTY);
        }
		;
	astmt
		: lhs ASG exp {
			if (! ((($1.type == TYPE_INT) && ($3.type == TYPE_INT)) ||
				   (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL)))) {
                printf("\n***Error: assignment types do not match\n");
			} else {
                emit(NOLABEL,
                     STORE,
                     $3.targetRegister,
                     $1.targetRegister,
                     EMPTY);
            }
		}
		;

	lhs
		: ID {
			SymTabEntry *symbol = lookup($1.str);
            if (!symbol) {
                printf("\n***Error: undeclared identifier %s\n", $1.str);
            } else if (symbol->isArray) {
                printf("\n***Error: assignment to whole array\n");
            } else {
                int newReg1 = NextRegister();
                int newReg2 = NextRegister();

                $$.targetRegister = newReg2;
                $$.type = symbol->type;

                sprintf(CommentBuffer, "Compute address of variable \"%s\" at offset %d in register %d", symbol->name, symbol->offset, newReg2);
                emitComment(CommentBuffer);
                emit(NOLABEL, LOADI, symbol->offset, newReg1, EMPTY);
                emit(NOLABEL, ADD, 0, newReg1, newReg2);
            }
		}
		|  ID '[' exp ']' {
			SymTabEntry *symbol = lookup($1.str);
            if (!symbol) {
                printf("\n***Error: undeclared identifier %s\n", $1.str);
            } else if (!symbol->isArray) {
                printf("\n***Error: id %s is not an array\n", $1.str);
            } else if ($3.type != TYPE_INT) {
                printf("\n***Error: subscript exp not type integer\n");
            } else {
                int newReg1 = NextRegister();
                int newReg2 = NextRegister();
                int newReg3 = NextRegister();
                int newReg4 = NextRegister();
                int newReg5 = NextRegister();

                $$.targetRegister = newReg1;
                $$.type = symbol->type;

                sprintf(CommentBuffer, "Compute address of array variable \"%s\" with base address %d", symbol->name, symbol->offset);
                emitComment(CommentBuffer);
                emit(NOLABEL, LOADI, 4, newReg2, EMPTY);
                emit(NOLABEL, MULT, $3.targetRegister, newReg2, newReg3);
                emit(NOLABEL, LOADI, symbol->offset, newReg4, EMPTY);
                emit(NOLABEL, ADD, newReg4, newReg3, newReg5);
                emit(NOLABEL, ADD, 0, newReg5, newReg1);
            }
		}
		;


	exp
		: exp '+' exp {
            if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation + do not match\n");
                $$.type = TYPE_ERROR;
			} else {
                int newReg = NextRegister();

                $$.targetRegister = newReg;
                $$.type = TYPE_INT;

                emit(NOLABEL,
                     ADD,
                     $1.targetRegister,
                     $3.targetRegister,
                     newReg);
            }
		}
		| exp '-' exp {
			if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation - do not match\n");
                $$.type = TYPE_ERROR;
			} else {
                int newReg = NextRegister();
                
                $$.targetRegister = newReg;
                $$.type = TYPE_INT;
                
                emit(NOLABEL,
                     SUB,
                     $1.targetRegister,
                     $3.targetRegister,
                     newReg);
            }
        }
		| exp '*' exp {
			if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation * do not match\n");
                $$.type = TYPE_ERROR;
			} else {
                int newReg = NextRegister();
                
                $$.targetRegister = newReg;
                $$.type = TYPE_INT;
                
                emit(NOLABEL,
                     MULT,
                     $1.targetRegister,
                     $3.targetRegister,
                     newReg);
            }
        }
		| exp AND exp {
			if (! (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL))) {
                printf("\n***Error: types of operands for operation AND do not match\n");
                $$.type = TYPE_ERROR;
			} else {
                int newReg = NextRegister();
                
                $$.targetRegister = newReg;
                $$.type = TYPE_BOOL;
                
                emit(NOLABEL,
                     AND_INSTR,
                     $1.targetRegister,
                     $3.targetRegister,
                     newReg);
            }
        }
		| exp OR exp {
			if (! (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL))) {
                printf("\n***Error: types of operands for operation OR do not match\n");
                $$.type = TYPE_ERROR;
			} else {
                int newReg = NextRegister();
                
                $$.targetRegister = newReg;
                $$.type = TYPE_BOOL;
                
                emit(NOLABEL,
                     OR_INSTR,
                     $1.targetRegister,
                     $3.targetRegister,
                     newReg);
            }
        }

		| ID {
			SymTabEntry *symbol = lookup($1.str);
            if (!symbol) {
                printf("\n***Error: undeclared identifier %s\n", $1.str);
                $$.type = TYPE_ERROR;
            } else {
                int newReg = NextRegister();

                $$.targetRegister = newReg;
                $$.type = symbol->type;

                sprintf(CommentBuffer, "Load RHS value of variable \"%s\" at offset %d", symbol->name, symbol->offset);
                emitComment(CommentBuffer);
                emit(NOLABEL, LOADAI, 0, symbol->offset, newReg);
            }
		}
		| ID '[' exp ']' {
			SymTabEntry *symbol = lookup($1.str);
            if (!symbol) {
                printf("\n***Error: undeclared identifier %s\n", $1.str);
            } else {
                int newReg1 = NextRegister();
                int newReg2 = NextRegister();
                int newReg3 = NextRegister();
                int newReg4 = NextRegister();
                int newReg5 = NextRegister();

                $$.targetRegister = newReg1;
                $$.type = symbol->type;

                sprintf(CommentBuffer, "Load RHS value of array variable \"%s\" with base address %d", symbol->name, symbol->offset);
                emitComment(CommentBuffer);
                emit(NOLABEL, LOADI, 4, newReg2, EMPTY);
                emit(NOLABEL, MULT, $3.targetRegister, newReg2, newReg3);
                emit(NOLABEL, LOADI, symbol->offset, newReg4, EMPTY);
                emit(NOLABEL, ADD, newReg4, newReg3, newReg5);
                emit(NOLABEL, LOADAO, 0, newReg5, newReg1);
            }
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
            if ($3.num > $5.num) {
                printf("\n***Error: lower bound exceeds upper bound\n");
            } else if (!symbol) {
                printf("\n***Error: undeclared identifier %s\n", $1.str);
            } else if (symbol->type != TYPE_INT) {
                printf("\n***Error: induction variable not scalar integer variable\n");
            } else {
                int newLbl1 = NextLabel();
                int newLbl2 = NextLabel();
                int newLbl3 = NextLabel();
                int newReg1 = NextRegister();
                int newReg2 = NextRegister();
                int newReg3 = NextRegister();
                int newReg4 = NextRegister();
                int newReg5 = NextRegister();
                int newReg6 = NextRegister();

                $$.iterName = $1.str;
                $$.bgnLbl = newLbl1;
                $$.endLbl = newLbl3;

                sprintf(CommentBuffer, "Initialize ind. variable \"%s\" at offset %d with lower bound value %d", symbol->name, symbol->offset, $3.num);
                emitComment(CommentBuffer);
                emit(NOLABEL, LOADI, symbol->offset, newReg1, EMPTY);
                emit(NOLABEL, ADD, 0, newReg1, newReg2);
                emit(NOLABEL, LOADI, $3.num, newReg5, EMPTY);
                emit(NOLABEL, LOADI, $5.num, newReg6, EMPTY);
                emit(NOLABEL, STORE, newReg5, newReg2, EMPTY);

                sprintf(CommentBuffer, "Generate control code for \"FOR\"");
                emitComment(CommentBuffer);
                emit(newLbl1, LOADAI, 0, symbol->offset, newReg3);
                emit(NOLABEL, CMPLE, newReg3, newReg6, newReg4);
                emit(NOLABEL, CBR, newReg4, newLbl2, newLbl3);
                emit(newLbl2, NOP, EMPTY, EMPTY, EMPTY);
            }
        }
		;

	condexp
		: exp NEQ exp {
            if ($1.type != $3.type) {
                printf("\n***Error: types of operands for operation NEQ do not match\n");
                $$.type = TYPE_ERROR;
            } else {
                int newReg = NextRegister();
                $$.type = TYPE_BOOL;
                $$.targetRegister = newReg;
                emit(NOLABEL,
                     CMPNE,
                     $1.targetRegister,
                     $3.targetRegister,
                     newReg);
            }
        }
		| exp EQ exp {
            if ($1.type != $3.type) {
                printf("\n***Error: types of operands for operation EQ do not match\n");
                $$.type = TYPE_ERROR;
            } else {
				int newReg = NextRegister();
				$$.type = TYPE_BOOL;
				$$.targetRegister = newReg;
				emit(NOLABEL,
					 CMPEQ,
					 $1.targetRegister,
					 $3.targetRegister,
					 newReg);
			}
        }
		| exp LT exp {
            if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation EQ do not match\n");
                $$.type = TYPE_ERROR;
            } else {
				int newReg = NextRegister();
				$$.type = TYPE_BOOL;
				$$.targetRegister = newReg;
				emit(NOLABEL,
					 CMPLT,
					 $1.targetRegister,
					 $3.targetRegister,
					 newReg);
			}
        }
		| exp LEQ exp {
            if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation EQ do not match\n");
                $$.type = TYPE_ERROR;
            } else {
				int newReg = NextRegister();
				$$.type = TYPE_BOOL;
				$$.targetRegister = newReg;
				emit(NOLABEL,
					 CMPLE,
					 $1.targetRegister,
					 $3.targetRegister,
					 newReg);
			}
        }
		| exp GT exp {
            if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation EQ do not match\n");
                $$.type = TYPE_ERROR;
            } else {
				int newReg = NextRegister();
				$$.type = TYPE_BOOL;
				$$.targetRegister = newReg;
				emit(NOLABEL,
					 CMPGT,
					 $1.targetRegister,
					 $3.targetRegister,
					 newReg);
			}
        }
		| exp GEQ exp {
            if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
                printf("\n***Error: types of operands for operation EQ do not match\n");
                $$.type = TYPE_ERROR;
            } else {
				int newReg = NextRegister();
				$$.type = TYPE_BOOL;
				$$.targetRegister = newReg;
				emit(NOLABEL,
					 CMPGE,
					 $1.targetRegister,
					 $3.targetRegister,
					 newReg);
			}
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
        printf("ERROR: Cannot open output file \"iloc.out\"\n");
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