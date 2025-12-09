; NES CHAOS - Psychedelic Visual & Audio Experience
; REWRITTEN: Using single parameterized renderer (stable!)
; Based on lessons learned from techno.s
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
; APU Registers
;------------------------------------------------------------------------------
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
beat_count:     .res 1      ; Beat counter
bar_count:      .res 1      ; Bar counter
song_section:   .res 1      ; Current section
intensity:      .res 1      ; Music intensity

; Visual parameters - all morph smoothly
vis_phase:      .res 1      ; Main animation phase
vis_phase2:     .res 1      ; Secondary phase (3/4 speed)
vis_a:          .res 1      ; Coefficient A
vis_b:          .res 1      ; Coefficient B
vis_c:          .res 1      ; Coefficient C
vis_d:          .res 1      ; Coefficient D (tracks intensity)
vis_pulse:      .res 1      ; Beat pulse
vis_hue:        .res 1      ; Color cycling
vis_temp:       .res 4      ; Temp storage

;------------------------------------------------------------------------------
; iNES Header
;------------------------------------------------------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 1                 ; 1 x 16KB PRG ROM
    .byte 1                 ; 1 x 8KB CHR ROM
    .byte $00               ; Mapper 0, horizontal mirroring
    .byte $00

;------------------------------------------------------------------------------
; Main Code
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
    stx $4010               ; Disable DMC

    ; Wait for vblank
@vblank1:
    bit PPU_STATUS
    bpl @vblank1

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
    sta vis_phase
    sta vis_pulse
    sta vis_hue
    
    lda #$10
    sta vis_a
    lda #$08
    sta vis_b
    lda #$04
    sta vis_c
    lda #$02
    sta vis_d
    sta intensity

    ; Init APU
    lda #%00001111
    sta APU_STATUS
    lda #$08
    sta APU_PULSE1_SWEEP
    sta APU_PULSE2_SWEEP

    ; Load palette
    jsr load_palette
    
    ; Fill nametable
    jsr init_nametable

    ; Enable NMI and rendering
    lda #%10000000
    sta PPU_CTRL
    lda #%00001010
    sta PPU_MASK

;------------------------------------------------------------------------------
; Main Loop
;------------------------------------------------------------------------------
main_loop:
    jmp main_loop

;------------------------------------------------------------------------------
; NMI Handler - Visuals then Music
;------------------------------------------------------------------------------
NMI:
    pha
    txa
    pha
    tya
    pha

    ; Frame counter
    inc frame_count
    bne @no_wrap
    inc frame_count+1
@no_wrap:

    ; === VISUALS (during vblank) ===
    jsr update_palette_cycle
    jsr update_tiles
    
    ; Reset scroll
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL
    
    ; === MUSIC ===
    jsr update_music
    
    ; === Update visual parameters ===
    jsr update_visual_params

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

;==============================================================================
; VISUAL ENGINE - ONE safe parameterized renderer
;==============================================================================

;------------------------------------------------------------------------------
; Load Palette
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
; Initialize Nametable
;------------------------------------------------------------------------------
init_nametable:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    
    ldx #$00
    ldy #$04
@fill:
    txa
    and #$1F
    ora #$01
    sta PPU_DATA
    inx
    bne @fill
    dey
    bne @fill
    rts

;------------------------------------------------------------------------------
; Update Palette - Beat reactive colors
;------------------------------------------------------------------------------
update_palette_cycle:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$01
    sta PPU_ADDR
    
    ; Color 1 - brightens on beat
    lda vis_hue
    and #$0C
    clc
    adc vis_pulse
    and #$0F
    cmp #$0D
    bcc @c1_ok
    lda #$0C
@c1_ok:
    ora #$10
    sta PPU_DATA
    
    ; Color 2 - tracks section
    lda vis_hue
    clc
    adc #$04
    adc song_section
    and #$0C
    ora #$20
    sta PPU_DATA
    
    ; Color 3 - complementary
    lda vis_hue
    clc
    adc #$08
    and #$0C
    ora #$30
    sta PPU_DATA
    rts

