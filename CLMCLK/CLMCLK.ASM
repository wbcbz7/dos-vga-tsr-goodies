; VGA60HZ.COM - VGA 60hz vertical refresh almost everywhere :)
; --wbcbz7 15.o7.2o17

; sets 60hz refresh for modes 0xD, 0xE and 0x13

; USE AT OWN RISK - UTILIZES NON-STANDARD CRTC PARAMETERS!!1!

; use FASM to compile

format binary
resident_start  equ     0x40                   ; resident start offset

start:
                org     0x100
                jmp     init
realint10:
                org     resident_start
int10:
newint10id      dw      "CL"                  ; our signature :)
newint10:
                test    ah, ah
                jz      .go
                jmp     .call                   ; call previous handler
.go:
                pushf
                push    cs
                push    boost
.call:
                db      0xEA ; jmp dword ?:?
int10ofs        dw  ?
int10seg        dw  ?
boost:                                        
                pusha
                
                ; unlock extended registers
                mov     dx, 0x3c4
                mov     ax, 0x1206
                out     dx, ax
                
                ; set new value for MCLK
                db      0xB8    ; mov ax, ?
                db      0x1F
.mclk           db      ?
                out     dx, ax
                
                ; lock registers
                mov     ax, 0x0006
                out     dx, ax
                
                popa
                iret
       
newint10end:

; START OF TRANSIENT PART
                org     realint10 + (newint10end - int10)
init:
                push    cs
                pop     ds
                xor     bp, bp                ; will be used later
                
                mov     ah, 9
                mov     dx, info_str
                int     21h
                mov     dx, dash_str
                int     21h                   ; display our message
                
                mov     ax, 3510h
                int     21h                   ; get int10h vector
                
                cmp     word [es:bx-2], "CL"  ; check for signature
                jnz     parse
                inc     bp                    ; if already installed
parse:
                ; parse command line
                mov     si, 80h
                lodsb
                or      al, al
                jz      no_params             ; empty commandline
                
                movzx   cx, al
@parse_loop:
                lodsb
                cmp     al, "?"               ; help
                jz      help
                cmp     al, 30h               ; spaces, slashes and other stuff
                jb      gottaloop
                cmp     al, 3Ah
                jb      parse_mclk
                cmp     al, 5Fh               ; a-z
                jb      @skip_upcase
                sub     al, 20h               ; upcase these symbols
@skip_upcase:
                cmp     al, "U"               ; release
                jz      release
                cmp     al, "R"               ; release
                jz      release
gottaloop:      jcxz    freeeeeee
                loop    @parse_loop           ; else gotta loop
freeeeeee:
                jmp     build
no_params:
                xor     cx, cx
                jmp     help                 ; empty or invalid commandline
                
build:
                ; build it! :)
                or      bp, bp
                mov     ah, 9
                jnz     installed
                
                mov     al, [tempmclk]
                test    al, al
                jz      help
                
                push    ax
                call    install
                pop     ax
                
                mov     [es:boost.mclk], al
                
                mov     ah, 9
                mov     dx, installed_str
                int     21h
                mov     dx, newint10end
                int     27h
                
installed:
                ; patch with new MCLK if provided 
                mov     al, [tempmclk]
                test    al, al
                jz      already
                
                mov     [es:boost.mclk], al
                
                mov     dx, reset_str
                int     21h
                jmp     done
                
already:        mov     dx, already_str
                int     21h
                mov     dx, installed_str
                int     21h
                jmp     done
                
; SUBPROGRAMS
; release resident from memory
; input: es - resident segment
; output: nope, immediate exit from application
release:        mov     ah, 9                   ; remove us
                or      bp, bp
                jz      cant_release
                
                mov     dx, released_str
                int     21h 
                
                mov     ax, [es:int10seg]
                mov     ds, ax
                mov     dx, [es:int10ofs]
                mov     ax, 2510h
                int     21h                    ; set old int10h
                
                ; now we should release memory, okay? :)
                
                mov     ah, 49h
                int     21h
                jmp     done
                
