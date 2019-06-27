.cpu "65816"
.include "macros_inc.asm"
.include "bank_00_inc.asm"
.include "super_io_def.asm"
.include "vicky_def.asm"
.include "interrupt_def.asm"

* = $60
MIDI_COUNTER    .byte 0
MIDI_REG        .byte 0
MIDI_CTRL       .byte 0
MIDI_DATA1      .byte 0
MIDI_DATA2      .byte 0
TIMING_CNTR     .byte 0

MOUSE_BUTTONS_REG= $180F00 ; bit 2=middle, bit 1=right, bit 0=left
MIDI_DATA_REG    = $AF1330 ; read/write MIDI data
MIDI_STATUS_REG  = $AF1331 ; read - status, write control
MIDI_ADDRESS_HI  = $AF1160
MIDI_ADDRESS_LO  = $AF1161

* = MOUSE_BUTTONS_REG
                .byte 0
TEMP_STORAGE    .byte 0,0
LOW_NIBBLE      .byte 0
HIGH_NIBBLE     .byte 0
HEX_MAP         .text '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'
STATE_MACHINE   .byte 0  ; 0 is live mode, 1 is play mode
TICK            .byte 0  ; this is used to count the number of 1/60 intervals
BPM             .byte 30 ; how fast should the lines change - 
PATTERN_NUM     .byte 1
LINE_NUM        .byte 1

* = HRESET
                CLC
                XCE   ; go into native mode
                SEI   ; ignore interrupts
                JML TRACKER

* = HIRQ       ; IRQ handler.
RHIRQ           setaxl
                PHB
                PHD
                PHA
                PHX
                PHY
                ;
                ; todo: look up IRQ triggered and do stuff
                ;
                JSL IRQ_HANDLER

                PLY
                PLX
                PLA
                PLD
                PLB
                RTI

; Interrupt Vectors
* = VECTORS_BEGIN
JUMP_READY      JML TRACKER    ; Kernel READY routine. Rewrite this address to jump to a custom kernel.
RVECTOR_COP     .addr HCOP     ; FFE4
RVECTOR_BRK     .addr HBRK     ; FFE6
RVECTOR_ABORT   .addr HABORT   ; FFE8
RVECTOR_NMI     .addr HNMI     ; FFEA
                .word $0000    ; FFEC
RVECTOR_IRQ     .addr HIRQ     ; FFEE

RRETURN         JML TRACKER

RVECTOR_ECOP    .addr HCOP     ; FFF4
RVECTOR_EBRK    .addr HBRK     ; FFF6
RVECTOR_EABORT  .addr HABORT   ; FFF8
RVECTOR_ENMI    .addr HNMI     ; FFFA
RVECTOR_ERESET  .addr HRESET   ; FFFC
RVECTOR_EIRQ    .addr HIRQ     ; FFFE

* = $181000


.include "OPL2_library.asm"
.include "keyboard_def.asm"
.include "display.asm"
.include "Interrupt_Handler.asm" ; Interrupt Handler Routines

; Draw the screen
; Top portion is the instruments editor (left) and order list (right)
; Bottom part is the pattern editor
; we'll need to figure out how to do stereo, left- and right-only.

TRACKER
                ; Setup the Interrupt Controller
                ; For Now all Interrupt are Falling Edge Detection (IRQ)
                LDA #$FF
                STA @lINT_EDGE_REG0
                STA @lINT_EDGE_REG1
                STA @lINT_EDGE_REG2
                
                ; Mask all Interrupt @ This Point
                LDA #$FF
                STA @lINT_MASK_REG0
                STA @lINT_MASK_REG1
                STA @lINT_MASK_REG2
                
                JSR DRAW_DISPLAY

                JSR LOAD_INSTRUMENTS
                
                ; we allow keyboard inputs 
                JSR INIT_KEYBOARD
                JSR INIT_MOUSEPOINTER
                JSR INIT_CURSOR
                JSR RESET_STATE_MACHINE
                JSL IOPL2_TONE_TEST

                JSR ENABLE_IRQS
                CLI
                
                ; we allow input of data via MIDI
                JSR INIT_MIDI
          
