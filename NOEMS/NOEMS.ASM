; NOEMS - EMS/VCPI supressor - wbcbz7 25.11.2o22




resident_start  =       0x40                   ; resident start offset
signature       =       "nE"

; BP and newint21flags flags:
; bit 0  - NOEMS found and is last in INT21 chain
;     1  - -----------//---------- in INT67 chain
;     2  - INT67 install request
;     3  - INT67 install check

PATCH_DISABLE_FILEOPEN    equ   (1 shl 0)
PATCH_DISABLE_EMS         equ   (1 shl 1)
PATCH_DISABLE_VCPI        equ   (1 shl 2)
PATCH_NULL_INT67          equ   (1 shl 3)

                format  binary
                use16
                org     0x100
start:
                jmp     init
realint21:
                ; INT 0x21 HANDLER
                org     resident_start
int21:          
.tsrflags       dw      0               ; flags (old BP content)
.id             dw      signature       ; our signature :)
.entry:
                cmp     ah, 0x3D        ; AH = 0    - open file?
                jz      .openfile
                jmp     .chain          ; chain to previous handler
                ; AH = 0x3D (open file handler)
.openfile:
                jmp     .chain          ; patched with jnz if EMS disabled
.patch_openfile =       $-2
                ; check for EMSXXXX0 device being opened
                push    si
                mov     si, dx
                cmp     word [si],   'EM'
                jnz     .skip
                cmp     word [si+2], 'SX'
                jnz     .skip
                cmp     word [si+4], 'XX'
                jnz     .skip
                cmp     word [si+6], 'X0'
                jnz     .skip
                pop     si

                ; we got it, mark with error
                stc
                mov     ax, 2           ; file not found
                retf    2               ; strip flags from stack

                ; chain to previous int21 handler
.skip:
                pop     si
.chain:
                jmp     0x1234:0x5678
int21ofs        =       $-4
int21seg        =       $-2

                ; align next code to para boundary
                align   16
int21size       =       ($ - int21)

                ; ---------------------------
                ; INT 0x67 HANDLER, aligned by para boundary
                org     0
int67:
.entry:
                cmp     ah, 0xDE                ; AH = DE:  VCPI?
                jmp     short .chain            ; patched with jnz if VCPI disabled
.vcpi_patch     =       $-2
                ; kill VCPI
                mov     ah, 0x84
                iret
                
                db      (int67 + 0xA - $) dup (0x90)
.devname:       db      "EMMXXXX0"              ; for compatibility with "get interrupt vector" EMS detection
                                                ; also, patched for EMS driver disable
.id             dw      signature               ; you know what :)
                ; chain to old INT67
.chain:
                jmp     0x9ABC:0xDEF0
int67ofs        =       $-4
int67seg        =       $-2
int67size       =      ($ - int67)
                ; ---------------------------

                ; fixup offsets
                ; .com image base
int21_rva       =       (realint21 - int21)
int67_rva       =       (realint21 - int67 + int21size)
                ; resident start
int21_res_rva   =       (resident_start - int21)
int67_res_rva   =       (resident_start - int67 + int21size)


                org     resident_start + int21size + int67size
resident_end:
                org     realint21 + int21size + int67size
                ; ------------------
                ; START OF NON-RESIDENT PORTION
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
                cmp     al, "E"               ; disable EMS detection
                jz      disable_ems
                cmp     al, "V"               ; disable VCPI
                jz      disable_vcpi
                cmp     al, "N"               ; null out INT67 vector
                jz      null_int67
.gottaloop:     loop    .parse_loop           ; else gotta loop
no_params:
                xor     cx, cx
                jmp     build                 ; empty or invalid commandline

disable_ems:
                or      [reset_flag], PATCH_DISABLE_EMS
                jmp     parse.gottaloop
disable_vcpi:
                or      [reset_flag], PATCH_DISABLE_VCPI
                jmp     parse.gottaloop
null_int67:
                or      [reset_flag], PATCH_NULL_INT67
                jmp     parse.gottaloop


