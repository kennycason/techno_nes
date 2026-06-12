; NES SYNTH v2 - Channel-Based Step Sequencer
;
; Controls:
;   PLAY mode (default):
;     Select      = Cycle channel (C1-C4: Pulse1, Pulse2, Triangle, Noise)
;     Up/Down     = Cycle parameter (SND, WAV, SEQ, SEG, SPD, LCK)
;     Left/Right  = Change current parameter value
;     Start       = Enter EDIT mode
;     LCK=YES     = Lock all editing
;   EDIT mode:
;     Left/Right  = Move edit cursor on grid
;     Up/Down     = Change pitch at cursor (places note if empty)
;     A (tap)     = Place/toggle note at cursor
;     A + L/R     = Extend with hold markers
;     B (tap)     = Clear step at cursor
;     B + L/R     = Clear sweep
;     Select      = Cycle channel
;     Start       = Return to PLAY mode

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
; Constants
;------------------------------------------------------------------------------
BTN_A      = $80
BTN_B      = $40
BTN_SELECT = $20
BTN_START  = $10
BTN_UP     = $08
BTN_DOWN   = $04
BTN_LEFT   = $02
BTN_RIGHT  = $01

STEP_FRAMES = 8
NUM_STEPS   = 16
NUM_SEGS    = 4
NUM_CHANNELS = 4
MAX_PITCH   = 19

PARAM_SND = 0
PARAM_WAV = 1
PARAM_SEQ = 2
PARAM_SEG = 3
PARAM_SPD = 4
PARAM_LCK = 5
NUM_PARAMS = 6

TILE_WHITE    = 2    ; solid white block (for edit cursor flash)

; Tile indices
TILE_EMPTY    = 0
TILE_E        = 32
TILE_G        = 33
TILE_A        = 34
TILE_B        = 35
TILE_D        = 36
TILE_1        = 37
TILE_2        = 38
TILE_3        = 39
TILE_4        = 40
TILE_FILLED   = 41   ; solid color 2 (filled step)
TILE_C        = 42
TILE_S        = 43
TILE_N        = 44
TILE_W        = 45
TILE_V        = 46
TILE_Q        = 47
TILE_0        = 48
TILE_5        = 49
TILE_6        = 50
TILE_7        = 51
TILE_8        = 52
TILE_9        = 53
TILE_STEP_E   = 54   ; empty step outline (color 2)
TILE_CURSOR   = 55   ; cursor arrow (color 1 white)
TILE_HOLD     = 56   ; hold/tie bar (color 2)
TILE_STAR     = 57   ; selection indicator (color 2)
TILE_H        = 58
TILE_I        = 59
TILE_K        = 60
TILE_L        = 61
TILE_M        = 62
TILE_O        = 63
TILE_P        = 64
TILE_R        = 65
TILE_T        = 66
TILE_U        = 67
TILE_ARROW    = 68   ; > param indicator (color 1 white)
TILE_Y        = 69   ; 'Y' letter (color 1 white)
TILE_F        = 70   ; 'F' letter (color 1 white)
TILE_Z        = 71   ; 'Z' letter (color 1 white)

;------------------------------------------------------------------------------
; Zero Page
;------------------------------------------------------------------------------
.segment "ZEROPAGE"
frame_count:     .res 2
buttons_cur:     .res 1
buttons_prev:    .res 1
buttons_new:     .res 1
cur_channel:     .res 1      ; 0-3
cur_param:       .res 1      ; 0-4
seq_cursor:      .res 1      ; 0-15 (playback position)
seq_tick:        .res 1
global_seg:      .res 1      ; 0-3 (current segment)
channel_snd:     .res 4      ; sound preset per channel
channel_wav:     .res 4      ; waveform per channel
last_played:     .res 4      ; last note index per channel ($FF=none)
display_dirty:   .res 1
speed:           .res 1      ; 0-15 (index into speed_table, displays as 1-16)
seq_mode:        .res 1      ; 0=OFF, 1=SEG (loop), 2=ALL (auto-advance)
locked:          .res 1      ; 0=NO, 1=YES (lock editing)
edit_mode:       .res 1      ; 0=PLAY, 1=EDIT
edit_cursor:     .res 1      ; 0-15 (edit position on grid)
edit_pitch:      .res 1      ; last used pitch value (1-20 tonal, 1-6 noise)
temp:            .res 1
temp2:           .res 1

;------------------------------------------------------------------------------
; BSS - Sequence data in RAM
;------------------------------------------------------------------------------
.segment "BSS"
; 4 channels x 4 segments x 16 steps = 256 bytes
; Layout: channel*64 + segment*16 + step
; Values: $00=rest, $01-$14=note, $FF=hold
seq_data:        .res 256

;------------------------------------------------------------------------------
; OAM
;------------------------------------------------------------------------------
.segment "OAM"

;------------------------------------------------------------------------------
; iNES Header
;------------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte $01               ; 1x 16KB PRG
    .byte $01               ; 1x 8KB CHR
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
    inx
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

    ; --- Initialize synth state ---
    ; Most ZP defaults to 0 from RAM clear:
    ;   cur_channel, cur_param, seq_cursor, seq_tick, global_seg,
    ;   channel_snd[4], edit_mode, edit_cursor, locked

    lda #$01
    sta seq_mode            ; SEG mode (play on boot)
    sta display_dirty

    lda #$06                ; E3 = default edit pitch
    sta edit_pitch

    lda #$07                ; SPD 8 (16 frames/step, ~56 BPM)
    sta speed

    lda #$FF
    sta last_played
    sta last_played+1
    sta last_played+2
    sta last_played+3

    ; Enable APU channels
    lda #%00001111
    sta APU_STATUS
    lda #$08
    sta APU_PULSE1_SWEEP
    sta APU_PULSE2_SWEEP

    ; Silence all
    lda #$30
    sta APU_PULSE1_CTRL
    sta APU_PULSE2_CTRL
    sta APU_NOISE_CTRL
    lda #$80
    sta APU_TRI_CTRL

    jsr load_palette
    jsr init_nametable

    lda #%10000000
    sta PPU_CTRL
    lda #%00001010
    sta PPU_MASK

main_loop:
    jmp main_loop

;------------------------------------------------------------------------------
; NMI
;------------------------------------------------------------------------------
NMI:
    pha
    txa
    pha
    tya
    pha

    inc frame_count
    bne @nw
    inc frame_count+1
@nw:
    ; === VBLANK PPU WRITES (phased to fit in vblank) ===
    lda display_dirty
    beq @cursor_only
    cmp #$02
    beq @phase2

    ; Phase 1: stars + grids C1/C2 + cursor
    bit PPU_STATUS
    jsr update_star_indicators
    lda #$00
    sta temp2
    jsr update_grids_pair
    jsr update_cursor_row_inner
    lda #$02
    sta display_dirty
    jmp @scroll_fixup

@phase2:
    ; Phase 2: grids C3/C4 + params + cursor
    bit PPU_STATUS
    lda #$02
    sta temp2
    jsr update_grids_pair
    jsr update_param_indicators
    jsr update_param_values
    jsr update_cursor_row_inner
    lda #$00
    sta display_dirty
    jmp @scroll_fixup

