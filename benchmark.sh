#!/bin/bash

make clean
make default || exit
mkdir -p out
mkdir -p sol-out

printf "\n\n"

readarray -d '' testcases < <(printf '%s\0' ./testcases/* | sort -zV)
for testcase in "${testcases[@]}"; do

    ./sol-codegen < "$testcase" > "./sol-out/${testcase##*/}.log"
    mv "iloc.out" "./sol-out/${testcase##*/}.iloc"
    ~uli/cs415/ILOC_Simulator/sim < "./sol-out/${testcase##*/}.iloc" > "./sol-out/${testcase##*/}.out"

    ./codegen < "$testcase" > "./out/${testcase##*/}.log"
    mv "iloc.out" "./out/${testcase##*/}.iloc"
    ~uli/cs415/ILOC_Simulator/sim < "./out/${testcase##*/}.iloc" > "./out/${testcase##*/}.out"


    if cmp -s "./sol-out/${testcase##*/}.out" "./out/${testcase##*/}.out"; then
        printf "%s:\tpassed\n" "${testcase##*/}"
    else
        printf "%s:\tfailed\n" "${testcase##*/}"
    fi

done