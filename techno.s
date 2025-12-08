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
arp_note:       .res 1      ; Current arp note index
intensity:      .res 1      ; Builds up over time

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
    
    ; New bar - advance bass pattern
    inc bar_count
    
    ; Every 4 bars, maybe change section
    lda bar_count
    and #$03
    bne @not_bar
    
    ; Increase intensity
    lda intensity
    cmp #$0F
    bcs @max_intensity
    inc intensity
@max_intensity:
@not_bar:
@not_beat:

    ; Always update all sound components
    jsr update_kick
    jsr update_hihat  
    jsr update_bass
    jsr update_lead
    jsr update_arp
    
    rts

;------------------------------------------------------------------------------
; Kick Drum - 4 on the floor
;------------------------------------------------------------------------------
update_kick:
    lda frame_count
    and #$1F                ; Every 32 frames
    
    cmp #$00
    bne @kick_decay
    
    ; KICK HIT!
    lda #%00111111          ; Vol 15, no loop
    sta APU_NOISE_CTRL
    lda #$02                ; Low pitch for deep kick
    sta APU_NOISE_FREQ
    lda #$18                ; Length
    sta APU_NOISE_LEN
    rts
    
@kick_decay:
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
    bne @silent
    lda #%00110000          ; Vol 0
    sta APU_NOISE_CTRL
@silent:
    rts

;------------------------------------------------------------------------------
; Hi-hat - offbeat
;------------------------------------------------------------------------------
update_hihat:
    lda frame_count
    and #$1F
    
    cmp #$10                ; Frame 16 = offbeat
    bne @hat_silent
    
    ; HI-HAT!
    lda #%00111000          ; Vol 8
    sta APU_NOISE_CTRL
    lda #$0F                ; High pitch
    sta APU_NOISE_FREQ
    lda #$08
    sta APU_NOISE_LEN
    rts
    
@hat_silent:
    cmp #$11
    bne @done
    lda #%00110000          ; Silence
    sta APU_NOISE_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Bass - Triangle channel, 8-note pattern
;------------------------------------------------------------------------------
update_bass:
    lda frame_count
    and #$1F                ; Every 32 frames = new note
    bne @sustain
    
    ; Get bass note from pattern
    lda beat_count
    and #$07                ; 8-note pattern
    tax
    
    ; Set triangle frequency
    lda bass_lo, x
    sta APU_TRI_LO
    lda bass_hi, x
    sta APU_TRI_HI
    
    ; Enable triangle
    lda #%11111111
    sta APU_TRI_CTRL
    
@sustain:
    rts

;------------------------------------------------------------------------------
; Lead Synth - Pulse 1, chord stabs
;------------------------------------------------------------------------------
update_lead:
    ; Only play on certain beats (every 4 beats)
    lda beat_count
    and #$03
    bne @lead_off
    
    lda frame_count
    and #$1F
    cmp #$04                ; Stab on frame 4 of beat
    bne @lead_decay
    
    ; STAB!
    lda beat_count
    lsr a
    lsr a
    and #$03
    tax
    lda lead_lo, x
    sta APU_PULSE1_LO
    lda lead_hi, x
    sta APU_PULSE1_HI
    lda #%10111111          ; 50% duty, vol 15
    sta APU_PULSE1_CTRL
    rts
    
@lead_decay:
    lda frame_count
    and #$1F
    cmp #$08
    bcc @done
    cmp #$10
    bcs @lead_off
    ; Decay
    lda #%10111000          ; Vol 8
    sta APU_PULSE1_CTRL
    rts
    
@lead_off:
    lda #%10110000          ; Vol 0
    sta APU_PULSE1_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Arpeggio - Pulse 2, fast notes
;------------------------------------------------------------------------------
update_arp:
    ; Arp speed based on intensity
    lda intensity
    cmp #$04                ; Only play arp after some buildup
    bcc @arp_off
    
    ; Fast arp - every 4 frames
    lda frame_count
    and #$03
    bne @arp_sustain
    
    ; Get note from arp pattern
    lda frame_count
    lsr a
    lsr a
    and #$07                ; 8-note pattern
    tax
    
    lda arp_lo, x
    sta APU_PULSE2_LO
    lda arp_hi, x
    sta APU_PULSE2_HI
    
    ; Volume based on intensity
    lda intensity
    lsr a                   ; 0-7
    ora #%01111000          ; 25% duty + volume
    sta APU_PULSE2_CTRL
    rts
    
@arp_sustain:
    ; Quick decay
    lda frame_count
    and #$03
    cmp #$02
    bcc @done
    lda #%01110011          ; Vol 3
    sta APU_PULSE2_CTRL
    rts
    
@arp_off:
    lda #%01110000          ; Vol 0
    sta APU_PULSE2_CTRL
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

; Bass frequencies - E minor groove
bass_lo:
    .byte $9D               ; E2
    .byte $9D               ; E2  
    .byte $4C               ; G2
    .byte $9D               ; E2
    .byte $00               ; A2
    .byte $9D               ; E2
    .byte $4C               ; G2
    .byte $F8               ; B2
bass_hi:
    .byte $05               ; E2
    .byte $05               ; E2
    .byte $05               ; G2
    .byte $05               ; E2
    .byte $05               ; A2
    .byte $05               ; E2
    .byte $05               ; G2
    .byte $04               ; B2

; Lead frequencies - E minor chord tones
lead_lo:
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $FD               ; B3
    .byte $A9               ; E4
lead_hi:
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; B3
    .byte $01               ; E4

; Arp frequencies - E minor pentatonic
arp_lo:
    .byte $A9               ; E4
    .byte $52               ; G4
    .byte $00               ; A4
    .byte $FD               ; B4
    .byte $52               ; G4
    .byte $A9               ; E4
    .byte $00               ; A4
    .byte $FD               ; B4
arp_hi:
    .byte $01               ; E4
    .byte $01               ; G4
    .byte $01               ; A4
    .byte $00               ; B4
    .byte $01               ; G4
    .byte $01               ; E4
    .byte $01               ; A4
    .byte $00               ; B4

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

