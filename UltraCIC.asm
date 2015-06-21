processor pic16f1613

; UltraCIC - Nintendo 64 CIC clone by Mike Ryan
; This code is released in the public domain

; Pins
; Num   Port    Function
;   9   C.1     PIF_DATA (bidir)
;  10   C.0     PIF_DCLK

include p16f1613.inc

;;;;;;;;;;;;;;
; DEFINES
;;;;;;;;;;;;;;
variable region = 0 ; 0 is NTSC, 1 is PAL


; CONFIG1
 __CONFIG _CONFIG1, _FOSC_ECM & _PWRTE_OFF & _MCLRE_ON & _CP_OFF & _BOREN_OFF & _CLKOUTEN_ON
; CONFIG2
 __CONFIG _CONFIG2, _WRT_OFF & _ZCD_ON & _PLLEN_ON & _STVREN_ON & _BORV_LO & _LPBOR_OFF & _LVP_ON
; CONFIG3
 __CONFIG _CONFIG3, _WDTCPS_WDTCPS1F & _WDTE_OFF & _WDTCWS_WDTCWSSW & _WDTCCS_SWC


;;;;;;;;;;;;
; UTILITY
;;;;;;;;;;;

; increment FSR0
; uses 70 (common RAM) as a temp register
; incf FSR0,F does not set DC on 4-bit overflow
incfsr MACRO
    movwf 70
    movlw 1
    addwf FSR0,F
    movf 70,W
    ENDM

; adc emulation
; uses 70 as carry in
adc_nocarry_out MACRO
    bcf STATUS, DC
    btfsc 70, 0 ; if carry, add 1
    addlw 1
    bcf 70, 0 ; clear fake C, will set it again below if necessary
    btfsc STATUS, DC
    bsf 70, 0 ; set fake C if there was DC
    ; after carry-in is accounted for, add mem
    addwf INDF0, W
    ENDM


;;;;;;;;;;;
;; ENTRY
;;;;;;;;;;
    ; initialize ports
    call init_ports

    movlw region
    movwf 72

    ; boot sequence
    movlw 0
    call write_bit
    movf 72, W     ; region: 0 for NTSC, 1 for PAL
    call write_bit
    movlw 0
    call write_bit
    movlw 1
    call write_bit

    ; load seed and write that
    call seed_write

    ; load checksum and write that
    call checksum_write

;;;;;;;;;;;;;;;;;;;;
; MAIN LOOP
;;;;;;;;;;;;;;;;;;

main_runtime:
    movlw 0xe
    movwf 20
    movlw 0xb
    movwf 31

    call load_pat

    movlw 21
    movwf FSR0
    call get_four_bits

    movlw 31
    movwf FSR0
    call get_four_bits

main_loop:
    call get_bit
    btfss STATUS, C
    goto main_zero

    ; received a one
    call get_bit
    btfss STATUS, C
    ; 1 then 0, x105 mode
    goto x105_main

    ; 1 then 1
    bcf STATUS, C
    goto console_reset

    ; received a zero
main_zero:
    call get_bit
    btfss STATUS, C
    goto main_zero_zero

    ; 0 then 1, kill yourself
    goto dead

    ; 0 then 0
main_zero_zero:
    movlw 0x20
    movwf FSR0
    call main_algorithm
    call main_algorithm
    call main_algorithm

    movlw 0x30
    movwf FSR0
    call main_algorithm
    call main_algorithm
    call main_algorithm

    ; W = RAM[17]
    ; if W < F
    ;   ++W
    ; [trust me on this]
    movf 37, W
    addlw 0xF
    btfss STATUS, DC
    movlw 0
    addlw 1

    ; BL = A
    ; such a hack
    bcf FSR0, 0
    bcf FSR0, 1
    bcf FSR0, 2
    bcf FSR0, 3
    andlw 0xF
    iorwf FSR0, F

getabit:
    clrf 70 ; storing carry here

    call get_bit
    btfsc STATUS, C
    bsf 70, 0 ; save the bit

    ;--------
    ; write lowest bit of RAM
    ; address is BM = 1, BL starts at RAM[17]

    ; BM = 1
    movlw 30
    iorwf FSR0, F

    ; W = lowest bit of current RAM
    movlw 1
    btfss INDF0, 0
    movlw 0

    call write_bit

    ; /writing lowest bit of ram
    ;--------

    movlw 2F
    andwf FSR0, F

    ; if bit from PIF was 0, if RAM is 1 then kill yourself
    btfss 70, 0
    goto pif_said_zero

    ; if bit from PIF was 1, if RAM is 0 then kill yourself
    btfss INDF0, 0
    goto dead

    goto more_bits

