proc erase_flash {address} {
    mww 0xff3808 0x00000001
    mww 0xff380c 0x00000700
    mww 0xff3808 0x00000003
    mww 0xff3804 $address
    set status [mdw 0xff380c]
    while {$status & 0x1} { set status [mdw 0xff380c] }
    mww 0xff3808 0x00000001
}