@cursor_only:
    jsr update_cursor_row
    jsr update_edit_cursor_flash
    jsr update_nte_status
@scroll_fixup:
    lda #%10000000
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL

    ; === GAME LOGIC ===
    jsr read_controller
    jsr handle_input
    jsr update_sound

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
; Load palette - 4 fixed BG palettes (one per channel color)
;------------------------------------------------------------------------------
load_palette:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    ldx #$00
@lp:
    lda initial_palette, x
    sta PPU_DATA
    inx
    cpx #$20
    bne @lp
    rts

;------------------------------------------------------------------------------
; Init nametable - draw full static layout + attributes
; Called during init (rendering off, no vblank constraint)
;------------------------------------------------------------------------------
; Layout:
;   Row  4: *C1 [16 steps]
;   Row  6:  C2 [16 steps]
;   Row  8:  C3 [16 steps]
;   Row 10:  C4 [16 steps]
;   Row 11:      [cursor]
;   Row 14: >SND val  WAV val
;   Row 16:  SEQ val  SEG val
;------------------------------------------------------------------------------
init_nametable:
    bit PPU_STATUS

    ; Clear entire nametable + attribute table (1024 bytes)
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    lda #$00
    ldx #$00
    ldy #$04
@clear:
    sta PPU_DATA
    inx
    bne @clear
    dey
    bne @clear

    ; --- C1 label (row 4, cols 1-3) ---
    lda #$20
    sta PPU_ADDR
    lda #$81
    sta PPU_ADDR
    lda #TILE_STAR          ; C1 starts selected
    sta PPU_DATA
    lda #TILE_C
    sta PPU_DATA
    lda #TILE_1
    sta PPU_DATA

    ; C1 empty steps (row 4, cols 5-20)
    lda #$20
    sta PPU_ADDR
    lda #$85
    sta PPU_ADDR
    lda #TILE_STEP_E
    ldx #NUM_STEPS
@s1:
    sta PPU_DATA
    dex
    bne @s1

    ; --- C2 label (row 6) ---
    lda #$20
    sta PPU_ADDR
    lda #$C1
    sta PPU_ADDR
    lda #TILE_EMPTY
    sta PPU_DATA
    lda #TILE_C
    sta PPU_DATA
    lda #TILE_2
    sta PPU_DATA

    lda #$20
    sta PPU_ADDR
    lda #$C5
    sta PPU_ADDR
    lda #TILE_STEP_E
    ldx #NUM_STEPS
@s2:
    sta PPU_DATA
    dex
    bne @s2

    ; --- C3 label (row 8) ---
    lda #$21
    sta PPU_ADDR
    lda #$01
    sta PPU_ADDR
    lda #TILE_EMPTY
    sta PPU_DATA
    lda #TILE_C
    sta PPU_DATA
    lda #TILE_3
    sta PPU_DATA

    lda #$21
    sta PPU_ADDR
    lda #$05
    sta PPU_ADDR
    lda #TILE_STEP_E
    ldx #NUM_STEPS
@s3:
    sta PPU_DATA
    dex
    bne @s3

    ; --- C4 label (row 10) ---
    lda #$21
    sta PPU_ADDR
    lda #$41
    sta PPU_ADDR
    lda #TILE_EMPTY
    sta PPU_DATA
    lda #TILE_C
    sta PPU_DATA
    lda #TILE_4
    sta PPU_DATA

    lda #$21
    sta PPU_ADDR
    lda #$45
    sta PPU_ADDR
    lda #TILE_STEP_E
    ldx #NUM_STEPS
@s4:
    sta PPU_DATA
    dex
    bne @s4

    ; --- Parameter labels (vertical column, rows 13-19) ---
    ; SND (row 13, col 2-4 = $21A2)
    lda #$21
    sta PPU_ADDR
    lda #$A2
    sta PPU_ADDR
    lda #TILE_S
    sta PPU_DATA
    lda #TILE_N
    sta PPU_DATA
    lda #TILE_D
    sta PPU_DATA

    ; WAV (row 14, col 2-4 = $21C2)
    lda #$21
    sta PPU_ADDR
    lda #$C2
    sta PPU_ADDR
    lda #TILE_W
    sta PPU_DATA
    lda #TILE_A
    sta PPU_DATA
    lda #TILE_V
    sta PPU_DATA

    ; NTE status label (row 12, col 2-4 = $2182) — not a param, display-only
    lda #$21
    sta PPU_ADDR
    lda #$82
    sta PPU_ADDR
    lda #TILE_N
    sta PPU_DATA
    lda #TILE_T
    sta PPU_DATA
    lda #TILE_E
    sta PPU_DATA

    ; SEQ (row 15, col 2-4 = $21E2)
    lda #$21
    sta PPU_ADDR
    lda #$E2
    sta PPU_ADDR
    lda #TILE_S
    sta PPU_DATA
    lda #TILE_E
    sta PPU_DATA
    lda #TILE_Q
    sta PPU_DATA

    ; SEG (row 16, col 2-4 = $2202)
    lda #$22
    sta PPU_ADDR
    lda #$02
    sta PPU_ADDR
    lda #TILE_S
    sta PPU_DATA
    lda #TILE_E
    sta PPU_DATA
    lda #TILE_G
    sta PPU_DATA

    ; SPD (row 17, col 2-4 = $2222)
    lda #$22
    sta PPU_ADDR
    lda #$22
    sta PPU_ADDR
    lda #TILE_S
    sta PPU_DATA
    lda #TILE_P
    sta PPU_DATA
    lda #TILE_D
    sta PPU_DATA

    ; LCK (row 18, col 2-4 = $2242)
    lda #$22
    sta PPU_ADDR
    lda #$42
    sta PPU_ADDR
    lda #TILE_L
    sta PPU_DATA
    lda #TILE_C
    sta PPU_DATA
    lda #TILE_K
    sta PPU_DATA

    ; --- Attribute table ($23C0-$23FF) ---
    lda #$23
    sta PPU_ADDR
    lda #$C0
    sta PPU_ADDR

    ; Row 0 (tile rows 0-3): palette 0
    lda #$00
    ldx #$08
@a0:
    sta PPU_DATA
    dex
    bne @a0

    ; Row 1 (tile rows 4-7): top=pal0(C1), bottom=pal1(C2)
    lda #$50
    ldx #$08
@a1:
    sta PPU_DATA
    dex
    bne @a1

    ; Row 2 (tile rows 8-11): top=pal2(C3), bottom=pal3(C4)
    lda #$FA
    ldx #$08
@a2:
    sta PPU_DATA
    dex
    bne @a2

    ; Rows 3-7 (tile rows 12-29): palette 0
    lda #$00
    ldx #40
@a3:
    sta PPU_DATA
    dex
    bne @a3

    rts

;------------------------------------------------------------------------------
; Update cursor row only (row 11, cols 5-20)
;------------------------------------------------------------------------------
update_cursor_row:
    bit PPU_STATUS
    lda #$21
    sta PPU_ADDR
    lda #$65
    sta PPU_ADDR
    ldx #$00
@loop:
    cpx seq_cursor
    bne @blank
    lda #TILE_CURSOR
    jmp @wr