build:
                ; build it! :)
                test    bp, 1
                mov     ah, 9
                jnz     installed
                call    install
                call    reset_vars
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
                jz      .cant_release           ; INT21 not hooked by us or  another TSR hooked it
                
                and     bp, (2 + 8)
                cmp     bp, 8
                je      .cant_release           ; INT67     hooked by us but another TSR hooked it
                
                mov     dx, released_str
                int     21h 
                
                mov     ax, [es:int21seg]
                mov     ds, ax
                mov     dx, [es:int21ofs]
                mov     ax, 2521h
                int     21h                    ; set old int21
                
                test    bp, 2
                jz      .release_mcb
                
                ; release INT67
                mov     ax, [es:int67seg + int67_res_rva]
                mov     ds, ax
                mov     dx, [es:int67ofs + int67_res_rva]
                mov     ax, 2567h
                int     21h                    ; set old int67
                
                ; now we should release memory, okay? :)
.release_mcb:
                mov     ah, 49h
                int     21h
                jmp     done
                
.cant_release:  mov     dx, relfail_str
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

;----
; set/reset requested parameters
; in: ES - resident segment
reset_vars:
                mov     bp, [reset_flag]
                test    bp, PATCH_DISABLE_FILEOPEN
                jz      @f

                ; patch EMSXXXX0 detect
                mov     byte [es:int21.patch_openfile], 0x75          ; patch jmp to jnz
                mov     byte [es:int67.devname + int67_res_rva], 0x00 ; screw the EMMXXXX0 string in INT67 handler
@@:

                test    bp, PATCH_DISABLE_VCPI
                jz      @f
@@:
                ; disable VCPI
                mov     byte [es:int67.vcpi_patch + int67_res_rva], 0x75    ; patch jmp to jnz

                test    bp, PATCH_NULL_INT67
                jz      @f
                
                ; kill INT67 vector completely
                xor     ax, ax
                push    es
                mov     es, ax
                mov     word [es:(0x67 shl 2)],     ax
                mov     word [es:(0x67 shl 2) + 2], ax
                pop     es
@@:

                ret


; install check
; output: bp    - install flags
;         es    - resident segment
install_check:
                ; test INT21 first
                mov     ax, 3521h
                int     21h                   ; get int67h vector
                
                cmp     word [es:bx-2], signature  ; check for signature
                jnz     .done
                or      bp, 1                 ; INT10 hooked, last in INT10 chain
                
                ; test INT67 then
                test    word [es:bx-4], 4
                jz      .done
                or      bp, 8
                
                ; get INT67 vector, test for signature
                mov     cx, es
                mov     ax, 0x3567
                int     0x21
                
                ; check if INT67 vector is zero. if so, ignore following check
                mov     ax, es
                or      ax, bx
                jz      .zero_int67

                ; int67 is non-zero, test for signature
                cmp     word [es:int67.id], signature
                mov     es, cx                ; restore INT21 ES
                jnz     .done                 ; curernt INT67 handler doesn't match the signature
                
.zero_int67:
                or      bp, 2                 ; INT67 hooked, last in INT67 chain
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
                mov     si, realint21
                mov     di, int21
                mov     cx, (resident_end - resident_start)    ; move all handlers
                rep     movsb
                
                pop     es
    
                ; hook INT10
                mov     ax, 0x3521
                int     21h
                mov     [int21seg], es
                mov     [int21ofs], bx
                mov     ax, 0x2521
                mov     dx, int21.entry
                int     21h
                
                ; hook INT67
                mov     ax, 0x3567
                int     0x21
                mov     [int67seg + int67_res_rva], es
                mov     [int67ofs + int67_res_rva], bx
                mov     ax, ds
                add     ax, ((int67.entry + int67_res_rva) shr 4) ; in paras
                mov     ds, ax
                mov     ax, 0x2567
                xor     dx, dx
                int     21h
                
                ; restore DS
                mov     ax, cs
                mov     ds, ax

                ; free environment
                mov     bx, [cs:2Ch]
                mov     es, bx
                mov     ah, 49h
                int     21h	
                
                ; save flags
                and     bp, 4
                mov     [int21.tsrflags], bp
    
                push    cs
                pop     es
                
                ret
;----

reset_flag      dw      0
info_str        db      "NOEMS -- wbcbz7 -- 25.11.2o22 - $"
already_str     db      "already $"
installed_str   db      "installed$"
released_str    db      "released$"
relfail_str     db      "unable to release$"
help_str        db      "help",10,13
                db      "/E      - disable EMS detection by EMSXXXX0 device driver",10,13
                db      "/V      - disable VCPI",10,13
                db      "/N      - null out INT67 vector",10,13
                db      "/R, /U  - release from memory$"


