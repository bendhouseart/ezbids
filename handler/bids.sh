#!/bin/bash

set -e
set -x

if [ -z $1 ]; then
    echo "please specify root dir"
    exit 1
fi
root=$1

rm -rf $root/bids

echo "making deface list"
./make_deface_list.py $root

echo "running defacing"
if [ ! -f $root/deface.out ]; then
    touch $root/deface.out
fi

function deface {
    ./deface.py $root $2
}
export -f deface
cat $root/deface_list.txt | parallel -j 10 deface {$root}

echo "converting output to bids"
./convert.js $root

echo "output bids directory structure"
tree $root/bids