@blank:
    lda #TILE_EMPTY
@wr:
    sta PPU_DATA
    inx
    cpx #NUM_STEPS
    bne @loop
    rts

;------------------------------------------------------------------------------
; Update * indicators for all 4 channels
;------------------------------------------------------------------------------
update_star_indicators:
    ldx #$00
@loop:
    lda star_addr_hi, x
    sta PPU_ADDR
    lda star_addr_lo, x
    sta PPU_ADDR
    cpx cur_channel
    bne @no_star
    lda #TILE_STAR
    jmp @wr
@no_star:
    lda #TILE_EMPTY
@wr:
    sta PPU_DATA
    inx
    cpx #NUM_CHANNELS
    bne @loop
    rts

;------------------------------------------------------------------------------
; Update 2 channel grids starting from channel in temp2
;------------------------------------------------------------------------------
update_grids_pair:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    pha                     ; save seg*16 on stack
@chan_loop:
    ldx temp2
    lda grid_addr_hi, x
    sta PPU_ADDR
    lda grid_addr_lo, x
    sta PPU_ADDR

    pla
    pha                     ; peek seg*16
    clc
    adc channel_base, x
    tax                     ; X = data offset

    ldy #NUM_STEPS
@tile:
    lda seq_data, x
    beq @empty
    cmp #$FF
    beq @hold
    lda #TILE_FILLED
    jmp @wr
@empty:
    lda #TILE_STEP_E
    jmp @wr
@hold:
    lda #TILE_HOLD
@wr:
    sta PPU_DATA
    inx
    dey
    bne @tile

    inc temp2
    lda temp2
    and #$01                ; done after 2 channels (0→1→2 or 2→3→4)
    bne @chan_loop
    pla                     ; clean stack
    rts

;------------------------------------------------------------------------------
; Update cursor row (no PPU_STATUS reset - called from update_display)
;------------------------------------------------------------------------------
update_cursor_row_inner:
    lda #$21
    sta PPU_ADDR
    lda #$65
    sta PPU_ADDR
    ldx #$00
@loop:
    cpx seq_cursor
    bne @blank
    lda #TILE_CURSOR
    jmp @wr
@blank:
    lda #TILE_EMPTY
@wr:
    sta PPU_DATA
    inx
    cpx #NUM_STEPS
    bne @loop
    rts

;------------------------------------------------------------------------------
; Update edit cursor flash (one tile on the grid, called every frame)
;------------------------------------------------------------------------------
update_edit_cursor_flash:
    lda edit_mode
    beq @done

    ldx cur_channel
    lda grid_addr_hi, x
    sta PPU_ADDR
    lda grid_addr_lo, x
    clc
    adc edit_cursor
    sta PPU_ADDR

    lda frame_count
    and #$08
    bne @show_normal

    lda #TILE_WHITE
    sta PPU_DATA
    rts

@show_normal:
    jsr calc_edit_offset
    lda seq_data, x
    beq @empty
    cmp #$FF
    beq @hold
    lda #TILE_FILLED
    jmp @write
@empty:
    lda #TILE_STEP_E
    jmp @write
@hold:
    lda #TILE_HOLD
@write:
    sta PPU_DATA
@done:
    rts

;------------------------------------------------------------------------------
; Update NTE status display (row 12, col 6-8 = $2186)
;------------------------------------------------------------------------------
update_nte_status:
    lda #$21
    sta PPU_ADDR
    lda #$86
    sta PPU_ADDR

    lda edit_mode
    bne @use_edit
    jsr calc_seq_offset
    jmp @read_note
@use_edit:
    jsr calc_edit_offset
@read_note:
    lda seq_data, x
    beq @show_empty
    cmp #$FF
    beq @show_empty

    sec
    sbc #$01
    tax

    lda cur_channel
    cmp #$03
    beq @noise_name

    lda pitch_to_note, x
    tay
    lda note_tiles, y
    sta PPU_DATA
    lda pitch_to_octave, x
    clc
    adc #TILE_1
    sta PPU_DATA
    lda #TILE_EMPTY
    sta PPU_DATA
    rts

@noise_name:
    txa
    sta temp
    asl a
    clc
    adc temp
    tax
    lda snd_name_noise, x
    sta PPU_DATA
    lda snd_name_noise+1, x
    sta PPU_DATA
    lda snd_name_noise+2, x
    sta PPU_DATA
    rts

@show_empty:
    lda #TILE_EMPTY
    sta PPU_DATA
    sta PPU_DATA
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Calculate edit cursor offset: channel_base + seg*16 + edit_cursor -> X
;------------------------------------------------------------------------------
calc_edit_offset:
    ldx cur_channel
    lda channel_base, x
    sta temp
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc temp
    clc
    adc edit_cursor
    tax
    rts

;------------------------------------------------------------------------------
; Update > param indicators
;------------------------------------------------------------------------------
update_param_indicators:
    ldx #$00
@loop:
    lda pind_addr_hi, x
    sta PPU_ADDR
    lda pind_addr_lo, x
    sta PPU_ADDR
    cpx cur_param
    bne @no_ind
    lda #TILE_ARROW
    jmp @wr
@no_ind:
    lda #TILE_EMPTY
@wr:
    sta PPU_DATA
    inx
    cpx #NUM_PARAMS
    bne @loop
    rts

;------------------------------------------------------------------------------
; Update parameter values
;------------------------------------------------------------------------------
update_param_values:
    ; SND value at row 13, col 6 ($21A6)
    lda #$21
    sta PPU_ADDR
    lda #$A6
    sta PPU_ADDR
    jsr write_snd_value

    ; WAV value at row 14, col 6 ($21C6)
    lda #$21
    sta PPU_ADDR
    lda #$C6
    sta PPU_ADDR
    jsr write_wav_value

    ; SEQ value at row 15, col 6 ($21E6)
    lda #$21
    sta PPU_ADDR
    lda #$E6
    sta PPU_ADDR
    jsr write_seq_mode_value

    ; SEG value at row 16, col 6 ($2206)
    lda #$22
    sta PPU_ADDR
    lda #$06
    sta PPU_ADDR
    lda global_seg
    clc
    adc #TILE_1
    sta PPU_DATA
    lda #TILE_EMPTY
    sta PPU_DATA
    sta PPU_DATA

    ; SPD value at row 17, col 6 ($2226)
    lda #$22
    sta PPU_ADDR
    lda #$26
    sta PPU_ADDR
    ldx speed
    lda speed_tens_tile, x
    beq @spd_single
    sta PPU_DATA
    lda speed_ones_tile, x
    sta PPU_DATA
    lda #TILE_EMPTY
    sta PPU_DATA
    jmp @spd_done
@spd_single:
    lda speed_ones_tile, x
    sta PPU_DATA
    lda #TILE_EMPTY
    sta PPU_DATA
    sta PPU_DATA
@spd_done:

    ; LCK value at row 18, col 6 ($2246)
    lda #$22
    sta PPU_ADDR
    lda #$46
    sta PPU_ADDR
    jsr write_lck_value
    rts

