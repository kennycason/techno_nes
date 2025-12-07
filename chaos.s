; NES CHAOS - Ultimate Psychedelic Visual & Audio Experience
; Features: 16+ visual modes, morphing fractals, hard techno music
; Pure 6502 assembly, NROM mapper
; Assemble with ca65, link with ld65

;------------------------------------------------------------------------------
; PPU Registers
;------------------------------------------------------------------------------
PPU_CTRL    = $2000
PPU_MASK    = $2001
PPU_STATUS  = $2002
PPU_SCROLL  = $2005
PPU_ADDR    = $2006
PPU_DATA    = $2007

;------------------------------------------------------------------------------
; APU Registers - For HARD TECHNO
;------------------------------------------------------------------------------
APU_PULSE1_CTRL  = $4000    ; Duty, envelope
APU_PULSE1_SWEEP = $4001    ; Sweep unit
APU_PULSE1_LO    = $4002    ; Timer low
APU_PULSE1_HI    = $4003    ; Length, timer high

APU_PULSE2_CTRL  = $4004
APU_PULSE2_SWEEP = $4005
APU_PULSE2_LO    = $4006
APU_PULSE2_HI    = $4007

APU_TRI_CTRL     = $4008    ; Triangle linear counter
APU_TRI_LO       = $400A    ; Triangle timer low
APU_TRI_HI       = $400B    ; Triangle length/timer high

APU_NOISE_CTRL   = $400C    ; Noise envelope
APU_NOISE_FREQ   = $400E    ; Noise period/mode
APU_NOISE_LEN    = $400F    ; Noise length

APU_DMC_CTRL     = $4010
APU_DMC_LOAD     = $4011
APU_STATUS       = $4015
APU_FRAME        = $4017

; Controller
JOY1             = $4016
JOY2             = $4017

; Button masks
BTN_RIGHT        = %00000001
BTN_LEFT         = %00000010
BTN_DOWN         = %00000100
BTN_UP           = %00001000
BTN_START        = %00010000
BTN_SELECT       = %00100000
BTN_B            = %01000000
BTN_A            = %10000000

DMC_FREQ    = $4010

;------------------------------------------------------------------------------
; Zero Page Variables
;------------------------------------------------------------------------------
.segment "ZEROPAGE"
rand_seed:      .res 2      ; 16-bit random seed
frame_count:    .res 2      ; 16-bit frame counter
temp:           .res 8      ; temporary variables
current_mode:   .res 1      ; current visual mode
mode_timer:     .res 1      ; frames until mode change
coeff_a:        .res 1      ; morphing coefficient A
coeff_b:        .res 1      ; morphing coefficient B  
coeff_c:        .res 1      ; morphing coefficient C
coeff_d:        .res 1      ; morphing coefficient D
buttons:        .res 1      ; current button state
buttons_prev:   .res 1      ; previous button state (for edge detection)
row:            .res 1      ; current row being drawn
col:            .res 1      ; current column
tile_val:       .res 1      ; computed tile value
phase:          .res 1      ; phase offset for animations
phase2:         .res 1      ; secondary phase

; Music variables
beat_count:     .res 1      ; current beat (0-15)
bar_count:      .res 1      ; current bar
beat_timer:     .res 1      ; frames until next beat
music_phase:    .res 1      ; music section phase
bass_note:      .res 1      ; current bass note index
kick_decay:     .res 1      ; kick drum decay counter
snare_decay:    .res 1      ; snare decay counter
hihat_timer:    .res 1      ; hi-hat timing
arp_index:      .res 1      ; arpeggio note index
lead_note:      .res 1      ; lead synth note
lead_decay:     .res 1      ; lead decay
intensity:      .res 1      ; current music intensity level

; Mode constants
NUM_MODES       = 16        ; number of visual modes (stable set)
MODE_DURATION   = 120       ; frames per mode (~2 seconds at 60fps)

; Music constants  
BEAT_FRAMES     = 8         ; ~130 BPM at 60fps (60/8 * 60 = 450... wait, 60fps / 8 frames = 7.5 beats/sec = 450 BPM... let me recalc)
                            ; For ~125 BPM: 60fps * 60sec / 125bpm = 28.8 frames per beat
                            ; Let's use 30 frames = 120 BPM
BEAT_FRAMES_FAST = 7        ; ~130 BPM for intensity

;------------------------------------------------------------------------------
; iNES Header
;------------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A        ; iNES magic number
    .byte 1                 ; 1 x 16KB PRG ROM
    .byte 1                 ; 1 x 8KB CHR ROM
    .byte $00               ; mapper 0 (NROM), horizontal mirroring
    .byte $00               ; mapper 0 continued
    .byte 0, 0, 0, 0, 0, 0, 0, 0  ; padding

;------------------------------------------------------------------------------
; Startup Code
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
    stx DMC_FREQ

    ; Wait for first vblank
@wait_vblank1:
    bit PPU_STATUS
    bpl @wait_vblank1

    ; Clear RAM
    lda #$00
    ldx #$00
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

    ; Wait for second vblank
@wait_vblank2:
    bit PPU_STATUS
    bpl @wait_vblank2

    ; Initialize variables
    lda #$A7
    sta rand_seed
    lda #$5D
    sta rand_seed+1
    
    lda #$00
    sta current_mode
    sta phase
    sta phase2
    sta coeff_a
    sta coeff_b
    sta frame_count
    sta frame_count+1
    sta beat_count
    sta bar_count
    sta bass_note
    sta arp_index
    sta music_phase
    
    lda #MODE_DURATION
    sta mode_timer
    
    lda #$40
    sta coeff_c
    lda #$20
    sta coeff_d
    
    lda #30                 ; ~120 BPM
    sta beat_timer
    
    lda #$02
    sta intensity

    ; Initialize APU - enable all channels
    lda #%00001111          ; Enable pulse1, pulse2, triangle, noise
    sta APU_STATUS
    ; Disable pulse sweep units
    lda #$08
    sta APU_PULSE1_SWEEP
    sta APU_PULSE2_SWEEP
    
    ; Load initial palette
    jsr load_palette
    
    ; Fill nametable with initial pattern
    jsr fill_pattern
    
    ; Fill attribute table
    jsr fill_attributes
    
    ; Enable rendering
    lda #%10000000
    sta PPU_CTRL
    lda #%00011110
    sta PPU_MASK

    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL

;------------------------------------------------------------------------------
; Main Loop - Simple
;------------------------------------------------------------------------------
main_loop:
    ; Read controller
    jsr read_controller
    
    ; Check for RIGHT press (new press only)
    lda buttons
    and #BTN_RIGHT
    beq @no_right
    lda buttons_prev
    and #BTN_RIGHT
    bne @no_right           ; Already held, skip
    ; RIGHT pressed - next mode
    inc current_mode
    lda current_mode
    cmp #NUM_MODES
    bcc @mode_ok
    lda #$00
    sta current_mode