ALWAYS          NOP
                NOP
                BRA ALWAYS
          

DRAW_DISPLAY
                ; set the display size - 128 x 64
                LDA #128
                STA COLS_PER_LINE
                LDA #64
                STA LINES_MAX

                ; set the visible display size - 80 x 60
                LDA #80
                STA COLS_VISIBLE
                LDA #60
                STA LINES_VISIBLE
                LDA #0
                STA BORDER_X_SIZE
                STA BORDER_Y_SIZE

                ; set the border to purple
                setas
                LDA #$20
                STA BORDER_COLOR_B
                STA BORDER_COLOR_R
                LDA #0
                STA BORDER_COLOR_G

                ; enable the border
                LDA #Border_Ctrl_Enable
                STA BORDER_CTRL_REG

                ; enable text display
                LDA #Mstr_Ctrl_Text_Mode_En + Mstr_Ctrl_Text_Overlay
                STA MASTER_CTRL_REG_L

                setal
                LDA #<>CS_TEXT_MEM_PTR      ; store the initial screen buffer location
                STA SCREENBEGIN
                STA CURSORPOS
                setas
                LDA #`CS_TEXT_MEM_PTR
                STA SCREENBEGIN+2
                STA CURSORPOS+2

                ; copy screen data from TRACKER_SCREEN to CS_TEXT_MEM_PTR
                setaxl
                LDA #128*64-1
                LDX #<>TRACKER_SCREEN
                LDY #<>CS_TEXT_MEM_PTR
                MVN #`TRACKER_SCREEN,#$AF

COPYFONT        LDA #256 * 8
                LDX #<>FNXFONT
                LDY #<>FONT_MEMORY_BANK0
                MVN #`FNXFONT,#$AF

                ; set the fg LUT to Green
                LDA #$60FF
                STA FG_CHAR_LUT_PTR + 8;
                LDA #$0080
                STA FG_CHAR_LUT_PTR + 10;

                ; set the character bg and fg color
                LDX #128*64
                setas
                LDA #$20
SETTEXTCOLOR
                STA CS_COLOR_MEM_PTR-1,X
                DEX
                BNE SETTEXTCOLOR

                RTS
          

;
; IINITCURSOR
; Author: Stefany
; Init the Cursor Registers
; Verify that the Math Block Works
; Inputs:
; None
; Affects:
;  Vicky's Internal Cursor's Registers
INIT_CURSOR     PHA
                LDA #$E9      ;The Cursor Character will be a Fully Filled Block
                STA VKY_TXT_CURSOR_CHAR_REG
                LDA #$0       ;Set Cursor Disabled
                STA VKY_TXT_CURSOR_CTRL_REG ;
                
                setaxl        ; Set Acc back to 16bits before setting the Cursor Position
                LDA #$0000;
                STA VKY_TXT_CURSOR_X_REG_L; // Set the X to Position 1
                LDA #$0000;
                STA VKY_TXT_CURSOR_Y_REG_L; // Set the Y to Position 1 (Below)
                
                setas
                PLA
                RTS
                
ENABLE_IRQS
                ; Clear Any Pending Interrupt
                LDA @lINT_PENDING_REG0
                AND #FNX0_INT07_MOUSE | FNX0_INT00_SOF
                STA @lINT_PENDING_REG0  ; Writing it back will clear the Active Bit
                
                LDA @lINT_PENDING_REG1
                AND #FNX1_INT00_KBD | FNX1_INT05_MPU401
                STA @lINT_PENDING_REG1  ; Writing it back will clear the Active Bit
                
                ; Enable Mouse and SOF
                LDA #~(FNX0_INT07_MOUSE | FNX0_INT00_SOF)
                STA @lINT_MASK_REG0
                
                ; Enable Keyboard
                LDA #~(FNX1_INT00_KBD | FNX1_INT05_MPU401)
                STA @lINT_MASK_REG1
                RTS
                
                