cant_release:   mov     dx, relfail_str
                int     21h

done:           int     20h                  ; and now we can exit (yes!)
;----

; display help
; input\output - none
help:
                mov    ah, 9
                mov    dx, help_str
                int    21h
                
                int    20h
;----

; extract MCLK
; input:  ds:si - string
; output: ax - MCLK value
parse_mclk:
                dec     si                  ; incremented by lodsb in parse loop
                call    bcdhex
                
                push    bx
                mov     bx, ax
                
                ; extract registers
                ; unlock extended registers
                mov     dx, 0x3c4
                mov     ax, 0x1206
                out     dx, ax
                
                ; set new value for MCLK
                mov     al, 0x1F
                out     dx, al
                inc     dx
                in      al, dx
                and     al, not 0x3F
                or      al, bl
                out     dx, al              ; verify it in place
                dec     dl
                mov     [tempmclk], al
                
                ; lock registers
                mov     ax, 0x0006
                out     dx, ax
                
                
                pop     bx
                
                jmp     gottaloop

; bcd to hex parser
; input:  ds:si - string, cx - number of avail chars in string
; output: ax - number
bcdhex:
                xor     ax, ax
                push    bx
                push    dx
                
                ; get BCD number
                xor     dx, dx
                mov     bx, 10              ; multiplier          
@bcdhex_loop:
                lodsb
                cmp     al, 0xA             ; CR
                jz      @bcdhex_end
                cmp     al, 0xD             ; LF
                jz      @bcdhex_end
                cmp     al, 0x3A            ; blabla :)
                ja      @bcdhex_gottaloop
                cmp     al, 0x30            ; end or invalid param
                jb      @bcdhex_end          
                ; else we have char in '0' - '9' range
                sub     al, 0x30
                imul    dx, bx              ; dx *= 10    
                add     dx, ax
@bcdhex_gottaloop:
                loop    @bcdhex_loop
                
@bcdhex_end:
                mov     ax, dx              ; save given number in ax
                pop     dx
                pop     bx
                ret
;----
                
; hex to bcd -> stdout converter 
; input:  ax - number
; output: bcd number in stdout
; uses up to 10 bytes in stack
hexbcd:
                push    bx
                push    cx
                push    dx
                mov     bx, 10
                xor     cx, cx
@hexbcd_loop:
                xor     dx, dx
                div     bx      ; remainder in dl
                add     dl, 0x30
                push    dx
                inc     cx
                test    ax, ax
                jnz     @hexbcd_loop
                
                mov     ah, 0x2
                ; закончили конвертировать
@hexbcd_print:
                pop     dx
                int     0x21
                loop    @hexbcd_print
                
                pop     dx
                pop     cx
                pop     bx
                ret
;----


; install resident
; input:  es:bx - address of preious int10h handler
; output: es    - new resident segment
install:
                push    es
                
                ; move TSR in PSP area
                cld
                push    cs
                pop     es
                mov     si, realint10
                mov     di, int10
                mov     cx, (newint10end - int10)
                rep     movsb
                
                pop     es
    
                mov     [int10seg], es
                mov     [int10ofs], bx
                mov     ax, 2510h
                mov     dx, newint10
                int     21h
	
                ; free environment
                mov     bx, [cs:2Ch]
                mov     es, bx
                mov     ah, 49h
                int     21h	
    
                push    cs
                pop     es
                
                ret
;----
                
                mov     dx, newint10end
                int     27h
                
info_str        db      "Cirrus Logic CL-GD542x MCLK tweak TSR - by wbcbz7 lz.o8.zolq$"
already_str     db      "already $"
installed_str   db      "installed$"
dash_str        db      " - $"
reset_str       db      "reset$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "<dec>   - set MCLK value:",10,13
                db      "          MCLK frequency = (14.318 MHz * dec) / 8",10,13
                db      "example:  CLMCLK 25 - set MCLK to 44.74431 Mhz",10,13
                db      "/U      - release from memory",10,13,"$"
reset_flag      db      0
tempmclk        db      0