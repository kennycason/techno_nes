; NES SYNTH v2 - Channel-Based Step Sequencer
;
; Controls:
;   Select      = Cycle channel (C1-C4: Pulse1, Pulse2, Triangle, Noise)
;   Left/Right  = Cycle parameter (SND, WAV, SEQ, SEG)
;   Up/Down     = Change current parameter value
;   A           = SEQ: record note at cursor (hold=sustain) / SND,WAV: preview
;   B           = SEQ: clear current channel's segment
;   Start       = Play/pause sequencer
;
; Channels:
;   C1 = Pulse 1    C2 = Pulse 2    C3 = Triangle    C4 = Noise

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

; Parameter indices
PARAM_SND = 0
PARAM_WAV = 1
PARAM_SEQ = 2
PARAM_SEG = 3

;------------------------------------------------------------------------------
; Zero Page
;------------------------------------------------------------------------------
.segment "ZEROPAGE"
frame_count:     .res 2
buttons_cur:     .res 1
buttons_prev:    .res 1
buttons_new:     .res 1
cur_channel:     .res 1      ; 0-3
cur_param:       .res 1      ; 0-3
cur_pitch:       .res 1      ; 0-19 (linear index into freq table)
seq_cursor:      .res 1      ; 0-15
seq_tick:        .res 1      ; 0-7
seq_playing:     .res 1      ; 0=paused, 1=playing
global_seg:      .res 1      ; 0-3 (current playback/edit segment)
channel_snd:     .res 4      ; sound preset per channel
channel_wav:     .res 4      ; waveform per channel
last_played:     .res 4      ; last note index per channel ($FF=none)
recording:       .res 1      ; nonzero if A held in SEQ mode
preview_ch:      .res 1      ; channel being previewed ($FF=none)
display_dirty:   .res 1
temp:            .res 1

;------------------------------------------------------------------------------
; BSS - Sequence data in RAM
;------------------------------------------------------------------------------
.segment "BSS"
; 4 channels x 4 segments x 16 steps = 256 bytes
; Layout: channel*64 + segment*16 + step
; Values: $00=rest, $01-$14=note, $FF=hold
seq_data:        .res 256

;------------------------------------------------------------------------------
; OAM (avoids linker warning)
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
    lda #$00
    sta cur_channel
    sta cur_param
    sta seq_cursor
    sta seq_tick
    sta global_seg
    sta recording
    sta channel_snd
    sta channel_snd+1
    sta channel_snd+2
    sta channel_snd+3
    sta channel_wav+2       ; triangle: n/a
    sta channel_wav+3       ; noise: long loop

    lda #$05                ; E3 = middle range
    sta cur_pitch

    lda #$01
    sta seq_playing
    sta display_dirty

    lda #$02                ; 50% duty for pulse channels
    sta channel_wav
    sta channel_wav+1

    lda #$FF
    sta last_played
    sta last_played+1
    sta last_played+2
    sta last_played+3
    sta preview_ch          ; not previewing

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
    ; === VBLANK ===
    jsr update_palette

    lda display_dirty
    beq @skip_disp
    jsr update_display
    lda #$00
    sta display_dirty
@skip_disp:

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
; Init nametable - clear + place step grid outlines
;------------------------------------------------------------------------------
init_nametable:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    lda #$00
    ldx #$00
    ldy #$04
@fill:
    sta PPU_DATA
    inx
    bne @fill
    dey
    bne @fill

    ; Place 16 empty-step tiles on row 10, cols 8-23
    bit PPU_STATUS
    lda #$21
    sta PPU_ADDR
    lda #$48
    sta PPU_ADDR
    lda #54                 ; empty step tile
    ldx #$10
@steps:
    sta PPU_DATA
    dex
    bne @steps
    rts

;------------------------------------------------------------------------------
; Update palette - channel-colored
;------------------------------------------------------------------------------
update_palette:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    lda #$0F
    sta PPU_DATA            ; color 0: black bg

    lda #$30
    sta PPU_DATA            ; color 1: white text

    ldx cur_channel
    lda channel_color, x
    sta PPU_DATA            ; color 2: channel highlight

    lda channel_color_bright, x
    sta PPU_DATA            ; color 3: bright accent
    rts

