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

# Константи для EEPROM (припущення, уточнити в документації)
set EEPROM_BASE_ADDR    0xff4000
set EEPROM_COMMAND_ADDR [expr {$EEPROM_BASE_ADDR + 0x08}]
set EEPROM_STATUS_ADDR  [expr {$EEPROM_BASE_ADDR + 0x0c}]
set EEPROM_ADDRESS_ADDR [expr {$EEPROM_BASE_ADDR + 0x04}]
set EEPROM_DATA_ADDR    [expr {$EEPROM_BASE_ADDR + 0x00}]
set EEPROM_UNLOCK_ADDR  [expr {$EEPROM_BASE_ADDR + 0x10}] ;# Припущення

set EEPROM_MODE_STANDBY 0
set EEPROM_MODE_READ    1
set EEPROM_MODE_PROGRAM 2
set EEPROM_MODE_ERASE   3

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

# Перевірка блокування EEPROM
proc is_eeprom_blocked {} {
    set status [mdw $::EEPROM_STATUS_ADDR]
    # Припускаємо, що EEPROM_BLOCK — біт 7 (з Python: EEPROM_Block=1<<7)
    if {$status & 0x80} {
        echo "EEPROM is blocked"
        return 1
    } else {
        echo "EEPROM is not blocked"
        return 0
    }
}

# Розблокування EEPROM
proc unlock_eeprom {password} {
    if {![is_eeprom_blocked]} {
        echo "Warning: EEPROM is not blocked, nothing to unlock"
        return 0
    }
    # Пароль — 31 біт, біт 31 має бути 0
    if {$password > 0x7FFFFFFF} {
        echo "Error: Password must be 31 bits (max 0x7FFFFFFF)"
        return -1
    }
    mww $::EEPROM_UNLOCK_ADDR $password
    if {[is_eeprom_blocked]} {
        echo "Error: EEPROM unlock failed"
        return -1
    } else {
        echo "EEPROM successfully unlocked"
        return 0
    }
}

# Ініціалізація EEPROM
proc eeprom_clean_start {} {
    if {[is_eeprom_blocked]} {
        echo "Error: EEPROM is blocked, no operations possible"
        return -1
    }
    mww $::EEPROM_COMMAND_ADDR 0x00000000 ;# Standby
    mww $::EEPROM_STATUS_ADDR  0x00000300 ;# Clear Busy_Err, CMD_Err
}

# Очікування завершення операції EEPROM
proc eeprom_wait_not_busy {} {
    set status [mdw $::EEPROM_STATUS_ADDR]
    while {$status & 0x1} {
        set status [mdw $::EEPROM_STATUS_ADDR]
        if {$status & 0x300} {
            echo "Error: EEPROM operation failed with status [format 0x%08x $status]"
            return -1
        }
    }
    return 0
}

proc eeprom_wait_data_not_full {} {
    set status [mdw $::EEPROM_STATUS_ADDR]
    while {$status & 0x2} {
        set status [mdw $::EEPROM_STATUS_ADDR]
        if {$status & 0x300} {
            echo "Error: EEPROM operation failed with status [format 0x%08x $status]"
            return -1
        }
    }
    return 0
}

# Читання EEPROM
proc read_eeprom {{address 0} {count $::EEPROM_SIZE}} {
    eeprom_clean_start
    mww $::EEPROM_COMMAND_ADDR 0x00000001 ;# Read mode
    mww $::EEPROM_ADDRESS_ADDR $address
    set bytes {}
    for {set i 0} {$i < $count} {incr i} {
        if {[eeprom_wait_not_busy] == -1} { return -1 }
        set data [mdw $::EEPROM_DATA_ADDR]
        lappend bytes [expr {$data & 0xFF}] ;# Беремо лише 1 байт
    }
    mww $::EEPROM_COMMAND_ADDR 0x00000000 ;# Standby
    return $bytes
}

# Стирання EEPROM
proc erase_eeprom {{address 0xF800}} {
    eeprom_clean_start
    mww $::EEPROM_COMMAND_ADDR 0x00000003 ;# Erase mode
    mww $::EEPROM_ADDRESS_ADDR $address
    if {[eeprom_wait_not_busy] == -1} { return -1 }
    mww $::EEPROM_COMMAND_ADDR 0x00000000 ;# Standby
    echo "EEPROM erased"
}

# Програмування EEPROM
proc program_eeprom {address bytes} {
    eeprom_clean_start
    mww $::EEPROM_COMMAND_ADDR 0x00000006 ;# Program mode, Burst=1
    mww $::EEPROM_ADDRESS_ADDR $address
    foreach data $bytes {
        if {[eeprom_wait_data_not_full] == -1} { return -1 }
        mww $::EEPROM_DATA_ADDR $data
    }
    if {[eeprom_wait_not_busy] == -1} { return -1 }
    mww $::EEPROM_COMMAND_ADDR 0x00000000 ;# Standby
    echo "EEPROM programmed at address [format 0x%08x $address]"
}

# Флеш-операції (з попереднього)
proc flash_clean_start {} {
    mww $::FLASH_COMMAND_ADDR 0x00000001
    mww $::FLASH_STATUS_ADDR 0x00000700
}

proc flash_wait_not_busy {} {
    set status [mdw $::FLASH_STATUS_ADDR]
    while {$status & 0x1} {
        set status [mdw $::FLASH_STATUS_ADDR]
        if {$status & 0x700} {
            echo "Error: Flash operation failed with status [format 0x%08x $status]"
            return -1
        }
    }
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

# Аварійне стирання
proc emergency_mass_erase {} {
    irscan arc600.cpu 0x2
    drscan arc600.cpu 32 0xC0000000
    drscan arc600.cpu 32 0xC0000008
    drscan arc600.cpu 32 0x8000008
    drscan arc600.cpu 32 0x8000009
    drscan arc600.cpu 32 0xC000009
    sleep 1000
    drscan arc600.cpu 32 0xC000008
    drscan arc600.cpu 32 0x8000008
    drscan arc600.cpu 32 0xC0000000
    echo "Emergency mass erase completed."
}