;------------------------------------------------------------------------------
; Update Tiles - THE CORE (safe, covers full screen)
;------------------------------------------------------------------------------
update_tiles:
    ldx #$10                ; 16 tiles per frame (safe!)
@tile_loop:
    bit PPU_STATUS
    stx vis_temp
    
    ; HIGH BYTE ($20-$23) - varies with frame + loop
    lda frame_count
    lsr a
    lsr a
    clc
    adc vis_temp
    and #$03
    clc
    adc #$20
    sta vis_temp+1
    sta PPU_ADDR
    
    ; LOW BYTE - spread across page
    lda frame_count
    asl a
    asl a
    asl a
    clc
    adc vis_temp
    adc vis_temp
    adc vis_temp
    clc
    adc frame_count+1
    sta PPU_ADDR
    
    ; === Morphing tile formula ===
    ; X component: frame + loop + phase + a
    lda frame_count
    clc
    adc vis_temp
    clc
    adc vis_phase
    clc
    adc vis_a
    sta vis_temp+1
    
    ; Y component: frame_hi XOR loop + phase2 + b
    lda frame_count+1
    eor vis_temp
    clc
    adc vis_phase2
    clc
    adc vis_b
    
    ; XOR creates interference + add c
    eor vis_temp+1
    clc
    adc vis_c
    
    ; Beat pulse
    clc
    adc vis_pulse
    adc vis_pulse
    
    ; Ensure valid tile (1-31)
    and #$1F
    ora #$01
    
    sta PPU_DATA
    
    dex
    bne @tile_loop
    rts

;------------------------------------------------------------------------------
; Update Visual Parameters - Smooth morphing
;------------------------------------------------------------------------------
update_visual_params:
    ; Main phase
    inc vis_phase
    
    ; Secondary phase (3/4 speed)
    lda frame_count
    and #$03
    cmp #$03
    beq @skip_p2
    inc vis_phase2
@skip_p2:
    
    ; Coefficient A oscillates
    lda frame_count
    and #$07
    bne @skip_a
    lda frame_count+1
    and #$01
    beq @a_up
    dec vis_a
    jmp @skip_a
@a_up:
    inc vis_a
@skip_a:

    ; Coefficient B (different rate)
    lda frame_count
    and #$0B
    bne @skip_b
    inc vis_b
@skip_b:

    ; Coefficient C (slowest)
    lda frame_count
    and #$1F
    bne @skip_c
    lda song_section
    and #$01
    beq @c_up
    dec vis_c
    jmp @skip_c
@c_up:
    inc vis_c
@skip_c:

    ; D tracks intensity
    lda intensity
    sta vis_d
    
    ; Hue cycling (faster at high intensity)
    lda intensity
    cmp #$08
    bcc @slow_hue
    lda frame_count
    and #$01
    bne @skip_hue
    inc vis_hue
    jmp @skip_hue
@slow_hue:
    lda frame_count
    and #$03
    bne @skip_hue
    inc vis_hue
@skip_hue:

    ; Beat pulse - spike and decay
    lda frame_count
    and #$1F
    cmp #$00
    bne @pulse_decay
    lda song_section
    cmp #$06
    bne @normal_pulse
    lda #$0C
    jmp @set_pulse
@normal_pulse:
    lda #$08
@set_pulse:
    sta vis_pulse
    rts
    
@pulse_decay:
    lda frame_count
    and #$03
    bne @pulse_done
    lda vis_pulse
    beq @pulse_done
    dec vis_pulse
@pulse_done:
    rts

;==============================================================================
; MUSIC ENGINE (from techno.s - proven stable)
;==============================================================================

update_music:
    ; Beat timing (120 BPM)
    lda frame_count
    and #$1F
    bne @not_beat
    
    inc beat_count
    lda beat_count
    and #$0F
    bne @not_bar
    
    inc bar_count
    jsr update_song_section
    
@not_bar:
@not_beat:
    ; Update all sound components
    jsr update_kick
    jsr update_hihat
    jsr update_bass
    jsr update_lead
    jsr update_arp
    rts

