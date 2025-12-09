; NES TECHNO - Pure evolving techno music
; Black screen, focus on audio only
; Assemble with ca65, link with ld65

;------------------------------------------------------------------------------
; NES Hardware Registers
;------------------------------------------------------------------------------
PPU_CTRL         = $2000
PPU_MASK         = $2001
PPU_STATUS       = $2002
PPU_SCROLL       = $2005
PPU_ADDR         = $2006
PPU_DATA         = $2007

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

; Visual engine parameters - all morph smoothly
vis_phase:      .res 1      ; Main animation phase
vis_a:          .res 1      ; Coefficient A (X scale)
vis_b:          .res 1      ; Coefficient B (Y scale)  
vis_c:          .res 1      ; Coefficient C (rotation/twist)
vis_d:          .res 1      ; Coefficient D (wave frequency)
vis_pulse:      .res 1      ; Beat pulse (spikes on kick)
vis_hue:        .res 1      ; Color cycling
vis_phase2:     .res 1      ; Secondary phase (different speed)
vis_wave:       .res 1      ; Wave offset (screen ripple effect)
vis_twist:      .res 1      ; Twist/spiral effect (NEW!)
vis_flash:      .res 1      ; Flash brightness on drops (NEW!)
vis_temp:       .res 4      ; Temp vars for calculations
tile_x:         .res 1      ; Current tile X position
tile_y:         .res 1      ; Current tile Y position

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

    ; Initialize visual parameters
    lda #$10
    sta vis_a
    lda #$08
    sta vis_b
    lda #$04
    sta vis_c
    lda #$02
    sta vis_d
    lda #$00
    sta vis_phase
    sta vis_pulse
    sta vis_hue
    
    ; Load initial palette
    jsr load_palette
    
    ; Fill nametable with initial tiles
    jsr init_nametable
    
    ; Enable NMI
    lda #%10000000
    sta PPU_CTRL
    
    ; Enable rendering (background on)
    lda #%00001010          ; Show background
    sta PPU_MASK

;------------------------------------------------------------------------------
; Main Loop - does nothing, all work in NMI
;------------------------------------------------------------------------------
main_loop:
    jmp main_loop

;------------------------------------------------------------------------------
; NMI Handler - Visuals first (in vblank), then music
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

    ; === VISUALS (during vblank) ===
    jsr update_palette_cycle
    jsr update_tiles        ; Safe: only 12 tiles per frame
    
    ; Reset scroll
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL
    
    ; === MUSIC (after vblank work) ===
    jsr update_music
    
    ; === Update visual parameters (sync to music) ===
    jsr update_visual_params

    pla
    tay
    pla
    tax
    pla
    rti

;==============================================================================
; VISUAL ENGINE - Safe, parameterized rendering
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
    
    ; Background palette - dark blues/purples
    ldx #$00
@pal_loop:
    lda initial_palette, x
    sta PPU_DATA
    inx
    cpx #$20
    bne @pal_loop
    rts

;------------------------------------------------------------------------------
; Initialize Nametable with gradient
;------------------------------------------------------------------------------
init_nametable:
    bit PPU_STATUS
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    
    ; Fill with simple gradient pattern
    ldx #$00
    ldy #$04                ; 4 pages = 1024 bytes
@fill_loop:
    txa
    and #$1F
    ora #$01                ; Tiles 1-31
    sta PPU_DATA
    inx
    bne @fill_loop
    dey
    bne @fill_loop
    rts

;------------------------------------------------------------------------------
; Update Palette - Cycle colors, respond to music
;------------------------------------------------------------------------------
update_palette_cycle:
    bit PPU_STATUS
    lda #$3F
    sta PPU_ADDR
    lda #$01                ; Start at color 1
    sta PPU_ADDR
    
    ; Color 1 - base hue, brightens on beat + flash
    lda vis_hue
    and #$0C                ; Hue (0, 4, 8, C)
    clc
    adc vis_pulse           ; Brighter on beat!
    clc
    adc vis_flash           ; FLASH on section change!
    lsr a                   ; Scale down
    and #$0F
    cmp #$0D
    bcc @c1_ok
    lda #$0C
@c1_ok:
    ora #$10
    sta PPU_DATA
    
    ; Color 2 - offset hue + flash makes it pop
    lda vis_flash
    cmp #$08                ; Strong flash?
    bcc @c2_normal
    ; Flash white-ish!
    lda #$30
    jmp @c2_write
@c2_normal:
    lda vis_hue
    clc
    adc #$04
    adc song_section
    and #$0C
    ora #$20
@c2_write:
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
; Update Tiles - The core visual engine (SAFE: only 16 tiles/frame)
; Nametable is $2000-$23BF (960 tiles, 32x30)
;------------------------------------------------------------------------------
update_tiles:
    ldx #$10                ; 16 tiles per frame
