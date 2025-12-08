; NES TECHNO - Pure evolving techno music
; Black screen, focus on audio only
; Assemble with ca65, link with ld65

;------------------------------------------------------------------------------
; NES Hardware Registers
;------------------------------------------------------------------------------
PPU_CTRL         = $2000
PPU_MASK         = $2001
PPU_STATUS       = $2002

; APU Registers
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

;------------------------------------------------------------------------------
; Zero Page Variables
;------------------------------------------------------------------------------
.segment "ZEROPAGE"
frame_count:    .res 2      ; 16-bit frame counter
beat_count:     .res 1      ; Beat counter (for pattern changes)
bar_count:      .res 1      ; Bar counter (for song structure)
song_section:   .res 1      ; Current section (intro, build, drop, etc)
bass_note:      .res 1      ; Current bass note index
bass_pattern:   .res 1      ; Which bass pattern (0 or 1)
arp_note:       .res 1      ; Current arp note index
arp_pattern:    .res 1      ; Which arp pattern
intensity:      .res 1      ; Builds up over time
hat_pattern:    .res 1      ; Hi-hat pattern variation
lead_duty:      .res 1      ; Lead duty cycle for filter sweep
acid_note:      .res 1      ; Current acid bass note
acid_slide:     .res 1      ; Slide target
drop_timer:     .res 1      ; For drop impact effect
groove_var:     .res 1      ; Groove variation

;------------------------------------------------------------------------------
; iNES Header
;------------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A        ; iNES header
    .byte $01               ; 1x 16KB PRG ROM
    .byte $01               ; 1x 8KB CHR ROM  
    .byte $00               ; Mapper 0, horizontal mirroring
    .byte $00               ; Mapper 0

;------------------------------------------------------------------------------
; Main Code
;------------------------------------------------------------------------------
.segment "CODE"

RESET:
    sei                     ; Disable IRQs
    cld                     ; Disable decimal mode
    ldx #$40
    stx APU_FRAME           ; Disable APU frame IRQ
    ldx #$FF
    txs                     ; Set up stack
    inx                     ; X = 0
    stx PPU_CTRL            ; Disable NMI
    stx PPU_MASK            ; Disable rendering
    stx $4010               ; Disable DMC IRQs

    ; Wait for first vblank
@vblank1:
    bit PPU_STATUS
    bpl @vblank1

    ; Clear RAM
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

    ; Wait for second vblank
@vblank2:
    bit PPU_STATUS
    bpl @vblank2

    ; Initialize variables
    lda #$00
    sta frame_count
    sta frame_count+1
    sta beat_count
    sta bar_count
    sta song_section
    sta bass_note
    sta arp_note
    sta intensity

    ; Initialize APU - enable all channels
    lda #%00001111          ; Enable pulse1, pulse2, triangle, noise
    sta APU_STATUS
    
    ; Disable sweep on both pulse channels
    lda #$08
    sta APU_PULSE1_SWEEP
    sta APU_PULSE2_SWEEP

    ; Enable NMI
    lda #%10000000
    sta PPU_CTRL
    
    ; Keep screen black (no rendering)
    lda #$00
    sta PPU_MASK

;------------------------------------------------------------------------------
; Main Loop - does nothing, all work in NMI
;------------------------------------------------------------------------------
main_loop:
    jmp main_loop

;------------------------------------------------------------------------------
; NMI Handler - Music engine runs here
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

    ; Update music
    jsr update_music

    pla
    tay
    pla
    tax
    pla
    rti

;------------------------------------------------------------------------------
; Main Music Update - called every frame (60fps)
;------------------------------------------------------------------------------
update_music:
    ; Update beat timing (120 BPM = beat every 30 frames)
    lda frame_count
    and #$1F                ; Every 32 frames (~120 BPM)
    bne @not_beat
    
    ; New beat!
    inc beat_count
    lda beat_count
    and #$0F                ; Every 16 beats = 1 bar
    bne @not_bar
    
    ; New bar!
    inc bar_count
    
    ; Update song section based on bar count
    jsr update_song_section
    