;------------------------------------------------------------------------------
; Write SND preset name (3 tiles)
;------------------------------------------------------------------------------
write_snd_value:
    ldx cur_channel
    lda channel_snd, x
    ; A = preset index, multiply by 3
    sta temp
    asl a
    clc
    adc temp
    tax                     ; X = name table offset

    lda cur_channel
    cmp #$02
    beq @tri
    cmp #$03
    beq @noise

    ; Pulse channel
    lda snd_name_pulse, x
    sta PPU_DATA
    lda snd_name_pulse+1, x
    sta PPU_DATA
    lda snd_name_pulse+2, x
    sta PPU_DATA
    rts

@tri:
    lda snd_name_tri, x
    sta PPU_DATA
    lda snd_name_tri+1, x
    sta PPU_DATA
    lda snd_name_tri+2, x
    sta PPU_DATA
    rts

@noise:
    lda snd_name_noise, x
    sta PPU_DATA
    lda snd_name_noise+1, x
    sta PPU_DATA
    lda snd_name_noise+2, x
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Write WAV type name (3 tiles)
;------------------------------------------------------------------------------
write_wav_value:
    ldx cur_channel
    lda channel_wav, x
    sta temp
    asl a
    clc
    adc temp
    tax

    lda cur_channel
    cmp #$02
    beq @tri
    cmp #$03
    beq @noise

    ; Pulse
    lda wav_name_pulse, x
    sta PPU_DATA
    lda wav_name_pulse+1, x
    sta PPU_DATA
    lda wav_name_pulse+2, x
    sta PPU_DATA
    rts

@tri:
    lda wav_name_tri, x
    sta PPU_DATA
    lda wav_name_tri+1, x
    sta PPU_DATA
    lda wav_name_tri+2, x
    sta PPU_DATA
    rts

@noise:
    lda wav_name_noise, x
    sta PPU_DATA
    lda wav_name_noise+1, x
    sta PPU_DATA
    lda wav_name_noise+2, x
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Write SEQ mode value (3 tiles: OFF, SEG, or ALL)
;------------------------------------------------------------------------------
write_seq_mode_value:
    lda seq_mode
    beq @off
    cmp #$02
    beq @all
    ; SEG (1)
    lda #TILE_S
    sta PPU_DATA
    lda #TILE_E
    sta PPU_DATA
    lda #TILE_G
    sta PPU_DATA
    rts
@off:
    lda #TILE_O
    sta PPU_DATA
    lda #TILE_F
    sta PPU_DATA
    lda #TILE_F
    sta PPU_DATA
    rts
@all:
    lda #TILE_A
    sta PPU_DATA
    lda #TILE_L
    sta PPU_DATA
    lda #TILE_L
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Write LCK value (3 tiles: NO or YES)
;------------------------------------------------------------------------------
write_lck_value:
    lda locked
    bne @yes
    lda #TILE_N
    sta PPU_DATA
    lda #TILE_O
    sta PPU_DATA
    lda #TILE_EMPTY
    sta PPU_DATA
    rts
@yes:
    lda #TILE_Y
    sta PPU_DATA
    lda #TILE_E
    sta PPU_DATA
    lda #TILE_S
    sta PPU_DATA
    rts

;==============================================================================
; INPUT
;==============================================================================

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
; Handle input
;------------------------------------------------------------------------------
handle_input:
    lda buttons_prev
    eor #$FF
    and buttons_cur
    sta buttons_new

    ; --- START: toggle PLAY/EDIT mode ---
    lda buttons_new
    and #BTN_START
    beq @no_st
    lda locked
    bne @no_st              ; can't enter edit mode when locked
    lda edit_mode
    eor #$01
    sta edit_mode
    beq @st_dirty
    ; Entering edit mode: snap edit cursor to play cursor
    lda seq_cursor
    sta edit_cursor
@st_dirty:
    lda #$01
    sta display_dirty
@no_st:

    ; --- SELECT: cycle channel (unless locked) ---
    lda locked
    bne @no_sel
    lda buttons_new
    and #BTN_SELECT
    beq @no_sel
    inc cur_channel
    lda cur_channel
    and #$03
    sta cur_channel
    lda #$01
    sta display_dirty
@no_sel:

    ; Branch: EDIT or PLAY mode
    lda edit_mode
    bne handle_edit_input
    ; Fall through to PLAY mode

    ; ============ PLAY MODE ============
    ; Lock check for L/R
    lda locked
    beq @play_unlocked

    ; Locked: only L/R on PARAM_LCK
    lda cur_param
    cmp #PARAM_LCK
    bne @play_updown
    lda buttons_new
    and #BTN_RIGHT
    beq @plck_no_r
    jsr param_up
    lda #$01
    sta display_dirty
@plck_no_r:
    lda buttons_new
    and #BTN_LEFT
    beq @play_updown
    jsr param_down
    lda #$01
    sta display_dirty
    jmp @play_updown

@play_unlocked:
    ; Right: increase param value
    lda buttons_new
    and #BTN_RIGHT
    beq @play_no_r
    jsr param_up
    lda #$01
    sta display_dirty
@play_no_r:
    ; Left: decrease param value
    lda buttons_new
    and #BTN_LEFT
    beq @play_updown
    jsr param_down
    lda #$01
    sta display_dirty

@play_updown:
    ; Up: prev parameter
    lda buttons_new
    and #BTN_UP
    beq @play_no_u
    lda cur_param
    bne @pu_dec
    lda #NUM_PARAMS
@pu_dec:
    sec
    sbc #$01
    sta cur_param
    lda #$01
    sta display_dirty
@play_no_u:
    ; Down: next parameter
    lda buttons_new
    and #BTN_DOWN
    beq @play_no_d
    inc cur_param
    lda cur_param
    cmp #NUM_PARAMS
    bcc @pd_ok
    lda #$00
    sta cur_param
@pd_ok:
    lda #$01
    sta display_dirty
@play_no_d:
    rts

    ; ============ EDIT MODE ============
handle_edit_input:
    ; Check A held (place/extend)
    lda buttons_cur
    and #BTN_A
    bne @a_held

    ; Check B held (clear)
    lda buttons_cur
    and #BTN_B
    beq @no_b_held
    jmp @b_held
@no_b_held:

    ; --- Normal cursor movement ---
    lda buttons_new
    and #BTN_RIGHT
    beq @ed_no_r
    inc edit_cursor
    lda edit_cursor
    and #$0F
    sta edit_cursor
    lda #$01
    sta display_dirty
@ed_no_r:
    lda buttons_new
    and #BTN_LEFT
    beq @ed_updown
    lda edit_cursor
    bne @ed_l_dec
    lda #$10
@ed_l_dec:
    sec
    sbc #$01
    sta edit_cursor
    lda #$01
    sta display_dirty

@ed_updown:
    ; Up/Down: change pitch at edit cursor
    lda buttons_new
    and #BTN_UP
    beq @ed_no_u
    jsr edit_pitch_up
    lda #$01
    sta display_dirty
@ed_no_u:
    lda buttons_new
    and #BTN_DOWN
    beq @ed_no_d
    jsr edit_pitch_down
    lda #$01
    sta display_dirty
@ed_no_d:
    rts