WRITE_HEX
                setas
                PHA
                PHB
                STA @lTEMP_STORAGE
                AND #$F0
                lsr A
                lsr A
                lsr A
                lsr A
                TAX
                LDA HEX_MAP,X
                STA @lLOW_NIBBLE
                
                LDA @lTEMP_STORAGE
                AND #$0F
                TAX
                LDA HEX_MAP,X
                STA @lHIGH_NIBBLE
                
                CLC
                setal
                TYA
                ADC SCREENBEGIN
                TAX
                setdbr $AF
                setal
                LDA @lLOW_NIBBLE
                STA 0, b, X  ; display the scan code upper-right
                LDA #0
                .databank 0
                
                setas
                PLB
                PLA
                RTS
                
RESET_STATE_MACHINE
                LDA #0
                STA STATE_MACHINE
                
                LDA #1
                STA LINE_NUM
                STA PATTERN_NUM
                
                JSR DISPLAY_LINE
                JSR DISPLAY_PATTERN
                
                RTS
                
DISPLAY_LINE
                LDA LINE_NUM
                ; display the line number
                LDY #22*128 + 7
                JSR WRITE_HEX
                RTS
                
DISPLAY_PATTERN
                LDA PATTERN_NUM
                ; display the pattern number
                LDY #22*128 + 19
                JSR WRITE_HEX
                RTS

LOAD_INSTRUMENTS
                RTS

INIT_MIDI
                PHA
                setas
                STZ MIDI_COUNTER
                STZ TIMING_CNTR
                
                LDA #5    ; (C256 - MIDI IN) Bit[0] = 1, Bit[2] = 1 (Page 132 Manual)
                STA @lGP25_REG
                ; LDA #0
                ; STA @lGP26_REG ; disable MIDI out
                
                LDA #$3F
                STA @lMIDI_STATUS_REG
                
                LDY #3 * 128
MORE_DATA       LDA @lMIDI_DATA_REG
                JSR WRITE_HEX
                INY
                INY
                
                LDA @lMIDI_STATUS_REG
                AND #$80
                CMP #$80
                BNE MORE_DATA
                
INIT_MIDI_DONE
                PLA
                RTS

INIT_KEYBOARD
                PHD
                PHP
                PHA
                PHX
                
                CLC
                setas
                LDA #$00
                STA KEYBOARD_SC_FLG     ; Clear the Keyboard Flag
                
                JSR Poll_Inbuf
                
                LDA #$AA      ;Send self test command
                STA KBD_CMD_BUF
                ;; Sent Self-Test Code and Waiting for Return value, it ought to be 0x55.
                JSR Poll_Outbuf ;

                LDA KBD_OUT_BUF   ;Check self test result
                CMP #$55
                BEQ passAAtest

                BRL initkb_loop_out

passAAtest      
;; Test AB
                LDA #$AB      ;Send test Interface command
                STA KBD_CMD_BUF

                JSR Poll_Outbuf ;

                LDA KBD_OUT_BUF   ;Display Interface test results
                CMP #$00      ;Should be 00
                BEQ passABtest

                BRL initkb_loop_out

passABtest      

                ;LDA #$A8        ; Enable Second PS2 Port
                ;STA KBD_DATA_BUF
                ;JSR Poll_Outbuf ;

;; Program the Keyboard & Enable Interrupt with Cmd 0x60
                LDA #$60            ; Send Command 0x60 so to Enable Interrupt
                STA KBD_CMD_BUF
                JSR Poll_Inbuf ;
                LDA #%01101001      ; Enable Interrupt
                ;LDA #%01001011      ; Enable Interrupt for Mouse and Keyboard
                STA KBD_DATA_BUF
                JSR Poll_Inbuf ;
                
; Reset Keyboard
                LDA #$FF      ; Send Keyboard Reset command
                STA KBD_DATA_BUF
                ; Must wait here;
                LDX #$FFFF
DLY_LOOP1       DEX
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                NOP
                CPX #$0000
                BNE DLY_LOOP1
                JSR Poll_Outbuf ;

                LDA KBD_OUT_BUF   ; Read Output Buffer