pif_said_zero:
    ; if PIF said 0 and we have 1, kill self (see above)
    btfss INDF0, 0
    goto more_bits

    goto dead

more_bits:
    movlw 1

    ; jump down to PAL if region is 1
    btfsc 72, 0
    goto mb_pal

    ; NTSC
    addwf FSR0, F

    btfss STATUS, DC
    goto getabit

    goto main_loop

mb_pal:
    ; PAL
    subwf FSR0, F
    movlw 0xF
    andwf FSR0, W
    btfss STATUS, Z
    goto getabit

    goto main_loop

; end of function


;;;;;;;;;;;;;;;;;
;; x105 algorithm
;;;;;;;;;;;;;;;;;
x105_main:
    ; write A A
    movlw 0xa
    movwf 40

    movlw 40
    movwf FSR0
    call write_nibble
    call write_nibble

    ; load 40 .. 5D
keep_loading:
    call get_four_bits
    incf FSR0,F
    call get_four_bits
    incf FSR0,F

    movlw 5E
    subwf FSR0,W
    btfss STATUS, Z
    goto keep_loading

    ; magic happens here
    call x105_algo

    movlw 0
    call write_bit

    ; write out RAM
    movlw 40
    movwf FSR0
x105_write_nibbles:
    call write_nibble
    incf FSR0, F
    movlw 5e
    subwf FSR0, W
    btfss STATUS, Z
    goto x105_write_nibbles

    goto main_loop

exc MACRO
    xorwf INDF0, W
    xorwf INDF0, F
    xorwf INDF0, W
    ENDM

; x105 core algorithm
x105_algo:
    movlw 0x40
    movwf FSR0

    ; using lowest bit of 70 as C stand-in
    clrf 70
    bsf 70, 0

    movlw 0x5

x105_loop:
    btfss INDF0, 0
    addlw 8
    exc

    btfss INDF0, 1
    addlw 4

    addwf INDF0, W
    movwf INDF0

    btfss 70, 0
    addlw 7

    addwf INDF0, W

    ; adc emulation is gross
    adc_no_carry_out
    btfsc STATUS, DC
    bsf 70, 0 ; set fake C if there was DC

    movwf INDF0
    comf INDF0, F

    movlw 5D
    subwf FSR0, W
    btfsc STATUS, Z
    goto done

    movf INDF0, W
    incf FSR0, F
    goto x105_loop

done:
    return


; 0 1 mode
console_reset:
    ; delay a bit
    movlw 0
    movwf 70
dloop:
    clrwdt
    incf 70
    btfss STATUS, Z
    goto dloop
    addlw 1
    btfss STATUS, Z
    goto dloop

    ; let the PIF know we're done delaying
    movlw 0
    call write_bit

    goto main_loop

;;;;;;;;;;;;;;;;;;
;; main algorithm
;;;;;;;;;;;;;;;;;;
cic_round:
    clrwdt

    ; 70 is fake carry, 71 is temporary storage
    clrf 70

    movlw 0xf
    iorwf FSR0, F
    movf INDF0, W

outer_loop:
    movwf 71 ; 71 is "X"

    bsf 70, 0

    ; jump back to RAM[1]
    movlw 0xf1
    andwf FSR0, F

    ; get back saved W
    movf 71, W

    ; adc emulation
    adc_nocarry_out
    bsf 70, 0 ; set carry

    movwf INDF0
    incf FSR0, F

    ; adc emulation again
    adc_nocarry_out
    bsf 70, 0 ; set carry

    exc
    comf INDF0, F
    incf FSR0, F

    adc_nocarry_out
    btfsc STATUS, DC
    bsf 70, 0 ; set fake C if there was DC

    btfsc 70, 0 ; need to skip if there was carry
    goto nostore

    exc
    incf FSR0, F

nostore:
    addwf INDF0, W
    movwf INDF0

    incf FSR0, F
    addwf INDF0, W
    exc

    incf FSR0, F
    addlw 8

    btfss STATUS, DC
    addwf INDF0, W

    exc
    incf FSR0, F

