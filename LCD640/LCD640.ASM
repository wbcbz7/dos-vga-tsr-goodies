; VGA 400-lines mode tweak and LCD "fix" :)
; sets negative verical/positive horizontal polarity for 350 lines detection
; if 320/640 by 200/400 line mode requested, tricking some LCD displays in
; detecting mode as 640x350/400 instead of 720x400, improving pixel clarity

; works in VGA modes, should also work for VESA modes on VGA-compatible cards

; v 0.2 - added option to hook INT08 and check for mode change every IRQ0
;         timer tick - ideal for oddball apps changing VGA registers after
;         mode set (like some Mode-X applications)

; --wbcbz7 ob.oz.zozz

; use FASM to compile

format binary
resident_start  =       0x40                   ; resident start offset


vertical_total  =       449 - 2
signature       =       "oc"

; BP and newint10flags flags:
; bit 0  - LCD640 found and is last in INT10 chain
;     1  - -----------//----------- in INT08 chain
;     2  - INT08 install request
;     3  - INT08 install check


start:
                org     0x100
                jmp     init
realint10:
                org     resident_start
int10:
newint10flags   dw      0                       ; flags (old BP content)
newint10id      dw      signature               ; our signature :)
newint10:
                test    ah, ah                  ; AH = 0      - set VGA mode?
                jz      .go
                cmp     ax, 0x4F02              ; AX = 0x4F02 - set VBE mode?
                jz      .go
                jmp     .chain                  ; call previous handler
.go:
                pushf
                push    cs
                push    .boost
.chain:
                db      0xEA ; jmp dword ?:?
.int10ofs       dw  ?
.int10seg       dw  ?
.boost:                    
                push    ax                      ; 2b more than pusha/popa, faster for 386 and earlier + 8086 compat
                push    dx

                ; test for vertical total = 449
                mov     dx, 0x3D4
                mov     al, 6
                out     dx, al
                inc     dx
                in      al, dx
                cmp     al, (vertical_total and 0xFF)
                jnz     .exit
                
                dec     dx
                mov     al, 7
                out     dx, al
                inc     dx
                in      al, dx
                and     al, 0x21
                cmp     al, ((vertical_total and 0x100) shr 8) or ((vertical_total and 0x200) shr 4)
                jnz     .exit

                ; test for 8 pixels/char
                mov     dl, 0xC4
                mov     al, 1
                out     dx, al
                inc     dx
                in      al, dx
                test    al, 1
                jz      .exit   ; set if 8 pixels/char, clear if 9
                
                ; set negative verical/positive horizontal polarity for 350 lines detection
                mov     dl, 0xCC
                in      al, dx
                and     al, not 0xC0
                or      al, 0x80
                mov     dl, 0xC2
                out     dx, al                  ; misc. output
                
.exit:
                pop     dx
                pop     ax
                iret

newint10end:

                ; INT08 handler for evil applications changing VGA registers
                ; after mode set (like some Mode-X applications)
                ; NB: assumes chain handler acknowledging interrupt 
newint08:
                pushf
                db      0x9A    ; call dword ?:?
.int08ofs       dw  ?
.int08seg       dw  ?
                jmp     newint10.boost
                
newint08end:

; START OF TRANSIENT PART
                org     realint10 + (newint08end - int10)
init:
                push    cs
                pop     ds
                xor     bp, bp                ; will be used later
                
                mov     ah, 9
                mov     dx, info_str
                int     21h
                
                call    install_check
parse:
                ; parse command line
                mov     si, 80h
                lodsb
                and     ax, 0x00FF            ; clear AH + test for AL==0
                jz      no_params             ; empty commandline
                
                mov     cx, ax
.parse_loop:
                lodsb
                cmp     al, "?"               ; help
                jz      help
                cmp     al, 40h               ; spaces, slashes and other stuff
                jb      .gottaloop
                cmp     al, 5Fh               ; a-z
                jb      .skip_upcase
                sub     al, 20h               ; upcase these symbols
.skip_upcase:
                cmp     al, "U"               ; release
                jz      release
                cmp     al, "R"               ; release
                jz      release
                cmp     al, "T"               ; hook INT08?
                jz      hook_int08_request