DO_CMD_F4_AGAIN
                JSR Poll_Inbuf ;
                LDA #$F4      ; Enable the Keyboard
                STA KBD_DATA_BUF
                JSR Poll_Outbuf ;

                LDA KBD_OUT_BUF   ; Clear the Output buffer
                CMP #$FA
                BNE DO_CMD_F4_AGAIN
                
                ; Till We Reach this point, the Keyboard is setup Properly
                JSR INIT_MOUSE

                ; Unmask the Keyboard interrupt
                ; Clear Any Pending Interrupt
                LDA @lINT_PENDING_REG0  ; Read the Pending Register &
                AND #FNX0_INT07_MOUSE
                STA @lINT_PENDING_REG0  ; Writing it back will clear the Active Bit

                LDA @lINT_PENDING_REG1  ; Read the Pending Register &
                AND #FNX1_INT00_KBD
                STA @lINT_PENDING_REG1  ; Writing it back will clear the Active Bit

initkb_loop_out 
InitSuccess     
                PLX
                PLA
                PLP
                PLD
                RTS
          
;INIT_MOUSEPOINTER
INIT_MOUSEPOINTER
                setaxl
                LDX #<>MOUSE_POINTER_PTR
                LDA #$100
                LDY #$0500
                MVN #`MOUSE_POINTER_PTR,#$AF
                
                setas
                LDA #$01
                STA @lMOUSE_PTR_CTRL_REG_L  ; Enable Mouse, Mouse Pointer Graphic Bank 0
                RTS
                
Poll_Inbuf      .as
                LDA STATUS_PORT   ; Load Status Byte
                AND #<INPT_BUF_FULL ; Test bit $02 (if 0, Empty)
                CMP #<INPT_BUF_FULL
                BEQ Poll_Inbuf
                RTS

Poll_Outbuf     .as
                LDA STATUS_PORT
                AND #OUT_BUF_FULL ; Test bit $01 (if 1, Full)
                CMP #OUT_BUF_FULL
                BNE Poll_Outbuf
                RTS

INIT_MOUSE      .as

                JSR Poll_Inbuf
                LDA #$A8          ; Enable the second PS2 Channel
                STA KBD_CMD_BUF

;                LDX #$4000
;DLY_MOUSE_LOOP  DEX
                ;CPX #$0000
                ;BNE DLY_MOUSE_LOOP
DO_CMD_A9_AGAIN
                JSR Poll_Inbuf
                LDA #$A9          ; Tests second PS2 Channel
                STA KBD_CMD_BUF
                JSR Poll_Outbuf ;
                LDA KBD_OUT_BUF   ; Clear the Output buffer
                CMP #$00
                BNE DO_CMD_A9_AGAIN
                ; IF we pass this point, the Channel is OKAY, Let's move on

                JSR Poll_Inbuf
                LDA #$20
                STA KBD_CMD_BUF
                JSR Poll_Outbuf ;

                LDA KBD_OUT_BUF
                ORA #$02
                PHA
                JSR Poll_Inbuf
                LDA #$60
                STA KBD_CMD_BUF
                JSR Poll_Inbuf ;
                PLA
                STA KBD_DATA_BUF

                LDA #$F6        ;Tell the mouse to use default settings
                JSR MOUSE_WRITE
                JSR MOUSE_READ

                ; Set the Mouse Resolution 1 Clicks for 1mm - For a 640 x 480, it needs to be the slowest
                LDA #$E8
                JSR MOUSE_WRITE
                JSR MOUSE_READ
                
                LDA #$00
                JSR MOUSE_WRITE
                JSR MOUSE_READ

                ; Set the Refresh Rate to 60
;                LDA #$F2
;                JSR MOUSE_WRITE
;                JSR MOUSE_READ
;                LDA #60
;                JSR MOUSE_WRITE
;                JSR MOUSE_READ


                LDA #$F4        ; Enable the Mouse
                JSR MOUSE_WRITE
                JSR MOUSE_READ
                
                ; Let's Clear all the Variables Necessary to Computer the Absolute Position of the Mouse
                LDA #$00
                STA MOUSE_PTR
                RTS

MOUSE_WRITE     .as
                PHA
                JSR Poll_Inbuf
                LDA #$D4
                STA KBD_CMD_BUF
                JSR Poll_Inbuf
                PLA
                STA KBD_DATA_BUF
                RTS

