; KEENFIX.ASM - VGA mode 0xD retrace\LCD color corruption fix TSR v.0.4
; mainly for Commander Keen series games :)
; coded in about one hour by Artem Vasilev - wbcbz7 16.o5.16 - o7.o2.22
; tested with Matrox Millennium, maybe works with other Matrox cards
; also Voodoo Banshee\3\4\5 and Intel i740 users - try it! :)

; USE AT OWN RISK - UTILIZES NON-STANDARD CRTC PARAMETERS!!1!
;
; v.0.4 - restore CRTC lock status - Catacomb 3D finally works now
;         fix noborder register values, leaving 1px top (thanks nvidia)

; use FASM to compile

format binary
resident_start  equ     40h                   ; resident start offset

start:
                org     100h
                jmp     init
realint10:
                org     resident_start
int10:
newint10id      dw      "S3"                  ; our signature :)
newint10:
                cmp     ax, 0000Dh            
                jne     @call
                
                pushf
                push    cs
                push    boost
@call:
                db      0EAh ; jmp dword ?:?
int10ofs        dw  ?
int10seg        dw  ?
boost:                                        
                push    ax
                push    dx
                mov     dx, 3D4h    
                mov     al, 11h
                out     dx, al
                inc     dx
                in      al, dx
                push    ax
                and     al, 7Fh
                out     dx, al                ; unlock cr0 - cr7
                dec     dx
                
                mov     ax, 09005h            ; horizontal retrace end
                out     dx, ax
                
                ; if you want to completely kill border set noborder to 1
                ; it can help if screen shifts down or shrinks horizontally
                ; may be incompatible with some videocards\monitors!
patch_dst:
                mov     ax, 02702h           ; horizontal blank start
                out     dx, ax
                mov     ax, 08F15h           ; vertical   blank start
                out     dx, ax
                mov     ax, 0BF16h           ; vertical   blank end
                out     dx, ax
patch_src:      
                ; restore CRTC lock status
                pop     ax
                mov     ah, al
                mov     al, 0x11
                out     dx, ax
                
                pop     dx
                pop     ax
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
                
                cmp     word [es:bx-2], "S3"  ; check for signature
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
                cmp     al, "B"               ; border specifier
                jz      parse_border
@gottaloop:     loop    @parse_loop           ; else gotta loop
no_params:
                xor     cx, cx
                jmp     build                 ; empty or invalid commandline
                
parse_border:   inc     [cs:reset_flag]
                xor     cx, cx
                lodsb
                cmp     al, "-"
                jnz     build
                inc     cx
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
                call    patch
                jmp     install_done
                
installed:
                cmp     [cs:reset_flag], 0
                jz      already               ; already installed
                mov     dx, reset_str
                int     21h
                mov     dx, dash_str
                int     21h
                call    patch
                jmp     done
                
already:        mov     dx, already_str
                int     21h
                mov     dx, installed_str
                int     21h
                jmp     done
                
install_done:   mov     dx, newint10end
                int     27h
                
                
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

; patch resident in memory
; input: ds - program segment; es - resident segment; (cx == 0) - border, else noborder; 
; output: ?
patch:
                or      cx, cx
                jz      @patch_border
                
                mov     si, realint10 + (patch_dst - int10)
                mov     dx, noborder_str
                jmp     @do_patch
@patch_border:   
                mov     si, realint10 + (patch_src - int10)
                mov     dx, border_str
@do_patch:              
                ; patch to noborder version
                mov     cx, (newint10end - patch_dst)
                mov     di, patch_dst
                rep     movsb                       ; do the patch
                
                int     21h
                ret


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
                
info_str        db      "VGA mode 0xD retrace fix - by wbc\\bz7 16.o5.2o16$"
already_str     db      "already $"
installed_str   db      "installed$"
dash_str        db      " - $"
reset_str       db      "reset$"
border_str      db      "border$"
noborder_str    db      "noborder$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "/B[+\-] - enable\disable border",10,13
                db      "/U      - release from memory$"
reset_flag      db      0