; NES SYNTH - Interactive Sound Synthesizer
; Controller-driven music creation on the NES APU
;
; Controls:
;   Left/Right  = Change note (E minor pentatonic: E G A B D)
;   Up/Down     = Change octave (1-4)
;   A (hold)    = Play note on Pulse 1
;   B (hold)    = Play harmony (4th above) on Pulse 2
;   Select      = Cycle waveform preset (4 duty cycles)
;   Start       = Toggle drum loop
;
; Channels:
;   Pulse 1   - Lead synth (A button)
;   Pulse 2   - Harmony synth (B button, plays 2 steps up)
;   Triangle  - Auto bass (follows player note at octave 1)
;   Noise     - Drum loop (kick/snare/hat when enabled)

;------------------------------------------------------------------------------
; Hardware Registers
;------------------------------------------------------------------------------
PPU_CTRL         = $2000
PPU_MASK         = $2001
PPU_STATUS       = $2002
PPU_SCROLL       = $2005
PPU_ADDR         = $2006
PPU_DATA         = $2007

APU_PULSE1_CTRL  = $4000
APU_PULSE1_SWEEP = $4001
APU_PULSE1_LO    = $4002
APU_PULSE1_HI    = $4003
APU_PULSE2_CTRL  = $4004
APU_PULSE2_SWEEP = $4005
APU_PULSE2_LO    = $4006
APU_PULSE2_HI    = $4007
APU_TRI_CTRL     = $4008
APU_TRI_LO       = $400A
APU_TRI_HI       = $400B
APU_NOISE_CTRL   = $400C
APU_NOISE_FREQ   = $400E
APU_NOISE_LEN    = $400F
APU_STATUS       = $4015
APU_FRAME        = $4017

CONTROLLER1      = $4016

;------------------------------------------------------------------------------
; Button Constants
;------------------------------------------------------------------------------
BTN_A      = $80
BTN_B      = $40
BTN_SELECT = $20
BTN_START  = $10
BTN_UP     = $08
BTN_DOWN   = $04
BTN_LEFT   = $02
BTN_RIGHT  = $01

NOTES_PER_OCT = 5
NUM_OCTAVES   = 4

;------------------------------------------------------------------------------
; Zero Page Variables
;------------------------------------------------------------------------------
.segment "ZEROPAGE"
frame_count:     .res 2
buttons_cur:     .res 1
buttons_prev:    .res 1
buttons_new:     .res 1
cur_note:        .res 1      ; 0-4 (E G A B D)
cur_octave:      .res 1      ; 0-3 (displayed as 1-4)
cur_duty:        .res 1      ; 0-3 (duty cycle preset)
drum_on:         .res 1      ; 0=off, 1=on
release_p1:      .res 1      ; release decay counter for pulse 1
release_p2:      .res 1      ; release decay counter for pulse 2
note_active_p1:  .res 1      ; 1 if pulse 1 is sounding
note_active_p2:  .res 1
last_index_p1:   .res 1      ; last note index written to pulse 1
last_index_p2:   .res 1
display_dirty:   .res 1      ; 1 = nametable needs update
vis_flash:       .res 1      ; visual flash counter on note trigger
temp:            .res 1

;------------------------------------------------------------------------------
; OAM segment (avoids linker warning)
;------------------------------------------------------------------------------
.segment "OAM"

;------------------------------------------------------------------------------
; iNES Header
;------------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte $01               ; 1x 16KB PRG ROM
    .byte $01               ; 1x 8KB CHR ROM
    .byte $00               ; Mapper 0, horizontal mirroring
    .byte $00

;------------------------------------------------------------------------------
; Code
;------------------------------------------------------------------------------
.segment "CODE"

RESET:
    sei
    cld
    ldx #$40
    stx APU_FRAME
    ldx #$FF
    txs
    inx                     ; X = 0
    stx PPU_CTRL
    stx PPU_MASK
    stx $4010

@vblank1:
    bit PPU_STATUS
    bpl @vblank1

    lda #$00
@clear_ram:
    sta $0000, x
    sta $0100, x
    sta $0200, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    inx
    bne @clear_ram