MOUSE_READ      .as
                JSR Poll_Outbuf ;
                LDA KBD_INPT_BUF
                RTS

                
SETUP_VDMA_FOR_TESTING_1D
                setas
                LDA #$01 ; Start Transfer
                STA @lVDMA_CONTROL_REG

                LDA #$FE
                STA @lVDMA_SIZE_L
                LDA #$9F
                STA @lVDMA_SIZE_M
                LDA #$00
                STA @lVDMA_SIZE_H

                LDA #$64
                STA @lVDMA_DST_ADDY_L
                LDA #$84
                STA @lVDMA_DST_ADDY_M
                LDA #$03
                STA @lVDMA_DST_ADDY_H

                LDA #$55
                STA @lVDMA_BYTE_2_WRITE

                LDA #$85 ; Start Transfer
                STA @lVDMA_CONTROL_REG
                LDA @lVDMA_STATUS_REG
                RTS
                
; Find the matching note for the key pressed
; A = Scan code
PLAY_TRACKER_NOTE
                PHA
                setxs
                TAX
                BMI NONOTE ; key release should not play a note

                LDA @lSCAN_TO_NOTE, X  
                
                setxl
                LDY #128 + 70
                JSR WRITE_HEX
                STA OPL2_NOTE
                
                BMI NONOTE  ; if the lookup table returns $80, then don't play the note
                
                AND #$70
                LSR
                LSR
                LSR
                LSR
                STA OPL2_OCTAVE
                LDA OPL2_NOTE
                AND #$0F
                STA OPL2_NOTE
                LDA #1
                STA OPL2_CHANNEL
                setal
                JSR OPL2_GET_REG_OFFSET
                JSL OPL2_PLAYNOTE
                setas
                
NONOTE          
                setxl
                PLA
                RTS

; databank is set to $18
; xl and as
; A contains the MIDI DATA
RECEIVE_MIDI_DATA
                .as
                setxl
                PHA
                
                BPL RECEIVED_DATA_MSG
                
                PHA
                AND #$F ; channel - store it somewhere when you care
                
                PLA
                AND #$70
                LSR 
                LSR 
                LSR 
                
                STA MIDI_CTRL
                CMP #$E
                BNE RECEIVE_MIDI_DATA_DONE
                
                JSR SYSTEM_COMMAND
                BRA RECEIVE_MIDI_DATA_DONE 
                
RECEIVED_DATA_MSG
                PHA
                setxs
                LDA MIDI_CTRL
                TAX
                PLA
                JSR (MIDI_COMMAND_TABLE,X)
                setxl
                
RECEIVE_MIDI_DATA_DONE
                PLA
                RTS
                
; /// A contains the last byte received from MIDI
NOTE_OFF
NOTE_ON         ; we need two data bytes: the note and the velocity
                .as
                .xs
                LDX MIDI_COUNTER
                STA MIDI_DATA1,X
                
                TXA
                INC A
                STA MIDI_COUNTER
                CMP #2
                BNE MORE_NOTE_DATA_NEEDED
                
                STZ MIDI_COUNTER
                LDA #1
                STA OPL2_CHANNEL
                
                
                setxl
                LDA MIDI_CTRL
                LDY #7*128
                JSR WRITE_HEX
                
                ; NOTE VALUE
                LDA MIDI_DATA1
                STA @lD0_OPERAND_B
                LDY #7*128+2
                JSR WRITE_HEX
                
                LDA #0
                STA @lD0_OPERAND_A + 1
                STA @lD0_OPERAND_B + 1
                LDA #12
                STA @lD0_OPERAND_A
                
                SEC
                LDA @lD0_RESULT
                SBC #2
                STA OPL2_OCTAVE
                LDY #7*128+10
                JSR WRITE_HEX
                
                LDA @lD0_REMAINDER
                STA OPL2_NOTE
                LDY #7*128+12
                JSR WRITE_HEX
                
                
                
                ; VELOCITY VALUE
                LDA MIDI_DATA2
                LDY #7*128+4
                JSR WRITE_HEX
                
                ; /// Turn note off
                ; CMP #0
                ; BEQ PLAY_NOTE_ON
                ; STA OPL2_PARAMETER0
                ; LDA #$FF
                ; LDY #7*128+20
                ; JSR WRITE_HEX
                
                ;JSR OPL2_SET_KEYON
                ;BRA MORE_NOTE_DATA_NEEDED
                