;------------------------------------------------------------------------------
; Song Section Management
;------------------------------------------------------------------------------
update_song_section:
    lda bar_count
    and #$03
    bne @check
    
    inc song_section
    lda song_section
    cmp #$07
    bcc @ok
    lda #$00
    sta song_section
    lda #$02
    sta intensity
    rts
    
@ok:
    lda song_section
    cmp #$03
    bne @check
    lda #$0F
    sta intensity
    
@check:
    lda frame_count
    and #$3F
    bne @done
    lda intensity
    cmp #$0F
    bcs @done
    inc intensity
@done:
    rts

;------------------------------------------------------------------------------
; Kick & Snare
;------------------------------------------------------------------------------
update_kick:
    lda frame_count
    and #$1F
    
    cmp #$00
    bne @check_snare
    ; KICK
    lda #%00111111
    sta APU_NOISE_CTRL
    lda #$02
    sta APU_NOISE_FREQ
    lda #$18
    sta APU_NOISE_LEN
    rts
    
@check_snare:
    cmp #$10
    bne @decay
    lda intensity
    cmp #$02
    bcc @decay
    ; SNARE
    lda #%00111100
    sta APU_NOISE_CTRL
    lda #$06
    sta APU_NOISE_FREQ
    lda #$10
    sta APU_NOISE_LEN
    rts
    
@decay:
    lda frame_count
    and #$1F
    cmp #$01
    bne @d2
    lda #%00111010
    sta APU_NOISE_CTRL
    rts
@d2:
    cmp #$02
    bne @d3
    lda #%00110101
    sta APU_NOISE_CTRL
    rts
@d3:
    cmp #$03
    bne @done
    lda #%00110000
    sta APU_NOISE_CTRL
@done:
    rts

;------------------------------------------------------------------------------
; Hi-hat
;------------------------------------------------------------------------------
update_hihat:
    lda frame_count
    and #$1F
    
    cmp #$10
    beq @play
    cmp #$00
    bne @done
    ; Quiet downbeat
    lda #%00110100
    sta APU_NOISE_CTRL
    lda #$0F
    sta APU_NOISE_FREQ
    lda #$02
    sta APU_NOISE_LEN
    rts
    
@play:
    lda #%00110111
    sta APU_NOISE_CTRL
    lda #$0E
    sta APU_NOISE_FREQ
    lda #$06
    sta APU_NOISE_LEN
@done:
    rts

;------------------------------------------------------------------------------
; Bass - Triangle
;------------------------------------------------------------------------------
update_bass:
    lda frame_count
    and #$0F
    bne @sustain
    
    lda beat_count
    and #$07
    tax
    lda bass_lo, x
    sta APU_TRI_LO
    lda bass_hi, x
    sta APU_TRI_HI
    lda #%11111111
    sta APU_TRI_CTRL
    
@sustain:
    rts

;------------------------------------------------------------------------------
; Lead - Pulse 1
;------------------------------------------------------------------------------
update_lead:
    lda beat_count
    and #$07
    bne @sustain
    
    lda frame_count
    and #$1F
    cmp #$04
    bne @sustain
    
    lda bar_count
    and #$03
    tax
    lda lead_lo, x
    sta APU_PULSE1_LO
    lda lead_hi, x
    sta APU_PULSE1_HI
    lda #%10111010
    sta APU_PULSE1_CTRL
    rts
    
@sustain:
    lda frame_count
    and #$1F
    cmp #$10
    bcs @off
    rts
@off:
    lda #%10110000
    sta APU_PULSE1_CTRL
    rts

;------------------------------------------------------------------------------
; Arpeggio - Pulse 2
;------------------------------------------------------------------------------
update_arp:
    lda intensity
    cmp #$04
    bcc @off
    
    lda frame_count
    and #$07
    bne @sustain
    
    lda frame_count
    lsr a
    lsr a
    lsr a
    and #$07
    tax
    lda arp_lo, x
    sta APU_PULSE2_LO
    lda arp_hi, x
    sta APU_PULSE2_HI
    lda #%01110101
    sta APU_PULSE2_CTRL
    rts
    
