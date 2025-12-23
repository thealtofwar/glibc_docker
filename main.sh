#!/bin/bash

git clone https://sourceware.org/git/glibc.git 

cd glibc

rm ../tags.txt

touch ../tags.txt

git tag | grep -E '^glibc-[0-9]+\.[0-9]+(\.[0-8]?[0-9])?$' \
| while read -r tag; do
    url="https://ftp.gnu.org/gnu/glibc/${tag}.tar.gz"
    if curl -sfI "$url" >/dev/null; then
        echo "${tag#glibc-}" >> ../tags.txt
    fi
done


echo "version_matrix=$(cat ../tags.txt | jq -Rcn '[inputs]')" >> $GITHUB_OUTPUT

