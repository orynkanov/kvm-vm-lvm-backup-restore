#!/bin/bash

BACKUPDIR=/mnt/backup
DDCMD=dcfldd
DDOPT="conv=notrunc,noerror"

VM=$1

if [ ! $# -eq 1 ]; then
    echo "VM not defined"
    exit 1
fi

if [ ! -d $BACKUPDIR/"$VM" ]; then
    echo "Directory backup $BACKUPDIR/$VM not exist"
    exit 1
fi

_vmexist(){
    LANG=C virsh dominfo "$1" 2>/dev/null | grep -c UUID
}

VMEXIST=$(_vmexist "$VM")
if [ "$VMEXIST" -eq 0 ]; then
    echo "VM $VM not exist"
    exit 1
fi

DIRLIST=$(find $BACKUPDIR/"$VM" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; | sort)" Cancel"
PS3="Select backup date: "
select DIR in $DIRLIST; do
    if [ -n "$DIR" ]; then
        if [ "$DIR" == "Cancel" ]; then
		    exit 0
        fi
        echo "Select $DIR"
        DIRBACKUP=$BACKUPDIR/$VM/$DIR
        break
    fi
done

_vmisrun(){
    LANG=C virsh domstate "$1" | grep -c run
}

_vmisshut(){
    LANG=C virsh domstate "$1" | grep -c shut
}

_vmshutdown(){
    virsh shutdown "$1" >/dev/null 2>&1
}

_vmgetdisks(){
    virsh domblklist "$1" --details | awk '/disk/ {print $4}'
}

_lvrestore(){
    LVBASENAME=$(basename "$1")
    BACKUPFILE=$LVBASENAME.img.gz
    gunzip -c "$2"/"$BACKUPFILE" | $DDCMD of="$1" $DDOPT
}

_vmrestore(){
    virsh restore "$1" 1>/dev/null
}

if [ -f "$DIRBACKUP"/"$VM".state ]; then
    VMISLIVE=1
else
    VMISLIVE=0
fi

if [ $VMISLIVE -eq 1 ]; then
    VMISRUN=$(_vmisrun "$VM")
    VMISSHUT=$(_vmisshut "$VM")
    if [ "$VMISRUN" -eq 1 ]; then
        echo "VM $VM is run"
        echo "Shutdown VM $VM"
        _vmshutdown "$VM"
        while [ "$VMISSHUT" -eq 0 ]; do
            echo "Wait 30 seconds VM $VM shutdown"
            sleep 30s
            VMISSHUT=$(_vmisshut "$VM")
        done
        for DISK in $(_vmgetdisks "$VM"); do
            echo "Restore LV backup to $DISK"
            _lvrestore "$DISK" "$DIRBACKUP"
        done
        echo "Restore VM state for $VM"
        _vmrestore "$DIRBACKUP"/"$VM".state
    elif [ "$VMISSHUT" -eq 1 ]; then
        for DISK in $(_vmgetdisks "$VM"); do
            echo "Restore LV backup to $DISK"
            _lvrestore "$DISK" "$DIRBACKUP"
        done
        echo "Restore VM state for $VM"
        _vmrestore "$DIRBACKUP"/"$VM".state
    fi
else
    VMISRUN=$(_vmisrun "$VM")
    VMISSHUT=$(_vmisshut "$VM")
    if [ "$VMISRUN" -eq 1 ]; then
        echo "VM $VM is run"
        echo "Shutdown VM $VM"
        _vmshutdown "$VM"
        while [ "$VMISSHUT" -eq 0 ]; do
            echo "Wait 30 seconds VM $VM shutdown"
            sleep 30s
            VMISSHUT=$(_vmisshut "$VM")
        done
        for DISK in $(_vmgetdisks "$VM"); do
            echo "Restore LV backup to $DISK"
            _lvrestore "$DISK" "$DIRBACKUP"
        done
    elif [ "$VMISSHUT" -eq 1 ]; then
        for DISK in $(_vmgetdisks "$VM"); do
            echo "Restore LV backup to $DISK"
            _lvrestore "$DISK" "$DIRBACKUP"
        done
    fi
fi
echo "Complete VM restore"
