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
newint10id      dw      "hz"                  ; our signature :)
newint10:
                ;cmp     ax, 0x000D            
                ;jz      .go 
                ;cmp     ax, 0x000E
                ;jz      .go
                cmp     ax, 0x0013
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
                
                mov     dx, 0x3CC
                in      al, dx
                or      al, 0xC0
                mov     dl, 0xC2
                out     dx, al                  ; misc. output
                
                mov     dl, 0xD4
                mov     al, 0x11
                out     dx, al
                inc     dx
                in      al, dx
                and     al, 0x7F
                out     dx, al                ; unlock cr0 - cr7
                dec     dx
                
                mov     ax, 0x0B06
                out     dx, ax          ; vertical total
                mov     ax, 0x3E07
                out     dx, ax          ; overflow
                mov     ax, 0xC310
                out     dx, ax          ; vertical start retrace
                mov     ax, 0x8C11
                out     dx, ax          ; vertical end retrace
                mov     ax, 0x8F12
                out     dx, ax          ; vertical display enable end
                mov     ax, 0xB815
                out     dx, ax          ; vertical blank start
                mov     ax, 0xE216
                out     dx, ax          ; vertical blank end
                
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
                
                cmp     word [es:bx-2], "hz"  ; check for signature
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
                cmp     al, 40h               ; spaces, slashes and other stuff
                jb      @gottaloop
                cmp     al, 5Fh               ; a-z
                jb      @skip_upcase
                sub     al, 20h               ; upcase these symbols
@skip_upcase:
                cmp     al, "U"               ; release
                jz      release
                cmp     al, "R"               ; release
                jz      release
@gottaloop:     loop    @parse_loop           ; else gotta loop
no_params:
                xor     cx, cx
                jmp     build                 ; empty or invalid commandline
                
build:
                ; build it! :)
                or      bp, bp
                mov     ah, 9
                jnz     installed
                push    cx
                call    install
                pop     cx
                mov     ah, 9
                mov     dx, installed_str
                int     21h
                mov     dx, dash_str
                int     21h
                mov     dx, newint10end
                int     27h
                
installed:
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
                
info_str        db      "VGA 60hz tweak - by wbc\\bz7 16.o5.2o16$"
already_str     db      "already $"
installed_str   db      "installed$"
dash_str        db      " - $"
reset_str       db      "reset$"
border_str      db      "border$"
noborder_str    db      "noborder$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "/U      - release from memory$"
reset_flag      db      0