@tile_loop:
    bit PPU_STATUS
    stx vis_temp            ; Save loop counter
    
    ; Generate pseudo-random offset 0-959 using frame + loop counter
    ; We'll use: offset = (frame*17 + x*59) mod 960
    ; Simplified: just spread across all 4 pages
    
    ; High byte ($20, $21, $22, $23) - changes based on frame + x
    lda frame_count
    lsr a
    lsr a                   ; Slow down page changes
    clc
    adc vis_temp            ; Add loop counter
    and #$03                ; 0-3
    clc
    adc #$20                ; $20-$23
    sta vis_temp+1          ; Save high byte
    sta PPU_ADDR
    
    ; Low byte - spread across 256 positions per page
    lda frame_count
    asl a
    asl a
    asl a                   ; * 8
    clc
    adc vis_temp
    adc vis_temp
    adc vis_temp            ; + x * 3
    clc
    adc frame_count+1       ; More variation
    ; Don't need to avoid attributes - they're at $23C0+, we'll rarely hit them
    sta PPU_ADDR
    
    ; Morphing formula - stable with flash
    
    ; X component: position + phase + a
    lda frame_count
    clc
    adc vis_temp
    clc
    adc vis_phase
    clc
    adc vis_a
    sta vis_temp+1
    
    ; Y component: position + phase2 + b
    lda frame_count+1
    eor vis_temp
    clc
    adc vis_phase2
    clc
    adc vis_b
    
    ; XOR + c + twist (twist affects pattern, not position)
    eor vis_temp+1
    clc
    adc vis_c
    clc
    adc vis_twist           ; Twist modifies the XOR result instead
    
    ; Beat pulse + flash
    clc
    adc vis_pulse
    adc vis_pulse
    clc
    adc vis_flash           ; Flash on section change
    
    ; Ensure valid tile (1-31) - this is critical!
    and #$1F
    ora #$01
    
    sta PPU_DATA
    
    dex
    bne @tile_loop
    rts

;------------------------------------------------------------------------------
; Update Visual Parameters - Smooth morphing, sync to beat
;------------------------------------------------------------------------------
update_visual_params:
    ; Advance phase (main animation driver)
    inc vis_phase
    
    ; Secondary phase - moves at 3/4 speed for interesting interference
    lda frame_count
    and #$03
    cmp #$03
    beq @skip_phase2
    inc vis_phase2
@skip_phase2:

    ; Wave offset - creates ripple across screen
    lda frame_count
    and #$07
    bne @skip_wave
    lda vis_wave
    clc
    adc #$03                ; Moves in steps of 3 (prime = less repetitive)
    sta vis_wave
@skip_wave:
    
    ; Morph coefficient A (slow sine-like motion)
    lda frame_count
    and #$07
    bne @skip_a
    ; A oscillates: inc for 128 frames, dec for 128 frames
    lda frame_count+1
    and #$01
    beq @a_up
    dec vis_a
    jmp @skip_a
@a_up:
    inc vis_a
@skip_a:

    ; Morph coefficient B (different rate)
    lda frame_count
    and #$0B                ; Every 12 frames (different rhythm)
    bne @skip_b
    inc vis_b
@skip_b:

    ; Morph coefficient C (slowest, adds drift)
    lda frame_count
    and #$1F
    bne @skip_c
    ; C direction changes with song section
    lda song_section
    and #$01
    beq @c_up
    dec vis_c
    jmp @skip_c
@c_up:
    inc vis_c
@skip_c:

    ; Coefficient D tracks intensity (music energy)
    lda intensity
    sta vis_d
    
    ; Update hue - faster during high intensity sections
    lda intensity
    cmp #$08
    bcc @slow_hue
    ; Fast hue cycling
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

    ; Beat pulse - spike on kick, smooth decay
    lda frame_count
    and #$1F
    cmp #$00                ; On kick
    bne @pulse_decay
    ; KICK! Spike the pulse (bigger during drops)
    lda song_section
    cmp #$06                ; Drop section
    bne @normal_pulse
    lda #$0C                ; Bigger pulse on drop
    jmp @set_pulse
@normal_pulse:
    lda #$08
@set_pulse:
    sta vis_pulse
    rts
    
@pulse_decay:
    ; Smooth decay (every 4 frames)
    lda frame_count
    and #$03
    bne @pulse_done
    lda vis_pulse
    beq @pulse_done
    dec vis_pulse
@pulse_done:

    ; === NEW: Twist effect - creates spiral motion ===
    lda frame_count
    and #$03                ; Every 4 frames
    bne @skip_twist
    ; Twist direction changes with section
    lda song_section
    and #$02
    beq @twist_cw
    dec vis_twist           ; Counter-clockwise
    jmp @skip_twist
@twist_cw:
    inc vis_twist           ; Clockwise