@mode_ok:
    jmp @done_input
    
@no_right:
    ; Check for LEFT press
    lda buttons
    and #BTN_LEFT
    beq @no_left
    lda buttons_prev
    and #BTN_LEFT
    bne @no_left
    ; LEFT pressed - previous mode
    lda current_mode
    beq @wrap_mode
    dec current_mode
    jmp @done_input
@wrap_mode:
    lda #NUM_MODES-1
    sta current_mode
    
@no_left:
@done_input:
    ; Save button state for next frame
    lda buttons
    sta buttons_prev
    
    ; Update coefficients (simple version)
    inc coeff_a             ; Every frame
    
    lda coeff_a
    and #$03
    bne @skip_b
    inc coeff_b             ; Every 4 frames
@skip_b:
    
    ; Wait for NMI (simple)
    lda frame_count
@wait_nmi:
    cmp frame_count
    beq @wait_nmi

    jmp main_loop

;------------------------------------------------------------------------------
; NMI Handler - SIMPLIFIED, no lock
;------------------------------------------------------------------------------
NMI:
    pha
    txa
    pha
    tya
    pha

    ; Increment frame counter
    inc frame_count
    bne @no_wrap
    inc frame_count+1
@no_wrap:

    ; Increment phase for animations
    inc phase
    
    ; Mode timer disabled - using manual D-pad control
    ; (Mode switching now happens in main_loop via controller)
    
@same_mode:
    ; Update palette FIRST (during vblank)
    jsr update_palette
    
    ; Update pattern
    jsr update_pattern
    
    ; Update attributes
    jsr update_attributes

    ; Reset scroll
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL
    
    ; Audio update LAST (after PPU work is done)
    jsr update_kick_only
    jsr update_bass_only
    jsr update_synth_stab
    jsr update_arpeggio_simple

    pla
    tay
    pla
    tax
    pla
    rti

;------------------------------------------------------------------------------
; IRQ Handler
;------------------------------------------------------------------------------
IRQ:
    rti

;------------------------------------------------------------------------------
; Initialize Audio - Set up APU for TECHNO
;------------------------------------------------------------------------------
init_audio:
    ; Enable all channels
    lda #%00001111          ; Enable pulse1, pulse2, triangle, noise
    sta APU_STATUS
    
    ; Set up pulse 1 for lead stabs (50% duty, constant volume)
    lda #%10111111          ; Duty 50%, no envelope, vol 15
    sta APU_PULSE1_CTRL
    lda #%00001000          ; Disable sweep
    sta APU_PULSE1_SWEEP
    
    ; Set up pulse 2 for arpeggio (25% duty)
    lda #%01111111          ; Duty 25%, no envelope, vol 15
    sta APU_PULSE2_CTRL
    lda #%00001000
    sta APU_PULSE2_SWEEP
    
    ; Set up triangle for bass
    lda #%11111111          ; Linear counter max
    sta APU_TRI_CTRL
    
    ; Noise for drums
    lda #%00111111          ; No envelope, vol 15
    sta APU_NOISE_CTRL
    
    rts

;------------------------------------------------------------------------------
; EDM Kick + Hi-hat - clean, no static
;------------------------------------------------------------------------------
update_kick_only:
    lda frame_count
    and #$0F                ; Every 16 frames
    
    ; Frame 0: KICK
    bne @not_kick
    lda #%00111111          ; Vol 15
    sta APU_NOISE_CTRL
    lda #$01                ; Very low pitch = deep kick
    sta APU_NOISE_FREQ
    lda #$18
    sta APU_NOISE_LEN
    rts
    
@not_kick:
    ; Frame 1: Kick decay
    cmp #$01
    bne @not_decay1
    lda #%00111010          ; Vol 10
    sta APU_NOISE_CTRL
    rts
    
@not_decay1:
    ; Frame 2: Last decay then OFF
    cmp #$02
    bne @check_hihat
    lda #%00110101          ; Vol 5
    sta APU_NOISE_CTRL
    rts

@check_hihat:
    ; Frame 8: Hi-hat only (simple, stable)
    cmp #$08
    bne @silence
    lda #%00111000          ; Vol 8
    sta APU_NOISE_CTRL
    lda #$0F                ; High pitch
    sta APU_NOISE_FREQ
    lda #$08
    sta APU_NOISE_LEN
    rts
    
@silence:
    ; All other frames: SILENCE
    lda #%00110000          ; Vol 0
    sta APU_NOISE_CTRL
    rts

;------------------------------------------------------------------------------
; Bass - Triangle channel, 8-note pattern (original working version)
;------------------------------------------------------------------------------
update_bass_only:
    ; Play bass note - change every 32 frames
    lda frame_count
    and #$1F                ; Every 32 frames = new note
    bne @sustain
    
    ; New bass note! Get note from 8-note pattern
    lda frame_count
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a                   ; Divide by 32
    and #$07                ; 8 notes in pattern
    tax
    
    ; Set triangle frequency
    lda bass_notes_lo, x
    sta APU_TRI_LO
    lda bass_notes_hi, x
    sta APU_TRI_HI
    
    ; Enable triangle
    lda #%11111111          
    sta APU_TRI_CTRL
    rts
    
@sustain:
    ; Keep triangle playing
    lda #%11111111          
    sta APU_TRI_CTRL
    rts

;------------------------------------------------------------------------------
; Synth Stab - Pulse channel, plays chord stabs
;------------------------------------------------------------------------------
update_synth_stab:
    ; Stab every 32 frames, offset from kick
    lda frame_count
    and #$1F
    cmp #$04                ; Stab on frame 4 of each 32-frame cycle
    bne @stab_decay
    
    ; STAB! Play a note
    lda #%10111111          ; 50% duty, vol 15
    sta APU_PULSE1_CTRL
    
    ; Pick note based on which 32-frame cycle we're in
    lda frame_count
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a                   ; Divide by 32
    and #$03                ; 4 different notes
    tax
    lda stab_notes_lo, x
    sta APU_PULSE1_LO
    lda stab_notes_hi, x
    sta APU_PULSE1_HI
    rts

@stab_decay:
    ; Decay the stab
    lda frame_count
    and #$1F
    cmp #$04
    bcc @stab_silent        ; Before stab: silent
    cmp #$0C
    bcs @stab_silent        ; After frame 12: silent
    ; Frames 5-11: decay
    sec
    sbc #$04                ; 1-7
    eor #$07                ; Invert: 7-1
    asl a                   ; *2 for volume
    ora #%10110000          ; 50% duty + constant vol
    sta APU_PULSE1_CTRL
    rts