@a_held:
    ; First frame of A: place note (or toggle off)
    lda buttons_new
    and #BTN_A
    beq @a_extend
    jsr calc_edit_offset
    lda seq_data, x
    beq @a_place
    cmp #$FF
    beq @a_place
    ; Note exists → clear it
    lda #$00
    sta seq_data, x
    lda #$01
    sta display_dirty
    rts
@a_place:
    ; Place note at edit_pitch
    lda edit_pitch
    ldx cur_channel
    cpx #$03
    bne @a_clamp_tonal
    ; Noise: clamp 1-6
    cmp #$07
    bcc @a_pitch_ok
    lda #$01
    jmp @a_pitch_ok
@a_clamp_tonal:
    cmp #$15
    bcc @a_pitch_ok
    lda #$06
@a_pitch_ok:
    cmp #$01
    bcs @a_store
    lda #$06                ; default E3
@a_store:
    sta edit_pitch
    jsr calc_edit_offset
    lda edit_pitch
    sta seq_data, x
    lda #$01
    sta display_dirty
    rts

@a_extend:
    ; A held + movement: extend with hold markers
    lda buttons_new
    and #BTN_RIGHT
    beq @ae_no_r
    inc edit_cursor
    lda edit_cursor
    and #$0F
    sta edit_cursor
    jsr calc_edit_offset
    lda #$FF
    sta seq_data, x
    lda #$01
    sta display_dirty
@ae_no_r:
    lda buttons_new
    and #BTN_LEFT
    beq @ae_ud
    lda edit_cursor
    bne @ae_l_dec
    lda #$10
@ae_l_dec:
    sec
    sbc #$01
    sta edit_cursor
    jsr calc_edit_offset
    lda #$FF
    sta seq_data, x
    lda #$01
    sta display_dirty
@ae_ud:
    ; Up/Down while A held: change pitch (no extend)
    lda buttons_new
    and #BTN_UP
    beq @ae_no_u
    jsr edit_pitch_up
    lda #$01
    sta display_dirty
@ae_no_u:
    lda buttons_new
    and #BTN_DOWN
    beq @ae_no_d
    jsr edit_pitch_down
    lda #$01
    sta display_dirty
@ae_no_d:
    rts

@b_held:
    ; First frame of B: clear current step
    lda buttons_new
    and #BTN_B
    beq @b_move
    jsr calc_edit_offset
    lda #$00
    sta seq_data, x
    lda #$01
    sta display_dirty
    rts
@b_move:
    ; B held + movement: clear as you go
    lda buttons_new
    and #BTN_RIGHT
    beq @bm_no_r
    inc edit_cursor
    lda edit_cursor
    and #$0F
    sta edit_cursor
    jsr calc_edit_offset
    lda #$00
    sta seq_data, x
    lda #$01
    sta display_dirty
@bm_no_r:
    lda buttons_new
    and #BTN_LEFT
    beq @bm_done
    lda edit_cursor
    bne @bm_l_dec
    lda #$10
@bm_l_dec:
    sec
    sbc #$01
    sta edit_cursor
    jsr calc_edit_offset
    lda #$00
    sta seq_data, x
    lda #$01
    sta display_dirty
@bm_done:
    rts

;------------------------------------------------------------------------------
; Edit pitch up — increment note at edit cursor (or place new)
;------------------------------------------------------------------------------
edit_pitch_up:
    jsr calc_edit_offset
    lda seq_data, x
    beq @done
    cmp #$FF
    beq @done

    sta temp
    stx temp2

    lda cur_channel
    cmp #$03
    beq @noise_up
    lda temp
    cmp #$14
    bcc @inc_t
    lda #$00
@inc_t:
    clc
    adc #$01
    jmp @store

@noise_up:
    lda temp
    cmp #$06
    bcc @inc_n
    lda #$00
@inc_n:
    clc
    adc #$01
    jmp @store

@done:
    rts

@store:
    sta edit_pitch
    ldx temp2
    sta seq_data, x
    rts

;------------------------------------------------------------------------------
; Edit pitch down — decrement note at edit cursor (or place new)
;------------------------------------------------------------------------------
edit_pitch_down:
    jsr calc_edit_offset
    lda seq_data, x
    beq @done
    cmp #$FF
    beq @done

    sta temp
    stx temp2

    lda cur_channel
    cmp #$03
    beq @noise_dn
    lda temp
    cmp #$02
    bcs @dec_t
    lda #$15
@dec_t:
    sec
    sbc #$01
    jmp @store

@noise_dn:
    lda temp
    cmp #$02
    bcs @dec_n
    lda #$07
@dec_n:
    sec
    sbc #$01
    jmp @store

@done:
    rts

@store:
    sta edit_pitch
    ldx temp2
    sta seq_data, x
    rts

;------------------------------------------------------------------------------
; Silence all APU channels
;------------------------------------------------------------------------------
silence_all:
    lda #$30
    sta APU_PULSE1_CTRL
    sta APU_PULSE2_CTRL
    sta APU_NOISE_CTRL
    lda #$80
    sta APU_TRI_CTRL
    rts

;------------------------------------------------------------------------------
; Param Up (Right button)
;------------------------------------------------------------------------------
param_up:
    lda cur_param
    cmp #PARAM_SND
    beq @snd
    cmp #PARAM_WAV
    beq @wav
    cmp #PARAM_SEQ
    beq @seq
    cmp #PARAM_SEG
    beq @seg
    cmp #PARAM_SPD
    beq @spd
    ; LCK
    lda locked
    eor #$01
    sta locked
    rts

@seq:
    inc seq_mode
    lda seq_mode
    cmp #$03
    bcc @seq_ok
    lda #$00
    sta seq_mode
@seq_ok:
    lda seq_mode
    bne @done
    jsr silence_all     ; switched to OFF
    rts

@seg:
    lda global_seg
    cmp #$03
    bcs @done
    inc global_seg
    rts

@spd:
    lda speed
    cmp #$0F
    bcs @done
    inc speed
    rts

@snd:
    ldx cur_channel
    inc channel_snd, x
    lda channel_snd, x
    cpx #$02
    beq @snd_max4
    cpx #$03
    beq @snd_max6
    cmp #$08            ; pulse: 8 presets
    bcc @done
    lda #$00
    sta channel_snd, x
    rts
@snd_max4:
    cmp #$04            ; triangle: 4 presets
    bcc @done
    lda #$00
    sta channel_snd, x
    rts
@snd_max6:
    cmp #$06            ; noise: 6 drum types
    bcc @done
    lda #$00
    sta channel_snd, x
    rts

@wav:
    ldx cur_channel
    cpx #$02
    beq @done           ; triangle: no WAV
    inc channel_wav, x
    lda channel_wav, x
    cpx #$03
    beq @wav_max2
    cmp #$04            ; pulse: 4 envelope modes
    bcc @done
    lda #$00
    sta channel_wav, x
    rts
@wav_max2:
    cmp #$02            ; noise: 2 modes (LNG/MTL)
    bcc @done
    lda #$00
    sta channel_wav, x
@done:
    rts