@skip_twist:

    ; === NEW: Flash on section changes ===
    lda vis_flash
    beq @flash_done
    dec vis_flash           ; Decay flash
@flash_done:
    rts

;------------------------------------------------------------------------------
; MUSIC ENGINE
;------------------------------------------------------------------------------

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

    ; MINIMAL TECHNO - clean sections, not too busy
    lda song_section
    cmp #$01                ; Section 1 = kick + bass + light arp
    beq @groove_mode
    cmp #$02                ; Section 2 = breakdown (bass only)
    beq @breakdown_mode
    cmp #$03                ; Section 3 = full groove
    beq @full_mode
    cmp #$04                ; Section 4 = acid (replace lead)
    beq @acid_mode
    cmp #$05                ; Section 5 = buildup
    beq @buildup_mode
    cmp #$06                ; Section 6 = drop (full but clean)
    beq @drop_mode
    
    ; Section 0: Intro - just kick and bass
    jsr update_kick
    jsr update_bass
    rts

@groove_mode:
    ; Kick + bass + soft arp (no hats yet)
    jsr update_kick
    jsr update_bass
    jsr update_arp_soft     ; Quieter arp
    rts
    
@breakdown_mode:
    ; Breakdown - just bass and pad, very minimal
    jsr update_bass
    jsr update_pad
    rts

@full_mode:
    ; Full groove - kick, hat, bass, lead (but not arp - avoid clutter)
    jsr update_kick
    jsr update_hihat
    jsr update_bass
    jsr update_lead
    rts

@acid_mode:
    ; Acid mode - kick, bass, acid (no other melodies)
    jsr update_kick
    jsr update_hihat
    jsr update_acid_clean   ; Cleaner acid
    rts
    
@buildup_mode:
    ; Buildup - kick gets faster, riser, tom fill!
    jsr update_kick
    jsr update_riser
    jsr update_tom_fill     ; NEW: tom roll builds tension!
    rts

@drop_mode:
    ; Drop - full but controlled
    jsr update_kick
    jsr update_hihat
    jsr update_bass
    jsr update_arp
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
    ; FLASH on section change!
    lda #$0F
    sta vis_flash
    
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
; Hi-hat - Clean, minimal pattern
;------------------------------------------------------------------------------
update_hihat:
    ; Simple offbeat hats - not too busy
    lda frame_count
    and #$1F
    
    cmp #$10                ; Just offbeat (frame 16)
    beq @play_hat
    
    ; Optional: add a quiet closed hat on beat
    cmp #$00
    bne @hat_done
    
    ; Quiet closed hat on downbeat
    lda #%00110100          ; Vol 4 (quiet)
    sta APU_NOISE_CTRL
    lda #$0F                ; Highest pitch
    sta APU_NOISE_FREQ
    lda #$02                ; Very short
    sta APU_NOISE_LEN
    rts
    
@play_hat:
    ; Open hat on offbeat
    lda #%00110111          ; Vol 7
    sta APU_NOISE_CTRL
    lda #$0E                ; High pitch
    sta APU_NOISE_FREQ
    lda #$06
    sta APU_NOISE_LEN
    rts
    
@hat_done:
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
; Lead Synth - Clean chord stabs (less busy)
;------------------------------------------------------------------------------
update_lead:
    ; Play sparse stabs - every 8 beats
    lda beat_count
    and #$07
    bne @lead_sustain       ; Only play on beat 0 of every 8
    
    lda frame_count
    and #$1F
    cmp #$04                ; Stab on frame 4
    bne @lead_sustain
    
    ; STAB! Simple chord tone
    lda bar_count
    and #$03                ; 4 notes cycle
    tax
    lda lead_lo, x
    sta APU_PULSE1_LO
    lda lead_hi, x
    sta APU_PULSE1_HI
    
    ; Clean, warm tone
    lda #%10111010          ; 50% duty, vol 10
    sta APU_PULSE1_CTRL
    rts
    
@lead_sustain:
    ; Gentle decay
    lda frame_count
    and #$1F
    cmp #$08
    bcc @lead_done
    cmp #$10
    bcs @lead_off
    
    lda #%10110110          ; Vol 6
    sta APU_PULSE1_CTRL
    rts
    
@lead_off:
    lda #%10110000          ; Vol 0
    sta APU_PULSE1_CTRL
@lead_done:
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
; Soft Arp - Quieter, more subtle (for minimal sections)
;------------------------------------------------------------------------------
update_arp_soft:
    ; Slower arp - every 8 frames
    lda frame_count
    and #$07
    bne @soft_sustain
    
    ; Get note
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
    
    ; Soft volume
    lda #%01110101          ; 25% duty, vol 5
    sta APU_PULSE2_CTRL
    rts
    
@soft_sustain:
    lda frame_count
    and #$07
    cmp #$04
    bcc @soft_done
    lda #%01110010          ; Vol 2
    sta APU_PULSE2_CTRL