@not_bar:
@not_beat:

    ; Check song section for different modes
    lda song_section
    cmp #$01                ; Section 1 = acid mode
    beq @acid_mode
    cmp #$02                ; Section 2 = breakdown
    beq @breakdown_mode
    cmp #$03                ; Section 3 = DROP!
    beq @drop_mode
    cmp #$05                ; Section 5 = buildup/riser
    beq @buildup_mode
    cmp #$06                ; Section 6 = minimal
    beq @minimal_mode
    
    ; Normal mode (sections 0, 4) - all elements
    ; Check for fill beat
    lda bar_count
    and #$03
    cmp #$03
    bne @normal_kick
    lda beat_count
    and #$0F
    cmp #$0E
    bcc @normal_kick
    jsr update_stutter
    jmp @after_kick
@normal_kick:
    jsr update_kick
@after_kick:
    jsr update_hihat  
    jsr update_bass
    jsr update_lead
    jsr update_arp
    rts

@acid_mode:
    ; Acid techno - 303-style bass!
    jsr update_kick
    jsr update_hihat
    jsr update_acid         ; Acid bass line!
    jsr update_arp
    rts
    
@breakdown_mode:
    ; Breakdown - atmospheric
    jsr update_bass
    jsr update_pad
    jsr update_hihat
    rts

@drop_mode:
    ; DROP! Maximum energy
    jsr update_drop_kick    ; Heavy kicks
    jsr update_hihat
    jsr update_bass
    jsr update_lead
    jsr update_arp
    jsr update_acid         ; Layer acid too!
    rts
    
@buildup_mode:
    ; Buildup with riser
    jsr update_kick
    jsr update_riser
    jsr update_bass
    rts

@minimal_mode:
    ; Minimal - just kick and bass
    jsr update_kick
    jsr update_bass
    rts

;------------------------------------------------------------------------------
; Song Section Management - 7 unique sections!
;------------------------------------------------------------------------------
; Section 0: Intro (normal)
; Section 1: Acid mode
; Section 2: Breakdown
; Section 3: DROP!
; Section 4: Peak (normal)
; Section 5: Buildup/Riser
; Section 6: Minimal
;------------------------------------------------------------------------------
update_song_section:
    ; Song structure every 4 bars (faster changes!)
    lda bar_count
    and #$03
    bne @check_section
    
    ; Every 4 bars, advance section
    inc song_section
    lda song_section
    cmp #$07                ; 7 sections, then loop
    bcc @section_ok
    lda #$00
    sta song_section
    ; Reset intensity for new cycle
    lda #$02
    sta intensity
    ; Change groove variation
    inc groove_var
    rts
    
@section_ok:
    ; DROP section (3) - set max intensity!
    lda song_section
    cmp #$03
    bne @check_section
    lda #$0F
    sta intensity
    
@check_section:
    ; Increase intensity within section
    lda frame_count
    and #$3F                ; Every 64 frames
    bne @done
    lda intensity
    cmp #$0F
    bcs @done
    inc intensity
@done:
    rts

;------------------------------------------------------------------------------
; Kick & Snare - 4 on the floor with backbeat snare
;------------------------------------------------------------------------------
update_kick:
    lda frame_count
    and #$1F                ; Every 32 frames
    
    cmp #$00
    bne @check_snare
    
    ; KICK HIT!
    lda #%00111111          ; Vol 15
    sta APU_NOISE_CTRL
    lda #$02                ; Low pitch for deep kick
    sta APU_NOISE_FREQ
    lda #$18
    sta APU_NOISE_LEN
    rts
    
@check_snare:
    cmp #$10                ; Frame 16 = snare (offbeat)
    bne @kick_decay
    
    ; Check if snare should play (only after some intensity)
    lda intensity
    cmp #$02
    bcc @kick_decay
    
    ; SNARE HIT!
    lda #%00111100          ; Vol 12
    sta APU_NOISE_CTRL
    lda #$06                ; Medium-high pitch
    sta APU_NOISE_FREQ
    lda #$10
    sta APU_NOISE_LEN
    rts
    
@kick_decay:
    lda frame_count
    and #$1F
    cmp #$01
    bne @decay2
    lda #%00111010          ; Vol 10
    sta APU_NOISE_CTRL
    rts
@decay2:
    cmp #$02
    bne @decay3
    lda #%00110101          ; Vol 5
    sta APU_NOISE_CTRL
    rts
@decay3:
    cmp #$03
    bne @snare_decay
    lda #%00110000          ; Vol 0
    sta APU_NOISE_CTRL
    rts
    