@stab_silent:
    lda #%10110000          ; Vol 0
    sta APU_PULSE1_CTRL
    rts

;------------------------------------------------------------------------------
; Fast Arpeggio - Pulse 2, runs constantly
;------------------------------------------------------------------------------
update_arpeggio_simple:
    ; Arpeggio every 4 frames for fast trance feel
    lda frame_count
    and #$03
    bne @arp_decay
    
    ; New arp note!
    lda frame_count
    lsr a
    lsr a                   ; Divide by 4
    and #$07                ; 8 notes in arp pattern
    tax
    
    ; Set note
    lda arp_notes_lo, x
    sta APU_PULSE2_LO
    lda arp_notes_hi, x
    sta APU_PULSE2_HI
    
    ; 25% duty for sharp arp sound
    lda #%01111001          ; 25% duty, vol 9
    sta APU_PULSE2_CTRL
    rts

@arp_decay:
    ; Quick decay between notes
    lda frame_count
    and #$03
    tax
    lda arp_vol_table, x
    sta APU_PULSE2_CTRL
    rts

;------------------------------------------------------------------------------
; SIMPLIFIED Update Music - For debugging
;------------------------------------------------------------------------------
update_music_simple:
    ; Simple beat timer - just count down
    dec beat_timer
    bne @no_beat
    
    ; Reset timer
    lda #8
    sta beat_timer
    
    ; Advance beat
    inc beat_count
    lda beat_count
    and #$0F
    sta beat_count
    
    ; KICK on 0, 4, 8, 12
    and #$03
    bne @no_kick
    
    ; Play kick - simple noise burst
    lda #%00111111
    sta APU_NOISE_CTRL
    lda #$03
    sta APU_NOISE_FREQ
    lda #%00001000
    sta APU_NOISE_LEN
    lda #$08
    sta kick_decay
    
@no_kick:
    ; BASS on 0, 4, 8, 12 - simple triangle
    lda beat_count
    and #$03
    bne @no_bass
    
    lda #%10011111          ; Linear counter
    sta APU_TRI_CTRL
    lda beat_count
    and #$04
    beq @bass_low
    ; Higher note
    lda #$A6                ; G2
    sta APU_TRI_LO
    lda #%00011010
    sta APU_TRI_HI
    jmp @no_bass
@bass_low:
    lda #$4D                ; E2
    sta APU_TRI_LO
    lda #%00011110
    sta APU_TRI_HI
    
@no_bass:
@no_beat:
    ; Decay kick
    lda kick_decay
    beq @decay_done
    dec kick_decay
    lda kick_decay
    lsr a
    ora #%00110000
    sta APU_NOISE_CTRL
@decay_done:
    rts

;------------------------------------------------------------------------------
; FULL Update Music - HARD TECHNO ENGINE
;------------------------------------------------------------------------------
update_music:
    ; Simple beat timer countdown
    dec beat_timer
    bne @no_beat
    
    ; Beat hit 0 - reset and play beat
    lda #8                  ; ~130 BPM
    sta beat_timer
    
    ; Advance beat count
    inc beat_count
    lda beat_count
    and #$0F                ; 16 beats per bar
    sta beat_count
    bne @same_bar
    
    ; New bar - advance patterns
    inc bar_count
    lda bar_count
    and #$1F                ; 32 bars then wrap
    sta bar_count
    
    ; Change intensity based on bar
    and #$07
    cmp #$06
    bcc @no_intensity_change
    inc intensity
    lda intensity
    cmp #$05
    bcc @no_intensity_change
    lda #$01
    sta intensity
@no_intensity_change:

@same_bar:
    ; Play beat elements (lead disabled for testing)
    jsr play_kick
    jsr play_snare
    jsr play_bass
    ; jsr play_lead
    
@no_beat:
    ; Update ongoing sounds (decay)
    jsr update_kick_decay
    jsr update_snare_decay
    ; jsr update_lead_decay  ; disabled with lead
    
    rts

;------------------------------------------------------------------------------
; Play Kick Drum - Pitch-sweeping noise
;------------------------------------------------------------------------------
play_kick:
    ; Kick on beats 0, 4, 8, 12 (4 on the floor)
    lda beat_count
    and #$03
    bne @no_kick
    
    ; PUNCHY KICK - start with high pitch, sweep down
    lda #%00111111          ; Constant volume, vol 15
    sta APU_NOISE_CTRL
    lda #$02                ; Low noise period = punchy
    sta APU_NOISE_FREQ
    lda #%00001000          ; Short length counter (we control decay)
    sta APU_NOISE_LEN
    
    lda #$10                ; Kick decay length
    sta kick_decay
    
@no_kick:
    rts

;------------------------------------------------------------------------------
; Update Kick Decay - Creates the pitch sweep
;------------------------------------------------------------------------------
update_kick_decay:
    lda kick_decay
    beq @done
    dec kick_decay
    
    ; Sweep pitch down
    lda #$10
    sec
    sbc kick_decay
    lsr a
    and #$0F
    sta APU_NOISE_FREQ
    
    ; Decay volume
    lda kick_decay
    lsr a
    ora #%00110000
    sta APU_NOISE_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Play Snare
;------------------------------------------------------------------------------
play_snare:
    ; Snare on beats 4, 12 (backbeat)
    lda beat_count
    cmp #$04
    beq @play
    cmp #$0C
    beq @play
    
    ; Extra snare hits at high intensity
    lda intensity
    cmp #$03
    bcc @no_snare
    lda beat_count
    cmp #$0A                ; Extra hit
    bne @no_snare
    
@play:
    ; Snare - noise burst (no metallic mode!)
    lda #%00111100          ; Constant volume, vol 12
    sta APU_NOISE_CTRL
    lda #$05                ; Medium-high noise pitch (no bit 7!)
    sta APU_NOISE_FREQ
    lda #%00011000          ; Shorter length
    sta APU_NOISE_LEN
    
    lda #$06                ; Shorter decay
    sta snare_decay
    
@no_snare:
    rts

;------------------------------------------------------------------------------
; Update Snare Decay
;------------------------------------------------------------------------------
update_snare_decay:
    lda snare_decay
    beq @done
    dec snare_decay
    
    ; Quick decay
    lda snare_decay
    ora #%00110000
    sta APU_NOISE_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Update Hi-Hat - 16th notes