;------------------------------------------------------------------------------
; Param Down (Left button)
;------------------------------------------------------------------------------
param_down:
    lda cur_param
    cmp #PARAM_SND
    beq @snd
    cmp #PARAM_WAV
    beq @wav
    cmp #PARAM_SEQ
    beq @seq
    cmp #PARAM_SEG
    beq @seg
    cmp #PARAM_SPD
    beq @spd
    ; LCK
    lda locked
    eor #$01
    sta locked
    rts

@seq:
    lda seq_mode
    bne @seq_dec
    lda #$02
    sta seq_mode
    rts
@seq_dec:
    dec seq_mode
    lda seq_mode
    bne @done
    jsr silence_all     ; switched to OFF
    rts

@seg:
    lda global_seg
    beq @done
    dec global_seg
    rts

@spd:
    lda speed
    beq @done
    dec speed
    rts

@snd:
    ldx cur_channel
    lda channel_snd, x
    bne @snd_dec
    cpx #$02
    beq @snd_wrap_tri
    cpx #$03
    beq @snd_wrap_noise
    lda #$07            ; pulse: wrap to 7
    sta channel_snd, x
    rts
@snd_wrap_tri:
    lda #$03            ; triangle: wrap to 3
    sta channel_snd, x
    rts
@snd_wrap_noise:
    lda #$05            ; noise: wrap to 5
    sta channel_snd, x
    rts
@snd_dec:
    dec channel_snd, x
    rts

@wav:
    ldx cur_channel
    cpx #$02
    beq @done           ; triangle: no WAV
    lda channel_wav, x
    bne @wav_dec
    cpx #$03
    beq @wav_wrap2
    lda #$03            ; pulse: wrap to 3
    sta channel_wav, x
    rts
@wav_wrap2:
    lda #$01            ; noise: wrap to 1
    sta channel_wav, x
    rts
@wav_dec:
    dec channel_wav, x
@done:
    rts

;------------------------------------------------------------------------------
; Clear current channel's current segment
;------------------------------------------------------------------------------
clear_channel_segment:
    jsr calc_seg_base
    lda #$00
    ldy #NUM_STEPS
@loop:
    sta seq_data, x
    inx
    dey
    bne @loop
    rts

;------------------------------------------------------------------------------
; Calculate seq_data offset: channel_base + seg*16 + cursor -> X
;------------------------------------------------------------------------------
calc_seq_offset:
    ldx cur_channel
    lda channel_base, x
    sta temp
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc temp
    clc
    adc seq_cursor
    tax
    rts

;------------------------------------------------------------------------------
; Calculate segment base offset: channel_base + seg*16 -> X
;------------------------------------------------------------------------------
calc_seg_base:
    ldx cur_channel
    lda channel_base, x
    sta temp
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc temp
    tax
    rts

;==============================================================================
; SOUND ENGINE
;==============================================================================

;------------------------------------------------------------------------------
; Update sound - sequencer tick + playback
;------------------------------------------------------------------------------
update_sound:
    lda seq_mode
    beq @done

    inc seq_tick
    ldx speed
    lda seq_tick
    cmp speed_table, x
    bcc @done

    ; --- New step ---
    lda #$00
    sta seq_tick

    inc seq_cursor
    lda seq_cursor
    cmp #NUM_STEPS
    bcc @play
    lda #$00
    sta seq_cursor

    ; Cursor wrapped — only advance segment in ALL mode
    lda seq_mode
    cmp #$02
    bne @play               ; SEG or OFF: just loop
    jsr advance_segment
    lda #$01
    sta display_dirty

@play:
    jsr play_pulse1
    jsr play_pulse2
    jsr play_triangle
    jsr play_noise
@done:
    rts

;------------------------------------------------------------------------------
; Advance segment (SEQ=ALL mode)
; Increments global_seg; if next segment is empty, wraps to 0
;------------------------------------------------------------------------------
advance_segment:
    inc global_seg
    lda global_seg
    cmp #NUM_SEGS
    bcc @check
    lda #$00
    sta global_seg
    rts

@check:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    sta temp                ; seg * 16

    ldy #$00               ; channel index
@chan:
    lda channel_base, y
    clc
    adc temp
    tax

    lda #16
    sta temp2
@byte:
    lda seq_data, x
    bne @has_data
    inx
    dec temp2
    bne @byte

    iny
    cpy #NUM_CHANNELS
    bne @chan

    ; All channels empty — wrap to segment 0
    lda #$00
    sta global_seg
@has_data:
    rts

;------------------------------------------------------------------------------
; Play Pulse 1 (channel 0)
;------------------------------------------------------------------------------
play_pulse1:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc seq_cursor
    tax
    lda seq_data, x

    beq @silence
    cmp #$FF
    beq @hold

    sec
    sbc #$01
    tax
    cpx last_played
    beq @sustain
    stx last_played
    lda note_freq_lo, x
    sta APU_PULSE1_LO
    lda note_freq_hi, x
    sta APU_PULSE1_HI

@sustain:
@hold:
    ldx channel_snd
    lda snd_pulse_vol, x    ; DD11VVVV (duty + volume)
    ldx channel_wav
    beq @p1_set
    and #$C0                ; keep duty from SND
    ora wav_envelope, x     ; apply envelope mode
@p1_set:
    sta APU_PULSE1_CTRL
    rts

@silence:
    lda #$30
    sta APU_PULSE1_CTRL
    lda #$FF
    sta last_played
    rts

;------------------------------------------------------------------------------
; Play Pulse 2 (channel 1)
;------------------------------------------------------------------------------
play_pulse2:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc seq_cursor
    clc
    adc #$40
    tax
    lda seq_data, x

    beq @silence
    cmp #$FF
    beq @hold

    sec
    sbc #$01
    tax
    cpx last_played+1
    beq @sustain
    stx last_played+1
    lda note_freq_lo, x
    sta APU_PULSE2_LO
    lda note_freq_hi, x
    sta APU_PULSE2_HI

@sustain:
@hold:
    ldx channel_snd+1
    lda snd_pulse_vol, x    ; DD11VVVV (duty + volume)
    ldx channel_wav+1
    beq @p2_set
    and #$C0                ; keep duty from SND
    ora wav_envelope, x     ; apply envelope mode
@p2_set:
    sta APU_PULSE2_CTRL
    rts

@silence:
    lda #$30
    sta APU_PULSE2_CTRL
    lda #$FF
    sta last_played+1
    rts

;------------------------------------------------------------------------------
; Play Triangle (channel 2)
;------------------------------------------------------------------------------
play_triangle:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc seq_cursor
    clc
    adc #$80
    tax
    lda seq_data, x

    beq @silence
    cmp #$FF
    beq @hold

    sec
    sbc #$01
    tax
    cpx last_played+2
    beq @sustain
    stx last_played+2
    lda note_freq_lo, x
    sta APU_TRI_LO
    lda note_freq_hi, x
    sta APU_TRI_HI

@sustain:
@hold:
    ldx channel_snd+2
    lda snd_tri_ctrl, x
    sta APU_TRI_CTRL
    rts

@silence:
    lda #$80
    sta APU_TRI_CTRL
    lda #$FF
    sta last_played+2
    rts