@soft_done:
    rts

;------------------------------------------------------------------------------
; Clean Acid - Less aggressive 303 sound
;------------------------------------------------------------------------------
update_acid_clean:
    ; Slower, cleaner acid - every 16 frames
    lda frame_count
    and #$0F
    bne @acid_clean_sustain
    
    ; Get note
    lda frame_count
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc beat_count
    and #$07                ; 8-note pattern (simpler)
    tax
    lda acid_lo, x
    sta APU_PULSE1_LO
    lda acid_hi, x
    sta APU_PULSE1_HI
    
    ; Clean tone
    lda #%10111001          ; 50% duty, vol 9
    sta APU_PULSE1_CTRL
    rts
    
@acid_clean_sustain:
    lda frame_count
    and #$0F
    cmp #$08
    bcc @acid_clean_done
    ; Gentle decay
    lda #%10110100          ; Vol 4
    sta APU_PULSE1_CTRL
@acid_clean_done:
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
; Tom Fill - Descending tom roll for buildups (uses Triangle briefly)
;------------------------------------------------------------------------------
update_tom_fill:
    ; Quick tom hits that descend in pitch - every 4 frames
    lda frame_count
    and #$03
    bne @tom_done
    
    ; Calculate descending pitch based on beat position
    lda beat_count
    and #$0F                ; 0-15 in bar
    asl a                   ; 0-30
    clc
    adc #$80                ; Start high ($80-$9E)
    sta APU_TRI_LO
    
    lda #$00
    sta APU_TRI_HI
    
    ; Quick trigger
    lda #%11000000          ; Short linear counter
    sta APU_TRI_CTRL
    
@tom_done:
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

; Initial palette - dark/moody colors
initial_palette:
    ; Background palettes
    .byte $0F, $11, $21, $31  ; Palette 0: black, blue shades
    .byte $0F, $14, $24, $34  ; Palette 1: black, purple shades
    .byte $0F, $19, $29, $39  ; Palette 2: black, green shades
    .byte $0F, $12, $22, $32  ; Palette 3: black, blue-purple
    ; Sprite palettes (unused but needed)
    .byte $0F, $11, $21, $31
    .byte $0F, $14, $24, $34
    .byte $0F, $19, $29, $39
    .byte $0F, $12, $22, $32

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
; CHR ROM - Gradient and pattern tiles
;------------------------------------------------------------------------------
.segment "CHARS"

; Tile 0: Empty (transparent)
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 1-8: Gradient fills (light to dark)
.byte $00,$00,$00,$00,$00,$00,$00,$00  ; Tile 1: Empty
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF  ; Tile 2: Solid
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $55,$AA,$55,$AA,$55,$AA,$55,$AA  ; Tile 3: Checkerboard
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00  ; Tile 4: Horizontal stripes
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA  ; Tile 5: Vertical stripes
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $81,$42,$24,$18,$18,$24,$42,$81  ; Tile 6: X pattern
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$24,$42,$81,$81,$42,$24,$18  ; Tile 7: Diamond
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $3C,$42,$81,$81,$81,$81,$42,$3C  ; Tile 8: Circle
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 9-16: Dither patterns
.byte $11,$22,$44,$88,$11,$22,$44,$88  ; Tile 9: Diagonal lines
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $88,$44,$22,$11,$88,$44,$22,$11  ; Tile 10: Diagonal other way
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F  ; Tile 11: Half and half
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $CC,$CC,$33,$33,$CC,$CC,$33,$33  ; Tile 12: Blocks
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55  ; Tile 13: Fine checker
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$81,$81,$81,$81,$81,$81,$FF  ; Tile 14: Square outline
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$3C,$42,$42,$42,$42,$3C,$00  ; Tile 15: Small circle
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$FF,$FF,$18,$18,$18  ; Tile 16: Cross/plus
.byte $00,$00,$00,$00,$00,$00,$00,$00

; Tiles 17-24: More patterns
.byte $01,$02,$04,$08,$10,$20,$40,$80  ; Tile 17: Diagonal single
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $80,$40,$20,$10,$08,$04,$02,$01  ; Tile 18: Other diagonal
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$00,$FF,$FF,$00,$00,$00  ; Tile 19: Horizontal line
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $18,$18,$18,$18,$18,$18,$18,$18  ; Tile 20: Vertical line
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $00,$00,$3C,$3C,$3C,$3C,$00,$00  ; Tile 21: Small square
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $E7,$E7,$00,$00,$00,$00,$E7,$E7  ; Tile 22: Corners
.byte $00,$00,$00,$00,$00,$00,$00,$00
.byte $FF,$80,$80,$80,$80,$80,$80,$FF  ; Tile 23: L shapes
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

; Fill rest with empty tiles
.res 8192 - (32 * 16), $00