inner_loop:
    addlw 1
    addwf INDF0, F

    ; test for overflow
    movlw 1
    addwf FSR0, W
    btfsc STATUS, DC
    goto break_loop

    movf INDF0, W
    incf FSR0, F

    goto inner_loop

break_loop:
    movf 71, W
    addlw 0xF

    btfsc STATUS, DC  ; inverted logic
    goto outer_loop

    return

;;;;;;;;;;;;;;;;;;;;;
;; seed and checksum
;;;;;;;;;;;;;;;;;;;;;
seed_write:
    call load_seed
    ; preload b5 then mishmash twice
    movlw 0xb
    movwf 2a
    movlw 5
    movwf 2b
    call mashup

    movlw 2a
    movwf FSR0

_loop_nibbles:
    call write_nibble

    incfsr
    btfss STATUS, DC

    goto _loop_nibbles

    return

load_seed:
    movlw 0xFF ; FIXME - use a real seed
    movwf 2c

    movf 2c, W
    movwf 2d
    movwf 2e
    movwf 2f

    lsrf 2c, f
    lsrf 2c, f
    lsrf 2c, f
    lsrf 2c, f
    lsrf 2e, f
    lsrf 2e, f
    lsrf 2e, f
    lsrf 2e, f
    return

checksum_write:
    call load_checksum

_checksum_wait_low:
    btfsc PORTC, 0
    goto _checksum_wait_low

    movlw 0xd
    movwf 21

    ; encode the checksum by running mishmash four times
    movlw 20
    movwf FSR0
    call mishmash
    movlw 20
    movwf FSR0
    call mishmash
    movlw 20
    movwf FSR0
    call mishmash
    movlw 20
    movwf FSR0
    call mishmash

    ; lower CIC_OUT to indicate we're done
    movlw 0
    call write_bit

    movlw 20
    movwf FSR0

_cw_dump_ram
    call write_nibble
    incfsr
    btfss STATUS, DC
    goto _cw_dump_ram

    return

; checksum byte
cb MACRO byte
    movlw byte
    movwf INDF0
    incf FSR0, 1
    ENDM

; checksum
checksum MACRO va, vb, vc, vd, ve, vf, vg, vh, vi, vj, vk, vl
    kb va
    kb vb
    kb vc
    kb vd
    kb ve
    kb vf
    kb vg
    kb vh
    kb vi
    kb vj
    kb vk
    kb vl
    ENDM

load_checksum:
    movlw 24
    movwf FSR0

    ; FIXME - replace this with a real checksum
    checksum 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xa, 0xb
    return

;;;;;;;;;;;;;
; ENCRAPTION
;;;;;;;;;;;;;
mashup:
    ; load 0xa into indirect reg pointer
    movlw 2a
    movwf FSR0
    call mishmash
    movlw 2a
    movwf FSR0
    call mishmash
    return

mishmash:
    ; operates on indf until it hits 0x20 or 0x30
    movf INDF0, 0
    incf FSR0, 1

mishmash_loop:
    addlw 1
    addwf INDF0, 0 ; A += M
    movwf INDF0

    ; increment FSR0
    ; DC is set if its lower 4 bits overflow
    incfsr

    ; skip if bottom four bits overflow
    btfss STATUS, DC
    goto mishmash_loop
    return


;;;;;;;;;;;;
;; Load RAM
;;;;;;;;;;;;

pat MACRO addr, nibble
    movlw nibble
    movwf addr
    ENDM

pat_nibbles MACRO a32, a22, a33, a23, a34, a24, a35, a25, a36, a26, a37, a27, a38, a28, a39, a29, a3A, a2A, a3B, a2B, a3C, a2C, a3D, a2D, a3E, a2E, a3F, a2F
    pat 0x22, a22
    pat 0x32, a32
    pat 0x23, a23
    pat 0x33, a33
    pat 0x24, a24
    pat 0x34, a34
    pat 0x25, a25
    pat 0x35, a35
    pat 0x26, a26
    pat 0x36, a36
    pat 0x27, a27
    pat 0x37, a37
    pat 0x28, a28
    pat 0x38, a38
    pat 0x29, a29
    pat 0x39, a39
    pat 0x2A, a2A
    pat 0x3A, a3A
    pat 0x2B, a2B
    pat 0x3B, a3B
    pat 0x2C, a2C
    pat 0x3C, a3C
    pat 0x2D, a2D
    pat 0x3D, a3D
    pat 0x2E, a2E
    pat 0x3E, a3E
    pat 0x2F, a2F
    pat 0x3F, a3F
    ENDM