PLAY_NOTE_ON
                LDA #1
                STA OPL2_PARAMETER0
                
                setal
                JSR OPL2_GET_REG_OFFSET
                JSL OPL2_PLAYNOTE
                setas
                
MORE_NOTE_DATA_NEEDED
                setxs
                RTS


POLY_PRESSURE
CONTROL_CHANGE
CHANNEL_PRESSURE
PITCH_BEND
                .xs
                LDX MIDI_COUNTER
                STA MIDI_DATA1,X
                
                TXA
                INC A
                STA MIDI_COUNTER
                CMP #2
                BNE MORE_CTRL_DATA_NEEDED
                
                STZ MIDI_COUNTER
                
                setxl
                LDA MIDI_CTRL
                LDY #9*128
                JSR WRITE_HEX
                
                LDA MIDI_DATA1
                LDY #9*128+2
                JSR WRITE_HEX
                
                LDA MIDI_DATA2
                LDY #9*128+4
                JSR WRITE_HEX
                
                ;JSR CTRL_TRACKER_NOTE
                
MORE_CTRL_DATA_NEEDED
                RTS
                
SYSTEM_COMMAND
                .as
                setxl
                LDA @lTIMING_CNTR
                INC A
                CMP #3
                BNE DISPLAY_COUNTER
                LDA #0
                
DISPLAY_COUNTER
                LDY #8*128
                JSR WRITE_HEX
                STA @lTIMING_CNTR
                RTS

SETUP_VDMA_FOR_TESTING_2D
        setas

VDMA_WAIT_TF
; Wait for the Previous Transfer to be Finished
                LDA @lVDMA_STATUS_REG
                AND #VDMA_STAT_VDMA_IPS
                CMP #VDMA_STAT_VDMA_IPS
                BEQ VDMA_WAIT_TF

                LDA #$01 ; Start Transfer
                STA @lVDMA_CONTROL_REG

                LDA #200
                STA @lVDMA_X_SIZE_L
                LDA #00
                STA @lVDMA_X_SIZE_H

                LDA #64
                STA @lVDMA_Y_SIZE_L
                LDA #00
                STA @lVDMA_Y_SIZE_H

                LDA #$60
                STA @lVDMA_DST_ADDY_L
                LDA #$90
                STA @lVDMA_DST_ADDY_M
                LDA #$01
                STA @lVDMA_DST_ADDY_H

                LDA #$80
                STA @lVDMA_DST_STRIDE_L
                LDA #$02
                STA @lVDMA_DST_STRIDE_H

                LDA #$F9
                STA @lVDMA_BYTE_2_WRITE

                LDA #$87 ; Start Transfer
                STA @lVDMA_CONTROL_REG
                LDA @lVDMA_STATUS_REG
                RTS
                
                ;      00,  01,  02,  03,  04,  05,  06,  07,  08,  09,  0A,  0B,  0C,  0D,  0E,  0F
SCAN_TO_NOTE    .text $80, $80, $80, $31, $33, $80, $36, $38, $3A, $80, $80, $80, $80, $80, $80, $80
                .text $30, $32, $34, $35, $37, $39, $3B, $40, $80, $80, $80, $80, $80, $80, $80, $21
                .text $23, $80, $26, $28, $2A, $80, $80, $80, $80, $80, $80, $80, $20, $22, $24, $25
                .text $27, $29, $2B, $30, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80
                .text $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80
                
MIDI_COMMAND_TABLE
                 .word <>NOTE_OFF, <>NOTE_ON, <>POLY_PRESSURE, <>CONTROL_CHANGE, <>CHANNEL_PRESSURE, <>PITCH_BEND, <>SYSTEM_COMMAND