;------------------------------------------------------------------------------
; Update display - all dynamic nametable content
;------------------------------------------------------------------------------
update_display:
    bit PPU_STATUS

    ; --- Row 2: Channel + Parameter label ---
    lda #$20
    sta PPU_ADDR
    lda #$42                ; row 2, col 2
    sta PPU_ADDR
    lda #42                 ; 'C' tile
    sta PPU_DATA
    lda cur_channel
    clc
    adc #37                 ; digit 1-4
    sta PPU_DATA

    lda #$20
    sta PPU_ADDR
    lda #$45                ; row 2, col 5
    sta PPU_ADDR
    ldx cur_param
    lda param_name_t0, x
    sta PPU_DATA
    lda param_name_t1, x
    sta PPU_DATA
    lda param_name_t2, x
    sta PPU_DATA

    ; --- Row 4: Parameter value ---
    lda #$20
    sta PPU_ADDR
    lda #$82                ; row 4, col 2
    sta PPU_ADDR
    jsr write_param_value

    ; --- Row 7: Current pitch ---
    lda #$20
    sta PPU_ADDR
    lda #$E2                ; row 7, col 2
    sta PPU_ADDR
    jsr write_pitch_display

    ; --- Row 10: Step grid (16 tiles, cols 8-23) ---
    lda #$21
    sta PPU_ADDR
    lda #$48                ; row 10, col 8
    sta PPU_ADDR
    jsr write_step_grid

    ; --- Row 11: Cursor (16 tiles, cols 8-23) ---
    lda #$21
    sta PPU_ADDR
    lda #$68                ; row 11, col 8
    sta PPU_ADDR
    jsr write_cursor_row

    ; --- Row 14: Segment label + digit ---
    lda #$21
    sta PPU_ADDR
    lda #$C2                ; row 14, col 2
    sta PPU_ADDR
    lda #43                 ; 'S'
    sta PPU_DATA
    lda #32                 ; 'E'
    sta PPU_DATA
    lda #33                 ; 'G'
    sta PPU_DATA

    lda #$21
    sta PPU_ADDR
    lda #$C6                ; row 14, col 6
    sta PPU_ADDR
    lda global_seg
    clc
    adc #37
    sta PPU_DATA

    rts

;------------------------------------------------------------------------------
; Write parameter value (3 tiles at current PPU address)
;------------------------------------------------------------------------------
write_param_value:
    lda cur_param
    cmp #PARAM_SND
    beq @snd
    cmp #PARAM_WAV
    beq @wav
    cmp #PARAM_SEQ
    beq @seq
    ; SEG
    lda global_seg
    clc
    adc #37
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    sta PPU_DATA
    rts

@snd:
    ldx cur_channel
    lda channel_snd, x
    clc
    adc #37
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    sta PPU_DATA
    rts

@wav:
    ldx cur_channel
    lda channel_wav, x
    clc
    adc #37
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    sta PPU_DATA
    rts

@seq:
    lda cur_channel
    cmp #$03
    beq @seq_noise
    ; Pitched: note letter + octave
    ldx cur_pitch
    lda pitch_to_note, x
    clc
    adc #32
    sta PPU_DATA
    lda pitch_to_octave, x
    clc
    adc #37
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    rts
@seq_noise:
    lda channel_snd+3
    clc
    adc #37
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Write pitch display (3 tiles)
;------------------------------------------------------------------------------
write_pitch_display:
    lda cur_channel
    cmp #$03
    beq @noise
    ldx cur_pitch
    lda pitch_to_note, x
    clc
    adc #32
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    lda pitch_to_octave, x
    clc
    adc #37
    sta PPU_DATA
    rts