.gottaloop:     loop    .parse_loop           ; else gotta loop
no_params:
                xor     cx, cx
                jmp     build                 ; empty or invalid commandline
                
build:
                ; build it! :)
                test    bp, 1
                mov     ah, 9
                jnz     installed
                call    install
                mov     ah, 9
                mov     dx, installed_str
                int     21h
                mov     dx, di
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
release:        
                mov     ah, 9                   ; remove us

                test    bp, 1
                jz      .cant_release           ; INT10 not hooked by us or  another TSR hooked it
                
                and     bp, (2 + 8)
                cmp     bp, 8
                je      .cant_release           ; INT08     hooked by us but another TSR hooked it
                
                mov     dx, released_str
                int     21h 
                
                mov     ax, [es:newint10.int10seg]
                mov     ds, ax
                mov     dx, [es:newint10.int10ofs]
                mov     ax, 2510h
                int     21h                    ; set old int10h
                
                test    bp, 2
                jz      .release_mcb
                
                ; release INT08
                mov     ax, [es:newint08.int08seg]
                mov     ds, ax
                mov     dx, [es:newint08.int08ofs]
                mov     ax, 2508h
                int     21h                    ; set old int08
                
                ; now we should release memory, okay? :)
.release_mcb:
                mov     ah, 49h
                int     21h
                jmp     done
                
.cant_release:  mov     dx, relfail_str
                int     21h

done:           int     20h                  ; and now we can exit (yes!)
;----

; set hook INT08 flag
hook_int08_request:
                or      bp, 4
                jmp     parse.parse_loop

; display help
; input\output - none
help:
                mov    ah, 9
                mov    dx, help_str
                int    21h
                
                int    20h
;----


; install check
; output: bp    - install flags
;         es    - resident segment
install_check:
                ; test INT10 first
                mov     ax, 3510h
                int     21h                   ; get int10h vector
                
                cmp     word [es:bx-2], signature  ; check for signature
                jnz     .done
                or      bp, 1                 ; INT10 hooked, last in INT10 chain
                
                ; test INT08 then
                test    word [es:bx-4], 4
                jz      .done
                or      bp, 8
                
                ; get INT08 vector, test for signature
                mov     cx, es
                mov     ax, 0x3508
                int     0x21
                mov     ax, es
                cmp     cx, ax
                mov     es, cx                ; restore INT10 ES
                jnz     .done                 ; INT10 ES != INT08 ES
                
                or      bp, 2                 ; INT08 hooked, last in INT08 chain
                
.done:
                ret

; install resident
; input:  bp    - flags
; output: es    - new resident segment
;         di    - last resident address
;         
install:
                push    es
                
                ; move TSR in PSP area
                cld
                push    cs
                pop     es
                mov     si, realint10
                mov     di, int10
                mov     cx, (newint08end - int10)    ; move INT08 handler
                rep     movsb
                
                pop     es
    
                ; hook INT10
                mov     ax, 3510h
                int     21h
                mov     [newint10.int10seg], es
                mov     [newint10.int10ofs], bx
                mov     ax, 2510h
                mov     dx, newint10
                int     21h
	
                test    bp, 4
                jz      .skip_int08_hook
                
                ; hook INT08 if requested
                mov     ax, 0x3508
                int     0x21
                mov     [newint08.int08seg], es
                mov     [newint08.int08ofs], bx
                mov     ax, 2508h
                mov     dx, newint08
                int     21h
    
.skip_int08_hook:
                ; free environment
                mov     bx, [cs:2Ch]
                mov     es, bx
                mov     ah, 49h
                int     21h	
                
                ; save flags
                and     bp, 4
                mov     [newint10flags], bp
    
                push    cs
                pop     es
                
                ret
;----

                
info_str        db      "VGA 320x200/640x400 modes LCD tweak -- wbcbz7 -- o3.o2.2o22 - $"
already_str     db      "already $"
installed_str   db      "installed$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "/T      - hook INT08 and check for mode change each timer tick",10,13
                db      "/U      - release from memory$"