;------------------------------------------------------------------------------
update_hihat:
    lda frame_count
    and #$01                ; Every 2 frames
    bne @done
    
    ; Alternate open/closed
    lda frame_count
    and #$06
    cmp #$06
    beq @open_hat
    
    ; Closed hi-hat - quiet tick
    lda #%00110010          ; Low volume
    sta APU_NOISE_CTRL
    lda #$0F                ; Highest pitch
    sta APU_NOISE_FREQ
    lda #%00001000          ; Short
    sta APU_NOISE_LEN
    jmp @done
    
@open_hat:
    ; Open hi-hat - longer
    lda #%00110100
    sta APU_NOISE_CTRL
    lda #$0D
    sta APU_NOISE_FREQ
    lda #%00010000
    sta APU_NOISE_LEN
    
@done:
    rts

;------------------------------------------------------------------------------
; Play Bass - Deep triangle wave
;------------------------------------------------------------------------------
play_bass:
    ; Bass pattern changes based on bar position
    lda beat_count
    and #$03
    bne @sustain
    
    ; New bass note on quarter notes
    lda bar_count
    and #$07
    tax
    lda bass_pattern, x
    sta bass_note
    
    ; Set triangle frequency
    tax
    lda note_table_lo, x
    sta APU_TRI_LO
    lda note_table_hi, x
    ora #%00011000          ; Shorter length counter (not infinite)
    sta APU_TRI_HI
    
    ; Enable triangle with shorter linear counter
    lda #%10011111          ; Linear counter = 31 (not infinite)
    sta APU_TRI_CTRL
    
@sustain:
    rts

;------------------------------------------------------------------------------
; Play Lead - Stab synth on pulse 1
;------------------------------------------------------------------------------
play_lead:
    ; Lead pattern - plays on certain beats based on intensity
    lda intensity
    cmp #$02
    bcc @no_lead            ; No lead at low intensity
    
    lda beat_count
    and #$03
    cmp #$02                ; Play on beat 2, 6, 10, 14
    bne @no_lead
    
    ; Get lead note from pattern
    lda bar_count
    lsr a
    and #$07
    tax
    lda lead_pattern, x
    tax
    
    ; Play on pulse 1
    lda note_table_lo, x
    sta APU_PULSE1_LO
    lda note_table_hi, x
    ora #%00001000          ; Short length counter
    sta APU_PULSE1_HI
    
    ; Stab envelope - constant volume so we can control decay
    lda #%10111111          ; 50% duty, constant vol, vol 15
    sta APU_PULSE1_CTRL
    
    lda #$0C
    sta lead_decay
    
@no_lead:
    rts

;------------------------------------------------------------------------------
; Update Lead Decay
;------------------------------------------------------------------------------
update_lead_decay:
    lda lead_decay
    beq @silence
    dec lead_decay
    beq @silence            ; Just hit zero, silence now
    
    ; Decay volume for stab effect
    lda lead_decay
    lsr a
    ora #%10110000          ; Keep duty cycle
    sta APU_PULSE1_CTRL
    rts
    
@silence:
    ; Silence pulse 1 when decay is done
    lda #%10110000          ; Vol 0
    sta APU_PULSE1_CTRL
    rts

;------------------------------------------------------------------------------
; Update Arpeggio - Fast notes on pulse 2
;------------------------------------------------------------------------------
update_arpeggio:
    ; Arpeggio runs every 4 frames
    lda frame_count
    and #$03
    bne @fade
    
    ; Skip at low intensity - silence instead
    lda intensity
    cmp #$02
    bcc @silence
    
    ; Cycle through arpeggio notes
    inc arp_index
    lda arp_index
    and #$07
    tax
    
    ; Get arpeggio note
    lda arp_pattern, x
    tax
    
    ; Play on pulse 2
    lda note_table_lo, x
    sta APU_PULSE2_LO
    lda note_table_hi, x
    ora #%00001000          ; Short length
    sta APU_PULSE2_HI
    
    ; Quick attack
    lda #%01111010          ; 25% duty, constant vol, vol 10
    sta APU_PULSE2_CTRL
    rts
    
@fade:
    ; Fade between arp notes
    lda frame_count
    and #$03
    tax
    lda arp_fade_vol, x
    sta APU_PULSE2_CTRL
    rts
    
@silence:
    lda #%01110000          ; Vol 0
    sta APU_PULSE2_CTRL
    rts

;------------------------------------------------------------------------------
; Read Controller 1
;------------------------------------------------------------------------------
read_controller:
    ; Strobe controller
    lda #$01
    sta JOY1
    lda #$00
    sta JOY1
    
    ; Read 8 buttons into buttons variable
    ldx #$08
    lda #$00
    sta buttons
@read_loop:
    lda JOY1
    lsr a                   ; Bit 0 -> carry
    rol buttons             ; Carry -> buttons
    dex
    bne @read_loop
    rts

;------------------------------------------------------------------------------
; Random Number Generator - with safety check
;------------------------------------------------------------------------------
random:
    ; Safety: if seed is 0, reset it (LFSR gets stuck at 0)
    lda rand_seed
    ora rand_seed+1
    bne @seed_ok
    ; Seed is 0! Reset it
    lda frame_count
    ora #$A7
    sta rand_seed
    lda frame_count+1
    ora #$5D
    sta rand_seed+1
@seed_ok:
    lda rand_seed+1
    lsr a
    ror rand_seed
    bcc @no_eor
    lda rand_seed+1
    eor #$B4
    sta rand_seed+1
    lda rand_seed
    eor #$00
    sta rand_seed
@no_eor:
    lda rand_seed
    rts

;------------------------------------------------------------------------------
; Sine Table Lookup
;------------------------------------------------------------------------------
get_sine:
    ; Save X (used as loop counter in callers)
    stx temp+7              ; Use last temp slot
    and #$1F
    tax
    lda sine_table, x
    ; Restore X
    ldx temp+7
    rts

;------------------------------------------------------------------------------
; Load Initial Palette
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
; Update Palette - Evolving colors synced to beat
;------------------------------------------------------------------------------
update_palette:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    ; Background color - flash on kick
    lda kick_decay
    cmp #$0C
    bcc @no_flash
    lda #$30                ; White flash on kick!
    jmp @set_bg
@no_flash:
    lda frame_count
    lsr a
    lsr a
    and #$0F
    cmp #$0D
    bcc @bg_ok
    lda #$01
@bg_ok:
@set_bg:
    sta PPU_DATA
    
    ; Color palette cycling with mode
    ldx #$00