@vblank2:
    bit PPU_STATUS
    bpl @vblank2

    ; Initialize synth state
    lda #$01
    sta cur_octave          ; start at octave 2 (middle range)
    lda #$02
    sta cur_duty            ; 50% duty (warm square wave)
    lda #$FF
    sta last_index_p1       ; force frequency write on first note
    sta last_index_p2
    lda #$01
    sta display_dirty

    ; Enable APU channels
    lda #%00001111
    sta APU_STATUS

    ; Disable sweep on pulse channels
    lda #$08
    sta APU_PULSE1_SWEEP
    sta APU_PULSE2_SWEEP

    ; Silence all channels
    lda #$30
    sta APU_PULSE1_CTRL
    sta APU_PULSE2_CTRL
    sta APU_NOISE_CTRL
    lda #$80
    sta APU_TRI_CTRL

    jsr load_palette
    jsr init_nametable

    ; Enable NMI + use pattern table 0 for BG
    lda #%10000000
    sta PPU_CTRL

    ; Show background
    lda #%00001010
    sta PPU_MASK

main_loop:
    jmp main_loop

;------------------------------------------------------------------------------
; NMI Handler
;------------------------------------------------------------------------------
NMI:
    pha
    txa
    pha
    tya
    pha

    inc frame_count
    bne @no_wrap
    inc frame_count+1
@no_wrap:

    ; === VBLANK: PPU updates ===
    jsr update_palette

    lda display_dirty
    beq @skip_display
    jsr update_display
    lda #$00
    sta display_dirty
@skip_display:

    ; Re-assert PPU_CTRL to fix nametable select after palette writes
    lda #%10000000
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL

    ; === Game logic (safe outside vblank) ===
    jsr read_controller
    jsr handle_input
    jsr update_sound

    ; Decay visual flash
    lda vis_flash
    beq @no_decay
    dec vis_flash
@no_decay:

    pla
    tay
    pla
    tax
    pla
    rti

;==============================================================================
; DISPLAY
;==============================================================================

;------------------------------------------------------------------------------
; Load initial palette
;------------------------------------------------------------------------------
load_palette:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    ldx #$00
@loop:
    lda initial_palette, x
    sta PPU_DATA
    inx
    cpx #$20
    bne @loop
    rts

;------------------------------------------------------------------------------
; Initialize nametable - static elements only
;------------------------------------------------------------------------------
init_nametable:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    ; Fill entire nametable + attributes with tile 0
    lda #$00
    ldx #$00
    ldy #$04
@fill:
    sta PPU_DATA
    inx
    bne @fill
    dey
    bne @fill

    ; Place note letter tiles on row 12 (E G A B D)
    ; Positions: cols 3, 9, 15, 21, 27
    bit PPU_STATUS
    ldx #$04
@letter_loop:
    lda #$21
    sta PPU_ADDR
    lda letter_addr_lo, x
    sta PPU_ADDR
    txa
    clc
    adc #32                 ; tiles 32-36 = E G A B D
    sta PPU_DATA
    dex
    bpl @letter_loop

    rts

;------------------------------------------------------------------------------
; Update palette - runs every frame
;------------------------------------------------------------------------------
update_palette:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    ; Color 0: background (flash on note trigger)
    lda vis_flash
    beq @bg_black
    lda #$00                ; dark grey flash
    jmp @bg_write
@bg_black:
    lda #$0F                ; pure black
@bg_write:
    sta PPU_DATA

    ; Color 1: white (text/letters)
    lda #$30
    sta PPU_DATA

    ; Color 2: note highlight (hue from note, brightness from octave)
    ldx cur_octave
    lda octave_brightness, x
    ldx cur_note
    ora note_hue, x
    sta PPU_DATA

    ; Color 3: bright accent
    ldx cur_note
    lda note_hue, x
    ora #$30
    sta PPU_DATA

    rts

;------------------------------------------------------------------------------
; Update display - nametable tiles (only when dirty)
;------------------------------------------------------------------------------
update_display:
    bit PPU_STATUS

    ; Update highlight bars on row 14
    ; Each bar is 3 tiles wide, centered under its note letter
    ldx #$00
@bar_loop:
    lda #$21
    sta PPU_ADDR
    lda bar_addr_lo, x
    sta PPU_ADDR

    cpx cur_note
    bne @bar_off
    lda #41                 ; highlight tile (color 2)
    sta PPU_DATA
    sta PPU_DATA
    sta PPU_DATA
    jmp @bar_next
@bar_off:
    lda #$00                ; empty
    sta PPU_DATA
    sta PPU_DATA
    sta PPU_DATA