load_pat:
    ; jump down to PAL if region is 1
    btfsc 72, 0
    goto lp_pal

    ; NTSC
    pat_nibbles 0x1, 0x9, 0x4, 0xA, 0xF, 0x1, 0x8, 0x8, 0xB, 0x5, 0x5, 0xA, 0x7, 0x1, 0xC, 0x3, 0xD, 0xE, 0x6, 0x1, 0x1, 0x0, 0xE, 0xD, 0x9, 0xE, 0x8, 0xC
    return

lp_pal:
    ; PAL
    pat_nibbles 0x1, 0x4, 0x2, 0xF, 0x3, 0x5, 0xF, 0x1, 0x8, 0x2, 0x2, 0x1, 0x7, 0x7, 0x1, 0x1, 0x9, 0x9, 0x8, 0x8, 0x1, 0x5, 0x1, 0x7, 0x5, 0x5, 0xC, 0xA
    return


; when CIC is instructed to halt: infinite loop
dead:
    nop
    goto dead

;;;;;;;;;;;;;;;;;;;;;
; I/O
;;;;;;;;;;;;;;;;;;;;;

; wait for PIF to go low write a bit, then wait for it to go high
write_bit:
    banksel PORTC

_wait_low:
    clrwdt
    btfsc PORTC, 0
    goto _wait_low

    ; write out W to port 1
    iorlw 0 ; test if W is 0
    btfss STATUS, Z
    goto _wait_high

    ; zero: drive zero
_zero:
    bcf PORTC, 1
    banksel TRISC
    bcf TRISC, 1    ; set port 1 to output
    banksel PORTC

_wait_high:
    clrwdt
    btfss PORTC, 0
    goto _wait_high
    nop
    nop
    nop
    nop

    banksel TRISC
    bsf TRISC, 1
    banksel PORTC

    return


; wait for PIF_DCLK (C.0) to go low
; gets one bit of input on PIF_DATA
; wait for PIF_DCLK to go high again
get_bit:
    bsf STATUS, C

    ; ensure port 1 is an input
    banksel TRISC
    bsf TRISC, 1
    bsf TRISC, 0
    banksel PORTC

    ; test bit 0
gb_wait_low:
    clrwdt
    btfsc PORTC, 0
    goto gb_wait_low

    ; get input
    btfss PORTC, 1
    bcf STATUS, C

gb_wait_high:
    clrwdt
    btfss PORTC, 0
    goto gb_wait_high

    return


; get four bits of input from the PIF
; clear bits of RAM depending on if these bits are set
get_four_bits:
    movlw 0xF
    movwf INDF0

    call get_bit
    btfss STATUS, C
    bcf INDF0, 3
    call get_bit
    btfss STATUS, C
    bcf INDF0, 2
    call get_bit
    btfss STATUS, C
    bcf INDF0, 1
    call get_bit
    btfss STATUS, C
    bcf INDF0, 0
    return


; write a nibble pointed to by INDF0
write_nibble:
    movlw 1
    btfss INDF0, 3
    movlw 0
    call write_bit
    movlw 1
    btfss INDF0, 2
    movlw 0
    call write_bit
    movlw 1
    btfss INDF0, 1
    movlw 0
    call write_bit
    movlw 1
    btfss INDF0, 0
    movlw 0
    call write_bit
    return

; time how long it takes the input to go low
; store the result in RAM 0 1 2
;
; This is normally used as a "random seed", for the mishmash function. The PIF
; doesn't seem to care if the seed value is the same every time, so punt.
wait_low_time:
    btfsc PORTC, 0
    goto wait_low_time
    return


init_ports:
    ; always input:
    ;  - A.*
    ;  - C.0
    ;
    ; open drain:
    ;  - C.1

    ; why the FUCK do these default as analog?
    banksel ANSELA
    clrf ANSELA
    clrf ANSELC

    banksel TRISA
    movlw b'1111'
    movwf TRISA
    movwf TRISC

    banksel PORTA
    clrf PORTA
    clrf PORTC

    return

end