;------------------------------------------------------------------------------
; Play Noise (channel 3)
;------------------------------------------------------------------------------
play_noise:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    clc
    adc seq_cursor
    clc
    adc #$C0
    tax
    lda seq_data, x

    beq @silence
    cmp #$FF
    beq @hold

    sec
    sbc #$01
    tax
    stx last_played+3

    lda drum_ctrl, x
    sta APU_NOISE_CTRL
    lda drum_freq, x
    ldy channel_wav+3
    ora noise_loop, y
    sta APU_NOISE_FREQ
    lda drum_len, x
    sta APU_NOISE_LEN
    rts

@hold:
    lda #$34
    sta APU_NOISE_CTRL
    rts

@silence:
    lda #$30
    sta APU_NOISE_CTRL
    lda #$FF
    sta last_played+3
    rts

;------------------------------------------------------------------------------
; IRQ (unused)
;------------------------------------------------------------------------------
IRQ:
    rti

;==============================================================================
; DATA TABLES
;==============================================================================
.segment "RODATA"

; 4 BG palettes - one per channel color
; Each: bg, white text, channel color, bright accent
initial_palette:
    .byte $0F, $30, $16, $26   ; Pal 0: C1 red
    .byte $0F, $30, $12, $22   ; Pal 1: C2 blue
    .byte $0F, $30, $1A, $2A   ; Pal 2: C3 green
    .byte $0F, $30, $28, $38   ; Pal 3: C4 yellow
    ; Sprite palettes (unused, fill)
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $12, $22
    .byte $0F, $30, $1A, $2A
    .byte $0F, $30, $28, $38

; Note frequencies - E minor pentatonic, 4 octaves (20 notes)
note_freq_lo:
    .byte $4C,$74,$F8,$89,$F9  ; Oct 0: E2 G2 A2 B2 D3
    .byte $A6,$3A,$FC,$C4,$7C  ; Oct 1: E3 G3 A3 B3 D4
    .byte $53,$1D,$FE,$E2,$BE  ; Oct 2: E4 G4 A4 B4 D5
    .byte $A9,$8E,$7F,$71,$5F  ; Oct 3: E5 G5 A5 B5 D6

note_freq_hi:
    .byte $05,$04,$03,$03,$02  ; Oct 0
    .byte $02,$02,$01,$01,$01  ; Oct 1
    .byte $01,$01,$00,$00,$00  ; Oct 2
    .byte $00,$00,$00,$00,$00  ; Oct 3

; Channel base offsets in seq_data
channel_base:
    .byte $00,$40,$80,$C0

; Pulse SND presets (duty + halt + const + volume in one byte)
; Format: DDhcVVVV — DD=duty, h=halt, c=const, VVVV=volume
snd_pulse_vol:
    .byte $BF                  ; 0=LED: 50% duty, vol 15 (warm lead)
    .byte $3F                  ; 1=STB: 12.5% duty, vol 15 (bright stab)
    .byte $FC                  ; 2=BAS: 75% duty, vol 12 (fat bass)
    .byte $75                  ; 3=PAD: 25% duty, vol 5 (soft pad)
    .byte $38                  ; 4=BUZ: 12.5% duty, vol 8 (thin buzz)
    .byte $B9                  ; 5=SQR: 50% duty, vol 9 (square med)
    .byte $FF                  ; 6=FUL: 75% duty, vol 15 (full power)
    .byte $7C                  ; 7=TNK: 25% duty, vol 12 (bright tonk)

; WAV envelope modes for pulse (applied when WAV != 0)
; Format: 0h0cVVVV — ORed with duty from SND (kept via AND $C0)
; h=1 (loop envelope), c=0 (envelope mode), VVVV=decay period
wav_envelope:
    .byte $30                  ; 0=SUS: unused (sustain path skips this)
    .byte $21                  ; 1=PLK: fast pluck (period 1, ~0.5s cycle)
    .byte $24                  ; 2=TRM: tremolo (period 4, ~1.3s cycle)
    .byte $28                  ; 3=SLW: slow fade (period 8, ~2.4s cycle)

; Triangle SND presets (linear counter value)
snd_tri_ctrl:
    .byte $FF                  ; 0=NRM: full sustain
    .byte $8A                  ; 1=STC: staccato
    .byte $84                  ; 2=SHT: short
    .byte $81                  ; 3=PLS: ultra-short pulse

; Drum parameters (6 types)
; NES noise: higher period = lower frequency. Bit 7 = metallic mode.
drum_ctrl:
    .byte $3F,$3C,$34,$37,$3B,$3A  ; kick/snare/hat-c/hat-o/tom/rim volume
drum_freq:
    .byte $0C,$06,$81,$81,$09,$83  ; kick(deep)/snare(crack)/hat-c(metal)/hat-o(metal)/tom(thump)/rim(metal)
drum_len:
    .byte $0C,$08,$02,$08,$0A,$04  ; kick/snare/hat-c/hat-o/tom/rim length

; Noise loop mode
noise_loop:
    .byte $00,$80              ; 0=normal, 1=metallic

; Note letter tiles (indexed by pitch_to_note value)
note_tiles:
    .byte TILE_E, TILE_G, TILE_A, TILE_B, TILE_D

; Pitch-to-note/octave lookup
pitch_to_note:
    .byte 0,1,2,3,4            ; E G A B D
    .byte 0,1,2,3,4
    .byte 0,1,2,3,4
    .byte 0,1,2,3,4
pitch_to_octave:
    .byte 0,0,0,0,0
    .byte 1,1,1,1,1
    .byte 2,2,2,2,2
    .byte 3,3,3,3,3

; PPU addresses for * channel indicators
star_addr_hi: .byte $20, $20, $21, $21
star_addr_lo: .byte $81, $C1, $01, $41

; PPU addresses for grid starts (row, col 5)
grid_addr_hi: .byte $20, $20, $21, $21
grid_addr_lo: .byte $85, $C5, $05, $45

; PPU addresses for > param indicators (rows 13-18, col 1)
pind_addr_hi: .byte $21, $21, $21, $22, $22, $22
pind_addr_lo: .byte $A1, $C1, $E1, $01, $21, $41

; SND preset name tiles (3 tiles per preset)
snd_name_pulse:
    .byte TILE_L, TILE_E, TILE_D   ; 0=LED (warm lead)
    .byte TILE_S, TILE_T, TILE_B   ; 1=STB (bright stab)
    .byte TILE_B, TILE_A, TILE_S   ; 2=BAS (fat bass)
    .byte TILE_P, TILE_A, TILE_D   ; 3=PAD (soft pad)
    .byte TILE_B, TILE_U, TILE_Z   ; 4=BUZ (thin buzz)
    .byte TILE_S, TILE_Q, TILE_R   ; 5=SQR (square med)
    .byte TILE_F, TILE_U, TILE_L   ; 6=FUL (full power)
    .byte TILE_T, TILE_N, TILE_K   ; 7=TNK (bright tonk)

snd_name_tri:
    .byte TILE_N, TILE_R, TILE_M   ; 0=NRM (full sustain)
    .byte TILE_S, TILE_T, TILE_C   ; 1=STC (staccato)
    .byte TILE_S, TILE_H, TILE_T   ; 2=SHT (short)
    .byte TILE_P, TILE_L, TILE_S   ; 3=PLS (pulse)