@snare_decay:
    ; Snare decay at frames 17-19
    cmp #$11
    bne @sd2
    lda #%00111000          ; Vol 8
    sta APU_NOISE_CTRL
    rts
@sd2:
    cmp #$12
    bne @sd3
    lda #%00110100          ; Vol 4
    sta APU_NOISE_CTRL
    rts
@sd3:
    cmp #$13
    bne @done
    lda #%00110000          ; Vol 0
    sta APU_NOISE_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Hi-hat - 16th note pattern (evolves with intensity)
;------------------------------------------------------------------------------
update_hihat:
    ; Different patterns based on intensity
    lda intensity
    cmp #$06
    bcs @fast_hats          ; Fast 16ths at high intensity
    cmp #$03
    bcs @medium_hats        ; 8th notes at medium
    
    ; Slow hats - just offbeat
    lda frame_count
    and #$1F
    cmp #$08                ; Frame 8 only
    beq @play_hat
    rts
    
@medium_hats:
    ; 8th note hats
    lda frame_count
    and #$0F                ; Every 16 frames
    cmp #$08
    beq @play_hat
    rts
    
@fast_hats:
    ; 16th note hats (every 8 frames)
    lda frame_count
    and #$07
    cmp #$04
    beq @play_hat
    cmp #$00
    beq @play_accent_hat    ; Accent on downbeat
    rts
    
@play_accent_hat:
    lda #%00111010          ; Vol 10 (accent)
    sta APU_NOISE_CTRL
    lda #$0E                ; High pitch
    sta APU_NOISE_FREQ
    lda #$08
    sta APU_NOISE_LEN
    rts
    
@play_hat:
    lda #%00110110          ; Vol 6
    sta APU_NOISE_CTRL
    lda #$0F                ; Highest pitch
    sta APU_NOISE_FREQ
    lda #$04
    sta APU_NOISE_LEN
    rts

;------------------------------------------------------------------------------
; Bass - Triangle channel, 3 alternating patterns
;------------------------------------------------------------------------------
update_bass:
    lda frame_count
    and #$0F                ; Every 16 frames = new note
    bne @sustain
    
    ; Get bass note from pattern
    lda beat_count
    and #$07                ; 8-note pattern
    tax
    
    ; Which bass pattern? Changes every 4 bars
    lda bar_count
    lsr a
    lsr a                   ; Divide by 4
    and #$03                ; 0-3
    
    cmp #$00
    beq @pattern1
    cmp #$01
    beq @pattern2
    cmp #$02
    beq @pattern3
    ; Fall through to pattern 1 for case 3
    
@pattern1:
    ; Pattern 1 - driving root
    lda bass_lo, x
    sta APU_TRI_LO
    lda bass_hi, x
    sta APU_TRI_HI
    jmp @enable
    
@pattern2:
    ; Pattern 2 - more melodic
    lda bass2_lo, x
    sta APU_TRI_LO
    lda bass2_hi, x
    sta APU_TRI_HI
    jmp @enable
    
@pattern3:
    ; Pattern 3 - syncopated
    lda bass3_lo, x
    sta APU_TRI_LO
    lda bass3_hi, x
    sta APU_TRI_HI
    
@enable:
    ; Enable triangle
    lda #%11111111
    sta APU_TRI_CTRL
    
@sustain:
    rts

;------------------------------------------------------------------------------
; Lead Synth - Pulse 1, chord stabs with filter sweep
;------------------------------------------------------------------------------
update_lead:
    ; Only play after some intensity
    lda intensity
    cmp #$03
    bcc @lead_off
    
    ; Different patterns based on bar
    lda bar_count
    and #$03
    cmp #$03
    beq @lead_fill          ; Every 4th bar = fill
    
    ; Normal: play on certain beats
    lda beat_count
    and #$03
    bne @lead_sustain
    
    lda frame_count
    and #$1F
    cmp #$04                ; Stab on frame 4
    bne @lead_sustain
    
    ; STAB! Get note from pattern
    lda beat_count
    lsr a
    lsr a
    clc
    adc bar_count           ; Add variation over time
    and #$07                ; 8 notes
    tax
    lda lead_lo, x
    sta APU_PULSE1_LO
    lda lead_hi, x
    sta APU_PULSE1_HI
    
    ; Duty cycle changes based on intensity (filter sweep effect)
    lda intensity
    and #$03
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a                   ; Shift to bits 6-7
    ora #%00111111          ; Vol 15
    sta APU_PULSE1_CTRL
    rts
    
