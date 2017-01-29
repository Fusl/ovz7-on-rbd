/root/scripts/irqbalance.sh $(cat /proc/interrupts | grep PCI-MSI-edge | awk -F: '{print $1"\n-"}') | awk '{print "echo "$2" > /proc/irq/"$1"/smp_affinity"}' | bash