@pal_loop:
    ; Color 1
    lda frame_count
    clc
    adc current_mode
    adc mode_hue_offsets, x
    and #$0C
    ora #$11
    sta PPU_DATA
    
    ; Color 2 - beat reactive
    lda frame_count
    clc
    adc beat_count
    adc mode_hue_offsets, x
    and #$0C
    ora #$21
    sta PPU_DATA
    
    ; Color 3
    lda phase
    clc
    adc mode_hue_offsets, x
    and #$0C
    ora #$31
    sta PPU_DATA
    
    ; Next palette background
    lda phase2
    clc
    adc pal_offsets, x
    and #$0F
    cmp #$0D
    bcc @pbg_ok
    lda #$00
@pbg_ok:
    sta PPU_DATA
    
    inx
    cpx #$07                ; 7 more palettes
    bne @pal_loop
    
    ; Final 3 colors
    lda #$16
    sta PPU_DATA
    lda #$26
    sta PPU_DATA
    lda #$36
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Fill Pattern - Initial nametable
;------------------------------------------------------------------------------
fill_pattern:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR

    lda #$00
    sta row
@row_loop:
    lda #$00
    sta col
@col_loop:
    lda row
    eor col
    ora #$01
    sta PPU_DATA
    
    inc col
    lda col
    cmp #$20
    bne @col_loop
    
    inc row
    lda row
    cmp #$1E
    bne @row_loop
    rts

;------------------------------------------------------------------------------
; Fill Attributes
;------------------------------------------------------------------------------
fill_attributes:
    bit PPU_STATUS
    lda #$23
    sta PPU_ADDR
    lda #$C0
    sta PPU_ADDR
    
    ldx #$00
@loop:
    txa
    eor phase
    sta PPU_DATA
    inx
    cpx #$40
    bne @loop
    rts

;------------------------------------------------------------------------------
; Update Pattern - Dispatch to current mode
;------------------------------------------------------------------------------
update_pattern:
    lda current_mode
    asl a
    tax
    lda mode_table, x
    sta temp
    lda mode_table+1, x
    sta temp+1
    jmp (temp)

;------------------------------------------------------------------------------
; Mode 0: XOR Fractal
;------------------------------------------------------------------------------
mode_xor_fractal:
    ldx #$30                ; Reduced to prevent NMI overrun
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    and #$EF
    sta PPU_ADDR
    sta temp
    
    and #$1F
    sta temp+1
    lda temp
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    eor temp+1
    clc
    adc phase
    eor coeff_a
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 1: Plasma
;------------------------------------------------------------------------------
mode_plasma:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    txa
    clc
    adc phase
    sta PPU_ADDR
    
    txa
    and #$1F
    clc
    adc phase
    jsr get_sine
    sta temp
    
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc phase
    adc coeff_b
    jsr get_sine
    clc
    adc temp
    lsr a
    lsr a
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 2: Diagonal Waves
;------------------------------------------------------------------------------
mode_diagonal:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    and #$1F
    sta temp+1
    lda temp
    lsr a
    lsr a
    lsr a
    clc
    adc temp+1
    clc
    adc phase
    adc coeff_a
    and #$1F
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 3: Interference
;------------------------------------------------------------------------------
mode_interference:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    and #$1F
    clc
    adc phase
    jsr get_sine
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    clc
    adc phase
    adc coeff_b
    jsr get_sine
    eor temp+1
    lsr a
    lsr a
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 4: Sierpinski
;------------------------------------------------------------------------------
mode_sierpinski:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    and #$1F
    sta temp+1
    lda temp
    lsr a
    lsr a
    lsr a
    clc
    adc phase
    and temp+1
    clc
    adc coeff_a
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 5: Ripple - Expanding circles
;------------------------------------------------------------------------------
mode_ripple:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    and #$1F
    sec
    sbc #$10
    bpl @x_pos
    eor #$FF
    clc
    adc #$01
@x_pos:
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    sec
    sbc #$0F
    bpl @y_pos
    eor #$FF
    clc
    adc #$01
@y_pos:
    clc
    adc temp+1
    clc
    adc phase
    adc phase
    adc coeff_a
    and #$1F
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 6: Morphing Grid
;------------------------------------------------------------------------------
mode_grid:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    and #$1F
    clc
    adc coeff_a
    jsr get_sine
    lsr a
    lsr a
    lsr a
    lsr a
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    clc
    adc coeff_b
    jsr get_sine
    lsr a
    lsr a
    lsr a
    lsr a
    eor temp+1
    clc
    adc phase
    and #$0F
    ora #$10
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 7: Chaos Rain
;------------------------------------------------------------------------------
mode_chaos:
    ldx #$30
@loop:
    bit PPU_STATUS
    jsr random
    and #$03
    ora #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    
    jsr random
    eor coeff_a
    clc
    adc coeff_b
    eor phase
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 8: Spiral
;------------------------------------------------------------------------------
mode_spiral:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Spiral: angle + radius
    and #$1F
    sec
    sbc #$10
    sta temp+1              ; x offset
    
    lda temp
    lsr a
    lsr a
    lsr a
    sec
    sbc #$0F
    sta temp+2              ; y offset
    
    ; Approximate angle: y + x (simplified)
    clc
    adc temp+1
    clc
    adc phase
    adc phase
    and #$1F
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 9: Tunnel / Zoom
;------------------------------------------------------------------------------
mode_tunnel:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Distance from center
    and #$1F
    sec
    sbc #$10
    bpl @tx_pos
    eor #$FF
    adc #$01
@tx_pos:
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    sec
    sbc #$0F
    bpl @ty_pos
    eor #$FF
    adc #$01
@ty_pos:
    ; Max of |x| and |y| for square tunnel
    cmp temp+1
    bcs @use_y
    lda temp+1
@use_y:
    ; Add phase for zoom effect
    clc
    adc phase
    adc phase
    adc phase               ; Fast zoom
    and #$1F
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 10: Kaleidoscope
;------------------------------------------------------------------------------
mode_kaleidoscope:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Mirror coordinates
    and #$0F                ; Half width
    sta temp+1
    lda temp
    and #$10                ; Which half?
    beq @no_mirror_x
    lda #$0F
    sec
    sbc temp+1
    sta temp+1
@no_mirror_x:
    
    lda temp
    lsr a
    lsr a
    lsr a
    and #$07                ; Half height
    sta temp+2
    lda temp
    and #$40
    beq @no_mirror_y
    lda #$07
    sec
    sbc temp+2
    sta temp+2