@lead_fill:
    ; Fill pattern - rapid notes
    lda frame_count
    and #$07                ; Every 8 frames
    bne @lead_sustain
    
    lda frame_count
    lsr a
    lsr a
    lsr a
    and #$07
    tax
    lda lead_lo, x
    sta APU_PULSE1_LO
    lda lead_hi, x
    sta APU_PULSE1_HI
    lda #%01111110          ; 25% duty, vol 14
    sta APU_PULSE1_CTRL
    rts
    
@lead_sustain:
    ; Quick decay
    lda frame_count
    and #$07
    cmp #$03
    bcc @done
    lda #%10110100          ; Vol 4
    sta APU_PULSE1_CTRL
    rts
    
@lead_off:
    lda #%10110000          ; Vol 0
    sta APU_PULSE1_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Arpeggio - Pulse 2, evolving patterns
;------------------------------------------------------------------------------
update_arp:
    ; Arp only after buildup
    lda intensity
    cmp #$04
    bcc @arp_off
    
    ; Arp speed varies with intensity
    lda intensity
    cmp #$08
    bcs @super_fast_arp
    cmp #$06
    bcs @fast_arp
    
    ; Normal arp - every 4 frames
    lda frame_count
    and #$03
    bne @arp_sustain
    jmp @play_arp
    
@fast_arp:
    ; Fast arp - every 3 frames
    lda frame_count
    and #$03
    cmp #$03
    beq @arp_sustain
    jmp @play_arp
    
@super_fast_arp:
    ; Super fast - every 2 frames!
    lda frame_count
    and #$01
    bne @arp_sustain
    
@play_arp:
    ; Which arp pattern?
    lda bar_count
    and #$04
    beq @arp_pattern1
    
    ; Pattern 2 - different notes
    lda frame_count
    lsr a
    lsr a
    and #$07
    tax
    lda arp2_lo, x
    sta APU_PULSE2_LO
    lda arp2_hi, x
    sta APU_PULSE2_HI
    jmp @arp_vol
    
@arp_pattern1:
    ; Pattern 1
    lda frame_count
    lsr a
    lsr a
    and #$07
    tax
    lda arp_lo, x
    sta APU_PULSE2_LO
    lda arp_hi, x
    sta APU_PULSE2_HI
    
@arp_vol:
    ; Volume and duty based on beat position
    lda frame_count
    and #$1F
    cmp #$10
    bcs @arp_quiet
    
    ; Louder on first half of beat
    lda intensity
    lsr a
    clc
    adc #$08                ; 8-15
    and #$0F
    ora #%01110000          ; 25% duty
    sta APU_PULSE2_CTRL
    rts
    
@arp_quiet:
    lda #%01110110          ; Vol 6
    sta APU_PULSE2_CTRL
    rts
    
@arp_sustain:
    lda #%01110010          ; Vol 2
    sta APU_PULSE2_CTRL
    rts
    
@arp_off:
    lda #%01110000          ; Vol 0
    sta APU_PULSE2_CTRL
    rts

;------------------------------------------------------------------------------
; Pad - Atmospheric sound for breakdowns (Pulse 1)
;------------------------------------------------------------------------------
update_pad:
    ; Slow-evolving chord pad
    lda frame_count
    and #$3F                ; Every 64 frames = change note
    bne @pad_sustain
    
    ; Get pad note
    lda beat_count
    lsr a
    and #$03
    tax
    lda pad_lo, x
    sta APU_PULSE1_LO
    lda pad_hi, x
    sta APU_PULSE1_HI
    
    ; Soft attack
    lda #%11110100          ; 75% duty (warmer), vol 4
    sta APU_PULSE1_CTRL
    rts
    
@pad_sustain:
    ; Slow swell
    lda frame_count
    and #$1F
    lsr a
    lsr a                   ; 0-7
    clc
    adc #$02                ; 2-9
    ora #%11110000          ; 75% duty
    sta APU_PULSE1_CTRL
    rts