snd_name_noise:
    .byte TILE_K, TILE_C, TILE_K   ; 0=Kick
    .byte TILE_S, TILE_N, TILE_R   ; 1=Snare
    .byte TILE_H, TILE_T, TILE_C   ; 2=Hat Closed
    .byte TILE_H, TILE_T, TILE_O   ; 3=Hat Open
    .byte TILE_T, TILE_O, TILE_M   ; 4=Tom
    .byte TILE_R, TILE_I, TILE_M   ; 5=Rimshot

; WAV type name tiles (3 tiles per value)
wav_name_pulse:
    .byte TILE_S, TILE_U, TILE_S   ; 0=SUS (sustain)
    .byte TILE_P, TILE_L, TILE_K   ; 1=PLK (pluck)
    .byte TILE_T, TILE_R, TILE_M   ; 2=TRM (tremolo)
    .byte TILE_S, TILE_L, TILE_W   ; 3=SLW (slow fade)

wav_name_tri:
    .byte TILE_T, TILE_R, TILE_I   ; 0=TRI

wav_name_noise:
    .byte TILE_L, TILE_N, TILE_G   ; 0=Long
    .byte TILE_M, TILE_T, TILE_L   ; 1=Metallic

; Speed table (frames per step, indexed 0-15 = SPD 01-16)
speed_table:
    .byte 60, 48, 40, 32, 26, 22, 18, 16
    .byte 14, 12, 10, 8, 6, 4, 3, 2

; Speed display tiles: tens digit (0 or 1)
speed_tens_tile:
    .byte TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY
    .byte TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY
    .byte TILE_EMPTY, TILE_1, TILE_1, TILE_1
    .byte TILE_1, TILE_1, TILE_1, TILE_1

; Speed display tiles: ones digit
speed_ones_tile:
    .byte TILE_1, TILE_2, TILE_3, TILE_4
    .byte TILE_5, TILE_6, TILE_7, TILE_8
    .byte TILE_9, TILE_0, TILE_1, TILE_2
    .byte TILE_3, TILE_4, TILE_5, TILE_6

;------------------------------------------------------------------------------
; Vectors
;------------------------------------------------------------------------------
.segment "VECTORS"
    .word NMI
    .word RESET
    .word IRQ

;------------------------------------------------------------------------------
; CHR ROM
;------------------------------------------------------------------------------
.segment "CHARS"

; Tile 0: Empty
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 1-31: Pattern tiles
.byte $00,$00,$00,$00,$00,$00,$00,$00  ; 1
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; 2: Solid
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA  ; 3
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00  ; 4
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA  ; 5
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $81,$42,$24,$18,$18,$24,$42,$81  ; 6
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$24,$42,$81,$81,$42,$24,$18  ; 7
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $3C,$42,$81,$81,$81,$81,$42,$3C  ; 8
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $11,$22,$44,$88,$11,$22,$44,$88  ; 9
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $88,$44,$22,$11,$88,$44,$22,$11  ; 10
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F  ; 11
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $CC,$CC,$33,$33,$CC,$CC,$33,$33  ; 12
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55  ; 13
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$81,$81,$81,$81,$81,$81,$FF  ; 14
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$3C,$42,$42,$42,$42,$3C,$00  ; 15
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$FF,$FF,$18,$18,$18  ; 16
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $01,$02,$04,$08,$10,$20,$40,$80  ; 17
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $80,$40,$20,$10,$08,$04,$02,$01  ; 18
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$FF,$FF,$00,$00,$00  ; 19
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$18,$18,$18,$18,$18  ; 20
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$3C,$3C,$3C,$3C,$00,$00  ; 21
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $E7,$E7,$00,$00,$00,$00,$E7,$E7  ; 22
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$80,$80,$80,$80,$80,$80,$FF  ; 23
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $7E,$81,$A5,$81,$A5,$99,$81,$7E  ; 24
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $11,$00,$44,$00,$11,$00,$44,$00  ; 25
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$00,$55,$00,$55,$00,$55,$00  ; 26
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$22,$55,$88,$55,$22,$55,$88  ; 27
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA  ; 28
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $77,$DD,$77,$DD,$77,$DD,$77,$DD  ; 29
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$AA,$FF,$AA,$FF,$AA,$FF,$AA  ; 30
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; 31
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

; Tile 41: Solid color 2 (filled step)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; Tile 42: 'C'
.byte $3C,$66,$60,$60,$60,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 43: 'S'
.byte $3C,$66,$70,$3C,$0E,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 44: 'N'
.byte $66,$76,$7E,$7E,$6E,$66,$66,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 45: 'W'
.byte $66,$66,$66,$5A,$5A,$5A,$24,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 46: 'V'
.byte $66,$66,$66,$3C,$3C,$18,$18,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 47: 'Q'
.byte $3C,$66,$66,$66,$66,$3C,$0E,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 48: '0'
.byte $3C,$66,$6E,$76,$66,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 49: '5'
.byte $7E,$60,$7C,$06,$06,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 50: '6'
.byte $3C,$66,$60,$7C,$66,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 51: '7'
.byte $7E,$06,$0C,$18,$18,$18,$18,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 52: '8'
.byte $3C,$66,$66,$3C,$66,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00
; Tile 53: '9'
.byte $3C,$66,$66,$3E,$06,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 54: Empty step (outline box, color 2)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$3C,$24,$24,$24,$3C,$00,$00

; Tile 55: Cursor marker (up arrow, color 1 = white)
.byte $00,$18,$3C,$7E,$18,$18,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 56: Hold/tie (horizontal bar, color 2)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$7E,$7E,$00,$00,$00

; --- New tiles for v2 multi-channel display ---

; Tile 57: Star/selection indicator (color 2 = channel color)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$3C,$3C,$3C,$3C,$00,$00

; Tile 58: 'H'
.byte $66,$66,$66,$7E,$66,$66,$66,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 59: 'I'
.byte $3C,$18,$18,$18,$18,$18,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 60: 'K'
.byte $66,$6C,$78,$70,$78,$6C,$66,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 61: 'L'
.byte $60,$60,$60,$60,$60,$60,$7E,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 62: 'M'
.byte $C6,$EE,$FE,$D6,$C6,$C6,$C6,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 63: 'O'
.byte $3C,$66,$66,$66,$66,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 64: 'P'
.byte $7C,$66,$66,$7C,$60,$60,$60,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 65: 'R'
.byte $7C,$66,$66,$7C,$6C,$66,$66,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 66: 'T'
.byte $7E,$18,$18,$18,$18,$18,$18,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 67: 'U'
.byte $66,$66,$66,$66,$66,$66,$3C,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 68: '>' arrow indicator (color 1 = white)
.byte $40,$60,$70,$78,$70,$60,$40,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 69: 'Y'
.byte $66,$66,$3C,$18,$18,$18,$18,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 70: 'F'
.byte $7E,$60,$60,$7C,$60,$60,$60,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 71: 'Z'
.byte $7E,$06,$0C,$18,$30,$60,$7E,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Fill remaining CHR space
.res 8192 - (72 * 16), $00