@no_mirror_y:
    
    ; Combine mirrored coords
    lda temp+1
    eor temp+2
    clc
    adc phase
    eor coeff_a
    and #$1F
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 11: Matrix Rain
;------------------------------------------------------------------------------
mode_matrix:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    
    ; Column-based update
    jsr random
    and #$1F                ; Random column
    sta temp
    jsr random
    and #$E0                ; Random row chunk
    ora temp
    sta PPU_ADDR
    
    ; Falling pattern
    lda temp
    clc
    adc phase
    adc phase
    jsr random
    and #$1F
    ora #$20                ; ASCII-ish range
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 12: Starfield
;------------------------------------------------------------------------------
mode_starfield:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Stars expand from center
    and #$1F
    sec
    sbc #$10
    sta temp+1
    
    ; Scale by phase for expansion
    lda phase
    lsr a
    lsr a
    sta temp+2
    
    lda temp+1
    clc
    adc temp+2
    and #$1F
    ora temp
    and #$EF
    
    ; Twinkle with random
    jsr random
    and #$07
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 13: Cellular Automata
;------------------------------------------------------------------------------
mode_cellular:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Rule 30-ish pattern
    and #$1F
    eor phase
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    eor phase2
    and temp+1
    eor coeff_a
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 14: Lissajous
;------------------------------------------------------------------------------
mode_lissajous:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    
    ; Parametric curves
    txa
    clc
    adc phase
    jsr get_sine
    lsr a
    lsr a
    lsr a
    sta temp                ; x = sin(t + phase)
    
    txa
    asl a                   ; Different frequency
    clc
    adc phase
    adc coeff_a
    jsr get_sine
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    asl a
    asl a
    asl a
    asl a
    asl a
    ora temp
    sta PPU_ADDR
    
    ; Tile based on position
    txa
    and #$0F
    ora #$10
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 15: Warp / Vortex
;------------------------------------------------------------------------------
mode_vortex:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Spiral distortion
    and #$1F
    sec
    sbc #$10
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    sec
    sbc #$0F
    sta temp+2
    
    ; Angle approximation + distance
    lda temp+1
    clc
    adc temp+2
    clc
    adc phase
    sta temp+3
    
    ; Radial component
    lda temp+1
    bpl @vx_pos
    eor #$FF
@vx_pos:
    clc
    adc temp+2
    bpl @vy_pos
    eor #$FF
@vy_pos:
    clc
    adc temp+3
    adc coeff_b
    and #$1F
    ora #$01
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 16: Pulse - Concentric rings radiating from center
;------------------------------------------------------------------------------
mode_pulse:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Get x,y from address
    and #$1F                ; x = 0-31
    sec
    sbc #$10                ; x offset from center (-16 to 15)
    bpl @px_pos
    eor #$FF
    adc #$01
@px_pos:
    sta temp+1              ; |x|
    
    lda temp
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a                   ; y = 0-7
    asl a
    asl a                   ; scale up
    sec
    sbc #$0F                ; y offset from center
    bpl @py_pos
    eor #$FF
    adc #$01