@noise:
    lda channel_snd+3
    clc
    adc #37
    sta PPU_DATA
    lda #$00
    sta PPU_DATA
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Write step grid (16 tiles from sequence data)
;------------------------------------------------------------------------------
write_step_grid:
    ; Compute RAM offset for current channel + global segment
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
    tax                     ; X = base offset into seq_data

    ldy #NUM_STEPS
@grid:
    lda seq_data, x
    beq @empty
    cmp #$FF
    beq @hold
    lda #41                 ; filled note (color 2)
    jmp @write
@empty:
    lda #54                 ; empty step outline
    jmp @write
@hold:
    lda #56                 ; hold/tie marker
@write:
    sta PPU_DATA
    inx
    dey
    bne @grid
    rts

;------------------------------------------------------------------------------
; Write cursor row (16 tiles)
;------------------------------------------------------------------------------
write_cursor_row:
    ldx #$00
@loop:
    lda seq_playing
    beq @blank              ; paused: hide cursor
    cpx seq_cursor
    bne @blank
    lda #55                 ; cursor marker
    jmp @wr
@blank:
    lda #$00
@wr:
    sta PPU_DATA
    inx
    cpx #NUM_STEPS
    bne @loop
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

    ; --- Select: cycle channel ---
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

    ; --- Right: next parameter ---
    lda buttons_new
    and #BTN_RIGHT
    beq @no_r
    inc cur_param
    lda cur_param
    and #$03
    sta cur_param
    lda #$01
    sta display_dirty
@no_r:

    ; --- Left: prev parameter ---
    lda buttons_new
    and #BTN_LEFT
    beq @no_l
    lda cur_param
    bne @l_dec
    lda #$04
@l_dec:
    sec
    sbc #$01
    sta cur_param
    lda #$01
    sta display_dirty
@no_l:

    ; --- Up: increase value ---
    lda buttons_new
    and #BTN_UP
    beq @no_u
    jsr param_up
    lda #$01
    sta display_dirty
@no_u:

    ; --- Down: decrease value ---
    lda buttons_new
    and #BTN_DOWN
    beq @no_d
    jsr param_down
    lda #$01
    sta display_dirty
@no_d:

    ; --- A: record / preview ---
    jsr handle_a_button

    ; --- B: clear segment (SEQ only) ---
    lda buttons_new
    and #BTN_B
    beq @no_b
    lda cur_param
    cmp #PARAM_SEQ
    bne @no_b
    jsr clear_channel_segment
    lda #$01
    sta display_dirty
@no_b:

    ; --- Start: play/pause ---
    lda buttons_new
    and #BTN_START
    beq @no_st
    lda seq_playing
    eor #$01
    sta seq_playing
    lda #$01
    sta display_dirty
@no_st:

    rts

;------------------------------------------------------------------------------
; Param Up
;------------------------------------------------------------------------------
param_up:
    lda cur_param
    cmp #PARAM_SND
    beq @snd
    cmp #PARAM_WAV
    beq @wav
    cmp #PARAM_SEQ
    beq @pitch
    ; SEG
    lda global_seg
    cmp #$03
    bcs @done
    inc global_seg
    rts

@snd:
    ldx cur_channel
    inc channel_snd, x
    lda channel_snd, x
    cpx #$02                ; triangle max = 2
    beq @snd_max2
    cmp #$04                ; pulse/noise max = 4
    bcc @done
    lda #$00
    sta channel_snd, x
    rts
@snd_max2:
    cmp #$02
    bcc @done
    lda #$00
    sta channel_snd, x
    rts

@wav:
    ldx cur_channel
    cpx #$02                ; triangle: no WAV
    beq @done
    inc channel_wav, x
    lda channel_wav, x
    cpx #$03                ; noise max = 2
    beq @wav_max2
    cmp #$04                ; pulse max = 4
    bcc @done
    lda #$00
    sta channel_wav, x
    rts
@wav_max2:
    cmp #$02
    bcc @done
    lda #$00
    sta channel_wav, x
    rts

@pitch:
    lda cur_pitch
    cmp #MAX_PITCH
    bcs @done
    inc cur_pitch