;------------------------------------------------------------------------------
; Riser - Building noise sweep for drops
;------------------------------------------------------------------------------
update_riser:
    ; Noise pitch rises over bar
    lda frame_count
    and #$07                ; Every 8 frames
    bne @riser_sustain
    
    ; Calculate pitch based on position in section
    lda beat_count
    and #$0F                ; 0-15 within bar
    eor #$0F                ; Invert: 15-0 (pitch goes UP)
    sta APU_NOISE_FREQ
    
    ; Volume builds up
    lda beat_count
    and #$0F
    lsr a                   ; 0-7
    clc
    adc #$08                ; 8-15
    ora #%00110000
    sta APU_NOISE_CTRL
    lda #$08
    sta APU_NOISE_LEN
    
@riser_sustain:
    rts

;------------------------------------------------------------------------------
; Stutter Kick - Rapid kicks for fills
;------------------------------------------------------------------------------
update_stutter:
    ; Only on specific beats
    lda beat_count
    and #$0F
    cmp #$0F                ; Last beat of bar
    bne @no_stutter
    
    ; Rapid kicks every 4 frames
    lda frame_count
    and #$03
    bne @stutter_decay
    
    lda #%00111101          ; Vol 13
    sta APU_NOISE_CTRL
    lda #$03                ; Medium-low pitch
    sta APU_NOISE_FREQ
    lda #$10
    sta APU_NOISE_LEN
    rts
    
@stutter_decay:
    lda #%00110100          ; Vol 4
    sta APU_NOISE_CTRL
    rts
    
@no_stutter:
    rts

;------------------------------------------------------------------------------
; Acid Bass - 303-style with slides (Pulse 1)
;------------------------------------------------------------------------------
update_acid:
    ; Fast note changes - every 8 frames
    lda frame_count
    and #$07
    bne @acid_slide
    
    ; Get acid note
    lda frame_count
    lsr a
    lsr a
    lsr a
    clc
    adc groove_var          ; Variation
    and #$0F                ; 16-note pattern
    tax
    lda acid_lo, x
    sta APU_PULSE1_LO
    lda acid_hi, x
    sta APU_PULSE1_HI
    
    ; Accented notes on certain beats
    lda frame_count
    and #$1F
    cmp #$00
    beq @acid_accent
    cmp #$0C
    beq @acid_accent
    
    ; Normal acid note
    lda #%00111011          ; 12.5% duty, vol 11
    sta APU_PULSE1_CTRL
    rts
    
@acid_accent:
    ; ACCENT! Louder, different duty
    lda #%01111111          ; 25% duty, vol 15
    sta APU_PULSE1_CTRL
    rts
    
@acid_slide:
    ; Pitch slide effect - bend between notes
    lda frame_count
    and #$07
    cmp #$04
    bcc @acid_done
    ; Slide up slightly
    lda APU_PULSE1_LO
    sec
    sbc #$02                ; Pitch bend up
    sta APU_PULSE1_LO
    ; Quick decay
    lda #%00110111          ; Vol 7
    sta APU_PULSE1_CTRL
@acid_done:
    rts

;------------------------------------------------------------------------------
; Drop Kick - Extra heavy kick for drops
;------------------------------------------------------------------------------
update_drop_kick:
    lda frame_count
    and #$1F
    
    cmp #$00
    bne @drop_decay
    
    ; MASSIVE KICK!
    lda #%00111111          ; Vol 15
    sta APU_NOISE_CTRL
    lda #$01                ; Lowest pitch = deepest
    sta APU_NOISE_FREQ
    lda #$20                ; Long decay
    sta APU_NOISE_LEN
    rts
    
@drop_decay:
    cmp #$01
    bne @dd2
    lda #%00111100          ; Vol 12
    sta APU_NOISE_CTRL
    lda #$02
    sta APU_NOISE_FREQ
    rts
@dd2:
    cmp #$02
    bne @dd3
    lda #%00111000          ; Vol 8
    sta APU_NOISE_CTRL
    rts
@dd3:
    cmp #$03
    bne @dd4
    lda #%00110100          ; Vol 4
    sta APU_NOISE_CTRL
    rts
@dd4:
    cmp #$04
    bne @check_sub
    lda #%00110000          ; Silent
    sta APU_NOISE_CTRL
    rts

@check_sub:
    ; Sub bass thump on frame 8 (layered with kick)
    cmp #$08
    bne @done
    lda #%00111010          ; Vol 10
    sta APU_NOISE_CTRL
    lda #$00                ; Lowest pitch
    sta APU_NOISE_FREQ
    lda #$08
    sta APU_NOISE_LEN