@py_pos:
    ; temp+1 = |x|, A = |y|
    ; Manhattan distance = |x| + |y|
    clc
    adc temp+1
    
    ; Add phase for pulsing animation
    clc
    adc phase
    adc phase
    adc phase               ; Triple phase = fast pulse
    
    ; Create ring pattern
    and #$0F                ; 16 levels
    ora #$01                ; Avoid tile 0
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 17: Diamond Wave - Diagonal stripes that create diamond patterns
;------------------------------------------------------------------------------
mode_diamond:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Get x and y components
    and #$1F                ; x = 0-31
    sta temp+1
    
    lda temp
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a                   ; y = 0-7
    asl a
    asl a                   ; Scale up y
    sta temp+2
    
    ; Diamond pattern: (x + y) XOR (x - y)
    lda temp+1
    clc
    adc temp+2              ; x + y
    clc
    adc phase               ; Animate
    sta temp+3
    
    lda temp+1
    sec
    sbc temp+2              ; x - y (may go negative, that's ok)
    clc  
    adc coeff_b             ; Add variation
    eor temp+3              ; XOR creates diamond interference
    
    and #$1F                ; Clamp to valid tiles
    ora #$01                ; Avoid tile 0
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; Mode 18: Rings - Expanding circles from a bouncing center
;------------------------------------------------------------------------------
mode_rings:
    ldx #$30
@loop:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    jsr random
    sta PPU_ADDR
    sta temp
    
    ; Get x coordinate (0-31)
    and #$1F
    sta temp+1
    
    ; Get y coordinate (0-29, scaled)
    lda temp
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a                   ; 0-7
    asl a
    asl a                   ; 0-28
    sta temp+2
    
    ; Calculate bouncing center X (using sine of phase)
    lda phase
    and #$1F
    tax
    lda sine_table, x       ; 0-31
    lsr a                   ; 0-15
    clc
    adc #$08                ; 8-23 (centered on screen)
    sta temp+3              ; center_x
    
    ; Calculate bouncing center Y (using sine of phase + offset)
    lda phase
    clc
    adc #$08                ; Offset so X and Y are out of phase
    and #$1F
    tax
    lda sine_table, x
    lsr a
    lsr a                   ; 0-7
    clc
    adc #$08                ; 8-15 (centered vertically)
    sta temp+4              ; center_y
    
    ; Distance from center: |x - cx| + |y - cy| (Manhattan)
    lda temp+1              ; x
    sec
    sbc temp+3              ; x - center_x
    bpl @rx_pos
    eor #$FF
    adc #$01
@rx_pos:
    sta temp+5              ; |x - cx|
    
    lda temp+2              ; y
    sec
    sbc temp+4              ; y - center_y
    bpl @ry_pos
    eor #$FF
    adc #$01
@ry_pos:
    clc
    adc temp+5              ; |x - cx| + |y - cy| = distance
    
    ; Subtract phase to make rings expand outward
    sec
    sbc phase
    sbc phase               ; Double speed expansion
    
    ; Create ring pattern
    and #$0F                ; 16 ring levels
    ora #$01                ; Avoid tile 0
    sta PPU_DATA
    
    dex
    bne @loop
    rts

;------------------------------------------------------------------------------
; DEBUG: Show current mode number in top-left (tiles 0-1)
;------------------------------------------------------------------------------
debug_show_mode:
    bit PPU_STATUS
    ; Write to top-left corner ($2000)
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    
    ; Write mode number as tile (add $10 to make it visible)
    lda current_mode
    clc
    adc #$10                ; Offset so 0 isn't transparent
    sta PPU_DATA
    
    ; Also write mode_timer in next position for debugging
    lda mode_timer
    lsr a
    lsr a
    lsr a                   ; Divide by 8 for smaller range
    clc
    adc #$10
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Update Attributes
;------------------------------------------------------------------------------
update_attributes:
    bit PPU_STATUS
    lda #$23
    sta PPU_ADDR
    lda #$C0
    sta PPU_ADDR
    
    ldx #$00
@loop:
    txa
    clc
    adc phase
    adc current_mode
    adc beat_count          ; Sync to beat!
    eor coeff_a
    sta PPU_DATA
    inx
    cpx #$40
    bne @loop
    rts

;------------------------------------------------------------------------------
; Data Tables
;------------------------------------------------------------------------------
.segment "RODATA"

; Mode jump table - 16 modes
mode_table:
    .word mode_xor_fractal      ; 0
    .word mode_plasma           ; 1
    .word mode_diagonal         ; 2
    .word mode_interference     ; 3
    .word mode_sierpinski       ; 4
    .word mode_ripple           ; 5
    .word mode_grid             ; 6
    .word mode_chaos            ; 7
    .word mode_spiral           ; 8
    .word mode_tunnel           ; 9
    .word mode_kaleidoscope     ; 10
    .word mode_matrix           ; 11
    .word mode_starfield        ; 12
    .word mode_cellular         ; 13
    .word mode_lissajous        ; 14
    .word mode_vortex           ; 15
    .word mode_pulse            ; 16
    .word mode_diamond          ; 17
    .word mode_rings            ; 18 - NEW! Bouncing expanding rings

; Mode hue offsets
mode_hue_offsets:
    .byte $00, $02, $04, $06, $08, $0A, $0C, $0E
    .byte $01                   ; mode 16
    .byte $01, $03, $05, $07, $09, $0B, $0D, $0F

; Palette offsets
pal_offsets:
    .byte $00, $04, $08, $0C, $10, $14, $18, $1C

; Sine table - 32 entries
sine_table:
    .byte 128, 152, 176, 198, 217, 233, 245, 252
    .byte 255, 252, 245, 233, 217, 198, 176, 152
    .byte 128, 103,  79,  57,  38,  22,  10,   3
    .byte   0,   3,  10,  22,  38,  57,  79, 103

; Initial palette
initial_palette:
    .byte $0F, $11, $21, $31
    .byte $0F, $14, $24, $34
    .byte $0F, $17, $27, $37
    .byte $0F, $1A, $2A, $3A
    .byte $0F, $12, $22, $32
    .byte $0F, $15, $25, $35
    .byte $0F, $18, $28, $38
    .byte $0F, $1B, $2B, $3B

; Note frequency table (lo byte) - C2 to B5
; NTSC NES APU timer values
note_table_lo:
    .byte $F1  ; 0  C2
    .byte $7F  ; 1  C#2
    .byte $13  ; 2  D2
    .byte $AD  ; 3  D#2
    .byte $4D  ; 4  E2
    .byte $F3  ; 5  F2
    .byte $9D  ; 6  F#2
    .byte $4C  ; 7  G2
    .byte $00  ; 8  G#2
    .byte $B8  ; 9  A2
    .byte $74  ; 10 A#2
    .byte $34  ; 11 B2
    .byte $F8  ; 12 C3
    .byte $BF  ; 13 C#3
    .byte $89  ; 14 D3
    .byte $56  ; 15 D#3
    .byte $26  ; 16 E3
    .byte $F9  ; 17 F3
    .byte $CE  ; 18 F#3
    .byte $A6  ; 19 G3
    .byte $7F  ; 20 G#3
    .byte $5C  ; 21 A3
    .byte $3A  ; 22 A#3
    .byte $1A  ; 23 B3
    .byte $FB  ; 24 C4
    .byte $DF  ; 25 C#4
    .byte $C4  ; 26 D4
    .byte $AB  ; 27 D#4
    .byte $93  ; 28 E4
    .byte $7C  ; 29 F4
    .byte $67  ; 30 F#4
    .byte $52  ; 31 G4
    .byte $3F  ; 32 G#4
    .byte $2D  ; 33 A4
    .byte $1C  ; 34 A#4
    .byte $0C  ; 35 B4
    .byte $FD  ; 36 C5
    .byte $EF  ; 37 C#5
    .byte $E1  ; 38 D5
    .byte $D5  ; 39 D#5
    .byte $C9  ; 40 E5
    .byte $BD  ; 41 F5
    .byte $B3  ; 42 F#5
    .byte $A9  ; 43 G5
    .byte $9F  ; 44 G#5
    .byte $96  ; 45 A5
    .byte $8E  ; 46 A#5
    .byte $86  ; 47 B5

; Note frequency table (hi byte)
note_table_hi:
    .byte $07  ; C2
    .byte $07  ; C#2
    .byte $07  ; D2
    .byte $06  ; D#2
    .byte $06  ; E2
    .byte $05  ; F2
    .byte $05  ; F#2
    .byte $05  ; G2
    .byte $05  ; G#2
    .byte $04  ; A2
    .byte $04  ; A#2
    .byte $04  ; B2
    .byte $03  ; C3
    .byte $03  ; C#3
    .byte $03  ; D3
    .byte $03  ; D#3
    .byte $03  ; E3
    .byte $02  ; F3
    .byte $02  ; F#3
    .byte $02  ; G3
    .byte $02  ; G#3
    .byte $02  ; A3
    .byte $02  ; A#3
    .byte $02  ; B3
    .byte $01  ; C4
    .byte $01  ; C#4
    .byte $01  ; D4
    .byte $01  ; D#4
    .byte $01  ; E4
    .byte $01  ; F4
    .byte $01  ; F#4
    .byte $01  ; G4
    .byte $01  ; G#4
    .byte $01  ; A4
    .byte $01  ; A#4
    .byte $01  ; B4
    .byte $00  ; C5
    .byte $00  ; C#5
    .byte $00  ; D5
    .byte $00  ; D#5
    .byte $00  ; E5
    .byte $00  ; F5
    .byte $00  ; F#5
    .byte $00  ; G5
    .byte $00  ; G#5
    .byte $00  ; A5
    .byte $00  ; A#5
    .byte $00  ; B5

; Bass pattern (note indices) - E minor
bass_pattern:
    .byte 4, 4, 4, 4         ; E2 E2 E2 E2
    .byte 4, 7, 4, 7         ; E2 G2 E2 G2

; Lead pattern (note indices) - high stabs
lead_pattern:
    .byte 28, 31, 35, 31     ; E4 G4 B4 G4
    .byte 28, 35, 31, 28     ; E4 B4 G4 E4

; Arpeggio pattern (note indices)
arp_pattern:
    .byte 28, 31, 35, 40     ; E4 G4 B4 E5
    .byte 35, 31, 28, 35     ; B4 G4 E4 B4

; Arpeggio fade volumes (for smooth decay between notes)
arp_fade_vol:
    .byte %01111010          ; Frame 0: vol 10 (just played)
    .byte %01110111          ; Frame 1: vol 7
    .byte %01110100          ; Frame 2: vol 4
    .byte %01110010          ; Frame 3: vol 2

; Kick decay table - frames 1-3 (fast decay, no static)
kick_decay_table:
    .byte %00111111          ; (unused - frame 0 handled separately)  
    .byte %00111011          ; Frame 1: vol 11
    .byte %00110111          ; Frame 2: vol 7
    .byte %00110011          ; Frame 3: vol 3 (then silent)

; Bass note frequencies - 8 note pattern (more melodic!)
bass_notes_lo:
    .byte $9D               ; E2 - root
    .byte $4C               ; G2 - minor 3rd
    .byte $9D               ; E2 - root
    .byte $00               ; A2 - 4th
    .byte $9D               ; E2 - root
    .byte $F8               ; B2 - 5th
    .byte $4C               ; G2 - minor 3rd
    .byte $00               ; A2 - 4th
bass_notes_hi:
    .byte $05               ; E2
    .byte $05               ; G2
    .byte $05               ; E2
    .byte $05               ; A2
    .byte $05               ; E2
    .byte $04               ; B2
    .byte $05               ; G2
    .byte $05               ; A2

; Synth stab notes (higher octave) - E minor chord tones
stab_notes_lo:
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $FD               ; B3
    .byte $A9               ; E4
stab_notes_hi:
    .byte $00               ; E4
    .byte $01               ; G4
    .byte $00               ; B3
    .byte $00               ; E4

; Arpeggio notes - fast E minor arp (higher octave for sparkle)
arp_notes_lo:
    .byte $54               ; E5
    .byte $A9               ; G5  
    .byte $17               ; B5
    .byte $A9               ; G5
    .byte $54               ; E5
    .byte $17               ; B5
    .byte $54               ; E5
    .byte $FC               ; D5
arp_notes_hi:
    .byte $00               ; E5
    .byte $00               ; G5
    .byte $00               ; B5
    .byte $00               ; G5
    .byte $00               ; E5
    .byte $00               ; B5
    .byte $00               ; E5
    .byte $00               ; D5

; Arp volume decay (frames 0-3)
arp_vol_table:
    .byte %01111001          ; Frame 0: vol 9 (hit)
    .byte %01110110          ; Frame 1: vol 6
    .byte %01110011          ; Frame 2: vol 3
    .byte %01110001          ; Frame 3: vol 1

;------------------------------------------------------------------------------
; Vectors
;------------------------------------------------------------------------------
.segment "VECTORS"
    .word NMI
    .word RESET
    .word IRQ

;------------------------------------------------------------------------------
; CHR ROM - Patterns for all modes
;------------------------------------------------------------------------------
.segment "CHARS"

; Tile 0: Empty
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tile 1: Solid
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; Tiles 2-15: Gradient patterns
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $88,$22,$88,$22,$88,$22,$88,$22

.byte $88,$22,$88,$22,$88,$22,$88,$22
.byte $22,$88,$22,$88,$22,$88,$22,$88

.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA

.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA

.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
.byte $55,$55,$55,$55,$55,$55,$55,$55

.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00
.byte $00,$FF,$00,$FF,$00,$FF,$00,$FF

.byte $01,$02,$04,$08,$10,$20,$40,$80
.byte $80,$40,$20,$10,$08,$04,$02,$01

.byte $80,$40,$20,$10,$08,$04,$02,$01
.byte $01,$02,$04,$08,$10,$20,$40,$80

.byte $18,$18,$18,$FF,$FF,$18,$18,$18
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $18,$3C,$7E,$FF,$FF,$7E,$3C,$18
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $3C,$7E,$FF,$FF,$FF,$FF,$7E,$3C
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 16-31: Geometric patterns
.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA

.byte $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F
.byte $0F,$0F,$0F,$0F,$F0,$F0,$F0,$F0

.byte $FF,$81,$81,$81,$81,$81,$81,$FF
.byte $00,$7E,$7E,$7E,$7E,$7E,$7E,$00

.byte $00,$00,$00,$18,$18,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $00,$24,$00,$81,$81,$00,$24,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $AA,$00,$AA,$00,$AA,$00,$AA,$00
.byte $00,$55,$00,$55,$00,$55,$00,$55

.byte $38,$7C,$EE,$C6,$C6,$EE,$7C,$38
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $CC,$CC,$CC,$CC,$33,$33,$33,$33
.byte $33,$33,$33,$33,$CC,$CC,$CC,$CC

.byte $00,$01,$03,$07,$0F,$1F,$3F,$7F
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $00,$80,$C0,$E0,$F0,$F8,$FC,$FE
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $00,$00,$00,$00,$00,$00,$00,$FF
.byte $00,$00,$00,$00,$00,$00,$FF,$FF

.byte $FF,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$00,$00,$00,$00,$00,$00

.byte $7F,$3F,$1F,$0F,$07,$03,$01,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $FE,$FC,$F8,$F0,$E0,$C0,$80,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

.byte $FF,$FE,$FC,$F8,$F0,$E0,$C0,$80
.byte $00,$01,$03,$07,$0F,$1F,$3F,$7F

.byte $FF,$7F,$3F,$1F,$0F,$07,$03,$01
.byte $00,$80,$C0,$E0,$F0,$F8,$FC,$FE

; Tiles 32+: Procedural patterns
.repeat 224, i
    .byte ((i * 7 + 13) ^ (i >> 1)) & $FF
    .byte ((i * 11 + 29) ^ (i >> 2)) & $FF
    .byte ((i * 17 + 41) ^ (i >> 1)) & $FF
    .byte ((i * 23 + 53) ^ (i >> 2)) & $FF
    .byte ((i * 31 + 67) ^ (i >> 1)) & $FF
    .byte ((i * 37 + 79) ^ (i >> 2)) & $FF
    .byte ((i * 43 + 97) ^ (i >> 1)) & $FF
    .byte ((i * 47 + 103) ^ (i >> 2)) & $FF
    .byte ((i * 53 + 107) ^ (i >> 3)) & $FF
    .byte ((i * 59 + 113) ^ (i >> 3)) & $FF
    .byte ((i * 61 + 127) ^ (i >> 3)) & $FF
    .byte ((i * 67 + 131) ^ (i >> 3)) & $FF
    .byte ((i * 71 + 137) ^ (i >> 3)) & $FF
    .byte ((i * 73 + 149) ^ (i >> 3)) & $FF
    .byte ((i * 79 + 151) ^ (i >> 3)) & $FF
    .byte ((i * 83 + 157) ^ (i >> 3)) & $FF
.endrepeat