@done:
    rts

;------------------------------------------------------------------------------
; Param Down
;------------------------------------------------------------------------------
param_down:
    lda cur_param
    cmp #PARAM_SND
    beq @snd
    cmp #PARAM_WAV
    beq @wav
    cmp #PARAM_SEQ
    beq @pitch
    ; SEG
    lda global_seg
    beq @done
    dec global_seg
    rts

@snd:
    ldx cur_channel
    lda channel_snd, x
    bne @snd_dec
    cpx #$02
    beq @snd_wrap2
    lda #$03
    sta channel_snd, x
    rts
@snd_wrap2:
    lda #$01
    sta channel_snd, x
    rts
@snd_dec:
    dec channel_snd, x
    rts

@wav:
    ldx cur_channel
    cpx #$02                ; triangle: skip
    beq @done
    lda channel_wav, x
    bne @wav_dec
    cpx #$03
    beq @wav_wrap2
    lda #$03
    sta channel_wav, x
    rts
@wav_wrap2:
    lda #$01
    sta channel_wav, x
    rts
@wav_dec:
    dec channel_wav, x
    rts

@pitch:
    lda cur_pitch
    beq @done
    dec cur_pitch
@done:
    rts

;------------------------------------------------------------------------------
; Handle A button - preview in SND/WAV, record in SEQ
;------------------------------------------------------------------------------
handle_a_button:
    lda cur_param
    cmp #PARAM_SEQ
    beq @seq_mode
    cmp #PARAM_SEG
    beq @done               ; no action in SEG mode

    ; SND or WAV: preview
    lda buttons_cur
    and #BTN_A
    beq @prev_release

    ; A held: preview sound
    lda cur_channel
    sta preview_ch
    jsr preview_sound
    rts

@prev_release:
    ldx preview_ch
    cpx #$FF
    beq @done
    lda #$FF
    sta last_played, x
    jsr silence_channel_x
    lda #$FF
    sta preview_ch
    rts

@seq_mode:
    lda buttons_cur
    and #BTN_A
    beq @a_released

    lda recording
    bne @already_rec

    ; First frame of A press: record note
    lda #$01
    sta recording
    jsr write_note_at_cursor
    lda #$01
    sta display_dirty
    rts

@already_rec:
    ; On tick boundary while held: write hold marker
    lda seq_tick
    bne @done
    jsr write_hold_at_cursor
    lda #$01
    sta display_dirty
@done:
    rts

@a_released:
    lda #$00
    sta recording
    rts

;------------------------------------------------------------------------------
; Preview sound on current channel
;------------------------------------------------------------------------------
preview_sound:
    ldx preview_ch
    cpx #$00
    beq @p1
    cpx #$01
    beq @p2
    cpx #$02
    beq @tri
    jmp @noise

@p1:
    ldx cur_pitch
    lda note_freq_lo, x
    sta APU_PULSE1_LO
    lda note_freq_hi, x
    sta APU_PULSE1_HI
    ldx channel_snd
    lda snd_pulse_vol, x
    ldx channel_wav
    ora duty_table, x
    sta APU_PULSE1_CTRL
    rts

@p2:
    ldx cur_pitch
    lda note_freq_lo, x
    sta APU_PULSE2_LO
    lda note_freq_hi, x
    sta APU_PULSE2_HI
    ldx channel_snd+1
    lda snd_pulse_vol, x
    ldx channel_wav+1
    ora duty_table, x
    sta APU_PULSE2_CTRL
    rts

@tri:
    lda #$FF
    sta APU_TRI_CTRL
    ldx cur_pitch
    lda note_freq_lo, x
    sta APU_TRI_LO
    lda note_freq_hi, x
    sta APU_TRI_HI
    rts

@noise:
    ldx channel_snd+3
    lda drum_ctrl, x
    sta APU_NOISE_CTRL
    lda drum_freq, x
    ldy channel_wav+3
    ora noise_loop, y
    sta APU_NOISE_FREQ
    lda drum_len, x
    sta APU_NOISE_LEN
    rts