@bar_next:
    inx
    cpx #$05
    bne @bar_loop

    ; Octave digit at row 17, col 15
    lda #$22
    sta PPU_ADDR
    lda #$2F
    sta PPU_ADDR
    lda cur_octave
    clc
    adc #37                 ; tiles 37-40 = '1'-'4'
    sta PPU_DATA

    ; Duty preset digit at row 19, col 15
    lda #$22
    sta PPU_ADDR
    lda #$6F
    sta PPU_ADDR
    lda cur_duty
    clc
    adc #37
    sta PPU_DATA

    ; Drum indicator at row 21, col 15
    lda #$22
    sta PPU_ADDR
    lda #$AF
    sta PPU_ADDR
    lda drum_on
    beq @drum_off_tile
    lda #41                 ; filled = on
    jmp @drum_write
@drum_off_tile:
    lda #$00                ; empty = off
@drum_write:
    sta PPU_DATA

    rts

;==============================================================================
; INPUT
;==============================================================================

;------------------------------------------------------------------------------
; Read controller 1
;------------------------------------------------------------------------------
read_controller:
    lda buttons_cur
    sta buttons_prev

    lda #$01
    sta CONTROLLER1
    lda #$00
    sta CONTROLLER1

    ldx #$08
@loop:
    lda CONTROLLER1
    lsr a
    rol buttons_cur
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Handle input - process button presses
;------------------------------------------------------------------------------
handle_input:
    ; Compute new presses (just pressed this frame)
    lda buttons_prev
    eor #$FF
    and buttons_cur
    sta buttons_new

    ; --- Right: next note ---
    lda buttons_new
    and #BTN_RIGHT
    beq @no_right
    inc cur_note
    lda cur_note
    cmp #NOTES_PER_OCT
    bcc @right_done
    lda #$00
    sta cur_note
@right_done:
    lda #$01
    sta display_dirty
@no_right:

    ; --- Left: previous note ---
    lda buttons_new
    and #BTN_LEFT
    beq @no_left
    lda cur_note
    bne @left_dec
    lda #NOTES_PER_OCT      ; wrap from 0 to 4
    ; fall through to dec
@left_dec:
    sec
    sbc #$01
    sta cur_note
    lda #$01
    sta display_dirty
@no_left:

    ; --- Up: higher octave ---
    lda buttons_new
    and #BTN_UP
    beq @no_up
    lda cur_octave
    cmp #(NUM_OCTAVES - 1)
    bcs @no_up
    inc cur_octave
    lda #$01
    sta display_dirty
@no_up:

    ; --- Down: lower octave ---
    lda buttons_new
    and #BTN_DOWN
    beq @no_down
    lda cur_octave
    beq @no_down
    dec cur_octave
    lda #$01
    sta display_dirty
@no_down:

    ; --- Select: cycle duty preset ---
    lda buttons_new
    and #BTN_SELECT
    beq @no_select
    inc cur_duty
    lda cur_duty
    and #$03
    sta cur_duty
    lda #$01
    sta display_dirty
@no_select:

    ; --- Start: toggle drum loop ---
    lda buttons_new
    and #BTN_START
    beq @no_start
    lda drum_on
    eor #$01
    sta drum_on
    bne @drums_activated
    ; Turning off: silence noise channel
    lda #$30
    sta APU_NOISE_CTRL
@drums_activated:
    lda #$01
    sta display_dirty
@no_start:

    ; --- Visual flash on note trigger ---
    lda buttons_new
    and #$C0                ; A or B just pressed
    beq @no_flash
    lda #$04
    sta vis_flash
@no_flash:

    rts

;==============================================================================
; SOUND ENGINE
;==============================================================================

;------------------------------------------------------------------------------
; Master sound update
;------------------------------------------------------------------------------
update_sound:
    jsr update_pulse1
    jsr update_pulse2
    jsr update_triangle
    jsr update_drums
    rts

;------------------------------------------------------------------------------
; Pulse 1 - Lead synth (A button)
;------------------------------------------------------------------------------
update_pulse1:
    lda buttons_cur
    and #BTN_A
    beq @a_released

    ; A is held: compute note index
    ldx cur_octave
    lda octave_offset, x
    clc
    adc cur_note
    tax                     ; X = note index (0-19)

    ; Only write frequency registers on note change
    cpx last_index_p1
    beq @p1_sustain

    ; New note: set frequency
    stx last_index_p1
    lda note_freq_lo, x
    sta APU_PULSE1_LO
    lda note_freq_hi, x
    sta APU_PULSE1_HI

