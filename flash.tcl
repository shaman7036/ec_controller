# Константи для флеш-пам’яті
set FLASH_BASE_ADDR 0xff3800
set FLASH_MBX_INDEX_ADDR [expr {$FLASH_BASE_ADDR + 0x00}]
set FLASH_MBX_DATA_ADDR  [expr {$FLASH_BASE_ADDR + 0x04}]
set FLASH_DATA_ADDR     [expr {$FLASH_BASE_ADDR + 0x100}]
set FLASH_ADDRESS_ADDR  [expr {$FLASH_BASE_ADDR + 0x104}]
set FLASH_COMMAND_ADDR  [expr {$FLASH_BASE_ADDR + 0x108}]
set FLASH_STATUS_ADDR   [expr {$FLASH_BASE_ADDR + 0x10c}]
set FLASH_CONFIG_ADDR   [expr {$FLASH_BASE_ADDR + 0x110}]
set FLASH_INIT_ADDR     [expr {$FLASH_BASE_ADDR + 0x114}]

set FLASH_MODE_STANDBY  0
set FLASH_MODE_READ     1
set FLASH_MODE_PROGRAM  2
set FLASH_MODE_ERASE    3
set FLASH_SIZE_MAX      0x40000
set EEPROM_SIZE         2048

# Ініціалізація
proc init_mec16xx {} {
    set idcode [jtag targetid arc600.cpu]
    if {$idcode != 0x200024b1} {
        echo "Error: Unknown device with IDCODE [format 0x%08x $idcode]"
        return -1
    }
    halt
    echo "CPU halted"
}

# Флеш-операції (з попереднього)
proc flash_clean_start {} {
    mww $::FLASH_COMMAND_ADDR 0x00000001
    mww $::FLASH_STATUS_ADDR 0x00000700
}

proc flash_wait_not_busy {} {
    set status [mdw $::FLASH_STATUS_ADDR]
    echo "Initial FLASH_STATUS_ADDR: 0x[format %08x $::FLASH_STATUS_ADDR], Status: 0x[format %08x $status]"
    while {$status & 0x1} {
        echo "FLASH_STATUS_ADDR: 0x[format %08x $::FLASH_STATUS_ADDR], Status: 0x[format %08x $status]"
        set status [mdw $::FLASH_STATUS_ADDR]
        echo "FLASH_STATUS_ADDR: 0x[format %08x $::FLASH_STATUS_ADDR], Status: 0x[format %08x $status]"
        if {$status & 0x700} {
            echo "Error: Flash operation failed with status [format 0x%08x $status]"
            return -1
        }
    }
    echo "Final FLASH_STATUS_ADDR: 0x[format %08x $::FLASH_STATUS_ADDR], Status: 0x[format %08x $status]"
    return 0
}

proc flash_wait_data_not_full {} {
    set status [mdw $::FLASH_STATUS_ADDR]
    while {$status & 0x2} {
        set status [mdw $::FLASH_STATUS_ADDR]
        if {$status & 0x700} {
            echo "Error: Flash operation failed with status [format 0x%08x $status]"
            return -1
        }
    }
    return 0
}

proc read_flash {address count} {
    flash_clean_start
    set words {}
    for {set i 0} {$i < $count} {incr i} {
        mww $::FLASH_COMMAND_ADDR 0x00000001
        mww $::FLASH_ADDRESS_ADDR [expr {$address + $i * 4}]
        if {[flash_wait_not_busy] == -1} { return -1 }
        set data1 [mdw $::FLASH_DATA_ADDR]
        mww $::FLASH_ADDRESS_ADDR [expr {$address + $i * 4}]
        set data2 [mdw $::FLASH_DATA_ADDR]
        if {$data1 == $data2} {
            lappend words $data1
        } else {
            mww $::FLASH_ADDRESS_ADDR [expr {$address + $i * 4}]
            set data3 [mdw $::FLASH_DATA_ADDR]
            if {$data1 == $data2 || $data2 == $data3 || $data1 == $data3} {
                lappend words [expr {$data1 == $data2 ? $data1 : $data2}]
            } else {
                echo "Error: Cannot resolve read glitch at [format 0x%08x [expr {$address + $i * 4}]]"
                return -1
            }
        }
    }
    mww $::FLASH_COMMAND_ADDR 0x00000001
    return $words
}

proc erase_flash {{address 0xF8000}} {
    flash_clean_start
    mww $::FLASH_COMMAND_ADDR 0x00000003
    mww $::FLASH_ADDRESS_ADDR $address
    if {[flash_wait_not_busy] == -1} { return -1 }
    mww $::FLASH_COMMAND_ADDR 0x00000001
    echo "Flash erased at address [format 0x%08x $address]"
}

proc program_flash {address words} {
    flash_clean_start
    mww $::FLASH_COMMAND_ADDR 0x00000006
    mww $::FLASH_ADDRESS_ADDR $address
    foreach data $words {
        if {[flash_wait_data_not_full] == -1} { return -1 }
        mww $::FLASH_DATA_ADDR $data
    }
    if {[flash_wait_not_busy] == -1} { return -1 }
    mww $::FLASH_COMMAND_ADDR 0x00000001
    echo "Flash programmed at address [format 0x%08x $address]"
}


