; SDSNOVS.COM - VESA Set Display Start VSync disable fix
; useful for ATi Rage128/Radeon cards and Build Engine games (Duke3D, etc)
;
; --wbcbz7 2o.11.2o23

; use FASM to compile

format binary
resident_start  equ     0x40                   ; resident start offset

signature       equ     'sv'

start:
                org     0x100
                jmp     init
realint10:
                org     resident_start
int10:
newint10id      dw      signature             ; our signature :)
newint10:
                cmp     ax, 0x4F07            ; VBE Set Display Start?
                jz      .sds_fix
                cmp     ax, 0x4F0A            ; VBE 2.0 Get PM services?
                jnz     .call
                xor     ax, ax                ; kill 'em
                iret                          ; =)

.sds_fix:
                and     bl, not 0x80          ; mask vsync flag

.call:
                db      0xEA ; jmp dword ?:?
int10ofs        dw  ?
int10seg        dw  ?

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

                cmp     word [es:bx-2], signature  ; check for signature
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

info_str        db      "VESA Set Display Start VSync disable - wbcbz7 2o.11.2o23$"
already_str     db      "already $"
installed_str   db      "installed$"
dash_str        db      " - $"
reset_str       db      "reset$"
released_str    db      "released$"
relfail_str     db      "can't release$"
help_str        db      "help",10,13
                db      "/U      - release from memory$"
reset_flag      db      0