@done:
    rts

;------------------------------------------------------------------------------
; IRQ Handler (not used)
;------------------------------------------------------------------------------
IRQ:
    rti

;------------------------------------------------------------------------------
; Data Tables
;------------------------------------------------------------------------------
.segment "RODATA"

; Bass frequencies - E minor groove (Pattern 1 - driving)
bass_lo:
    .byte $9D               ; E2
    .byte $9D               ; E2  
    .byte $9D               ; E2
    .byte $9D               ; E2
    .byte $9D               ; E2
    .byte $4C               ; G2
    .byte $9D               ; E2
    .byte $9D               ; E2
bass_hi:
    .byte $05, $05, $05, $05, $05, $05, $05, $05

; Bass Pattern 2 - more melodic
bass2_lo:
    .byte $9D               ; E2
    .byte $4C               ; G2
    .byte $00               ; A2
    .byte $9D               ; E2
    .byte $F8               ; B2
    .byte $00               ; A2
    .byte $4C               ; G2
    .byte $9D               ; E2
bass2_hi:
    .byte $05, $05, $05, $05, $04, $05, $05, $05

; Bass Pattern 3 - syncopated funk
bass3_lo:
    .byte $9D               ; E2
    .byte $9D               ; E2
    .byte $4C               ; G2
    .byte $4C               ; G2
    .byte $00               ; A2
    .byte $F8               ; B2
    .byte $00               ; A2
    .byte $4C               ; G2
bass3_hi:
    .byte $05, $05, $05, $05, $05, $04, $05, $05

; Lead frequencies - E minor chord tones (8 notes)
lead_lo:
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $FD               ; B3
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $00               ; A4
    .byte $FD               ; B3
    .byte $D4               ; E3
lead_hi:
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; B3
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; A4
    .byte $01               ; B3
    .byte $02               ; E3

; Arp Pattern 1 - ascending/descending
arp_lo:
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $00               ; A4
    .byte $FD               ; B4
    .byte $D4               ; E5
    .byte $FD               ; B4
    .byte $00               ; A4
    .byte $52               ; G4
arp_hi:
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; A4
    .byte $00               ; B4
    .byte $00               ; E5
    .byte $00               ; B4
    .byte $01               ; A4
    .byte $01               ; G4

; Arp Pattern 2 - octave jumps
arp2_lo:
    .byte $A9               ; E4
    .byte $D4               ; E5
    .byte $52               ; G4
    .byte $A9               ; G5
    .byte $00               ; A4
    .byte $00               ; A5 (approximated)
    .byte $FD               ; B4
    .byte $D4               ; E5
arp2_hi:
    .byte $01               ; E4
    .byte $00               ; E5
    .byte $01               ; G4
    .byte $00               ; G5
    .byte $01               ; A4
    .byte $00               ; A5
    .byte $00               ; B4
    .byte $00               ; E5

; Pad notes - slow chord tones (lower octave)
pad_lo:
    .byte $9D               ; E2
    .byte $4C               ; G2
    .byte $F8               ; B2
    .byte $00               ; A2
pad_hi:
    .byte $05               ; E2
    .byte $05               ; G2
    .byte $04               ; B2
    .byte $05               ; A2

; Acid bass pattern - 16 notes, classic 303 style!
acid_lo:
    .byte $A9               ; E4
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $A9               ; E4
    .byte $00               ; A4
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $00               ; A4
    .byte $A9               ; E4
    .byte $FD               ; B4
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $D4               ; E5 (octave up!)
    .byte $A9               ; E4
    .byte $00               ; A4
    .byte $52               ; G4
acid_hi:
    .byte $01               ; E4
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; E4
    .byte $01               ; A4
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; A4
    .byte $01               ; E4
    .byte $00               ; B4
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $00               ; E5
    .byte $01               ; E4
    .byte $01               ; A4
    .byte $01               ; G4

;------------------------------------------------------------------------------
; Vectors
;------------------------------------------------------------------------------
.segment "VECTORS"
    .word NMI
    .word RESET
    .word IRQ

;------------------------------------------------------------------------------
; CHR ROM - Empty (no graphics needed)
;------------------------------------------------------------------------------
.segment "CHARS"
    .res 8192, $00          ; 8KB of empty tiles

