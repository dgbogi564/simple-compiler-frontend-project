/**********************************************
        CS415  Project 2
        Spring  2022
        Student Version
**********************************************/

#ifndef ATTR_H
#define ATTR_H

typedef union {int num; char *str;} tokentype;

typedef enum type_expression {TYPE_INT=0, TYPE_BOOL, TYPE_ERROR} Type_Expression;

typedef struct {
    Type_Expression type;
    int targetRegister;
} regInfo;

typedef struct idInfo idInfo;
struct idInfo {
    char *str;
    idInfo *next;
};

typedef struct {
    Type_Expression type;
    int size;
    int isArray;
} datatype;

typedef struct {
    char *iterName;
    int bgnLbl;
    int endLbl;
} ctrlExpInfo;

typedef struct {
    int label[3];
} jmpInfo;



#endif


  