@sustain:
    lda #%01110010
    sta APU_PULSE2_CTRL
    rts
    
@off:
    lda #%01110000
    sta APU_PULSE2_CTRL
    rts

;------------------------------------------------------------------------------
; Data Tables
;------------------------------------------------------------------------------
.segment "RODATA"

initial_palette:
    .byte $0F, $11, $21, $31
    .byte $0F, $14, $24, $34
    .byte $0F, $19, $29, $39
    .byte $0F, $12, $22, $32
    .byte $0F, $11, $21, $31
    .byte $0F, $14, $24, $34
    .byte $0F, $19, $29, $39
    .byte $0F, $12, $22, $32

bass_lo:
    .byte $9D, $9D, $4C, $9D, $00, $9D, $4C, $F8
bass_hi:
    .byte $05, $05, $05, $05, $05, $05, $05, $04

lead_lo:
    .byte $A9, $52, $FD, $A9
lead_hi:
    .byte $01, $01, $01, $01

arp_lo:
    .byte $A9, $52, $00, $FD, $D4, $FD, $00, $52
arp_hi:
    .byte $01, $01, $01, $00, $00, $00, $01, $01

;------------------------------------------------------------------------------
; Vectors
;------------------------------------------------------------------------------
.segment "VECTORS"
    .word NMI
    .word RESET
    .word IRQ

;------------------------------------------------------------------------------
; CHR ROM - Pattern tiles
;------------------------------------------------------------------------------
.segment "CHARS"

; Tile 0: Empty
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 1-31: Various patterns
.byte $00,$00,$00,$00,$00,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF, $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA, $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA, $00,$00,$00,$00,$00,$00,$00,$00
.byte $81,$42,$24,$18,$18,$24,$42,$81, $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$24,$42,$81,$81,$42,$24,$18, $00,$00,$00,$00,$00,$00,$00,$00
.byte $3C,$42,$81,$81,$81,$81,$42,$3C, $00,$00,$00,$00,$00,$00,$00,$00
.byte $11,$22,$44,$88,$11,$22,$44,$88, $00,$00,$00,$00,$00,$00,$00,$00
.byte $88,$44,$22,$11,$88,$44,$22,$11, $00,$00,$00,$00,$00,$00,$00,$00
.byte $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F, $00,$00,$00,$00,$00,$00,$00,$00
.byte $CC,$CC,$33,$33,$CC,$CC,$33,$33, $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55, $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$81,$81,$81,$81,$81,$81,$FF, $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$3C,$42,$42,$42,$42,$3C,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$FF,$FF,$18,$18,$18, $00,$00,$00,$00,$00,$00,$00,$00
.byte $01,$02,$04,$08,$10,$20,$40,$80, $00,$00,$00,$00,$00,$00,$00,$00
.byte $80,$40,$20,$10,$08,$04,$02,$01, $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$FF,$FF,$00,$00,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$18,$18,$18,$18,$18, $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$3C,$3C,$3C,$3C,$00,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $E7,$E7,$00,$00,$00,$00,$E7,$E7, $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$80,$80,$80,$80,$80,$80,$FF, $00,$00,$00,$00,$00,$00,$00,$00
.byte $7E,$81,$A5,$81,$A5,$99,$81,$7E, $00,$00,$00,$00,$00,$00,$00,$00
.byte $11,$00,$44,$00,$11,$00,$44,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$00,$55,$00,$55,$00,$55,$00, $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$22,$55,$88,$55,$22,$55,$88, $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA, $00,$00,$00,$00,$00,$00,$00,$00
.byte $77,$DD,$77,$DD,$77,$DD,$77,$DD, $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$AA,$FF,$AA,$FF,$AA,$FF,$AA, $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF, $00,$00,$00,$00,$00,$00,$00,$00

; Fill rest
.res 8192 - (32 * 16), $00