@p1_sustain:
    ; Set ctrl: selected duty + halt + constant vol + volume 12
    ldx cur_duty
    lda duty_table, x
    ora #$3C                ; halt + constant + vol 12
    sta APU_PULSE1_CTRL

    lda #$00
    sta release_p1
    lda #$01
    sta note_active_p1
    rts

@a_released:
    lda note_active_p1
    beq @p1_silent

    ; Release decay
    lda release_p1
    cmp #12
    bcs @p1_done
    inc release_p1

    ; Ctrl: duty + halt + constant + decaying volume
    ldx cur_duty
    lda duty_table, x
    ora #$30
    sta temp
    lda #12
    sec
    sbc release_p1
    ora temp
    sta APU_PULSE1_CTRL
    rts

@p1_done:
    lda #$00
    sta note_active_p1
@p1_silent:
    lda #$30
    sta APU_PULSE1_CTRL
    rts

;------------------------------------------------------------------------------
; Pulse 2 - Harmony synth (B button, plays interval a 4th above)
;------------------------------------------------------------------------------
update_pulse2:
    lda buttons_cur
    and #BTN_B
    beq @b_released

    ; B is held: compute harmony note (cur_note + 2, wrapping)
    lda cur_note
    clc
    adc #$02
    cmp #NOTES_PER_OCT
    bcc @p2_note_ok
    sec
    sbc #NOTES_PER_OCT
@p2_note_ok:
    sta temp

    ldx cur_octave
    lda octave_offset, x
    clc
    adc temp
    tax                     ; X = harmony note index

    cpx last_index_p2
    beq @p2_sustain

    stx last_index_p2
    lda note_freq_lo, x
    sta APU_PULSE2_LO
    lda note_freq_hi, x
    sta APU_PULSE2_HI

@p2_sustain:
    ; Different duty for timbral contrast (offset by 1)
    ldx cur_duty
    lda duty_table_p2, x
    ora #$3C
    sta APU_PULSE2_CTRL

    lda #$00
    sta release_p2
    lda #$01
    sta note_active_p2
    rts

@b_released:
    lda note_active_p2
    beq @p2_silent

    lda release_p2
    cmp #12
    bcs @p2_done
    inc release_p2

    ldx cur_duty
    lda duty_table_p2, x
    ora #$30
    sta temp
    lda #12
    sec
    sbc release_p2
    ora temp
    sta APU_PULSE2_CTRL
    rts

@p2_done:
    lda #$00
    sta note_active_p2
@p2_silent:
    lda #$30
    sta APU_PULSE2_CTRL
    rts

;------------------------------------------------------------------------------
; Triangle - Bass drone (plays cur_note at octave 0 when A or B held)
;------------------------------------------------------------------------------
update_triangle:
    lda buttons_cur
    and #$C0                ; A or B held?
    beq @tri_off

    lda #$FF
    sta APU_TRI_CTRL

    ldx cur_note            ; octave 0 = indices 0-4
    lda note_freq_lo, x
    sta APU_TRI_LO
    lda note_freq_hi, x
    sta APU_TRI_HI
    rts

@tri_off:
    lda #$80
    sta APU_TRI_CTRL
    rts

;------------------------------------------------------------------------------
; Drum loop - kick/snare/hat pattern on noise channel
;------------------------------------------------------------------------------
update_drums:
    lda drum_on
    beq @drums_done

    lda frame_count
    and #$1F                ; 32-frame cycle (~112 BPM)

    cmp #$00
    beq @kick
    cmp #$01
    beq @kick_d1
    cmp #$02
    beq @kick_d2
    cmp #$03
    beq @kick_d3

    cmp #$08
    beq @hat_closed

    cmp #$10
    beq @snare
    cmp #$11
    beq @snare_d1
    cmp #$12
    beq @snare_d2

    cmp #$18
    beq @hat_open
    cmp #$19
    beq @hat_decay

@drums_done:
    rts

@kick:
    lda #$3F                ; vol 15
    sta APU_NOISE_CTRL
    lda #$02                ; low pitch
    sta APU_NOISE_FREQ
    lda #$18
    sta APU_NOISE_LEN
    rts
@kick_d1:
    lda #$3A
    sta APU_NOISE_CTRL
    rts
@kick_d2:
    lda #$35
    sta APU_NOISE_CTRL
    rts
@kick_d3:
    lda #$30
    sta APU_NOISE_CTRL
    rts