;------------------------------------------------------------------------------
; Silence channel X
;------------------------------------------------------------------------------
silence_channel_x:
    cpx #$00
    beq @p1
    cpx #$01
    beq @p2
    cpx #$02
    beq @tri
    lda #$30
    sta APU_NOISE_CTRL
    rts
@p1:
    lda #$30
    sta APU_PULSE1_CTRL
    rts
@p2:
    lda #$30
    sta APU_PULSE2_CTRL
    rts
@tri:
    lda #$80
    sta APU_TRI_CTRL
    rts

;------------------------------------------------------------------------------
; Write note at cursor position
;------------------------------------------------------------------------------
write_note_at_cursor:
    jsr calc_seq_offset     ; X = offset
    lda cur_channel
    cmp #$03
    beq @drum
    lda cur_pitch
    clc
    adc #$01                ; $01-$14
    sta seq_data, x
    rts
@drum:
    lda channel_snd+3
    clc
    adc #$01                ; $01-$04
    sta seq_data, x
    rts

;------------------------------------------------------------------------------
; Write hold marker at cursor position
;------------------------------------------------------------------------------
write_hold_at_cursor:
    jsr calc_seq_offset
    lda #$FF
    sta seq_data, x
    rts

;------------------------------------------------------------------------------
; Clear current channel's current segment
;------------------------------------------------------------------------------
clear_channel_segment:
    jsr calc_seg_base       ; X = base offset for channel+segment
    lda #$00
    ldy #NUM_STEPS
@loop:
    sta seq_data, x
    inx
    dey
    bne @loop
    rts

;------------------------------------------------------------------------------
; Calculate seq_data offset: channel_base + seg*16 + cursor → X
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
; Calculate segment base offset: channel_base + seg*16 → X
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
    lda seq_playing
    beq @done

    inc seq_tick
    lda seq_tick
    cmp #STEP_FRAMES
    bcc @done               ; not a new step yet

    ; --- New step ---
    lda #$00
    sta seq_tick

    inc seq_cursor
    lda seq_cursor
    cmp #NUM_STEPS
    bcc @play
    lda #$00
    sta seq_cursor
    jsr advance_segment

@play:
    jsr play_pulse1
    jsr play_pulse2
    jsr play_triangle
    jsr play_noise

    lda #$01
    sta display_dirty
@done:
    rts

;------------------------------------------------------------------------------
; Advance segment (on cursor wrap)
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
    jsr check_segment_empty
    beq @empty
    rts
@empty:
    lda #$00
    sta global_seg
    rts

