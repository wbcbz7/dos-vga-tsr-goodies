# MS-DOS VGA TSR goodies

This is a small collection of tiny MS-DOS resident .COM applications made by me around 2015-2019, mostly for fixing small quirks in VGA graphics cards implementation; aiming at simplicity and low runtime footprint (~128-256 bytes in memory)

Note that as S3VBEFIX already outgrown the concept, it had its own repository for years (albeit not being updated since 2016 :)

Note 2: almost all TSRs are following the common command line switches concept. Notable common switches are:

* `/U` releases TSR from memory if INT10 chain is not already hooked by another TSR



### KEENFIX

A VGA mode 0xD (320x200 16 color) CRTC retrace fix, primarily made for fixing color tint issues in Commander Keen series games on Matrox graphics cards and certain LCD monitors. Also includes option to completely remove all (but left - I gave up :) borders for fixing display adjustment issues.

### CLMCLK

Cirrus Logic CL-GD5420-5429 memory clock utility. Similar to MCLK/CIRMCLK but works around a quirk in GD542x Video BIOS, which resets memory clock to default every mode set (hence the TSR nature :)

Syntax is `CLMCLK.COM [dec]`, where `dec` is that so `MCLK frequency = (14.318 MHz * dec) / 8`. 

### MGA15BPP

Fix issues with 15bit per pixel (RGB555) VESA modes incorrectly reported as 16 bpp, commonly occuring on Matrox and Tseng built-in VBE 2.0 Video BIOS interfaces; sources were lost :(

### VGA60HZ

Force 60 Hz refresh rate and 4:3 letterboxed aspect ratio for certain VGA modes like mode 0x13 (320x200 256 color)

### LCD640

VGA 400-lines mode tweak and LCD "fix". Sets negative vertical/positive horizontal polarity for 350 lines detection if 320/640 by 200/400 line mode requested, tricking some LCD displays in detecting mode as 640x350/400 instead of 720x400, improving pixel clarity.

Would be useful in combination with OSSC if 640/720-pixel mode detection for AV3 RGBHV input implemented, which is not the case today :)

### DACFIX

Resets VGA RAMDAC Write/Read Index to 0 and Mask register (0x3C6) to 0xFF after each mode set; purpose unknown (as it also unlocks CRTC registers 0-7), sources were also lost.



-- wbcbz7 02.02.2022





P.S. by the way, I'm often hanging out in Sizecoding Discord Server, join us at https://discord.gg/5yUQmHJgfV :)