@hat_closed:
    lda #$34
    sta APU_NOISE_CTRL
    lda #$0F
    sta APU_NOISE_FREQ
    lda #$02
    sta APU_NOISE_LEN
    rts

@snare:
    lda #$3C
    sta APU_NOISE_CTRL
    lda #$06
    sta APU_NOISE_FREQ
    lda #$10
    sta APU_NOISE_LEN
    rts
@snare_d1:
    lda #$38
    sta APU_NOISE_CTRL
    rts
@snare_d2:
    lda #$30
    sta APU_NOISE_CTRL
    rts

@hat_open:
    lda #$37
    sta APU_NOISE_CTRL
    lda #$0E
    sta APU_NOISE_FREQ
    lda #$06
    sta APU_NOISE_LEN
    rts
@hat_decay:
    lda #$32
    sta APU_NOISE_CTRL
    rts

;------------------------------------------------------------------------------
; IRQ (unused)
;------------------------------------------------------------------------------
IRQ:
    rti

;==============================================================================
; DATA
;==============================================================================
.segment "RODATA"

; Initial palette
initial_palette:
    .byte $0F, $30, $16, $36   ; Palette 0: black, white, red, bright red
    .byte $0F, $30, $16, $36   ; Palette 1 (same)
    .byte $0F, $30, $16, $36   ; Palette 2
    .byte $0F, $30, $16, $36   ; Palette 3
    .byte $0F, $30, $16, $36   ; Sprite palettes (unused)
    .byte $0F, $30, $16, $36
    .byte $0F, $30, $16, $36
    .byte $0F, $30, $16, $36

; Note frequency table - E minor pentatonic (E G A B D)
; 4 octaves × 5 notes = 20 entries
; Timer = round(1789773 / (16 * freq)) - 1
note_freq_lo:
    ; Octave 0 (display: 1)
    .byte $4C               ; E2  82.4 Hz
    .byte $74               ; G2  98.0 Hz
    .byte $F8               ; A2  110 Hz
    .byte $89               ; B2  123.5 Hz
    .byte $F9               ; D3  146.8 Hz
    ; Octave 1 (display: 2)
    .byte $A6               ; E3  164.8 Hz
    .byte $3A               ; G3  196.0 Hz
    .byte $FC               ; A3  220 Hz
    .byte $C4               ; B3  246.9 Hz
    .byte $7C               ; D4  293.7 Hz
    ; Octave 2 (display: 3)
    .byte $53               ; E4  329.6 Hz
    .byte $1D               ; G4  392.0 Hz
    .byte $FE               ; A4  440 Hz
    .byte $E2               ; B4  493.9 Hz
    .byte $BE               ; D5  587.3 Hz
    ; Octave 3 (display: 4)
    .byte $A9               ; E5  659.3 Hz
    .byte $8E               ; G5  784.0 Hz
    .byte $7F               ; A5  880 Hz
    .byte $71               ; B5  987.8 Hz
    .byte $5F               ; D6  1174.7 Hz

note_freq_hi:
    ; Octave 0
    .byte $05, $04, $03, $03, $02
    ; Octave 1
    .byte $02, $02, $01, $01, $01
    ; Octave 2
    .byte $01, $01, $00, $00, $00
    ; Octave 3
    .byte $00, $00, $00, $00, $00

; Duty cycle lookup (bits 7-6 of pulse ctrl)
duty_table:
    .byte $00               ; 12.5% (thin, buzzy)
    .byte $40               ; 25%   (classic NES)
    .byte $80               ; 50%   (warm square)
    .byte $C0               ; 75%   (hollow)

; Pulse 2 duty (offset by 1 for timbral contrast)
duty_table_p2:
    .byte $40               ; when P1=12.5%, P2=25%
    .byte $80               ; when P1=25%,   P2=50%
    .byte $C0               ; when P1=50%,   P2=75%
    .byte $00               ; when P1=75%,   P2=12.5%

; Octave base offset into frequency table
octave_offset:
    .byte 0, 5, 10, 15

; Octave brightness for palette (NES color row)
octave_brightness:
    .byte $10               ; octave 0: dark
    .byte $20               ; octave 1: medium
    .byte $20               ; octave 2: bright
    .byte $30               ; octave 3: brightest

; Note hue for palette (NES color column)
note_hue:
    .byte $05               ; E = red
    .byte $0A               ; G = green
    .byte $01               ; A = blue
    .byte $03               ; B = purple
    .byte $08               ; D = yellow

