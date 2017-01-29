#!/bin/bash

suffix=
prefix=1
cpumax=$(cat /proc/cpuinfo | grep ^processor | wc -l)
cpunum=0

irqs=$*

for irq in $irqs; do
        cpunum=$(($cpunum+1))
        echo $irq $prefix$suffix
        case $prefix in
                1)
                        prefix=2
                ;;
                2)
                        prefix=4
                ;;
                4)
                        prefix=8
                ;;
                8)
                        prefix=1
                        suffix=${suffix}0
                ;;
        esac
        if [ "$cpumax" == "$cpunum" ]; then
                cpunum=0
                suffix=
                prefix=1
        fi
done
