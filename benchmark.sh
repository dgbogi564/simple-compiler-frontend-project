#!/bin/bash

make clean
make default || exit

printf "\n\n"

readarray -d '' testcases < <(printf '%s\0' ./testcases/* | sort -zV)
for testcase in "${testcases[@]}"; do
    ./sol-codegen < "$testcase" > /dev/null
    mv "iloc.out" "sol-iloc.out"
    ./codegen < "$testcase" > /dev/null

    if cmp -s "iloc.out" "sol-iloc.out"; then
        printf "%s:\tpassed\n" "${testcase##*/}"
    else
        printf "%s:\tfailed\n" "${testcase##*/}"
    fi
    rm -f iloc.out sol-iloc.out
done