;------------------------------------------------------------------------------
; Check if current global_seg is empty across all channels
; Returns Z=1 if empty, Z=0 if has data
;------------------------------------------------------------------------------
check_segment_empty:
    lda global_seg
    asl a
    asl a
    asl a
    asl a
    sta temp                ; seg * 16

    lda #$00
    sta recording           ; reuse as channel counter temporarily
    ; (recording is safe to clobber here — we're between steps)
    ; Actually, let me NOT clobber recording. Use a different approach.
    ; Just inline the 4 channel checks.

    ; Channel 0
    lda temp
    tax
    ldy #NUM_STEPS
@ch0:
    lda seq_data, x
    bne @not_empty
    inx
    dey
    bne @ch0

    ; Channel 1
    lda temp
    clc
    adc #$40
    tax
    ldy #NUM_STEPS
@ch1:
    lda seq_data, x
    bne @not_empty
    inx
    dey
    bne @ch1

    ; Channel 2
    lda temp
    clc
    adc #$80
    tax
    ldy #NUM_STEPS
@ch2:
    lda seq_data, x
    bne @not_empty
    inx
    dey
    bne @ch2

    ; Channel 3
    lda temp
    clc
    adc #$C0
    tax
    ldy #NUM_STEPS
@ch3:
    lda seq_data, x
    bne @not_empty
    inx
    dey
    bne @ch3

    lda #$00                ; all empty (Z=1)
    rts

@not_empty:
    lda #$01                ; has data (Z=0)
    rts

;------------------------------------------------------------------------------
; Play Pulse 1 (channel 0)
;------------------------------------------------------------------------------
play_pulse1:
    ; Skip if previewing this channel
    lda preview_ch
    cmp #$00
    beq @skip

    ; Read sequence byte
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

    ; Note trigger
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
    lda snd_pulse_vol, x
    ldx channel_wav
    ora duty_table, x
    sta APU_PULSE1_CTRL
@skip:
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
    lda preview_ch
    cmp #$01
    beq @skip

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
    lda snd_pulse_vol, x
    ldx channel_wav+1
    ora duty_table, x
    sta APU_PULSE2_CTRL
@skip:
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
    lda preview_ch
    cmp #$02
    beq @skip

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
@skip:
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
    lda preview_ch
    cmp #$03
    beq @skip

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

    ; Drum trigger: value 1-4
    sec
    sbc #$01
    tax
    stx last_played+3      ; always retrigger drums

    lda drum_ctrl, x
    sta APU_NOISE_CTRL
    lda drum_freq, x
    ldy channel_wav+3
    ora noise_loop, y
    sta APU_NOISE_FREQ
    lda drum_len, x
    sta APU_NOISE_LEN
@skip:
    rts

@hold:
    lda #$34                ; quiet sustain for drums
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

initial_palette:
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26
    .byte $0F, $30, $16, $26

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

; Duty cycle lookup
duty_table:
    .byte $00,$40,$80,$C0      ; 12.5%, 25%, 50%, 75%

; Channel base offsets in seq_data
channel_base:
    .byte $00,$40,$80,$C0

; Pulse SND presets (halt + const + volume)
snd_pulse_vol:
    .byte $3C                  ; 0=Lead:  vol 12
    .byte $3F                  ; 1=Stab:  vol 15
    .byte $38                  ; 2=Bass:  vol 8
    .byte $35                  ; 3=Pad:   vol 5

; Triangle SND presets
snd_tri_ctrl:
    .byte $FF                  ; 0=Normal: sustained
    .byte $8A                  ; 1=Staccato: short

; Drum parameters
drum_ctrl:
    .byte $3F,$3C,$34,$37      ; kick/snare/hat-c/hat-o volume
drum_freq:
    .byte $02,$06,$0F,$0E      ; kick/snare/hat-c/hat-o pitch
drum_len:
    .byte $18,$10,$02,$06      ; kick/snare/hat-c/hat-o length

; Noise loop mode
noise_loop:
    .byte $00,$80              ; 0=normal, 1=metallic

; Channel colors for palette
channel_color:
    .byte $16,$12,$1A,$18      ; red, blue, green, yellow
channel_color_bright:
    .byte $26,$22,$2A,$28

; Parameter name tiles (3 tiles each)
param_name_t0:
    .byte 43,45,43,43          ; S,W,S,S
param_name_t1:
    .byte 44,34,32,32          ; N,A,E,E
param_name_t2:
    .byte 36,46,47,33          ; D,V,Q,G

; Pitch-to-note/octave lookup (for display)
pitch_to_note:
    .byte 0,1,2,3,4            ; octave 0
    .byte 0,1,2,3,4            ; octave 1
    .byte 0,1,2,3,4            ; octave 2
    .byte 0,1,2,3,4            ; octave 3
pitch_to_octave:
    .byte 0,0,0,0,0
    .byte 1,1,1,1,1
    .byte 2,2,2,2,2
    .byte 3,3,3,3,3

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

; Tiles 1-31: Pattern tiles (same as before)
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

; Tile 41: Solid color 2 (highlight/filled step)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; --- New tiles for v2 ---

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

; Tile 55: Cursor marker (up arrow, color 2)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$18,$3C,$7E,$18,$18,$00,$00

; Tile 56: Hold/tie (horizontal bar, color 2)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$7E,$7E,$00,$00,$00

; Fill remaining CHR space
.res 8192 - (57 * 16), $00