; Nametable addresses for note letters (row 12, cols 3/9/15/21/27)
letter_addr_lo:
    .byte $83, $89, $8F, $95, $9B

; Nametable addresses for highlight bars (row 14, cols 2/8/14/20/26)
bar_addr_lo:
    .byte $C2, $C8, $CE, $D4, $DA

;------------------------------------------------------------------------------
; Vectors
;------------------------------------------------------------------------------
.segment "VECTORS"
    .word NMI
    .word RESET
    .word IRQ

;------------------------------------------------------------------------------
; CHR ROM - Pattern tiles + font tiles
;------------------------------------------------------------------------------
.segment "CHARS"

; Tile 0: Empty
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 1-8: Basic patterns
.byte $00,$00,$00,$00,$00,$00,$00,$00  ; Tile 1: Empty
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; Tile 2: Solid (color 1)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA  ; Tile 3: Checkerboard
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00  ; Tile 4: H stripes
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA  ; Tile 5: V stripes
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $81,$42,$24,$18,$18,$24,$42,$81  ; Tile 6: X pattern
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$24,$42,$81,$81,$42,$24,$18  ; Tile 7: Diamond
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $3C,$42,$81,$81,$81,$81,$42,$3C  ; Tile 8: Circle
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 9-16: More patterns
.byte $11,$22,$44,$88,$11,$22,$44,$88  ; Tile 9: Diagonal
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $88,$44,$22,$11,$88,$44,$22,$11  ; Tile 10: Diagonal rev
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F  ; Tile 11: Half
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $CC,$CC,$33,$33,$CC,$CC,$33,$33  ; Tile 12: Blocks
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55  ; Tile 13: Fine checker
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$81,$81,$81,$81,$81,$81,$FF  ; Tile 14: Square outline
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$3C,$42,$42,$42,$42,$3C,$00  ; Tile 15: Small circle
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$FF,$FF,$18,$18,$18  ; Tile 16: Cross
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 17-24
.byte $01,$02,$04,$08,$10,$20,$40,$80  ; Tile 17
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $80,$40,$20,$10,$08,$04,$02,$01  ; Tile 18
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$FF,$FF,$00,$00,$00  ; Tile 19: H line
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$18,$18,$18,$18,$18  ; Tile 20: V line
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$3C,$3C,$3C,$3C,$00,$00  ; Tile 21: Small square
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $E7,$E7,$00,$00,$00,$00,$E7,$E7  ; Tile 22: Corners
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$80,$80,$80,$80,$80,$80,$FF  ; Tile 23: L shape
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $7E,$81,$A5,$81,$A5,$99,$81,$7E  ; Tile 24: Smiley
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 25-31: Gradient densities
.byte $11,$00,$44,$00,$11,$00,$44,$00  ; Tile 25: Very sparse
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$00,$55,$00,$55,$00,$55,$00  ; Tile 26: Sparse
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$22,$55,$88,$55,$22,$55,$88  ; Tile 27: Light
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA  ; Tile 28: Medium
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $77,$DD,$77,$DD,$77,$DD,$77,$DD  ; Tile 29: Dense
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$AA,$FF,$AA,$FF,$AA,$FF,$AA  ; Tile 30: Very dense
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; Tile 31: Solid
.byte $00,$00,$00,$00,$00,$00,$00,$00

; --- Font tiles (plane 0 = color 1 = white) ---

; Tile 32: 'E'
.byte $7E,$60,$60,$7C,$60,$60,$7E,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 33: 'G'
.byte $3C,$66,$60,$6E,$66,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 34: 'A'
.byte $18,$3C,$66,$66,$7E,$66,$66,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 35: 'B'
.byte $7C,$66,$66,$7C,$66,$66,$7C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 36: 'D'
.byte $78,$6C,$66,$66,$66,$6C,$78,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 37: '1'
.byte $18,$38,$18,$18,$18,$18,$7E,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 38: '2'
.byte $3C,$66,$06,$0C,$18,$30,$7E,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 39: '3'
.byte $3C,$66,$06,$1C,$06,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 40: '4'
.byte $0C,$1C,$3C,$6C,$7E,$0C,$0C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 41: Solid color 2 (highlight bar)
; Plane 0 = 0, Plane 1 = FF → color index 2
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; Fill remaining CHR space
.res 8192 - (42 * 16), $00
