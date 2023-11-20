; NV15BPP.COM - flips 16bpp (RGB565) modes to 15bpp (RGB555) on NVidia cards
; --wbcbz7 o4.o6.2023

; use FASM to compile

struc ModeInfoBlock {
     ; Mandatory information for all VBE revisions
    .ModeAttributes      dw ?      ; mode attributes
    .WinAAttributes      db ?      ; window A attributes
    .WinBAttributes      db ?      ; window B attributes
    .WinGranularity      dw ?      ; window granularity
    .WinSize             dw ?      ; window size
    .WinASegment         dw ?      ; window A start segment
    .WinBSegment         dw ?      ; window B start segment
    .WinFuncPtr          dd ?      ; pointer to window function
    .BytesPerScanLine    dw ?      ; bytes per scan line

     ; Mandatory information for VBE 1.2 and above
    .XResolution         dw ?      ; horizontal resolution in pixels or chars
    .YResolution         dw ?      ; vertical resolution in pixels or chars
    .XCharSize           db ?      ; character cell width in pixels
    .YCharSize           db ?      ; character cell height in pixels
    .NumberOfPlanes      db ?      ; number of memory planes
    .BitsPerPixel        db ?      ; bits per pixel
    .NumberOfBanks       db ?      ; number of banks
    .MemoryModel         db ?      ; memory model type
    .BankSize            db ?      ; bank size in KB
    .NumberOfImagePages  db ?      ; number of images
    .Reserved            db ?      ; reserved for page function

     ; Direct Color fields (required for direct/6 and YUV/7 memory models)
    .RedMaskSize         db ?      ; size of direct color red mask in bits
    .RedFieldPosition    db ?      ; bit position of lsb of red mask
    .GreenMaskSize       db ?      ; size of direct color green mask in bits
    .GreenFieldPosition  db ?      ; bit position of lsb of green mask
    .BlueMaskSize        db ?      ; size of direct color blue mask in bits
    .BlueFieldPosition   db ?      ; bit position of lsb of blue mask
    .RsvdMaskSize        db ?      ; size of direct color reserved mask in bits
    .RsvdFieldPosition   db ?      ; bit position of lsb of reserved mask
    .DirectColorModeInfo db ?      ; direct color mode attributes

     ; Mandatory information for VBE 2.0 and above
    .PhysBasePtr         dd ?      ; physical address for flat frame buffer
    .OffScreenMemOffset  dd ?      ; pointer to start of off screen memory
    .OffScreenMemSize    dw ?      ; amount of off screen memory in 1k units
    .Reserved2           db 206 dup (?)  ; remainder of ModeInfoBlock
}

virtual at 0
    ModeInfoBlock ModeInfoBlock
end virtual

signature       =       "15"

format binary
resident_start  equ     0x40                   ; resident start offset

start:
                org     0x100
                jmp     init
realint10:
                org     resident_start
int10:
newint10id      dw      signature       ; our signature :)
newint10:
                cmp     ax, 0x4F01      ; VBE Get Mode Info?
                jz      getmodeinfo 
                cmp     ax, 0x4F02      ; VBE Set Mode?
                jz      setmode

                ; else fall through
                db      0xEA ; jmp dword ?:?
int10ofs        dw  ?
int10seg        dw  ?

                ; -----------------
                ; VBE Get Mode Info (0x01) patch
getmodeinfo:
                ; call original INT0x10
                pushf
                call    dword [int10ofs]
                
                ; is 16bpp mode?
                cmp     byte [es:di + ModeInfoBlock.BitsPerPixel], 16
                jnz     .done
                ; flip to 15bpp
.done:
                mov     byte [es:di + ModeInfoBlock.BitsPerPixel],     15
                mov     byte [es:di + ModeInfoBlock.GreenMaskSize],    5
                mov     byte [es:di + ModeInfoBlock.RedFieldPosition], 10
                iret

                ; -----------------
                ; VBE Set Mode (0x02) patch
setmode:
                pushf
                call    dword [int10ofs]

                push    eax
                push    edx

                ; save current
                mov     dx, 0x3d4
                in      al, dx
                push    ax

                ; unlock CRTC
                mov     al, 0x1F
                out     dx, al
                inc     dx
                in      al, dx
                dec     dx
                push    ax
                mov     ax, 0x571f
                out     dx, ax

                ; select PIXEL register (0x28) (see https://rivatv.sourceforge.net/stuff/riva128.txt)
                mov     al, 0x28
                out     dx, al
                inc     dx
                in      al, dx
                dec     dx
                and     al, 3
                cmp     al, 2       ; 15/16bpp?
                jnz     .skip       ; skip if nope

                ; enable NV realmode backdoor, save current address
                mov     ax, 0x0338
                out     dx, ax
                mov     dl, 0xD0
                in      eax, dx
                push    eax
                
                ; select PRAMDAC_GENERAL_CONFIG
                mov     eax, 0x680600
                out     dx, eax

                ; toggle 565 bit
                mov     dl, 0xD4
                mov     ax, 0x0538
                out     dx, ax
                mov     dl, 0xD0
                in      eax, dx
                and     eax, not (1 shl 12)
                out     dx, eax

                ; restore backdoor address
                mov     dl, 0xD4
                mov     ax, 0x0338
                out     dx, ax
                mov     dl, 0xD0
                pop     eax
                out     dx, eax

.skip:
                ; lock CRTC
                pop     ax
                mov     ah, al
                mov     al, 0x1F
                out     dx, ax

                ; restore CRTC index
                pop     ax
                out     dx, al

                pop     edx
                pop     eax

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
                
                cmp     word [es:bx-2], signature   ; check for signature
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
                
info_str        db      "NVidia 16->15bpp tweak - by wbcbz7 o4.o6.2o23$"
already_str     db      "already $"
installed_str   db      "installed$"
dash_str        db      " - $"
reset_str       db      "reset$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "/U      - release from memory$"
reset_flag      db      0